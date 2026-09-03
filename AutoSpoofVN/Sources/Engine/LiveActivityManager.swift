//
//  LiveActivityManager.swift
//  AutoSpoofVN
//
//  Quan ly Live Activity va Dynamic Island cap nhat lien tuc theo GPS.
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

        let engine = SpoofEngine.shared
        let routine = RoutineManager.shared
        let flight = FlightManager.shared

        let coord = engine.currentCoordinate
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
        } else {
            stateName = routine.currentState.rawValue
            desc = routine.statusDescription
            speed = routine.currentSpeedKmh
            flightNo = nil
            flightProgress = nil
        }

        let contentState = SpoofActivityAttributes.ContentState(
            stateName: stateName,
            statusDescription: desc,
            speedKmh: speed,
            coordinateText: coordText,
            flightNumber: flightNo,
            flightProgress: flightProgress,
            activeSource: engine.activeSource?.displayName ?? "GPS Thật",
            isHalted: engine.isHalted
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
                // Khong lam gian doan app neu nguoi dung tat Live Activity
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
        Publishers.Merge4(
            SpoofEngine.shared.$currentCoordinate.map { _ in () }.eraseToAnyPublisher(),
            SpoofEngine.shared.$isSimulating.map { _ in () }.eraseToAnyPublisher(),
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
