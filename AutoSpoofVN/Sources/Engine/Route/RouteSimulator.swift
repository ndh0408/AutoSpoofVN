import CoreLocation
import Foundation

/// Chạy mô phỏng dọc theo một tuyến đường đã tính toán.
/// Sở hữu MotionEngine riêng, báo cáo coordinate lên SimulationCoordinator.
@MainActor
final class RouteSimulator: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var progress: Double = 0  // 0.0 - 1.0
    @Published private(set) var currentSegmentIndex: Int = 0
    @Published private(set) var distanceTravelled: Double = 0
    @Published private(set) var distanceRemaining: Double = 0
    @Published private(set) var eta: Date? = nil

    private var routeCoordinates: [CLLocationCoordinate2D] = []
    private var currentIndex: Int = 0
    private var simulationTask: Task<Void, Never>?
    private let motionEngine = MotionEngine()
    private var headingEngine = HeadingEngine()
    private let coordinator = SimulationCoordinator.shared

    /// Tick rate — mô phỏng chạy ở tần số này.
    private let tickInterval: TimeInterval = 0.1  // 10 Hz

    /// Bắt đầu mô phỏng trên tuyến đường cho trước.
    func start(coordinates: [CLLocationCoordinate2D], travelMode: TravelMode = .driving) {
        guard coordinates.count >= 2 else { return }
        stop()

        routeCoordinates = coordinates
        currentIndex = 0
        distanceTravelled = 0
        distanceRemaining = totalRouteDistance()
        isRunning = true

        Task { await motionEngine.setSpeedProfile(travelMode.defaultSpeed) }

        let session = coordinator.startSession(source: .route, travelMode: travelMode)
        _ = session // captured for future use

        simulationTask = Task { [weak self] in
            await self?.runSimulationLoop()
        }
    }

    func pause() {
        coordinator.pauseSession()
        isRunning = false
    }

    func resume() {
        guard !routeCoordinates.isEmpty else { return }
        coordinator.resumeSession()
        isRunning = true
        simulationTask = Task { [weak self] in
            await self?.runSimulationLoop()
        }
    }

    func stop() {
        simulationTask?.cancel()
        simulationTask = nil
        isRunning = false
        coordinator.stopSession()
        Task { await motionEngine.reset() }
        headingEngine.reset()
    }

    /// Seek to a specific progress point (0.0 - 1.0)
    func seek(to progress: Double) {
        let targetIndex = Int(Double(routeCoordinates.count - 1) * progress.clamped(to: 0...1))
        currentIndex = targetIndex
        self.progress = progress
        if let coord = routeCoordinates[safe: targetIndex] {
            coordinator.submit(coordinate: coord, from: .route)
        }
    }

    // MARK: - Simulation Loop

    private func runSimulationLoop() async {
        while !Task.isCancelled && currentIndex < routeCoordinates.count - 1 && isRunning {
            let current = coordinator.currentCoordinate
            let target = routeCoordinates[currentIndex + 1]
            let remainingOnRoute = distanceFromIndex(currentIndex + 1)

            let result = await motionEngine.nextPosition(
                from: current,
                toward: target,
                deltaTime: tickInterval * coordinator.timeMultiplier,
                distanceToEnd: remainingOnRoute
            )

            let heading = headingEngine.update(with: result.coordinate)

            coordinator.submit(
                coordinate: result.coordinate,
                from: .route,
                speedKmh: result.speedKmh,
                headingDegrees: heading
            )

            distanceTravelled += result.distanceMoved
            distanceRemaining = max(0, totalRouteDistance() - distanceTravelled)
            progress = totalRouteDistance() > 0 ? distanceTravelled / totalRouteDistance() : 0
            currentSegmentIndex = currentIndex

            // ETA
            if result.speedKmh > 0 {
                let remainingHours = (distanceRemaining / 1000) / result.speedKmh
                eta = Date().addingTimeInterval(remainingHours * 3600)
            }

            if result.reachedTarget {
                currentIndex += 1
            }

            try? await Task.sleep(nanoseconds: UInt64(tickInterval * 1_000_000_000))
        }

        if !Task.isCancelled {
            // Route hoàn thành
            isRunning = false
            progress = 1.0
            coordinator.stopSession()
        }
    }

    // MARK: - Distance Helpers

    private func totalRouteDistance() -> Double {
        var total: Double = 0
        for i in 0..<routeCoordinates.count - 1 {
            total += MotionEngine.haversineDistance(from: routeCoordinates[i], to: routeCoordinates[i + 1])
        }
        return total
    }

    private func distanceFromIndex(_ index: Int) -> Double {
        var total: Double = 0
        for i in index..<routeCoordinates.count - 1 {
            total += MotionEngine.haversineDistance(from: routeCoordinates[i], to: routeCoordinates[i + 1])
        }
        return total
    }
}

// MARK: - Helpers

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// subscript(safe:) da co san, module-wide, trong Engine/RoutineManager.swift - khong khai
// bao lai o day (hai "private extension Array" trung chu ky o hai file khac nhau bi Swift
// bao "invalid redeclaration"; RoutineManager.swift dung ban khong-private nen dung chung
// duoc cho ca file nay).
