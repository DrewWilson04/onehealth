import SwiftUI
import WidgetKit
import PulseCore
import PulseKit

@main
struct PulseBoardWatchApp: App {
    @State private var model = WatchModel()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(model)
                .task { await model.start() }
                .onChange(of: phase) { _, p in if p == .active { Task { await model.refresh() } } }
        }
    }
}
