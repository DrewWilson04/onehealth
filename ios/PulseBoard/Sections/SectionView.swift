import SwiftUI
import PulseCore
import PulseKit

/// One dashboard section (Activity, Sleep, Heart, Body): every metric that has
/// data, plus section-specific extras.
struct SectionView: View {
    let section: DashboardSection
    @Environment(AppServices.self) private var services
    @Environment(IngestionStatus.self) private var status
    @State private var model = DashboardModel()
    @State private var missing: [MetricType] = []

    private var metrics: [MetricType] { MetricRegistry.metrics(in: section) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                extras
                AdaptiveCardGrid {
                    ForEach(metrics.filter { model.metrics[$0.id]?.latest != nil }) { m in
                        NavigationLink { MetricDetailView(metric: m) } label: {
                            MetricCardView(metric: m, snapshot: model.metrics[m.id])
                        }
                        .buttonStyle(.plain)
                    }
                }
                if model.loaded && !missing.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Not available").font(.subheadline.weight(.semibold))
                        Text(missing.map(\.displayName).joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary)
                        Text("These metrics are only recorded by some devices, or access hasn't been granted.")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .padding(.top, 8)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(section.title)
        .tint(Theme.accent(section))
        .task(id: status.dataRevision) {
            await model.load(services: services, metricIDs: metrics.map(\.id))
            missing = metrics.filter { model.metrics[$0.id]?.latest == nil }
        }
    }

    @ViewBuilder private var extras: some View {
        switch section {
        case .activity:
            RingsCardView(rings: model.rings)
            NavigationLink { WorkoutsView() } label: {
                Label("Workouts", systemImage: "dumbbell.fill").frame(maxWidth: .infinity, alignment: .leading)
                    .padding().background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            }.buttonStyle(.plain)
        case .sleep:
            NavigationLink { SleepDetailView() } label: { SleepNightCardView(night: model.lastNight) }.buttonStyle(.plain)
        case .heart, .body:
            EmptyView()
        }
    }
}
