import SwiftUI

@main
struct AutoSpoofVNApp: App {
    @StateObject private var engine = SpoofEngine.shared
    @StateObject private var routineManager = RoutineManager.shared
    @StateObject private var flightManager = FlightManager.shared
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
                .onAppear {
                    if hasCompletedOnboarding {
                        engine.startBackgroundKeepAlive()
                    }
                }
                .onChange(of: hasCompletedOnboarding) { _, completed in
                    if completed {
                        engine.startBackgroundKeepAlive()
                    }
                }
        }
    }
}
