//
//  ScenarioEngine.swift
//  AutoSpoofVN
//
//  Executes declarative automated QA & test scenarios with sequential steps.
//

import Combine
import CoreLocation
import Foundation

@MainActor
public final class ScenarioEngine: ObservableObject {
    public static let shared = ScenarioEngine()

    @Published public private(set) var activeScenario: Scenario? = nil
    @Published public private(set) var currentStepIndex: Int = 0
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var statusText: String = "Sẵn sàng"

    private var currentTask: Task<Void, Never>?

    public init() {}

    public func startScenario(_ scenario: Scenario) {
        stopScenario()
        self.activeScenario = scenario
        self.currentStepIndex = 0
        self.isRunning = true

        currentTask = Task { [weak self] in
            await self?.executeScenarioLoop(scenario)
        }
    }

    public func stopScenario() {
        currentTask?.cancel()
        currentTask = nil
        isRunning = false
        statusText = "Đã dừng kịch bản"
        activeScenario = nil
    }

    private func executeScenarioLoop(_ scenario: Scenario) async {
        let coordinator = SimulationCoordinator.shared
        repeat {
            for (index, step) in scenario.steps.enumerated() {
                guard !Task.isCancelled, isRunning else { return }
                self.currentStepIndex = index
                self.statusText = "Bước \(index + 1)/\(scenario.steps.count): \(step.title)"

                switch step.actionType {
                case .setLocation:
                    if let target = step.targetCoordinate {
                        coordinator.setManualLocation(target.clCoordinate)
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                    }
                case .waitSeconds:
                    let duration = step.waitDurationSeconds ?? 5.0
                    let nano = UInt64(duration * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: nano)
                case .changeSpeed:
                    break
                case .changeTravelMode:
                    break
                case .moveTo, .followRoute:
                    if let target = step.targetCoordinate {
                        let origin = coordinator.currentCoordinate
                        let waypoints = RouteProvider.straightLineCoordinates(
                            from: origin,
                            to: target.clCoordinate,
                            spacingMeters: 25.0
                        )
                        coordinator.startRouteSimulation(
                            name: step.title,
                            waypoints: waypoints,
                            travelMode: step.travelMode ?? .driving,
                            speedKmh: step.targetSpeedKmh ?? 40.0
                        )
                        while coordinator.state == .running && !Task.isCancelled {
                            try? await Task.sleep(nanoseconds: 500_000_000)
                        }
                    }
                case .dwellArea:
                    let radius = step.dwellRadiusMeters ?? 40.0
                    let center = step.targetCoordinate?.clCoordinate ?? coordinator.currentCoordinate
                    let motion = MotionEngine.shared
                    for _ in 0..<10 {
                        guard !Task.isCancelled, isRunning else { break }
                        let jittered = motion.applyJitter(to: center, maxMeters: radius)
                        coordinator.setManualLocation(jittered)
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                    }
                case .randomJitter:
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
        } while scenario.isLooping && !Task.isCancelled && isRunning

        self.isRunning = false
        self.statusText = "Kịch bản đã hoàn thành"
    }
}
