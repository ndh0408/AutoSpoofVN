import CoreLocation
import Foundation

/// Chạy kịch bản tự động — chuỗi hành động tuần tự.
@MainActor
final class ScenarioEngine: ObservableObject {
    static let shared = ScenarioEngine()

    @Published private(set) var isRunning = false
    @Published private(set) var currentStepIndex: Int = 0
    @Published private(set) var currentStepDescription: String = ""
    @Published private(set) var progress: Double = 0
    @Published var scenarios: [Scenario] = []
    /// Kich ban dang chay — de danh sach biet the nao dang hoat dong.
    @Published private(set) var currentScenarioID: UUID? = nil
    /// Tam dung khac han dung han: tam dung thi VAN giu quyen dieu khien GPS.
    @Published private(set) var isPaused = false

    private var activeScenario: Scenario?
    private var executionTask: Task<Void, Never>?
    private let coordinator = SimulationCoordinator.shared
    private let motionEngine = MotionEngine()

    private init() {
        scenarios = PersistenceManager.shared.loadScenarios()
    }

    func start(scenario: Scenario) {
        stop()
        activeScenario = scenario
        currentScenarioID = scenario.id
        isRunning = true
        isPaused = false
        currentStepIndex = 0

        guard coordinator.acquire(.scenario) else {
            isRunning = false
            return
        }

        executionTask = Task { [weak self] in
            await self?.executeScenario(scenario)
        }
    }

    func stop() {
        executionTask?.cancel()
        executionTask = nil
        isRunning = false
        isPaused = false
        activeScenario = nil
        currentScenarioID = nil
        currentStepIndex = 0
        currentStepDescription = ""
        progress = 0
        coordinator.release(.scenario)
    }

    func pause() {
        guard isRunning else { return }
        isRunning = false
        isPaused = true
        coordinator.pauseSession()
    }

    func resume() {
        guard activeScenario != nil, isPaused else { return }
        coordinator.resumeSession()
        isPaused = false
        isRunning = true
        // Re-launch from current step
        executionTask = Task { [weak self] in
            guard let self, let scenario = self.activeScenario else { return }
            let remaining = Array(scenario.steps.dropFirst(self.currentStepIndex))
            await self.executeSteps(remaining, totalSteps: scenario.steps.count, isLoop: scenario.isLoop)
        }
    }

    // MARK: - CRUD

    func saveScenario(_ scenario: Scenario) {
        if let idx = scenarios.firstIndex(where: { $0.id == scenario.id }) {
            scenarios[idx] = scenario
        } else {
            scenarios.append(scenario)
        }
        PersistenceManager.shared.saveScenarios(scenarios)
    }

    func deleteScenario(id: UUID) {
        scenarios.removeAll { $0.id == id }
        PersistenceManager.shared.saveScenarios(scenarios)
    }

    // MARK: - Execution

    private func executeScenario(_ scenario: Scenario) async {
        await executeSteps(scenario.steps, totalSteps: scenario.steps.count, isLoop: scenario.isLoop)
        // Chi nha quyen khi kich ban THUC SU ket thuc. Ban truoc khong phan biet, nen
        // `pause()` (von chi dat isRunning = false) cung roi vao nhanh nay va nha
        // `.scenario` — mot nguon uu tien thap hon (chu trinh 40, phat lai 20) co the
        // gianh quyen trong khi nguoi dung tuong kich ban chi dang tam dung.
        guard !Task.isCancelled, !isPaused else { return }
        isRunning = false
        currentScenarioID = nil
        coordinator.release(.scenario)
    }

    private func executeSteps(_ steps: [ScenarioStep], totalSteps: Int, isLoop: Bool) async {
        var loopCount = 0
        let maxLoops = 1000 // safety

        repeat {
            for (i, step) in steps.enumerated() {
                guard !Task.isCancelled, isRunning else { return }
                currentStepIndex = i + (totalSteps - steps.count)
                progress = Double(currentStepIndex) / Double(max(totalSteps, 1))
                currentStepDescription = step.action.displayName

                await executeAction(step.action)
            }
            loopCount += 1
        } while isLoop && !Task.isCancelled && loopCount < maxLoops

        progress = 1.0
    }

    private func executeAction(_ action: ScenarioAction) async {
        switch action {
        case .setLocation(let coord):
            coordinator.submit(coordinate: coord.clCoordinate, from: .scenario)
            try? await Task.sleep(nanoseconds: 500_000_000)

        case .moveTo(let coord, let speedKmh):
            await moveToward(coord.clCoordinate, speedKmh: speedKmh)

        case .followRoute(let routeId):
            let routes = PersistenceManager.shared.loadRoutes()
            if let route = routes.first(where: { $0.id == routeId }),
               let geometry = route.routeGeometry {
                let coords = geometry.map { $0.clCoordinate }
                await moveAlongRoute(coords, speedKmh: route.travelMode.defaultSpeed.cruise)
            }

        case .wait(let seconds):
            currentStepDescription = "Chờ \(Int(seconds))s"
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))

        case .changeSpeed(let kmh):
            let profile = SpeedProfile(min: kmh * 0.3, cruise: kmh, max: kmh * 1.2, acceleration: 3, deceleration: 4)
            await motionEngine.setSpeedProfile(profile)

        case .changeTravelMode(let mode):
            await motionEngine.setSpeedProfile(mode.defaultSpeed)

        case .pause:
            pause()
            // Wait until resumed
            while !isRunning && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }

        case .resume:
            break // handled by pause logic

        case .loop:
            break // handled by executeSteps loop

        case .dwell(let seconds):
            currentStepDescription = "Dừng chân \(Int(seconds))s"
            let start = Date()
            while Date().timeIntervalSince(start) < seconds && !Task.isCancelled {
                // Jitter tại chỗ
                let current = coordinator.currentCoordinate
                coordinator.submit(coordinate: current, from: .scenario, speedKmh: 0)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }

        case .randomNearby(let radius, let duration):
            currentStepDescription = "Di chuyển ngẫu nhiên"
            let center = coordinator.currentCoordinate
            let start = Date()
            while Date().timeIntervalSince(start) < duration && !Task.isCancelled {
                let angle = Double.random(in: 0..<360)
                let dist = Double.random(in: 0...radius)
                let target = MotionEngine.moveCoordinate(center, distanceMeters: dist, bearingDegrees: angle)
                await moveToward(target, speedKmh: 3.5)
            }
        }
    }

    private func moveToward(_ target: CLLocationCoordinate2D, speedKmh: Double) async {
        let tickInterval: TimeInterval = 0.1
        var iterations = 0
        let maxIterations = 10000

        while !Task.isCancelled && iterations < maxIterations {
            let current = coordinator.currentCoordinate
            let distance = MotionEngine.haversineDistance(from: current, to: target)
            guard distance > 2 else { break }

            let result = await motionEngine.nextPosition(
                from: current, toward: target,
                deltaTime: tickInterval * coordinator.timeMultiplier,
                distanceToEnd: distance
            )
            coordinator.submit(
                coordinate: result.coordinate, from: .scenario,
                speedKmh: result.speedKmh, headingDegrees: result.headingDegrees
            )
            iterations += 1
            try? await Task.sleep(nanoseconds: UInt64(tickInterval * 1_000_000_000))
        }
    }

    private func moveAlongRoute(_ coords: [CLLocationCoordinate2D], speedKmh: Double) async {
        for i in 0..<coords.count - 1 {
            guard !Task.isCancelled else { return }
            await moveToward(coords[i + 1], speedKmh: speedKmh)
        }
    }
}
