import SwiftUI

/// Entry point — v2 architecture.
/// Migration chạy trước khi UI hiện. Recovery check sau onboarding.
@main
struct AutoSpoofVNApp: App {
    @StateObject private var engine = SpoofEngine.shared
    @StateObject private var routineManager = RoutineManager.shared
    @StateObject private var flightManager = FlightManager.shared
    @StateObject private var liveActivity = LiveActivityManager.shared
    @StateObject private var coordinator = SimulationCoordinator.shared
    @StateObject private var recovery = AppRecoveryManager.shared
    @StateObject private var deviceManager = DeviceManager.shared
    @AppStorage("autospoof_onboarding_completed") private var hasCompletedOnboarding = false

    init() {
        MigrationManager.runIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    MainViewV2()
                } else {
                    OnboardingViewV2()
                }
            }
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
            .alert("Phát hiện phiên chưa hoàn thành", isPresented: $recovery.hasPendingRecovery) {
                Button("Tiếp tục") { recovery.recover() }
                Button("Bỏ qua", role: .cancel) { recovery.discard() }
            } message: {
                if let info = recovery.pendingSession {
                    Text("\(info.source.displayName) tại \(String(format: "%.4f, %.4f", info.lastCoordinate.latitude, info.lastCoordinate.longitude))")
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

        AppLogger.simulation.info("Bootstrap complete")
    }
}
