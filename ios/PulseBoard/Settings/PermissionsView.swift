import SwiftUI
import UIKit
import PulseCore
import PulseKit

/// Shows which sections are limited. HealthKit never tells apps whether *read*
/// access was denied, so "no data" is reported as possibly-denied with steps
/// to fix it; write access is shown exactly.
struct PermissionsView: View {
    @Environment(AppServices.self) private var services
    @State private var summary: AccessSummary?

    var body: some View {
        List {
            if let summary {
                let limited = summary.limitedSections()
                Section {
                    if limited.isEmpty {
                        Label("All dashboard sections have data.", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.bluishGreen)
                    } else {
                        ForEach(DashboardSection.allCases.filter { limited[$0] != nil }) { s in
                            VStack(alignment: .leading, spacing: 4) {
                                Label(s.title, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.orange)
                                Text("No data for: " + (limited[s] ?? []).compactMap { MetricRegistry.type($0)?.displayName }.joined(separator: ", "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Limited sections")
                } footer: {
                    Text("If you expected data here, open Settings → Health → Data Access & Devices → \(PulseKitConfig.appName) and turn on the categories you want. Some metrics are only recorded by certain devices.")
                }

                Section("Write access (for logging)") {
                    ForEach(summary.metrics.filter { $0.write != .unavailable }, id: \.metric) { m in
                        LabeledContent(MetricRegistry.type(m.metric)?.displayName ?? m.metric.rawValue) {
                            Text(label(m.write)).foregroundStyle(m.write == .granted ? Theme.bluishGreen : .secondary)
                        }
                    }
                }

                Section {
                    Button("Ask for access again") {
                        Task {
                            try? await services.provider.requestAuthorization(read: MetricRegistry.all.map(\.id), write: MetricRegistry.writable.map(\.id))
                            summary = await services.provider.accessSummary()
                        }
                    }
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        Link("Open Settings", destination: url)
                    }
                } footer: {
                    Text("Apple Health only shows the permission sheet for types you haven't been asked about yet. To change earlier choices, use Settings → Health.")
                }
            } else {
                ProgressView("Checking…")
            }
        }
        .navigationTitle("Health Permissions")
        .task { summary = await services.provider.accessSummary() }
    }

    private func label(_ s: AccessState) -> String {
        switch s {
        case .granted: return "Allowed"
        case .denied: return "Not allowed"
        case .notRequested: return "Not asked"
        case .unknown: return "Unknown"
        case .unavailable: return "—"
        }
    }
}
