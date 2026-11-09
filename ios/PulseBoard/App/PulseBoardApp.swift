import SwiftUI
import PulseCore
import PulseKit

@main
struct PulseBoardApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(AppServices.shared)
                .environment(AppServices.shared.ingestionStatus)
                .environment(AppServices.shared.settings)
                .environment(AppServices.shared.entitlements)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { AppServices.shared.didBecomeActive() }
            if phase == .background { AppServices.shared.didEnterBackground() }
        }
    }
}
