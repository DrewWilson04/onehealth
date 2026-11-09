import SwiftUI
import PulseCore
import PulseKit

/// Milestone 1 placeholder: today's value per core metric. Replaced by the
/// full grid in Milestone 2.
struct DashboardView: View {
    @Environment(AppServices.self) private var services
    @Environment(IngestionStatus.self) private var status
    @State private var latest: [MetricID: DailyAggregate] = [:]

    private let metrics: [MetricID] = [.steps, .activeEnergy, .exerciseTime, .sleep, .restingHeartRate, .hrv, .bodyMass, .water]

    var body: some View {
        List {
            BackfillBanner().listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            ForEach(metrics, id: \.self) { id in
                if let m = MetricRegistry.type(id) {
                    LabeledContent {
                        Text(Fmt.value(latest[id]?.value(for: m.dailyStatistic), metric: m))
                    } label: {
                        Label(m.displayName, systemImage: m.symbol).foregroundStyle(Theme.accent(m.section))
                    }
                }
            }
        }
        .navigationTitle("Today")
        .task(id: status.dataRevision) {
            var out: [MetricID: DailyAggregate] = [:]
            for id in metrics { out[id] = try? await services.store.latestAggregate(id) }
            latest = out
        }
    }
}
