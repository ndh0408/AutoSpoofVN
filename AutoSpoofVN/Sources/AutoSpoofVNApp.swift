import SwiftUI

@main
struct AutoSpoofVNApp: App {
    @StateObject private var engine = SpoofEngine.shared
    @StateObject private var routineManager = RoutineManager.shared

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(engine)
                .environmentObject(routineManager)
                .onAppear {
                    engine.startBackgroundKeepAlive()
                }
        }
    }
}
