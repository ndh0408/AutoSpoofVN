import SwiftUI

/// App entry point v2 — với migration, recovery, và SimulationCoordinator.
/// Đổi tên file cũ hoặc thay @main khi sẵn sàng chuyển.
// @main  // Uncomment khi sẵn sàng thay thế AutoSpoofVNApp.swift
struct AutoSpoofVNAppV2: App {
    @StateObject private var engine = SpoofEngine.shared
    @StateObject private var routineManager = RoutineManager.shared
    @StateObject private var flightManager = FlightManager.shared
    @StateObject private var liveActivity = LiveActivityManager.shared
    @StateObject private var coordinator = SimulationCoordinator.shared
    @StateObject private var recovery = AppRecoveryManager.shared
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
                    OnboardingView()
                }
            }
            .environmentObject(engine)
            .environmentObject(routineManager)
            .environmentObject(flightManager)
            .environmentObject(liveActivity)
            .environmentObject(coordinator)
            .onAppear {
                SelfPairingManager.shared.registerBackgroundTask()
                if hasCompletedOnboarding {
                    engine.startBackgroundKeepAlive()
                    liveActivity.startOrUpdateActivity()
                    DeviceManager.shared.startHeartbeat()
                }
            }
            .onChange(of: hasCompletedOnboarding) { _, completed in
                if completed {
                    engine.startBackgroundKeepAlive()
                    liveActivity.startOrUpdateActivity()
                    DeviceManager.shared.startHeartbeat()
                }
            }
            .alert("Phát hiện phiên chưa hoàn thành", isPresented: $recovery.hasPendingRecovery) {
                Button("Tiếp tục") { recovery.recover() }
                Button("Bỏ qua", role: .cancel) { recovery.discard() }
            } message: {
                if let info = recovery.pendingSession {
                    Text("\(info.source.displayName) — \(String(format: "%.4f, %.4f", info.lastCoordinate.latitude, info.lastCoordinate.longitude))")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                recovery.checkpoint()
            }
        }
    }
}
