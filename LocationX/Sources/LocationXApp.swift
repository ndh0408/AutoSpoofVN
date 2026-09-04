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
    @StateObject private var appSettings = AppSettingsStore.shared
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
                    OnboardingScreen()
                }
            }
            // Đổi ngôn ngữ trong Cài đặt là dựng lại toàn bộ cây view ngay lập tức.
            .localized()
            // Tuỳ chọn Giao diện (sáng/tối/theo hệ thống) — trước đây được lưu nhưng
            // `preferredColorScheme` không xuất hiện ở đâu trong toàn bộ mã nguồn.
            .preferredColorScheme(appSettings.preferredColorScheme)
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
            // Trở lại foreground: đo lại đường truyền ngay thay vì đợi hết nhịp 5 giây.
            //
            // Thường người dùng vừa rời app để bật VPN trong Shadowrocket rồi quay lại,
            // nên đây chính là lúc trạng thái cũ nhất.
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                ShadowrocketManager.shared.detectInstallation()
            }
        }
    }

    /// Khởi động tất cả subsystem sau onboarding.
    private func bootstrap() {
        // Khởi động đường truyền Shadowrocket TRƯỚC: `apply()` cấu hình nhịp đo của nó.
        _ = ShadowrocketManager.shared
        // Áp cài đặt người dùng TRƯỚC khi khởi động các hệ thống con, để chúng bắt đầu
        // với đúng nhịp và đúng trạng thái bật/tắt.
        AppSettingsStore.shared.apply()
        engine.startBackgroundKeepAlive()
        liveActivity.start()

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

        AppLogger.simulation.info("Bootstrap complete")
    }
}
