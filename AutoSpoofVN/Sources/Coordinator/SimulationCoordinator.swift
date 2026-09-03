import Combine
import CoreLocation
import Foundation

/// Bộ điều phối trung tâm — MỘT nguồn sự thật duy nhất cho toàn bộ mô phỏng GPS.
///
/// Mọi module (Route, Scenario, Routine, Flight, Manual, Replay) gửi coordinate
/// thông qua Coordinator. Coordinator sở hữu session, arbitrate source, throttle
/// device update, và phát telemetry cho UI.
///
/// ```
/// Source → SimulationCoordinator → SimulationEngine → DeviceTransport → DVT
/// ```
@MainActor
final class SimulationCoordinator: ObservableObject {
    static let shared = SimulationCoordinator()

    // MARK: - Published State

    @Published private(set) var state: SimulationState = .idle
    @Published private(set) var activeSource: SimulationSource? = nil
    @Published private(set) var session: SimulationSession? = nil
    @Published private(set) var telemetry = SimulationTelemetry()
    @Published private(set) var deviceState: DeviceConnectionState = .disconnected
    @Published private(set) var health = SystemHealth()

    /// Coordinate hiện tại — UI đọc trực tiếp từ đây.
    @Published var currentCoordinate: CLLocationCoordinate2D = CLLocationCoordinate2D(
        latitude: 21.0285, longitude: 105.8542  // Hoàn Kiếm, Hà Nội
    )

    /// GPS noise config — có thể thay đổi runtime.
    @Published var noiseConfig: GPSNoiseConfig = .normal

    /// Tốc độ mô phỏng — hệ số nhân thời gian.
    @Published var timeMultiplier: Double = 1.0

    /// Cờ dừng hẳn — giữ GPS thật cho đến khi user chủ động bắt đầu lại.
    @Published private(set) var isHalted: Bool = false

    // MARK: - Private

    private var sessionStartDate: Date?
    private var jitterOffsetNorth: Double = 0
    private var jitterOffsetEast: Double = 0
    private var deviceUpdateTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    /// Tham chiếu tới SpoofEngine hiện tại để backward-compatible.
    /// Sẽ dần thay thế khi migrate xong.
    private let legacyEngine = SpoofEngine.shared

    private init() {
        // Đồng bộ state từ legacy engine trong giai đoạn chuyển tiếp
        syncFromLegacyEngine()
        // Khởi động CoordinateServer cho Shadowrocket MITM
        CoordinateServer.shared.start()
    }

    // MARK: - Source Arbitration

    /// Đăng ký quyền điều khiển GPS cho một source.
    /// Trả về false nếu source ưu tiên cao hơn đang giữ quyền.
    @discardableResult
    func acquire(_ source: SimulationSource) -> Bool {
        if let holder = activeSource, holder != source, holder.priority > source.priority {
            return false
        }
        isHalted = false
        activeSource = source
        // Bridge sang legacy
        if let legacy = legacySpoofSource(source) {
            legacyEngine.acquire(legacy)
        }
        return true
    }

    /// Trả lại quyền. Chỉ có tác dụng nếu chính source đó đang giữ.
    func release(_ source: SimulationSource) {
        guard activeSource == source else { return }
        activeSource = nil
        if let legacy = legacySpoofSource(source) {
            legacyEngine.release(legacy)
        }
    }

    // MARK: - Session Lifecycle

    func startSession(source: SimulationSource, travelMode: TravelMode = .driving) -> SimulationSession {
        // Dừng session cũ nếu đang chạy
        if session?.status == .running || session?.status == .paused {
            stopSession()
        }

        var newSession = SimulationSession(source: source, travelMode: travelMode)
        newSession.noiseConfig = noiseConfig
        newSession.startCoordinate = CoordinateCodable(currentCoordinate)
        newSession.status = .preparing

        session = newSession
        state = .preparing
        sessionStartDate = Date()

        guard acquire(source) else {
            newSession.status = .failed("Nguồn ưu tiên cao hơn đang hoạt động")
            session = newSession
            state = .failed("Nguồn ưu tiên cao hơn đang hoạt động")
            return newSession
        }

        newSession.status = .running
        newSession.startedAt = Date()
        session = newSession
        state = .running

        // Auto-trigger Shadowrocket VPN khi bắt đầu simulation
        ShadowrocketManager.shared.ensureVPNActive()

        startDeviceUpdateTimer()
        return newSession
    }

    func pauseSession() {
        guard state == .running else { return }
        state = .paused
        session?.status = .paused
        stopDeviceUpdateTimer()
    }

    func resumeSession() {
        guard state == .paused else { return }
        state = .running
        session?.status = .running
        startDeviceUpdateTimer()
    }

    func stopSession() {
        guard state.canStop || state == .running || state == .paused else { return }

        state = .stopping
        session?.status = .stopping

        // Clear device location
        legacyEngine.clearDeviceLocation()

        if let source = activeSource {
            release(source)
        }

        session?.endedAt = Date()
        session?.endCoordinate = CoordinateCodable(currentCoordinate)
        session?.status = .completed
        state = .idle

        stopDeviceUpdateTimer()
        telemetry = SimulationTelemetry()
    }

    /// Dừng hẳn — GPS trả về thật.
    func halt() {
        stopSession()
        isHalted = true
        legacyEngine.haltSimulation()
    }

    // MARK: - Coordinate Submission

    /// Gửi coordinate mới từ bất kỳ source nào.
    /// Đây là hàm duy nhất ghi coordinate vào device.
    @discardableResult
    func submit(coordinate: CLLocationCoordinate2D, from source: SimulationSource,
                speedKmh: Double = 0, headingDegrees: Double = 0) -> Bool {
        guard !isHalted else { return false }
        guard acquire(source) else { return false }

        let noisy = applyNoise(to: coordinate)
        currentCoordinate = noisy

        // Update telemetry
        telemetry.coordinate = noisy
        telemetry.speedKmh = speedKmh
        telemetry.headingDegrees = headingDegrees

        if let start = sessionStartDate {
            telemetry.elapsedTime = Date().timeIntervalSince(start)
        }
        session?.currentCoordinate = CoordinateCodable(noisy)
        session?.currentSpeedKmh = speedKmh
        session?.currentHeadingDegrees = headingDegrees
        session?.elapsedSeconds = telemetry.elapsedTime

        // Track max speed
        if speedKmh > (session?.maxSpeedKmh ?? 0) {
            session?.maxSpeedKmh = speedKmh
        }

        // Bridge: gửi xuống legacy engine → FFI → device
        legacyEngine.setLocation(latitude: noisy.latitude, longitude: noisy.longitude)

        // Sync toạ độ tới CoordinateServer → Shadowrocket MITM đọc realtime
        CoordinateServer.shared.updateCoordinate(
            latitude: noisy.latitude, longitude: noisy.longitude,
            accuracy: Int(noiseConfig.radiusMeters * 10 + 10),
            speed: speedKmh, heading: headingDegrees
        )

        return true
    }

    /// Đặt vị trí thủ công — luôn thắng mọi source.
    func setManualLocation(_ coordinate: CLLocationCoordinate2D) {
        if state == .idle {
            _ = startSession(source: .manual)
        }
        submit(coordinate: coordinate, from: .manual)
    }

    // MARK: - Noise

    private func applyNoise(to coord: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard noiseConfig.enabled, noiseConfig.radiusMeters > 0 else { return coord }

        let kick = noiseConfig.radiusMeters * 0.55
        jitterOffsetNorth = jitterOffsetNorth * noiseConfig.inertia + Double.random(in: -kick...kick)
        jitterOffsetEast = jitterOffsetEast * noiseConfig.inertia + Double.random(in: -kick...kick)

        let radius = hypot(jitterOffsetNorth, jitterOffsetEast)
        if radius > noiseConfig.radiusMeters, radius > 0 {
            let scale = noiseConfig.radiusMeters / radius
            jitterOffsetNorth *= scale
            jitterOffsetEast *= scale
        }

        var lat = coord.latitude
        var lon = coord.longitude
        let cosLat = cos(lat * .pi / 180.0)
        let lonScale = abs(cosLat) < 1e-6 ? 1e-6 : abs(cosLat)
        lat += jitterOffsetNorth / 111_320.0
        lon += jitterOffsetEast / (111_320.0 * lonScale)

        lat = min(max(lat, -90), 90)
        if lon > 180 { lon -= 360 }
        if lon < -180 { lon += 360 }

        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    // MARK: - Device Update Timer

    private func startDeviceUpdateTimer() {
        stopDeviceUpdateTimer()
        // Heartbeat: gửi lại coordinate mỗi 20s để DVT không drop session
        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state == .running else { return }
                self.legacyEngine.sendLocationToDevice(self.currentCoordinate)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        deviceUpdateTimer = timer
    }

    private func stopDeviceUpdateTimer() {
        deviceUpdateTimer?.invalidate()
        deviceUpdateTimer = nil
    }

    // MARK: - Legacy Bridge

    private func legacySpoofSource(_ source: SimulationSource) -> SpoofSource? {
        switch source {
        case .manual: return .manual
        case .flight: return .flight
        case .routine: return .routine
        default: return .manual  // Route, Scenario, Replay map sang manual cho legacy
        }
    }

    private func syncFromLegacyEngine() {
        legacyEngine.$currentCoordinate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] coord in
                guard let self else { return }
                self.currentCoordinate = coord
                self.telemetry.coordinate = coord
                // Sync tới CoordinateServer cho Shadowrocket — cover cả
                // FlightManager và RoutineManager gửi trực tiếp qua SpoofEngine
                CoordinateServer.shared.updateCoordinate(
                    latitude: coord.latitude,
                    longitude: coord.longitude,
                    accuracy: Int(self.noiseConfig.radiusMeters * 10 + 10),
                    speed: self.telemetry.speedKmh,
                    heading: self.telemetry.headingDegrees
                )
            }
            .store(in: &cancellables)

        // Sync isSimulating → cập nhật state
        legacyEngine.$isSimulating
            .receive(on: DispatchQueue.main)
            .sink { [weak self] simulating in
                guard let self else { return }
                if simulating && self.state == .idle {
                    // FlightManager hoặc RoutineManager bắt đầu mô phỏng
                    if self.activeSource == nil {
                        if FlightManager.shared.isFlying {
                            self.activeSource = .flight
                        } else if RoutineManager.shared.isAutoRoutineEnabled {
                            self.activeSource = .routine
                        }
                    }
                    self.state = .running
                } else if !simulating && self.state == .running && self.activeSource != .route && self.activeSource != .scenario {
                    self.state = .idle
                    self.activeSource = nil
                }
            }
            .store(in: &cancellables)

        // Sync speed từ FlightManager
        FlightManager.shared.$activeFlight
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] sim in
                self?.telemetry.speedKmh = sim.currentSpeedKmh
                self?.telemetry.altitudeMeters = sim.altitudeMeters
            }
            .store(in: &cancellables)

        // Sync speed từ RoutineManager
        RoutineManager.shared.$currentSpeedKmh
            .receive(on: DispatchQueue.main)
            .sink { [weak self] speed in
                if !(FlightManager.shared.isFlying) {
                    self?.telemetry.speedKmh = speed
                }
            }
            .store(in: &cancellables)

        legacyEngine.$isLoopbackConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in
                if connected {
                    self?.deviceState = .connected(transport: "DVT")
                    self?.health.device = .healthy
                    self?.health.transport = .healthy
                } else {
                    self?.deviceState = .disconnected
                    self?.health.device = .unknown
                    self?.health.transport = .unknown
                }
            }
            .store(in: &cancellables)

        legacyEngine.$connectionStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                if status.contains("thất bại") || status.contains("Lỗi") {
                    self?.deviceState = .error(status)
                    self?.health.transport = .error
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Diagnostics

    func runDiagnostics() -> [(String, SystemHealth.Status, String)] {
        var results: [(String, SystemHealth.Status, String)] = []

        // Device
        results.append((
            "Thiết bị",
            deviceState.isConnected ? .healthy : .warning,
            deviceState.displayName
        ))

        // Transport
        results.append((
            "Transport",
            legacyEngine.isLoopbackConnected ? .healthy : .error,
            legacyEngine.isLoopbackConnected ? "DVT hoạt động" : "Chưa kết nối DVT"
        ))

        // Background
        let keeper = BackgroundKeeper.shared
        results.append((
            "Chạy nền",
            keeper.isAudioRunning ? .healthy : .warning,
            keeper.isAudioRunning ? "Audio keep-alive đang chạy" : (keeper.audioError ?? "Chưa khởi động")
        ))

        // Simulation
        results.append((
            "Mô phỏng",
            state.isActive ? .healthy : .unknown,
            state.displayName
        ))

        // Live Activity
        results.append((
            "Live Activity",
            .unknown,
            "Kiểm tra ActivityKit"
        ))

        return results
    }
}
