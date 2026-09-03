import SwiftUI

@main
struct AutoSpoofVNApp: App {
    @StateObject private var engine = SpoofEngine.shared
    @StateObject private var routineManager = RoutineManager.shared
    @StateObject private var flightManager = FlightManager.shared

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(engine)
                .environmentObject(routineManager)
                .environmentObject(flightManager)
                .onAppear {
                    engine.startBackgroundKeepAlive()
                }
        }
    }
}
