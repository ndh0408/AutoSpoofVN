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
    /// Chặn đệ quy: `RouteSimulator.stop()` gọi ngược `stopSession()`, mà `stopSession()`
    /// lại gọi `RouteSimulator.stop()` để dừng thật sự.
    private var isTearingDown = false
    /// Toạ độ vừa gửi xuống legacy engine.
    ///
    /// `legacyEngine.$currentCoordinate` phát ngược lại chính giá trị ta vừa ghi. Không
    /// chặn tiếng vọng đó thì `currentCoordinate` (vị trí thật) bị ghi đè bằng bản đã
    /// nhiễu, và vòng lặp chuyển động lại tích phân từ đó.
    private var lastReportedCoordinate: CLLocationCoordinate2D?

    /// Tham chiếu tới SpoofEngine hiện tại để backward-compatible.
    /// Sẽ dần thay thế khi migrate xong.
    private let legacyEngine = SpoofEngine.shared

    private init() {
        // Đồng bộ state từ legacy engine trong giai đoạn chuyển tiếp
        syncFromLegacyEngine()
        // Khởi động CoordinateServer cho Shadowrocket MITM.
        //
        // Bỏ qua khi đang chạy kiểm thử: mỗi lần chạy test lại mở cổng 8765, mà tiến trình
        // của lần chạy trước có thể còn giữ cổng — khi đó test runner treo trước khi kết
        // nối được ("The test runner hung before establishing connection").
        if !Self.isRunningUnitTests {
            CoordinateServer.shared.start()
        }
    }

    /// Có đang chạy trong môi trường XCTest không.
    ///
    /// Dùng để tránh mở tài nguyên hệ thống (cổng mạng, timer nền) trong kiểm thử đơn vị.
    nonisolated static var isRunningUnitTests: Bool {
        NSClassFromString("XCTestCase") != nil
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

        // Bảo nguồn đang chạy tự dừng TRƯỚC khi nhả quyền — nếu nhả trước, nguồn vẫn
        // đang chạy sẽ lập tức `acquire` lại ở tick kế tiếp.
        teardownActiveSource()

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

    /// Dừng THẬT nguồn đang giữ quyền.
    ///
    /// `stopSession()` trước đây chỉ đổi state của coordinator rồi nhả quyền. Nhưng
    /// `FlightManager` và `RoutineManager` chạy timer RIÊNG và ghi toạ độ thẳng qua
    /// `SpoofEngine`, còn `RouteSimulator`/`ScenarioEngine` có Task riêng — không cái nào
    /// nghe theo state của coordinator. Nên bấm Dừng xong chúng vẫn tiếp tục chạy và
    /// tiếp tục ghi vị trí. Đó chính là lỗi "bấm huỷ không được".
    private func teardownActiveSource() {
        guard !isTearingDown else { return }
        isTearingDown = true
        defer { isTearingDown = false }

        switch activeSource {
        case .route:    RouteSimulator.shared.stop()
        case .scenario: ScenarioEngine.shared.stop()
        case .flight:   FlightManager.shared.stopFlight()
        case .routine:  RoutineManager.shared.stopAutoRoutine()
        case .replay:   ReplayEngine.shared.stop()
        case .manual, .none: break
        }
    }

    /// Dừng MỌI nguồn, kể cả nguồn không giữ quyền. Dùng cho `halt()`: người dùng đã bảo
    /// "trả GPS thật về", không nguồn nào được phép ghi tiếp.
    private func teardownAllSources() {
        guard !isTearingDown else { return }
        isTearingDown = true
        defer { isTearingDown = false }

        RouteSimulator.shared.stop()
        ScenarioEngine.shared.stop()
        ReplayEngine.shared.stop()
        FlightManager.shared.stopFlight()
        RoutineManager.shared.stopAutoRoutine()
    }

    /// Dừng hẳn — GPS trả về thật.
    func halt() {
        teardownAllSources()
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

        // Vị trí THẬT của mô phỏng — KHÔNG áp nhiễu.
        //
        // Đây là điểm mấu chốt: vòng lặp chuyển động lấy `currentCoordinate` làm điểm
        // xuất phát cho tick kế tiếp. Nếu ghi toạ độ đã nhiễu vào đây thì nhiễu không còn
        // là nhiễu nữa mà TÍCH LUỸ thành trôi thật — mỗi tick lệch thêm một chút và
        // đường đi lang thang khỏi tuyến. Nhiễu chỉ được áp lúc GỬI RA NGOÀI.
        currentCoordinate = coordinate

        // Update telemetry
        telemetry.coordinate = coordinate
        telemetry.speedKmh = speedKmh
        telemetry.headingDegrees = headingDegrees

        if let start = sessionStartDate {
            telemetry.elapsedTime = Date().timeIntervalSince(start)
        }
        session?.currentCoordinate = CoordinateCodable(coordinate)
        session?.currentSpeedKmh = speedKmh
        session?.currentHeadingDegrees = headingDegrees
        session?.elapsedSeconds = telemetry.elapsedTime

        // Track max speed
        if speedKmh > (session?.maxSpeedKmh ?? 0) {
            session?.maxSpeedKmh = speedKmh
        }

        // Chỉ tới đây mới áp nhiễu — đúng một lần, trên đường ra thiết bị.
        let reported = applyNoise(to: coordinate)
        lastReportedCoordinate = reported

        // Bridge: gửi xuống legacy engine → thiết bị.
        // Dùng `applyExactLocation` chứ không phải `setLocation`: `setLocation` sẽ jitter
        // THÊM một lần nữa bên trong SpoofEngine, thành nhiễu chồng nhiễu.
        legacyEngine.applyExactLocation(latitude: reported.latitude, longitude: reported.longitude)

        // Sync toạ độ tới CoordinateServer → Shadowrocket MITM đọc realtime
        CoordinateServer.shared.updateCoordinate(
            latitude: reported.latitude, longitude: reported.longitude,
            accuracy: Int(noiseConfig.radiusMeters * 10 + 10),
            speed: speedKmh, heading: headingDegrees
        )

        return true
    }

    /// Gắn mô tả cho phiên đang chạy (tên tuyến, tổng quãng đường).
    ///
    /// `session` là `private(set)` nên nguồn bên ngoài không ghi thẳng được — đây là
    /// đường chính thức để RouteSimulator/ScenarioEngine cho biết chúng đang chạy cái gì.
    func describeSession(routeName: String?, totalDistanceMeters: Double? = nil) {
        session?.routeName = routeName
        if let total = totalDistanceMeters {
            session?.distanceRemainingMeters = total
        }
    }

    /// Cập nhật tiến độ tuyến vào telemetry.
    ///
    /// Trước đây `telemetry.distanceTravelledMeters`, `distanceRemainingMeters`,
    /// `routeProgress` và `estimatedArrival` **không có ai ghi** — mọi ô số liệu liên quan
    /// trên giao diện vĩnh viễn bằng 0. Coordinator vẫn là nơi sở hữu telemetry; hàm này
    /// chỉ là đường để nguồn đang giữ quyền báo tiến độ về.
    func updateRouteProgress(travelledMeters: Double,
                             remainingMeters: Double,
                             progress: Double,
                             estimatedArrival: Date?) {
        telemetry.distanceTravelledMeters = travelledMeters
        telemetry.distanceRemainingMeters = remainingMeters
        telemetry.routeProgress = min(max(progress, 0), 1)
        telemetry.estimatedArrival = estimatedArrival

        session?.distanceTravelledMeters = travelledMeters
        session?.distanceRemainingMeters = remainingMeters
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
                // Bỏ qua tiếng vọng của chính mình: nếu đây đúng là toạ độ ta vừa gửi
                // xuống thì nhận lại sẽ ghi bản ĐÃ NHIỄU đè lên vị trí thật, và tick sau
                // của vòng lặp chuyển động sẽ xuất phát từ điểm lệch đó.
                if let sent = self.lastReportedCoordinate,
                   abs(sent.latitude - coord.latitude) < 1e-9,
                   abs(sent.longitude - coord.longitude) < 1e-9 {
                    return
                }
                // Còn lại là Flight/Routine ghi thẳng qua SpoofEngine — nguồn thật sự.
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
