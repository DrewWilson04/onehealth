import SwiftUI
import PulseCore
import PulseKit

/// AI insights (Pro, Apple Intelligence devices only). The stats engine
/// finds the patterns and supplies every number; the on-device model only
/// phrases them. No network calls.
struct InsightsView: View {
    @Environment(AppServices.self) private var services
    @Environment(EntitlementManager.self) private var entitlements
    @Environment(IngestionStatus.self) private var status
    @State private var items: [(Finding, PhrasedInsight)] = []
    @State private var loading = true
    @State private var showPaywall = false

    var body: some View {
        List {
            if !entitlements.isEnabled(.aiInsights) {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Personal insights", systemImage: "sparkles").font(.headline)
                        Text("Find patterns like how late workouts affect your HRV, or how steps relate to your sleep — explained in plain language, privately on your device.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button("Unlock with Pro") { showPaywall = true }.buttonStyle(.borderedProminent)
                    }
                }
            } else if loading {
                ProgressView("Looking for patterns…")
            } else if items.isEmpty {
                ContentUnavailableView("No clear patterns yet", systemImage: "sparkle.magnifyingglass",
                                       description: Text("Insights appear once there's enough data to be confident — usually a few weeks of wear."))
            } else {
                ForEach(items, id: \.0.id) { f, p in
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(p.headline, systemImage: icon(f.kind)).font(.headline).foregroundStyle(tint(f.kind))
                            Text(p.explanation)
                            if let s = p.suggestion { Text(s).font(.subheadline).foregroundStyle(.secondary) }
                            HStack {
                                Text(evidence(f)).font(.caption2).foregroundStyle(.tertiary)
                                Spacer()
                                if p.usedModel {
                                    Label("Phrased on-device", systemImage: "apple.intelligence").font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            Section {
                Text("Insights describe patterns in your own data, not causes. They're not medical advice. If something worries you, talk to a healthcare professional.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Insights")
        .sheet(isPresented: $showPaywall) { PaywallView(highlight: .aiInsights) }
        .task(id: "\(status.dataRevision)-\(entitlements.isPro)") { await load() }
    }

    private func load() async {
        guard entitlements.isEnabled(.aiInsights) else { loading = false; return }
        loading = true
        let findings = await services.insights.findings(priority: services.settings.sourcePriority)
        var out: [(Finding, PhrasedInsight)] = []
        for f in findings.prefix(8) { out.append((f, await services.phraser.phrase(f))) }
        items = out
        loading = false
    }

    private func evidence(_ f: Finding) -> String {
        switch f.kind {
        case .conditional: return "Based on \(f.n) days · p = \(String(format: "%.3f", f.pValue ?? 1))"
        case .correlation: return "\(f.n) days · Spearman correlation"
        case .anomaly: return "Compared with your last \(f.n) days"
        case .trendChange: return "Last 14 days vs the 28 before"
        }
    }

    private func icon(_ k: Finding.Kind) -> String {
        switch k {
        case .conditional: return "arrow.triangle.branch"
        case .correlation: return "point.3.connected.trianglepath.dotted"
        case .anomaly: return "exclamationmark.circle"
        case .trendChange: return "chart.line.uptrend.xyaxis"
        }
    }

    private func tint(_ k: Finding.Kind) -> Color {
        switch k {
        case .anomaly: return Theme.vermillion
        case .trendChange: return Theme.orange
        default: return Theme.blue
        }
    }
}
