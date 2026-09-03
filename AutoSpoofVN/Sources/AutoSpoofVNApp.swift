import SwiftUI

@main
struct AutoSpoofVNApp: App {
    @StateObject private var engine = SpoofEngine.shared
    @StateObject private var routineManager = RoutineManager.shared
    @StateObject private var flightManager = FlightManager.shared
    @StateObject private var liveActivity = LiveActivityManager.shared
    @AppStorage("autospoof_onboarding_completed") private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    MainView()
                } else {
                    OnboardingView()
                }
            }
                .environmentObject(engine)
                .environmentObject(routineManager)
                .environmentObject(flightManager)
                .environmentObject(liveActivity)
                .onAppear {
                    SelfPairingManager.shared.registerBackgroundTask()
                    if hasCompletedOnboarding {
                        engine.startBackgroundKeepAlive()
                        liveActivity.startOrUpdateActivity()
                    }
                }
                .onChange(of: hasCompletedOnboarding) { _, completed in
                    if completed {
                        engine.startBackgroundKeepAlive()
                        liveActivity.startOrUpdateActivity()
                    }
                }
        }
    }
}
