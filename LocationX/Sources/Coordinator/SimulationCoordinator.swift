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
    /// Nhịp gửi lại toạ độ xuống thiết bị (giây). Đổi được từ Cài đặt.
    private var deviceUpdateInterval: TimeInterval = 20
    private var cancellables = Set<AnyCancellable>()
    /// Chặn đệ quy: `RouteSimulator.stop()` gọi ngược `stopSession()`, mà `stopSession()`
    /// lại gọi `RouteSimulator.stop()` để dừng thật sự.
    private var isTearingDown = false
    /// Toạ độ vừa gửi xuống legacy engine.
    ///
    /// `legacyEngine.$currentCoordinate` phát ngược lại chính giá trị ta vừa ghi. Không
    /// chặn tiếng vọng đó thì `currentCoordinate` (vị trí thật) bị ghi đè bằng bản đã
    /// nhiễu, và vòng lặp chuyển động lại tích phân từ đó.
    /// Toạ độ thực sự đã báo ra ngoài — bằng toạ độ mô phỏng cộng phần nhiễu.
    ///
    /// Màn Chẩn đoán hiển thị cả hai để phân biệt "nhiễu" với "sai".
    private(set) var lastReportedCoordinate: CLLocationCoordinate2D?

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
            newSession.status = .failed(L("error.higher_priority_source"))
            session = newSession
            state = .failed(L("error.higher_priority_source"))
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

    /// Đặt nhịp gửi lại toạ độ xuống thiết bị. Áp ngay nếu timer đang chạy.
    ///
    /// Trước đây con số 20 giây bị viết cứng, nên tuỳ chọn "tần số cập nhật thiết bị"
    /// trong Cài đặt hoàn toàn không có tác dụng.
    func setDeviceUpdateInterval(_ seconds: TimeInterval) {
        let clamped = min(60, max(0.2, seconds))
        guard clamped != deviceUpdateInterval else { return }
        deviceUpdateInterval = clamped
        if deviceUpdateTimer != nil { startDeviceUpdateTimer() }
    }

    private func startDeviceUpdateTimer() {
        stopDeviceUpdateTimer()
        // Làm tươi lại ảnh chụp mà CoordinateServer phục vụ, kể cả khi đứng yên.
        //
        // Trước đây timer này gọi `sendLocationToDevice`, mà sau khi bỏ FFI đó là một hàm
        // rỗng — nên "nhịp gửi thiết bị" trong Cài đặt điều khiển một timer không làm gì cả.
        let timer = Timer(timeInterval: deviceUpdateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state == .running else { return }
                let c = self.lastReportedCoordinate ?? self.currentCoordinate
                CoordinateServer.shared.updateCoordinate(
                    latitude: c.latitude,
                    longitude: c.longitude,
                    speed: self.telemetry.speedKmh / 3.6,
                    heading: self.telemetry.headingDegrees)
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
                // Bac ca huong bay — thieu dong nay thi moi man hinh hien "0 B" khi bay.
                self?.telemetry.headingDegrees = sim.headingDegrees
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

        // Trang thai "duong truyen" bam vao Shadowrocket, khong phai DVT nua.
        //
        // Sau khi bo FFI, `isLoopbackConnected` khong bao gio thanh true, nen thanh trang
        // thai bao "chua ket noi" vinh vien va chan doan luon bao loi — ke ca luc viec
        // gia lap dang chay hoan hao. Nguon su that bay gio la ShadowrocketManager: no
        // biet app da cai chua, module import chua, VPN bat chua, va — quan trong nhat —
        // MITM co that su fetch script gan day khong.
        let shadowrocket = ShadowrocketManager.shared
        Publishers.CombineLatest4(shadowrocket.$isInstalled,
                                  shadowrocket.$isModuleImported,
                                  shadowrocket.$isVPNActive,
                                  shadowrocket.$isServerRunning)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] installed, imported, vpn, server in
                guard let self else { return }
                self.deviceState = Self.pipelineState(installed: installed,
                                                      imported: imported,
                                                      vpnActive: vpn,
                                                      serverRunning: server)
                switch self.deviceState {
                case .connected:
                    self.health.device = .healthy
                    self.health.transport = .healthy
                case .connecting:
                    self.health.device = .warning
                    self.health.transport = .warning
                case .error:
                    self.health.device = .error
                    self.health.transport = .error
                case .disconnected:
                    self.health.device = .unknown
                    self.health.transport = .unknown
                }
            }
            .store(in: &cancellables)
    }

    /// Suy ra trang thai duong truyen tu bon tin hieu cua Shadowrocket.
    ///
    /// Tach thanh ham thuan tuy `static` de kiem thu duoc ma khong can dung ca mot
    /// pipeline that.
    nonisolated static func pipelineState(installed: Bool,
                                          imported: Bool,
                                          vpnActive: Bool,
                                          serverRunning: Bool) -> DeviceConnectionState {
        // `.error` chi danh cho hong hoc CUA CHINH APP.
        //
        // Chua cai Shadowrocket la mot BUOC THIET LAP chua lam, khong phai loi — dan
        // huy hieu do "Loi" vao do la doi ten mot viec con phai lam thanh mot su co, va
        // banner ngay ben duoi da noi ro can cai gi roi.
        guard serverRunning else { return .error(L("pipeline.error.server_down")) }
        guard installed, imported else { return .disconnected }
        return vpnActive ? .connected(transport: "Shadowrocket") : .connecting
    }

    // MARK: - Diagnostics

    func runDiagnostics() -> [(String, SystemHealth.Status, String)] {
        var results: [(String, SystemHealth.Status, String)] = []
        let shadowrocket = ShadowrocketManager.shared

        results.append((
            L("diagnostics.item.server"),
            CoordinateServer.shared.isRunning ? .healthy : .error,
            CoordinateServer.shared.isRunning
                ? L("diagnostics.server.listening", Int(CoordinateServer.shared.port))
                : L("diagnostics.server.down")
        ))

        results.append((
            L("diagnostics.item.shadowrocket"),
            shadowrocket.isInstalled ? .healthy : .error,
            shadowrocket.isInstalled ? L("common.installed") : L("common.not_installed")
        ))

        results.append((
            L("diagnostics.item.module"),
            shadowrocket.isModuleImported ? .healthy : .warning,
            shadowrocket.isModuleImported ? L("common.imported") : L("common.not_imported")
        ))

        results.append((
            L("diagnostics.item.vpn"),
            shadowrocket.isVPNActive ? .healthy : .warning,
            shadowrocket.isVPNActive ? L("common.on") : L("common.off")
        ))

        // Bang chung truc tiep, khong phai suy doan: MITM co dang fetch script khong.
        results.append((
            L("diagnostics.item.mitm"),
            shadowrocket.isPipelineFresh ? .healthy : .warning,
            shadowrocket.isPipelineFresh
                ? L("diagnostics.mitm.fresh", shadowrocket.lastRequestCount)
                : L("diagnostics.mitm.stale")
        ))

        results.append((
            L("diagnostics.item.simulation"),
            state.isActive ? .healthy : .unknown,
            state.displayName
        ))

        results.append((
            L("diagnostics.item.background"),
            BackgroundKeeper.shared.isAudioRunning ? .healthy : .warning,
            BackgroundKeeper.shared.isAudioRunning ? L("common.running") : L("common.off")
        ))

        return results
    }
}
