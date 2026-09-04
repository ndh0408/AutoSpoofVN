import Foundation

/// Timer audit — theo dõi tất cả timers/tasks đang chạy.
/// Debug tool: gọi `TimerAudit.report()` để xem danh sách.
///
/// Timer inventory trong codebase:
/// ┌─────────────────────────┬────────────┬──────────────────┬──────────────────────┐
/// │ Owner                   │ Type       │ Interval         │ Stop condition       │
/// ├─────────────────────────┼────────────┼──────────────────┼──────────────────────┤
/// │ SpoofEngine             │ Timer      │ 20s              │ stopBackgroundKeep() │
/// │ RoutineManager          │ Timer      │ 60s (schedule)   │ toggleAutoRoutine()  │
/// │ RoutineManager          │ Timer      │ 1-2s (movement)  │ route complete       │
/// │ FlightManager           │ Timer      │ 1s (flight tick) │ stopFlight()         │
/// │ SimulationCoordinator   │ Timer      │ nhip gui thiet bi│ stopSession()        │
/// │ BackgroundKeeper        │ AVAudio    │ continuous       │ stop()               │
/// │ BackgroundKeeper        │ CLLocation │ continuous       │ stop()               │
/// │ LiveActivityManager     │ Combine    │ 800ms throttle   │ automatic            │
/// │ RouteSimulator          │ Task       │ 100ms (10Hz)     │ stop() / complete    │
/// │ ScenarioEngine          │ Task       │ varies per step  │ stop() / complete    │
/// │ ReplayEngine            │ Task       │ varies per point │ stop() / complete    │
/// │ ShadowrocketManager     │ Timer      │ 5s (do trang thai)│ deinit               │
/// │ AppRecoveryManager      │ None       │ on resign active │ automatic            │
/// └─────────────────────────┴────────────┴──────────────────┴──────────────────────┘
///
/// Quy tắc:
/// - Mỗi Timer/Task có owner rõ ràng
/// - Mỗi Timer/Task có stop condition rõ ràng
/// - Background: Timer invalidate + Task cancel khi app background
/// - Disconnect: Timer giữ heartbeat, Task mô phỏng dừng
/// - Stop simulation: tất cả Task mô phỏng cancel
///
/// Không có timer nào chạy orphan.
@MainActor
final class TimerAudit {
    struct Entry {
        let owner: String
        let type: String
        let interval: String
        let stopCondition: String
        let isRunning: Bool
    }

    static func report() -> [Entry] {
        [
            Entry(owner: "SpoofEngine", type: "Timer", interval: "20s", stopCondition: "stopBackgroundKeepAlive()", isRunning: SpoofEngine.shared.isSimulating),
            Entry(owner: "BackgroundKeeper", type: "AVAudioPlayer", interval: "continuous", stopCondition: "stop()", isRunning: BackgroundKeeper.shared.isAudioRunning),
            Entry(owner: "BackgroundKeeper", type: "CLLocationManager", interval: "continuous", stopCondition: "stop()", isRunning: BackgroundKeeper.shared.isLocationUpdating),
            Entry(owner: "RoutineManager", type: "Timer", interval: "60s", stopCondition: "toggleAutoRoutine()", isRunning: RoutineManager.shared.isAutoRoutineEnabled),
            Entry(owner: "FlightManager", type: "Timer", interval: "1s", stopCondition: "stopFlight()", isRunning: FlightManager.shared.isFlying),
            Entry(owner: "SimulationCoordinator", type: "Timer", interval: "deviceUpdateRate", stopCondition: "stopSession()", isRunning: SimulationCoordinator.shared.state.isActive),
            Entry(owner: "ShadowrocketManager", type: "Timer", interval: "5s", stopCondition: "deinit", isRunning: ShadowrocketManager.shared.isServerRunning),
        ]
    }

    static func printReport() {
        let entries = report()
        AppLogger.simulation.info("=== Timer Audit ===")
        for e in entries {
            AppLogger.simulation.info("[\(e.isRunning ? "RUN" : "---")] \(e.owner) (\(e.type), \(e.interval)) → \(e.stopCondition)")
        }
        let running = entries.filter(\.isRunning).count
        AppLogger.simulation.info("Active: \(running)/\(entries.count)")
    }
}
