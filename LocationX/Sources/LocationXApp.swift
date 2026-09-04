import Combine
import SwiftUI

/// Giữ Combine cancellables của bootstrap ở tầng class để tránh
/// "Cannot pass immutable value as inout: self is immutable" khi
/// LocationXApp (struct) gọi .store(in:) từ non-mutating method.
private final class AppBootstrap {
    static let shared = AppBootstrap()
    var cancellables = Set<AnyCancellable>()
    private init() {}
}

/// Entry point — v2 architecture.
/// Migration chạy trước khi UI hiện. Recovery check sau onboarding.
@main
struct LocationXApp: App {
    @StateObject private var engine = SpoofEngine.shared
    @StateObject private var routineManager = RoutineManager.shared
    @StateObject private var flightManager = FlightManager.shared
    @StateObject private var liveActivity = LiveActivityManager.shared
    @StateObject private var coordinator = SimulationCoordinator.shared
    @StateObject private var recovery = AppRecoveryManager.shared
    @StateObject private var deviceManager = DeviceManager.shared
    @AppStorage("locationx_onboarding_completed") private var hasCompletedOnboarding = false

    init() {
        MigrationManager.runIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    RootTabView()
                } else {
                    OnboardingViewV2()
                }
            }
            // Đổi ngôn ngữ trong Cài đặt là dựng lại toàn bộ cây view ngay lập tức.
            .localized()
            .environmentObject(engine)
            .environmentObject(routineManager)
            .environmentObject(flightManager)
            .environmentObject(liveActivity)
            .environmentObject(coordinator)
            .onAppear {
                if hasCompletedOnboarding {
                    bootstrap()
                }
            }
            .onChange(of: hasCompletedOnboarding) { _, completed in
                if completed { bootstrap() }
            }
            // Recovery alert
            .alert(L("recovery.title"), isPresented: $recovery.hasPendingRecovery) {
                Button(L("recovery.resume")) { recovery.recover() }
                Button(L("recovery.discard"), role: .cancel) { recovery.discard() }
            } message: {
                if let info = recovery.pendingSession {
                    Text(L("recovery.session_at",
                           info.source.displayName,
                           String(format: "%.4f, %.4f", info.lastCoordinate.latitude, info.lastCoordinate.longitude)))
                }
            }
            // Checkpoint khi app rời foreground
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                recovery.checkpoint()
            }
            // Reconnect khi app trở lại foreground
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                if engine.isLoopbackConnected {
                    engine.sendLocationToDevice(coordinator.currentCoordinate)
                } else if deviceManager.autoReconnect {
                    deviceManager.connect()
                }
            }
        }
    }

    /// Khởi động tất cả subsystem sau onboarding.
    private func bootstrap() {
        SelfPairingManager.shared.registerBackgroundTask()
        engine.startBackgroundKeepAlive()
        liveActivity.startOrUpdateActivity()
        deviceManager.startHeartbeat()

        // Auto-connect nếu có pairing sẵn
        if !engine.isLoopbackConnected && (engine.pairingData != nil || SelfPairingManager.shared.hasSavedPairing) {
            deviceManager.connect()
        }

        // Auto-record history khi simulation bắt đầu
        SimulationCoordinator.shared.$state
            .receive(on: DispatchQueue.main)
            .sink { state in
                if state == .running {
                    HistoryManager.shared.startRecording(
                        source: SimulationCoordinator.shared.activeSource ?? .manual,
                        travelMode: SimulationCoordinator.shared.session?.travelMode ?? .driving
                    )
                } else if state == .idle || state == .completed {
                    _ = HistoryManager.shared.stopRecording()
                }
            }
            .store(in: &AppBootstrap.shared.cancellables)

        // Khởi động ConnectionRecovery
        _ = ConnectionRecovery.shared

        // Khởi động ShadowrocketManager — auto-detect, VPN monitor
        _ = ShadowrocketManager.shared

        AppLogger.simulation.info("Bootstrap complete")
    }
}
