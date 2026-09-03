import Foundation
import AVFoundation
import CoreLocation

/// Giữ tiến trình sống khi app ở nền.
///
/// Dùng hai chân độc lập, vì một chân không đủ:
///
/// 1. **Audio im lặng** — phát vòng lặp một file WAV toàn mẫu 0 dưới background mode
///    `audio`. Đây là chân chính giữ tiến trình chạy liên tục.
/// 2. **Cập nhật vị trí nền** — `CLLocationManager` với `allowsBackgroundLocationUpdates`.
///    Trước đây `Info.plist` khai background mode `location` mà không có
///    `CLLocationManager` nào, nên khai báo đó vừa vô tác dụng vừa là rủi ro bị từ chối.
///    Quan trọng hơn: đây là **cơ chế duy nhất iOS cho phép app được đánh thức lại**
///    sau khi bị hệ thống thu hồi. Audio không có cơ chế tương đương.
///
/// Không chân nào là bảo đảm. Apple không cam kết background mode `audio` giữ app sống,
/// và sau khi người dùng vuốt tắt app hay máy khởi động lại thì không có gì tự chạy lại.
final class BackgroundKeeper: NSObject, ObservableObject {
    static let shared = BackgroundKeeper()

    @Published private(set) var isAudioRunning: Bool = false
    @Published private(set) var audioError: String? = nil
    @Published private(set) var isLocationUpdating: Bool = false
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    /// Số lần audio bị gián đoạn rồi được khôi phục. Hữu ích khi chẩn đoán tại sao
    /// một phiên 24/7 chết giữa chừng.
    @Published private(set) var interruptionCount: Int = 0

    private var player: AVAudioPlayer?
    private let locationManager = CLLocationManager()
    private var isStarted = false

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        locationManager.distanceFilter = 1000
        locationManager.pausesLocationUpdatesAutomatically = false
        authorizationStatus = locationManager.authorizationStatus

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMediaServicesReset),
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    // MARK: - Vòng đời

    @discardableResult
    func start() -> Bool {
        isStarted = true
        startAudio()
        startLocation()
        return isAudioRunning
    }

    func stop() {
        isStarted = false
        player?.stop()
        player = nil
        isAudioRunning = false
        locationManager.stopUpdatingLocation()
        locationManager.allowsBackgroundLocationUpdates = false
        isLocationUpdating = false
        DispatchQueue.global(qos: .userInitiated).async {
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }

    // MARK: - Audio

    private func startAudio() {
        // Dispatch audio setup off main thread — AVAudioSession.setActive blocks
        // briefly và iOS 18 cảnh báo nếu gọi trên main thread.
        // Chu thich kieu ro rang: neu khong, `self?.configureAndPlayAudio()` suy ra closure
        // tra ve `Void?` (khong phai `Void`), khien DispatchQueue.async(execute:) chon nham
        // overload nhan DispatchWorkItem thay vi @escaping () -> Void.
        let work: () -> Void = { [weak self] in
            self?.configureAndPlayAudio()
        }
        if Thread.isMainThread {
            DispatchQueue.global(qos: .userInitiated).async(execute: work)
        } else {
            work()
        }
    }

    private func configureAndPlayAudio() {
        do {
            let session = AVAudioSession.sharedInstance()
            // .mixWithOthers để không cướp audio của app khác; đổi lại phiên dễ bị thu hồi hơn,
            // nên phải có observer gián đoạn ở dưới.
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            let player = try AVAudioPlayer(data: SpoofEngine.makeSilentWavData(seconds: 1.0))
            player.numberOfLoops = -1
            player.volume = 0.01
            player.prepareToPlay()
            let started = player.play()
            self.player = player
            isAudioRunning = started
            audioError = started ? nil : "AVAudioPlayer.play() trả về false"
        } catch {
            player = nil
            isAudioRunning = false
            audioError = error.localizedDescription
        }
    }

    /// Sau một cuộc gọi, Siri, hoặc báo thức, iOS dừng phiên âm thanh và **không** tự chạy lại.
    /// Không có observer này thì app im lặng chết sau lần gián đoạn đầu tiên.
    @objc private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }

        switch type {
        case .began:
            isAudioRunning = false
        case .ended:
            guard isStarted else { return }
            interruptionCount += 1
            // Chờ một nhịp: khôi phục ngay lập tức thường bị hệ thống từ chối.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self, self.isStarted else { return }
                self.startAudio()
            }
        @unknown default:
            break
        }
    }

    /// Media daemon bị khởi động lại: mọi AVAudioPlayer cũ thành vô hiệu, phải dựng lại từ đầu.
    @objc private func handleMediaServicesReset() {
        guard isStarted else { return }
        player = nil
        isAudioRunning = false
        startAudio()
    }

    // MARK: - Vị trí

    /// Chỉ bật cập nhật nền khi quyền ĐÃ được cấp.
    ///
    /// Cố tình không tự xin quyền ở đây: `start()` chạy ngay lúc mở app, và bật hộp thoại
    /// quyền vị trí trước khi người dùng đọc được một dòng giải thích nào là cách chắc
    /// chắn nhất để bị từ chối. Việc xin quyền thuộc về màn hình hướng dẫn — gọi
    /// `requestLocationPermission()`.
    private func startLocation() {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            enableBackgroundLocation()
        default:
            isLocationUpdating = false
        }
    }

    /// Xin quyền vị trí Luôn luôn. Gọi từ màn hình hướng dẫn, khi người dùng đã hiểu vì sao.
    ///
    /// Trả về `false` nếu quyền đã bị từ chối trước đó — khi ấy hộp thoại sẽ không hiện
    /// lại được nữa và người dùng phải tự vào Settings.
    @discardableResult
    func requestLocationPermission() -> Bool {
        switch locationManager.authorizationStatus {
        case .notDetermined, .authorizedWhenInUse:
            locationManager.requestAlwaysAuthorization()
            return true
        case .authorizedAlways:
            enableBackgroundLocation()
            return true
        default:
            return false
        }
    }

    /// Quyền đã bị từ chối hẳn: hộp thoại không hiện lại được, phải mở Settings.
    var needsSettingsForLocation: Bool {
        switch locationManager.authorizationStatus {
        case .denied, .restricted: return true
        default: return false
        }
    }

    private func enableBackgroundLocation() {
        // Chỉ đặt được khi Info.plist khai background mode `location`, nếu không sẽ ném exception.
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.startUpdatingLocation()
        // Cho phép iOS đánh thức lại app sau khi thu hồi.
        locationManager.startMonitoringSignificantLocationChanges()
        isLocationUpdating = true
    }
}

extension BackgroundKeeper: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        guard isStarted else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            enableBackgroundLocation()
        default:
            isLocationUpdating = false
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Cố tình bỏ qua. Vị trí thật không được dùng làm gì; việc đăng ký cập nhật chỉ để
        // giữ app sống và cho iOS một lý do đánh thức lại.
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Không tắt isLocationUpdating: lỗi tạm thời (mất tín hiệu) là bình thường và
        // CoreLocation sẽ tự thử lại.
        AppLogger.background.info("[BackgroundKeeper] CoreLocation lỗi: \(error.localizedDescription)")
    }
}
