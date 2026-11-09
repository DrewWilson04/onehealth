import SwiftUI
import PulseCore
import PulseKit

/// What syncs where, iCloud status, and the gray-area toggles.
struct SyncSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var monitor = CloudSyncMonitor(containerID: PulseKitConfig.iCloudContainer)
    @State private var syncGoals = SettingsSync.syncGoals
    @State private var syncMeals = SettingsSync.syncMealTemplates

    var body: some View {
        Form {
            Section {
                LabeledContent("iCloud", value: settings.isCloudBacked ? monitor.account.description : "Off (local only)")
                if case .upToDate(let d) = settings.syncState {
                    LabeledContent("Last change from another device", value: d.formatted(date: .abbreviated, time: .shortened))
                }
            } footer: {
                Text("Uses your private iCloud database. \(PulseKitConfig.appName) has no access to it.")
            }

            Section("Synced through iCloud") {
                Label("Settings & units", systemImage: "gearshape")
                Label("Dashboard layout", systemImage: "square.grid.2x2")
                Label("Preferred sources", systemImage: "square.stack.3d.up")
                Label("Challenge setup", systemImage: "trophy")
                Toggle(isOn: $syncGoals) { Label("Goals", systemImage: "target") }
                Toggle(isOn: $syncMeals) { Label("Saved meal templates", systemImage: "fork.knife") }
            }

            Section {
                Label("Food, water, workouts and weight you log → saved to Apple Health, which Apple syncs between your iPhone, iPad and Apple Watch.", systemImage: "heart.fill")
                Label("Health data read from Apple Health → cached on this device only.", systemImage: "iphone")
                Label("Custom metrics → this device only.", systemImage: "lock.fill")
            } header: {
                Text("Never in iCloud")
            } footer: {
                Text("Apple doesn't allow apps to store personal health information in iCloud. Goals and meal templates contain no health records, but you can keep them on this device if you prefer.")
            }
        }
        .navigationTitle("iCloud Sync")
        .task { await monitor.refresh() }
        .onChange(of: syncGoals) { _, v in SettingsSync.syncGoals = v; settings.applySyncPolicy() }
        .onChange(of: syncMeals) { _, v in SettingsSync.syncMealTemplates = v; settings.applySyncPolicy() }
    }
}
