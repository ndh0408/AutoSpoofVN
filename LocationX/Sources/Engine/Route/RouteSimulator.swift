import CoreLocation
import Foundation

/// Chạy mô phỏng dọc theo một tuyến đường đã tính toán.
/// Sở hữu MotionEngine riêng, báo cáo coordinate lên SimulationCoordinator.
///
/// **Phai dung qua `RouteSimulator.shared`.** Ban truoc de UI tu tao instance cuc bo
/// (`let simulator = RouteSimulator()`), nen doi tuong bi giai phong ngay khi ham tao no
/// tra ve: vong lap 10 Hz capture `[weak self]` thay `self == nil` va thoat lap tuc.
/// Ket qua la `startSession(.route)` DA chay (session `.running`, timer thiet bi bat,
/// VPN Shadowrocket kich hoat) nhung khong mot toa do nao duoc gui, va khong ai goi
/// `stopSession()`. Tinh nang tuyen duong chet ngay tu dau ma khong bao loi.
@MainActor
final class RouteSimulator: ObservableObject {
    static let shared = RouteSimulator()

    @Published private(set) var isRunning = false
    /// Tach rieng khoi `isRunning`: dang tam dung thi khong chay, nhung van con tuyen
    /// de tiep tuc — khac han voi da dung han.
    @Published private(set) var isPaused = false
    @Published private(set) var progress: Double = 0  // 0.0 - 1.0
    @Published private(set) var currentSegmentIndex: Int = 0
    @Published private(set) var distanceTravelled: Double = 0
    @Published private(set) var distanceRemaining: Double = 0
    @Published private(set) var eta: Date? = nil
    /// Ten tuyen dang chay, de UI hien duoc "dang chay tuyen nao".
    @Published private(set) var activeRouteName: String? = nil
    /// Id cua tuyen da luu dang chay. Danh sach tuyen dua vao day de biet the nao dang
    /// hoat dong — so sanh bang ten khong an toan vi ten co the trung.
    @Published private(set) var activeRouteID: UUID? = nil
    /// Ly do dung bat thuong gan nhat (bi gianh quyen, bi chan vi halt...).
    @Published private(set) var lastFailure: String? = nil

    private var routeCoordinates: [CLLocationCoordinate2D] = []
    /// Quang duong cong don tu diem dau toi tung diem. `cumulative[0] == 0`.
    ///
    /// Tinh MOT lan luc bat dau. Ban truoc goi `totalRouteDistance()` va
    /// `distanceFromIndex()` — moi ham duyet ca mang — bon lan trong MOI tick 10 Hz.
    /// Voi tuyen resample toi 20.000 diem, do la hang tram nghin phep haversine moi giay
    /// tren main actor.
    private var cumulativeDistances: [CLLocationDistance] = []
    private var currentIndex: Int = 0
    private var travelMode: TravelMode = .driving
    private var simulationTask: Task<Void, Never>?
    private let motionEngine = MotionEngine()
    private var headingEngine = HeadingEngine()
    private let coordinator = SimulationCoordinator.shared

    /// Tick rate — mô phỏng chạy ở tần số này. Mặc định 10 Hz, đổi được từ Cài đặt.
    private var tickInterval: TimeInterval = 0.1

    /// Đặt tần số tick. Có hiệu lực từ vòng lặp kế tiếp.
    ///
    /// Trước đây 0.1 s bị viết cứng nên tuỳ chọn "tần số mô phỏng" trong Cài đặt là công
    /// tắc giả.
    func setTickInterval(_ seconds: TimeInterval) {
        tickInterval = min(1.0, max(0.02, seconds))
    }

    private init() {}

    /// Ly do vong lap ket thuc. Phan biet ro "di het tuyen" voi "bi dung giua chung" —
    /// ban truoc gop chung lam mot nen tam dung bi bao la hoan thanh 100%.
    private enum LoopExit {
        case completed
        case paused
        case cancelled
        /// `coordinator.submit` tra ve false: dang bi halt hoac mot nguon uu tien cao hon
        /// da gianh quyen.
        case preempted
    }

    var totalDistance: CLLocationDistance { cumulativeDistances.last ?? 0 }

    /// Con tuyen de tiep tuc hay khong.
    var hasActiveRoute: Bool { routeCoordinates.count >= 2 }

    // MARK: - Lifecycle

    /// Bắt đầu mô phỏng trên tuyến đường cho trước.
    @discardableResult
    func start(coordinates: [CLLocationCoordinate2D],
               travelMode: TravelMode = .driving,
               routeName: String? = nil,
               routeID: UUID? = nil) -> Bool {
        let valid = coordinates.filter { CLLocationCoordinate2DIsValid($0) }
        guard valid.count >= 2 else {
            lastFailure = "Tuyến đường cần ít nhất hai điểm hợp lệ."
            return false
        }
        stop()

        routeCoordinates = valid
        cumulativeDistances = Self.cumulativeDistances(of: valid)
        currentIndex = 0
        distanceTravelled = 0
        distanceRemaining = totalDistance
        progress = 0
        eta = nil
        lastFailure = nil
        activeRouteName = routeName
        activeRouteID = routeID
        self.travelMode = travelMode
        isPaused = false
        isRunning = true

        let profile = travelMode.defaultSpeed
        Task { await motionEngine.setSpeedProfile(profile) }

        _ = coordinator.startSession(source: .route, travelMode: travelMode)
        coordinator.describeSession(routeName: routeName, totalDistanceMeters: totalDistance)

        // Dat vi tri xuat phat ngay, khong doi tick dau tien.
        coordinator.submit(coordinate: valid[0], from: .route, speedKmh: 0,
                           headingDegrees: MotionEngine.bearing(from: valid[0], to: valid[1]))

        launchLoop()
        return true
    }

    func pause() {
        guard isRunning else { return }
        isRunning = false
        isPaused = true
        // Huy task TRUOC khi doi trang thai coordinator, de vong lap khong kip ghi them.
        simulationTask?.cancel()
        simulationTask = nil
        coordinator.pauseSession()
    }

    func resume() {
        guard isPaused, hasActiveRoute else { return }
        isPaused = false
        isRunning = true
        lastFailure = nil
        coordinator.resumeSession()
        launchLoop()
    }

    func stop() {
        simulationTask?.cancel()
        simulationTask = nil
        isRunning = false
        isPaused = false
        activeRouteName = nil
        activeRouteID = nil
        routeCoordinates = []
        cumulativeDistances = []
        currentIndex = 0
        coordinator.stopSession()
        Task { await motionEngine.reset() }
        headingEngine.reset()
    }

    /// Seek to a specific progress point (0.0 - 1.0)
    func seek(to progress: Double) {
        guard hasActiveRoute else { return }
        let clamped = min(max(progress, 0), 1)
        let targetIndex = Int(Double(routeCoordinates.count - 1) * clamped)
        currentIndex = targetIndex
        self.progress = clamped
        distanceTravelled = cumulativeDistances[safe: targetIndex] ?? 0
        distanceRemaining = max(0, totalDistance - distanceTravelled)
        if let coord = routeCoordinates[safe: targetIndex] {
            coordinator.submit(coordinate: coord, from: .route)
            publishProgress()
        }
    }

    // MARK: - Simulation Loop

    private func launchLoop() {
        simulationTask = Task { [weak self] in
            guard let self else { return }
            let exit = await self.runSimulationLoop()
            await self.handle(exit: exit)
        }
    }

    private func runSimulationLoop() async -> LoopExit {
        while currentIndex < routeCoordinates.count - 1 {
            if Task.isCancelled { return isPaused ? .paused : .cancelled }
            guard isRunning else { return isPaused ? .paused : .cancelled }

            let current = coordinator.currentCoordinate
            let target = routeCoordinates[currentIndex + 1]
            let remainingOnRoute = max(0, totalDistance - (cumulativeDistances[safe: currentIndex + 1] ?? totalDistance))

            let result = await motionEngine.nextPosition(
                from: current,
                toward: target,
                deltaTime: tickInterval * coordinator.timeMultiplier,
                distanceToEnd: remainingOnRoute
            )

            if Task.isCancelled { return isPaused ? .paused : .cancelled }

            let heading = headingEngine.update(with: result.coordinate)

            // Ban truoc bo qua gia tri tra ve. Khi bi halt hoac bi gianh quyen, submit tra
            // ve false mai mai ma vong lap van quay 10 Hz vo tan, dot CPU va khong bao gi.
            let accepted = coordinator.submit(
                coordinate: result.coordinate,
                from: .route,
                speedKmh: result.speedKmh,
                headingDegrees: heading
            )
            guard accepted else { return .preempted }

            distanceTravelled += result.distanceMoved
            distanceRemaining = max(0, totalDistance - distanceTravelled)
            progress = totalDistance > 0 ? min(1, distanceTravelled / totalDistance) : 0
            currentSegmentIndex = currentIndex

            if result.speedKmh > 0.1 {
                let remainingHours = (distanceRemaining / 1000) / result.speedKmh
                eta = Date().addingTimeInterval(remainingHours * 3600)
            }

            publishProgress()

            if result.reachedTarget {
                currentIndex += 1
            }

            try? await Task.sleep(nanoseconds: UInt64(tickInterval * 1_000_000_000))
        }
        return .completed
    }

    private func handle(exit: LoopExit) {
        switch exit {
        case .completed:
            isRunning = false
            isPaused = false
            progress = 1.0
            distanceRemaining = 0
            publishProgress()
            coordinator.stopSession()
            activeRouteName = nil
            activeRouteID = nil

        case .preempted:
            isRunning = false
            isPaused = false
            lastFailure = coordinator.isHalted
                ? "Đã dừng vì GPS thật được khôi phục."
                : "Một nguồn ưu tiên cao hơn đã giành quyền điều khiển."
            // KHONG goi stopSession(): nguon kia dang so huu phien, dung se cat phien cua ho.
            activeRouteName = nil
            activeRouteID = nil

        case .paused, .cancelled:
            break  // pause()/stop() da dat trang thai roi
        }
    }

    /// Day tien do tuyen len coordinator de telemetry co "Đã đi / Còn lại / Tiến độ / ETA".
    /// Truoc day khong ai ghi cac truong nay nen chung luon bang 0 tren giao dien.
    private func publishProgress() {
        coordinator.updateRouteProgress(
            travelledMeters: distanceTravelled,
            remainingMeters: distanceRemaining,
            progress: progress,
            estimatedArrival: eta
        )
    }

    // MARK: - Distance Helpers

    /// Quang duong cong don. Phan tu thu i la tong do dai tu diem 0 den diem i.
    static func cumulativeDistances(of coordinates: [CLLocationCoordinate2D]) -> [CLLocationDistance] {
        guard coordinates.count > 1 else { return [0] }
        var result: [CLLocationDistance] = [0]
        result.reserveCapacity(coordinates.count)
        for i in 1..<coordinates.count {
            let step = MotionEngine.haversineDistance(from: coordinates[i - 1], to: coordinates[i])
            result.append(result[i - 1] + step)
        }
        return result
    }
}
