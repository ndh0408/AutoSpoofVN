import Foundation
import CoreLocation
import AVFoundation
import Combine

#if USE_IDEVICE_FFI
import idevice
#endif

/// Nguồn phát toạ độ. Dùng để phân xử khi nhiều module cùng muốn ghi vị trí.
/// Ưu tiên: Manual (người dùng bấm) > Flight (đang bay) > Routine (thói quen 24/7).
enum SpoofSource: String, CaseIterable, Codable {
    case routine
    case flight
    case manual

    var priority: Int {
        switch self {
        case .routine: return 10
        case .flight: return 20
        case .manual: return 30
        }
    }

    var displayName: String {
        switch self {
        case .routine: return "Chu trình 24/7"
        case .flight: return "Chuyến bay"
        case .manual: return "Thủ công"
        }
    }
}

/// Trình điều khiển mô phỏng GPS và duy trì chạy ngầm (Keep-Alive).
///
/// Toàn bộ API công khai của lớp này PHẢI được gọi trên main thread; nếu gọi từ
/// thread khác, lớp tự chuyển về main thread một cách bất đồng bộ.
final class SpoofEngine: ObservableObject {
    static let shared = SpoofEngine()

    @Published var isSimulating: Bool = false
    @Published var currentCoordinate: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 21.0285, longitude: 105.8542) // Mặc định: Hoàn Kiếm, Hà Nội
    @Published var connectionStatus: String = "Chưa kết nối"
    @Published var isLoopbackConnected: Bool = false
    @Published var enableJitter: Bool = true
    @Published var jitterMeters: Double = 3.0
    @Published var lastSpoofedAt: Date? = nil
    /// Nội dung thô của lockdown pairing record.
    ///
    /// Phải là `Data`, không phải `String`: pairing file thật là **binary plist** và
    /// chứa byte 0, nên chuyển qua chuỗi C sẽ bị cắt cụt ngay ký tự đầu tiên.
    @Published private(set) var pairingData: Data? = nil

    /// Chỉ dùng cho ô nhập dạng chữ (plist XML). Với file nhị phân, giá trị này rỗng —
    /// đọc `pairingData` mới là nguồn sự thật.
    @Published var pairingPlist: String = ""

    /// Lý do thất bại gần nhất do thư viện FFI báo về, đã dịch sang thông điệp cho người dùng.
    @Published private(set) var lastFFIError: String? = nil

    /// Mô tả ngắn về pairing record đang nạp, để hiển thị trên UI.
    var pairingSummary: String {
        guard let d = pairingData, !d.isEmpty else { return "Chưa nạp pairing file" }
        if d.starts(with: Array("<?xml".utf8)) && (String(data: d, encoding: .utf8)?.contains("public_key") == true) {
            return "Đã ghép nối RPPairing trên máy (\(d.count) byte)"
        }
        let kind = d.starts(with: Array("bplist".utf8)) ? "binary plist" : "plist văn bản"
        return "Đã nạp \(d.count) byte (\(kind))"
    }

    /// Module đang giữ quyền ghi toạ độ. `nil` nghĩa là chưa ai giữ.
    @Published private(set) var activeSource: SpoofSource? = nil

    /// Cờ cho biết keep-alive nền có thực sự chạy được hay không.
    /// Trước đây lỗi khởi tạo audio bị nuốt im lặng khiến app tưởng đang chạy ngầm.
    @Published private(set) var isKeepAliveRunning: Bool = false
    @Published private(set) var keepAliveError: String? = nil

    /// Người dùng đã bấm "khôi phục GPS thật". Mọi nguồn bị chặn ghi cho tới khi có
    /// hành động khởi động lại rõ ràng (bật chu trình, bắt đầu chuyến bay, hoặc đặt tay).
    @Published private(set) var isHalted: Bool = false

    private var heartBeatTimer: Timer?
    private var keeperObservers: Set<AnyCancellable> = []

    /// Mọi lời gọi FFI phải chạy trên đúng hàng đợi này.
    ///
    /// Các hàm của libidevice bọc `run_sync` nên chúng CHẶN thread gọi cho tới khi I/O
    /// mạng xong. Trước đây chúng chạy trên main thread từ Timer, nên tunnel lag là treo UI
    /// và iOS watchdog giết app (0x8badf00d). Handle cũng không thread-safe, nên phải nối
    /// tiếp trên một hàng đợi duy nhất.
    private let ffiQueue = DispatchQueue(label: "com.autospoof.vn.ffi")
    /// Chỉ được đọc/ghi bên trong `ffiQueue`.
    private var deviceHandle: UnsafeMutableRawPointer? = nil

    /// Độ lệch nhiễu hiện tại, tính bằng mét. Giữ lại giữa các lần gọi để nhiễu có
    /// tương quan theo thời gian thay vì nhảy ngẫu nhiên độc lập.
    private var jitterOffsetNorthMeters: Double = 0
    private var jitterOffsetEastMeters: Double = 0

    private init() {
        if let saved = UserDefaults.standard.data(forKey: "autospoof_pairing_data") {
            self.pairingData = saved
            // Chỉ đổ ngược ra ô chữ khi nội dung thực sự là văn bản.
            if !saved.starts(with: Array("bplist".utf8)),
               let text = String(data: saved, encoding: .utf8) {
                self.pairingPlist = text
            }
        } else if let sandboxData = try? Data(contentsOf: SelfPairingManager.pairingFileURL), !sandboxData.isEmpty {
            self.pairingData = sandboxData
        } else if let legacy = UserDefaults.standard.string(forKey: "autospoof_pairing_plist") {
            // Di trú từ bản cũ từng lưu dạng chuỗi.
            self.pairingPlist = legacy
            self.pairingData = Data(legacy.utf8)
        }
        // Phản chiếu trạng thái nền ra đúng hai thuộc tính MainView đang đọc.
        let keeper = BackgroundKeeper.shared
        keeper.$isAudioRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.isKeepAliveRunning = $0 }
            .store(in: &keeperObservers)
        keeper.$audioError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.keepAliveError = $0 }
            .store(in: &keeperObservers)
    }

    // MARK: - Phân xử nguồn phát toạ độ (Arbiter)

    /// Xin quyền ghi toạ độ cho một nguồn. Trả về `false` nếu đang có nguồn ưu tiên cao hơn giữ quyền.
    @discardableResult
    func acquire(_ source: SpoofSource) -> Bool {
        if let holder = activeSource, holder != source, holder.priority > source.priority {
            return false
        }
        isHalted = false
        if activeSource != source {
            activeSource = source
        }
        return true
    }

    /// Trả lại quyền. Chỉ có tác dụng nếu chính nguồn đó đang giữ.
    func release(_ source: SpoofSource) {
        if activeSource == source {
            activeSource = nil
        }
    }

    /// Gửi một toạ độ mới kèm danh tính nguồn phát.
    /// Trả về `false` nếu bị từ chối vì một nguồn ưu tiên cao hơn đang giữ quyền.
    @discardableResult
    func submit(latitude: Double, longitude: Double, from source: SpoofSource) -> Bool {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                _ = self?.submit(latitude: latitude, longitude: longitude, from: source)
            }
            return true
        }
        guard !isHalted else { return false }
        guard acquire(source) else { return false }
        applyLocation(latitude: latitude, longitude: longitude)
        return true
    }

    /// Đặt vị trí thủ công (người dùng chạm bản đồ / nhập toạ độ). Luôn thắng mọi nguồn khác.
    func setLocation(latitude: Double, longitude: Double) {
        _ = submit(latitude: latitude, longitude: longitude, from: .manual)
    }

    private func applyLocation(latitude: Double, longitude: Double) {
        var lat = latitude
        var lon = longitude

        // Nhiễu GPS. Dùng bước ngẫu nhiên có tương quan chứ không phải nhiễu trắng:
        // sai số GPS thật trôi dần theo thời gian, còn nhiễu trắng cho ra chuỗi toạ độ
        // giật ngẫu nhiên hoàn toàn quanh một điểm — chính là dấu hiệu của vị trí giả.
        if enableJitter {
            let inertia = 0.82  // giữ lại phần lớn độ lệch cũ
            let kick = jitterMeters * 0.55
            jitterOffsetNorthMeters = jitterOffsetNorthMeters * inertia + Double.random(in: -kick...kick)
            jitterOffsetEastMeters = jitterOffsetEastMeters * inertia + Double.random(in: -kick...kick)

            // Giữ độ lệch trong bán kính người dùng đặt.
            let radius = hypot(jitterOffsetNorthMeters, jitterOffsetEastMeters)
            if radius > jitterMeters, radius > 0 {
                let scale = jitterMeters / radius
                jitterOffsetNorthMeters *= scale
                jitterOffsetEastMeters *= scale
            }

            let cosLat = cos(lat * .pi / 180.0)
            let lonScale = abs(cosLat) < 1e-6 ? 1e-6 : abs(cosLat)
            lat += jitterOffsetNorthMeters / 111_320.0
            lon += jitterOffsetEastMeters / (111_320.0 * lonScale)
        }

        lat = min(max(lat, -90.0), 90.0)
        if lon > 180.0 { lon -= 360.0 }
        if lon < -180.0 { lon += 360.0 }

        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        currentCoordinate = coord
        isSimulating = true
        lastSpoofedAt = Date()
        sendLocationToDevice(coord)
    }

    // MARK: - Chạy ngầm (Keep-Alive)

    /// Bật chế độ chạy ngầm. Trả về `true` nếu audio thực sự khởi động được.
    ///
    /// Gọi lại nhiều lần là an toàn — `MainView.onAppear` chạy mỗi lần view xuất hiện.
    @discardableResult
    func startBackgroundKeepAlive() -> Bool {
        BackgroundKeeper.shared.start()

        // Watchdog định kỳ. Với cầu nối FFI thật, chỗ này phải đổi thành kiểm tra
        // heartbeat (com.apple.mobile.heartbeat) và dựng lại cả chuỗi kết nối khi đứt,
        // chứ không phải gửi lặp toạ độ: DVT giữ nguyên vị trí chừng nào kênh còn mở.
        heartBeatTimer?.invalidate()
        let timer = Timer(timeInterval: 20.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isSimulating else { return }
            self.sendLocationToDevice(self.currentCoordinate)
        }
        // .common để timer không bị dừng khi người dùng đang cuộn bản đồ.
        RunLoop.main.add(timer, forMode: .common)
        heartBeatTimer = timer

        return isKeepAliveRunning
    }

    func stopBackgroundKeepAlive() {
        heartBeatTimer?.invalidate()
        heartBeatTimer = nil
        BackgroundKeeper.shared.stop()
    }

    // MARK: - Kết nối DVT

    /// Kết nối vào cổng DVT nội bộ qua loopback LocalDevVPN (10.7.0.1).
    ///
    /// Bản nhận `String` chỉ dùng được với plist dạng văn bản. Pairing record thật
    /// thường là binary plist — dùng bản nhận `Data` và một `.fileImporter`.
    func connectLoopback(plistContent: String) {
        let trimmed = plistContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            connectionStatus = "Chưa có nội dung pairing file"
            return
        }
        pairingPlist = trimmed
        connectLoopback(pairingData: Data(trimmed.utf8))
    }

    /// Kết nối bằng nội dung nhị phân của pairing record. Đây là đường đúng.
    func connectLoopback(pairingData data: Data) {
        guard !data.isEmpty else {
            connectionStatus = "Pairing file rỗng"
            return
        }

        self.pairingData = data
        UserDefaults.standard.set(data, forKey: "autospoof_pairing_data")
        lastFFIError = nil
        connectionStatus = "Đang kết nối 10.7.0.1:62078..."

        ffiQueue.async { [weak self] in
            guard let self = self else { return }
            #if USE_IDEVICE_FFI
            let isRPPairing = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any])?["public_key"] != nil
            let handle: UnsafeMutableRawPointer? = data.withUnsafeBytes { raw in
                guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return nil }
                if isRPPairing {
                    return idevice_connect_dvt_remote("10.7.0.1", 49152, base, raw.count, "000000")
                } else {
                    return idevice_connect_dvt("10.7.0.1", 62078, base, raw.count)
                }
            }
            self.deviceHandle = handle
            // Đọc lý do thất bại NGAY, trước bất kỳ lời gọi FFI nào khác:
            // con trỏ chỉ hợp lệ tới lần gọi kế tiếp.
            let reason: String? = handle == nil ? SpoofEngine.readLastFFIError() : nil
            DispatchQueue.main.async {
                if handle != nil {
                    self.isLoopbackConnected = true
                    self.lastFFIError = nil
                    self.connectionStatus = isRPPairing
                        ? "Đã kết nối DVT thật qua RPPairing (10.7.0.1:49152)"
                        : "Đã kết nối DVT Loopback (10.7.0.1:62078)"
                } else {
                    self.isLoopbackConnected = false
                    self.lastFFIError = reason
                    self.connectionStatus = reason ?? "Kết nối DVT thất bại"
                }
            }
            #else
            DispatchQueue.main.async {
                self.isLoopbackConnected = false
                self.lastFFIError = "Bản build thiếu thư viện Rust FFI"
                self.connectionStatus = "Chưa kết nối: bản build chưa có libidevice_ffi.a"
            }
            #endif
        }
    }

    #if USE_IDEVICE_FFI
    /// Sao chép ngay chuỗi lỗi: con trỏ thư viện trả về chỉ sống tới lần gọi FFI kế tiếp.
    private static func readLastFFIError() -> String? {
        guard let p = idevice_last_error() else { return nil }
        return String(cString: p)
    }
    #endif

    /// Khôi phục vị trí GPS thật và CHẶN mọi nguồn ghi tiếp.
    ///
    /// Nếu không có cờ `isHalted`, chu trình 24/7 (timer 60 giây) hoặc chuyến bay sẽ ghi đè
    /// toạ độ ngay ở tick kế tiếp, khiến nút "khôi phục GPS thật" trông như không có tác dụng.
    func clearSimulation() {
        isSimulating = false
        isHalted = true
        activeSource = nil
        #if USE_IDEVICE_FFI
        ffiQueue.async { [weak self] in
            guard let handle = self?.deviceHandle else { return }
            _ = idevice_clear_location(handle)
        }
        #endif
        print("[SpoofEngine] Đã xoá mô phỏng toạ độ, khôi phục GPS thật.")
    }

    /// Ngắt kết nối DVT.
    func disconnect() {
        #if USE_IDEVICE_FFI
        ffiQueue.async { [weak self] in
            guard let self = self, let handle = self.deviceHandle else { return }
            idevice_disconnect(handle)
            self.deviceHandle = nil
        }
        #endif
        isLoopbackConnected = false
        isSimulating = false
        activeSource = nil
        lastFFIError = nil
        connectionStatus = "Đã ngắt kết nối"
    }

    private func sendLocationToDevice(_ coord: CLLocationCoordinate2D) {
        #if USE_IDEVICE_FFI
        ffiQueue.async { [weak self] in
            guard let handle = self?.deviceHandle else { return }
            _ = idevice_set_location(handle, coord.latitude, coord.longitude)
        }
        #endif
    }

    // MARK: - Sinh WAV im lặng

    /// Tạo dữ liệu WAV PCM 16-bit mono 44.1kHz toàn mẫu 0.
    ///
    /// Bản cũ để trống 4 trường bắt buộc (ChunkSize, ByteRate, BlockAlign, Subchunk2Size)
    /// nên `AVAudioPlayer(data:)` ném lỗi OSStatus 1685348671 và keep-alive không bao giờ chạy.
    static func makeSilentWavData(seconds: Double = 1.0) -> Data {
        let sampleRate: UInt32 = 44_100
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let blockAlign: UInt16 = channels * bitsPerSample / 8
        let byteRate: UInt32 = sampleRate * UInt32(blockAlign)
        let frameCount = UInt32(max(1.0, seconds * Double(sampleRate)))
        let dataSize: UInt32 = frameCount * UInt32(blockAlign)

        var data = Data(capacity: 44 + Int(dataSize))

        func appendASCII(_ s: String) { data.append(contentsOf: Array(s.utf8)) }
        func appendLE32(_ v: UInt32) {
            data.append(contentsOf: [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)])
        }
        func appendLE16(_ v: UInt16) {
            data.append(contentsOf: [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)])
        }

        appendASCII("RIFF")
        appendLE32(36 + dataSize)      // ChunkSize
        appendASCII("WAVE")
        appendASCII("fmt ")
        appendLE32(16)                 // Subchunk1Size (PCM)
        appendLE16(1)                  // AudioFormat = PCM
        appendLE16(channels)
        appendLE32(sampleRate)
        appendLE32(byteRate)
        appendLE16(blockAlign)
        appendLE16(bitsPerSample)
        appendASCII("data")
        appendLE32(dataSize)
        data.append(Data(count: Int(dataSize)))  // toàn bộ mẫu = 0 (im lặng)

        return data
    }
}
