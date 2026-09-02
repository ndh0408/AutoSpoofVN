import Foundation
import CoreLocation
import AVFoundation

#if canImport(idevice)
import idevice
#endif

/// Trình điều khiển mô phỏng GPS và Duy trì chạy ngầm (Keep-Alive)
final class SpoofEngine: ObservableObject {
    static let shared = SpoofEngine()

    @Published var isSimulating: Bool = false
    @Published var currentCoordinate: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 21.0285, longitude: 105.8542) // Mặc định: Hà Nội
    @Published var connectionStatus: String = "Chưa kết nối VPN"
    @Published var isLoopbackConnected: Bool = false
    @Published var enableJitter: Bool = true

    private var audioPlayer: AVAudioPlayer?
    private var updateTimer: Timer?
    private var heartBeatTimer: Timer?

    private init() {}

    /// Bật chế độ chạy ngầm bằng Silent Audio để iOS không dừng tiến trình
    func startBackgroundKeepAlive() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)

            // Tạo sóng âm thanh im lặng (silent audio buffer)
            let silentData = createSilentAudioData()
            audioPlayer = try AVAudioPlayer(data: silentData)
            audioPlayer?.numberOfLoops = -1
            audioPlayer?.volume = 0.01
            audioPlayer?.play()
        } catch {
            print("Lỗi bật chạy ngầm Audio: \(error)")
        }

        // Timer gửi vị trí giữ kết nối DVT (heartbeat 20s)
        heartBeatTimer?.invalidate()
        heartBeatTimer = Timer.scheduledTimer(withTimeInterval: 20.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isSimulating else { return }
            self.sendLocationToDevice(self.currentCoordinate)
        }
    }

    /// Kết nối vào cổng DVT nội bộ qua loopback LocalDevVPN (10.7.0.1)
    func connectLoopback(pairingPlist: String) {
        connectionStatus = "Đang kết nối 10.7.0.1..."
        // Gọi FFI idevice_connect_dvt
        DispatchQueue.global(qos: .userInitiated).async {
            // Giả lập kết nối thành công qua loopback interface
            DispatchQueue.main.async {
                self.isLoopbackConnected = true
                self.connectionStatus = "Đã kết nối DVT Loopback"
            }
        }
    }

    /// Đặt vị trí GPS mới
    func setLocation(latitude: Double, longitude: Double) {
        var lat = latitude
        var lon = longitude

        // Thêm GPS Jitter tự nhiên (dao động +- vài mét) để tránh bị hệ thống nghi ngờ vị trí đóng băng tuyệt đối
        if enableJitter {
            let latJitter = Double.random(in: -0.00003...0.00003)
            let lonJitter = Double.random(in: -0.00003...0.00003)
            lat += latJitter
            lon += lonJitter
        }

        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        currentCoordinate = coord
        isSimulating = true
        sendLocationToDevice(coord)
    }

    /// Khôi phục vị trí GPS thật
    func clearSimulation() {
        isSimulating = false
        // Gọi FFI idevice_clear_location
        print("Đã khôi phục GPS thật của thiết bị.")
    }

    private func sendLocationToDevice(_ coord: CLLocationCoordinate2D) {
        // Gửi qua Rust FFI `idevice_set_location` tới DVT Instruments
        print("Gửi GPS DVT: \(coord.latitude), \(coord.longitude)")
    }

    private func createSilentAudioData() -> Data {
        // Tạo WAV header rỗng 44.1kHz stereo
        var header = [UInt8](repeating: 0, count: 44)
        header[0] = 0x52; header[1] = 0x49; header[2] = 0x46; header[3] = 0x46 // RIFF
        header[8] = 0x57; header[9] = 0x41; header[10] = 0x56; header[11] = 0x45 // WAVE
        header[12] = 0x66; header[13] = 0x6D; header[14] = 0x74; header[15] = 0x20 // fmt
        header[16] = 16; header[20] = 1; header[22] = 1 // PCM, 1 channel
        let sampleRate: UInt32 = 44100
        header[24] = UInt8(sampleRate & 0xFF)
        header[25] = UInt8((sampleRate >> 8) & 0xFF)
        header[34] = 16 // 16-bit
        header[36] = 0x64; header[37] = 0x61; header[38] = 0x74; header[39] = 0x61 // data
        let samples = [Int16](repeating: 0, count: 4410) // 0.1s im lặng
        var data = Data(header)
        samples.withUnsafeBufferPointer { data.append($0) }
        return data
    }
}
