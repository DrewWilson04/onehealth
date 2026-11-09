import SwiftUI
import PulseCore
import PulseKit

struct SettingsView: View {
    @Environment(AppServices.self) private var services
    @Environment(IngestionStatus.self) private var status
    @State private var confirmReset = false

    var body: some View {
        List {
            Section("Personalize") {
                NavigationLink { GoalsView() } label: { Label("Goals & streaks", systemImage: "target") }
                NavigationLink { UnitsSettingsView() } label: { Label("Units", systemImage: "ruler") }
            }

            Section("Data") {
                NavigationLink { SourcesView() } label: {
                    Label("Sources & priority", systemImage: "square.stack.3d.up.fill")
                }
                NavigationLink { PermissionsView() } label: {
                    Label("Health permissions", systemImage: "checkmark.shield.fill")
                }
                LabeledContent {
                    Text(importStatus).foregroundStyle(.secondary)
                } label: {
                    Label("History import", systemImage: "clock.arrow.circlepath")
                }
                Button(role: .destructive) { confirmReset = true } label: {
                    Label("Rebuild local cache", systemImage: "arrow.triangle.2.circlepath")
                }
            }

            Section {
                Label("Health data never leaves your devices except through Apple Health's own sync.", systemImage: "lock.fill")
                Label("Settings, goals and layouts sync via your private iCloud.", systemImage: "icloud")
                Label("Custom metrics are stored on this device only.", systemImage: "iphone")
            } header: {
                Text("Privacy")
            }

            Section("About") {
                NavigationLink { PrivacyPolicyView() } label: { Label("Privacy policy", systemImage: "doc.text") }
                NavigationLink { AboutScoresView() } label: { Label("How scores work", systemImage: "function") }
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
            }
            Section {
                Text("\(PulseKitConfig.appName) is not a medical device and does not provide medical advice. Scores are our own estimates and are not equivalent to WHOOP, Garmin or Oura scores.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Rebuild the local cache?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Rebuild", role: .destructive) { Task { await services.resetCache() } }
        } message: {
            Text("Your Apple Health data is not affected. \(PulseKitConfig.appName) will re-import it.")
        }
    }

    private var importStatus: String {
        switch status.phase {
        case .complete: return "Complete"
        case .recent, .history: return "\(Int(status.progress * 100))%"
        case .paused: return "Paused"
        case .authorizing: return "Waiting for permission"
        case .idle: return status.progress >= 1 ? "Complete" : "Idle"
        }
    }
}

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            Text(PrivacyPolicy.text)
                .font(.body)
                .padding()
                .frame(maxWidth: 700, alignment: .leading)
        }
        .navigationTitle("Privacy Policy")
    }
}

enum PrivacyPolicy {
    // Keep in sync with /docs/privacy-policy.md (placeholder — have it
    // reviewed before App Store submission and host it at a public URL).
    static var text: String {
        let app = PulseKitConfig.appName
        return """
        \(app) Privacy Policy (placeholder)

        • \(app) reads health data from Apple Health only to show it to you. It is processed on your device.
        • We do not operate servers. We do not collect, upload, sell or share your health data, and we never use it for advertising or marketing.
        • Entries you log (food, water, workouts, weight…) are written to Apple Health, which syncs them across your devices under Apple's privacy policy.
        • Non-health settings (goals, dashboard layout, saved meals, preferred sources, challenge configuration) sync through your private iCloud database. We cannot access it.
        • Custom metrics stay on this device.
        • No analytics, advertising or third-party SDKs are included.
        • Challenges (preview): when you opt in for a specific challenge, only an aggregated daily score is shared — never raw health data. Location for local challenges is limited to city/region.
        • You can delete all local data by deleting the app. Apple Health data is managed in the Health app.

        Contact: privacy@example.com
        """
    }
}


struct UnitsSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    var body: some View {
        Form {
            Picker("Units", selection: Binding(get: { settings.preferences.unitSystem }, set: { v in settings.update { $0.unitSystem = v } })) {
                Text("Automatic").tag(UserPreferences.UnitSystem.automatic)
                Text("Metric").tag(UserPreferences.UnitSystem.metric)
                Text("Imperial").tag(UserPreferences.UnitSystem.imperial)
            }
            .pickerStyle(.inline)
        }
        .navigationTitle("Units")
    }
}
