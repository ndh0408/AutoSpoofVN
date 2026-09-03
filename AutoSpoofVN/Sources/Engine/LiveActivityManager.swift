//
//  LiveActivityManager.swift
//  AutoSpoofVN
//
//  Quan ly Live Activity va Dynamic Island — đọc từ cả SpoofEngine (legacy)
//  VÀ SimulationCoordinator (v2) để cover mọi nguồn GPS.
//

import ActivityKit
import Combine
import Foundation

@MainActor
final class LiveActivityManager: ObservableObject {
    static let shared = LiveActivityManager()

    private var currentActivity: Activity<SpoofActivityAttributes>?
    private var cancellables: Set<AnyCancellable> = []

    private init() {
        observeStateChanges()
    }

    func startOrUpdateActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let coordinator = SimulationCoordinator.shared
        let engine = SpoofEngine.shared
        let routine = RoutineManager.shared
        let flight = FlightManager.shared

        // Ưu tiên toạ độ từ Coordinator (v2), fallback SpoofEngine (legacy)
        let coord = coordinator.currentCoordinate
        let coordText = String(format: "%.4f, %.4f", coord.latitude, coord.longitude)

        let stateName: String
        let desc: String
        let speed: Double
        let flightNo: String?
        let flightProgress: Double?

        if flight.isFlying, let sim = flight.activeFlight {
            stateName = "Đang Bay"
            desc = "\(sim.origin.code) → \(sim.destination.code) (\(sim.destination.name))"
            speed = sim.currentSpeedKmh
            flightNo = sim.flightNumber
            flightProgress = sim.progressFraction
        } else if coordinator.state.isActive {
            stateName = coordinator.state.displayName
            desc = coordinator.activeSource?.displayName ?? routine.statusDescription
            speed = coordinator.telemetry.speedKmh
            flightNo = nil
            flightProgress = nil
        } else {
            stateName = routine.currentState.rawValue
            desc = routine.statusDescription
            speed = routine.currentSpeedKmh
            flightNo = nil
            flightProgress = nil
        }

        // Active source — ưu tiên coordinator
        let sourceDisplay: String
        if let coordSource = coordinator.activeSource {
            sourceDisplay = coordSource.displayName
        } else if let legacySource = engine.activeSource {
            sourceDisplay = legacySource.displayName
        } else {
            sourceDisplay = "GPS Thật"
        }

        let contentState = SpoofActivityAttributes.ContentState(
            stateName: stateName,
            statusDescription: desc,
            speedKmh: speed,
            coordinateText: coordText,
            flightNumber: flightNo,
            flightProgress: flightProgress,
            activeSource: sourceDisplay,
            isHalted: coordinator.isHalted || engine.isHalted
        )

        if let activity = currentActivity {
            Task {
                await activity.update(ActivityContent(state: contentState, staleDate: nil))
            }
        } else {
            do {
                let attributes = SpoofActivityAttributes(appName: "AutoSpoof VN")
                let activity = try Activity.request(
                    attributes: attributes,
                    content: ActivityContent(state: contentState, staleDate: nil),
                    pushType: nil
                )
                self.currentActivity = activity
            } catch {
                AppLogger.ui.error("Live Activity start failed: \(error)")
            }
        }
    }

    func endActivity() {
        guard let activity = currentActivity else { return }
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
            self.currentActivity = nil
        }
    }

    private func observeStateChanges() {
        // Observe cả SpoofEngine (legacy) VÀ SimulationCoordinator (v2)
        Publishers.MergeMany(
            SpoofEngine.shared.$currentCoordinate.map { _ in () }.eraseToAnyPublisher(),
            SpoofEngine.shared.$isSimulating.map { _ in () }.eraseToAnyPublisher(),
            SimulationCoordinator.shared.$state.map { _ in () }.eraseToAnyPublisher(),
            SimulationCoordinator.shared.$telemetry.map { _ in () }.eraseToAnyPublisher(),
            RoutineManager.shared.$currentState.map { _ in () }.eraseToAnyPublisher(),
            FlightManager.shared.$isFlying.map { _ in () }.eraseToAnyPublisher()
        )
        .throttle(for: .milliseconds(800), scheduler: DispatchQueue.main, latest: true)
        .sink { [weak self] in
            self?.startOrUpdateActivity()
        }
        .store(in: &cancellables)
    }
}
