import Foundation
import CoreLocation
import AVFoundation
import Combine


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
        case .routine: return L("common.source.routine")
        case .flight: return L("common.source.flight")
        case .manual: return L("common.source.manual")
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
    @Published var enableJitter: Bool = true
    @Published var jitterMeters: Double = 3.0
    @Published var lastSpoofedAt: Date? = nil
    /// Module đang giữ quyền ghi toạ độ. `nil` nghĩa là chưa ai giữ.
    @Published private(set) var activeSource: SpoofSource? = nil

    /// Cờ cho biết keep-alive nền có thực sự chạy được hay không.
    /// Trước đây lỗi khởi tạo audio bị nuốt im lặng khiến app tưởng đang chạy ngầm.
    @Published private(set) var isKeepAliveRunning: Bool = false
    @Published private(set) var keepAliveError: String? = nil

    /// Người dùng đã bấm "khôi phục GPS thật". Mọi nguồn bị chặn ghi cho tới khi có
    /// hành động khởi động lại rõ ràng (bật chu trình, bắt đầu chuyến bay, hoặc đặt tay).
    @Published private(set) var isHalted: Bool = false

    private var keeperObservers: Set<AnyCancellable> = []

    /// Độ lệch nhiễu hiện tại, tính bằng mét. Giữ lại giữa các lần gọi để nhiễu có
    /// tương quan theo thời gian thay vì nhảy ngẫu nhiên độc lập.
    private var jitterOffsetNorthMeters: Double = 0
    private var jitterOffsetEastMeters: Double = 0

    private init() {
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

    /// Ghi toạ độ ĐÚNG NHƯ ĐƯỢC TRUYỀN, không thêm jitter.
    ///
    /// Dùng bởi `SimulationCoordinator`, vốn đã tự áp nhiễu theo `noiseConfig` của nó.
    /// Đi qua `setLocation` sẽ bị jitter lần thứ hai ở đây, thành nhiễu chồng nhiễu và
    /// tích luỹ thành trôi vị trí thật sự.
    func applyExactLocation(latitude: Double, longitude: Double) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.applyExactLocation(latitude: latitude, longitude: longitude)
            }
            return
        }
        guard !isHalted else { return }

        var lat = min(max(latitude, -90.0), 90.0)
        var lon = longitude
        if lon > 180.0 { lon -= 360.0 }
        if lon < -180.0 { lon += 360.0 }

        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        currentCoordinate = coord
        isSimulating = true
        lastSpoofedAt = Date()
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
    }

    // MARK: - Chạy ngầm (Keep-Alive)

    /// Bật chế độ chạy ngầm. Trả về `true` nếu audio thực sự khởi động được.
    ///
    /// Gọi lại nhiều lần là an toàn — `MainView.onAppear` chạy mỗi lần view xuất hiện.
    @discardableResult
    func startBackgroundKeepAlive() -> Bool {
        BackgroundKeeper.shared.start()
        return isKeepAliveRunning
    }

    func stopBackgroundKeepAlive() {
        BackgroundKeeper.shared.stop()
    }

    /// Khôi phục vị trí GPS thật và CHẶN mọi nguồn ghi tiếp.
    ///
    /// Nếu không có cờ `isHalted`, chu trình 24/7 (timer 60 giây) hoặc chuyến bay sẽ ghi đè
    /// toạ độ ngay ở tick kế tiếp, khiến nút "khôi phục GPS thật" trông như không có tác dụng.
    func clearSimulation() {
        isSimulating = false
        isHalted = true
        activeSource = nil
        AppLogger.simulation.info(" Đã xoá mô phỏng toạ độ, khôi phục GPS thật.")
    }

    /// Alias tuong thich cho `Coordinator/SimulationCoordinator.swift` - hanh vi giong het
    /// `clearSimulation()`: khoi phuc GPS that va CHAN moi nguon ghi tiep cho toi khi nguoi
    /// dung chu dong bat lai.
    func haltSimulation() {
        clearSimulation()
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
