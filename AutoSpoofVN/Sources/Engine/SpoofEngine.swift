import Foundation
import CoreLocation
import AVFoundation

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
    @Published var pairingPlist: String = ""

    /// Module đang giữ quyền ghi toạ độ. `nil` nghĩa là chưa ai giữ.
    @Published private(set) var activeSource: SpoofSource? = nil

    /// Cờ cho biết keep-alive nền có thực sự chạy được hay không.
    /// Trước đây lỗi khởi tạo audio bị nuốt im lặng khiến app tưởng đang chạy ngầm.
    @Published private(set) var isKeepAliveRunning: Bool = false
    @Published private(set) var keepAliveError: String? = nil

    /// Người dùng đã bấm "khôi phục GPS thật". Mọi nguồn bị chặn ghi cho tới khi có
    /// hành động khởi động lại rõ ràng (bật chu trình, bắt đầu chuyến bay, hoặc đặt tay).
    @Published private(set) var isHalted: Bool = false

    private var audioPlayer: AVAudioPlayer?
    private var heartBeatTimer: Timer?

    /// Mọi lời gọi FFI phải chạy trên đúng hàng đợi này.
    ///
    /// Các hàm của libidevice bọc `run_sync` nên chúng CHẶN thread gọi cho tới khi I/O
    /// mạng xong. Trước đây chúng chạy trên main thread từ Timer, nên tunnel lag là treo UI
    /// và iOS watchdog giết app (0x8badf00d). Handle cũng không thread-safe, nên phải nối
    /// tiếp trên một hàng đợi duy nhất.
    private let ffiQueue = DispatchQueue(label: "com.autospoof.vn.ffi")
    /// Chỉ được đọc/ghi bên trong `ffiQueue`.
    private var deviceHandle: UnsafeMutableRawPointer? = nil

    private init() {
        if let savedPlist = UserDefaults.standard.string(forKey: "autospoof_pairing_plist") {
            self.pairingPlist = savedPlist
        }
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

        // Thêm GPS Jitter tự nhiên (dao động vài mét) để vị trí không đứng yên tuyệt đối.
        if enableJitter {
            let cosLat = cos(lat * .pi / 180.0)
            let latOffsetDeg = (jitterMeters / 111_320.0) * Double.random(in: -1.0...1.0)
            // Chặn chia cho 0 khi ở gần hai cực.
            let lonScale = abs(cosLat) < 1e-6 ? 1e-6 : abs(cosLat)
            let lonOffsetDeg = (jitterMeters / (111_320.0 * lonScale)) * Double.random(in: -1.0...1.0)
            lat += latOffsetDeg
            lon += lonOffsetDeg
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

    /// Bật chế độ chạy ngầm bằng Silent Audio để iOS không treo tiến trình.
    /// Trả về `true` nếu audio thực sự khởi động được.
    @discardableResult
    func startBackgroundKeepAlive() -> Bool {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)

            let silentData = SpoofEngine.makeSilentWavData(seconds: 1.0)
            let player = try AVAudioPlayer(data: silentData)
            player.numberOfLoops = -1
            player.volume = 0.01
            player.prepareToPlay()
            let started = player.play()
            audioPlayer = player
            isKeepAliveRunning = started
            keepAliveError = started ? nil : "AVAudioPlayer.play() trả về false"
            if !started {
                print("[SpoofEngine] Keep-Alive: play() thất bại.")
            }
        } catch {
            audioPlayer = nil
            isKeepAliveRunning = false
            keepAliveError = error.localizedDescription
            print("[SpoofEngine] Lỗi kích hoạt Audio Keep-Alive: \(error.localizedDescription)")
        }

        // Heartbeat gửi lại toạ độ định kỳ để giữ phiên DVT sống.
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
        audioPlayer?.stop()
        audioPlayer = nil
        isKeepAliveRunning = false
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    // MARK: - Kết nối DVT

    /// Kết nối vào cổng DVT nội bộ qua loopback LocalDevVPN (10.7.0.1).
    func connectLoopback(plistContent: String) {
        let trimmedPlist = plistContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPlist.isEmpty else {
            connectionStatus = "File plist không hợp lệ"
            return
        }

        self.pairingPlist = trimmedPlist
        UserDefaults.standard.set(trimmedPlist, forKey: "autospoof_pairing_plist")
        connectionStatus = "Đang kết nối 10.7.0.1:62078..."

        ffiQueue.async { [weak self] in
            guard let self = self else { return }
            #if USE_IDEVICE_FFI
            let handle = idevice_connect_dvt("10.7.0.1", 62078, trimmedPlist)
            self.deviceHandle = handle
            DispatchQueue.main.async {
                if handle != nil {
                    self.isLoopbackConnected = true
                    self.connectionStatus = "Đã kết nối DVT Loopback (10.7.0.1)"
                } else {
                    self.isLoopbackConnected = false
                    self.connectionStatus = "Kết nối DVT thất bại (Kiểm tra VPN & Plist)"
                }
            }
            #else
            DispatchQueue.main.async {
                self.isLoopbackConnected = true
                self.connectionStatus = "Chế độ MÔ PHỎNG (chưa có libidevice_ffi) - GPS thật KHÔNG đổi"
            }
            #endif
        }
    }

    /// Khôi phục vị trí GPS thật.
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
