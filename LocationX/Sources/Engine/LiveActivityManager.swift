//
//  LiveActivityManager.swift
//  LocationX
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
    private var stateWatcher: Task<Void, Never>?

    /// `init` cố tình KHÔNG chạm singleton nào khác.
    ///
    /// Bản trước gọi `observeStateChanges()` ngay trong `init`, mà hàm đó đọc
    /// `SimulationCoordinator.shared`, `RoutineManager.shared`, `FlightManager.shared` và
    /// `SpoofEngine.shared`. Vì `LocationXApp` khởi tạo `LiveActivityManager.shared` TRƯỚC
    /// `SimulationCoordinator.shared`, chuỗi khởi tạo đó chạy lồng vào nhau — kiểu mắc xích
    /// này là đường ngắn nhất tới khoá chết `swift_once`, biểu hiện là app treo mà không
    /// crash. Việc đăng ký quan sát chuyển sang `start()`, gọi tường minh lúc bootstrap.
    private init() {}

    /// Bắt đầu theo dõi trạng thái. Gọi một lần lúc bootstrap.
    func start() {
        guard cancellables.isEmpty else { return }
        observeStateChanges()
        refresh()
    }

    // MARK: - Có nên hiện Live Activity không

    /// Chỉ hiện khi thực sự có thứ gì đó đang chạy.
    ///
    /// Bản trước gọi `startOrUpdateActivity()` ngay lúc bootstrap, nên Live Activity xuất
    /// hiện trên màn khoá với nội dung "Sẵn sàng · 0 km/h" dù người dùng chưa bắt đầu gì,
    /// rồi ở lại đó cho tới giới hạn 8 tiếng của hệ thống.
    private var shouldShowActivity: Bool {
        if SimulationCoordinator.shared.isHalted { return false }
        if SimulationCoordinator.shared.state.isActive { return true }
        if FlightManager.shared.isFlying { return true }
        if RoutineManager.shared.isAutoRoutineEnabled { return true }
        return SpoofEngine.shared.isSimulating
    }

    /// Cập nhật, tạo mới, hoặc kết thúc Live Activity tuỳ trạng thái hiện tại.
    func refresh() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard shouldShowActivity else {
            endActivity()
            return
        }
        startOrUpdateActivity()
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
            stateName = L("flight.live_activity.flying")
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
            sourceDisplay = L("live_activity.real_gps")
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
                let attributes = SpoofActivityAttributes(appName: "LocationX")
                let activity = try Activity.request(
                    attributes: attributes,
                    content: ActivityContent(state: contentState, staleDate: nil),
                    pushType: nil
                )
                currentActivity = activity
                watchForExternalDismissal(of: activity)
            } catch {
                AppLogger.ui.error("Live Activity start failed: \(error)")
            }
        }
    }

    func endActivity() {
        guard let activity = currentActivity else { return }
        currentActivity = nil
        stateWatcher?.cancel()
        stateWatcher = nil
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Người dùng có thể tự vuốt bỏ Live Activity từ màn khoá.
    ///
    /// Không theo dõi việc đó thì `currentActivity` vẫn khác `nil`, ta cứ gọi `update()`
    /// lên một activity đã chết và **không bao giờ tạo lại** — người dùng bỏ nó một lần là
    /// mất luôn cho tới khi khởi động lại app.
    private func watchForExternalDismissal(of activity: Activity<SpoofActivityAttributes>) {
        stateWatcher?.cancel()
        stateWatcher = Task { [weak self] in
            for await state in activity.activityStateUpdates {
                if state == .dismissed || state == .ended {
                    await MainActor.run {
                        guard let self else { return }
                        if self.currentActivity?.id == activity.id {
                            self.currentActivity = nil
                        }
                    }
                    return
                }
            }
        }
    }

    private func observeStateChanges() {
        // Observe cả SpoofEngine (legacy) VÀ SimulationCoordinator (v2)
        Publishers.MergeMany(
            SpoofEngine.shared.$currentCoordinate.map { _ in () }.eraseToAnyPublisher(),
            SpoofEngine.shared.$isSimulating.map { _ in () }.eraseToAnyPublisher(),
            SimulationCoordinator.shared.$state.map { _ in () }.eraseToAnyPublisher(),
            SimulationCoordinator.shared.$telemetry.map { _ in () }.eraseToAnyPublisher(),
            SimulationCoordinator.shared.$isHalted.map { _ in () }.eraseToAnyPublisher(),
            RoutineManager.shared.$currentState.map { _ in () }.eraseToAnyPublisher(),
            RoutineManager.shared.$isAutoRoutineEnabled.map { _ in () }.eraseToAnyPublisher(),
            FlightManager.shared.$isFlying.map { _ in () }.eraseToAnyPublisher()
        )
        .throttle(for: .milliseconds(800), scheduler: DispatchQueue.main, latest: true)
        .sink { [weak self] in
            // `refresh` chứ không phải `startOrUpdateActivity`: nó còn biết KẾT THÚC
            // activity khi mọi thứ đã dừng.
            self?.refresh()
        }
        .store(in: &cancellables)
    }
}
