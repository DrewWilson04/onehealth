import SwiftUI
import PulseCore
import PulseKit

/// Trends hub: this-week-vs-last for key metrics, then every metric by section.
struct TrendsHomeView: View {
    @Environment(AppServices.self) private var services
    @Environment(IngestionStatus.self) private var status
    @State private var comparisons: [(MetricType, PeriodComparison)] = []
    @State private var available: Set<MetricID> = []

    private let keyMetrics: [MetricID] = [.steps, .activeEnergy, .exerciseTime, .sleep, .restingHeartRate, .hrv, .bodyMass, .dietaryEnergy]

    var body: some View {
        List {
            if !comparisons.isEmpty {
                Section("This week vs last week") {
                    ForEach(comparisons, id: \.0.id) { m, c in
                        NavigationLink { MetricDetailView(metric: m) } label: {
                            ComparisonRow(title: m.displayName, comparison: c, metric: m)
                        }
                    }
                }
            }
            ForEach(DashboardSection.allCases) { s in
                Section(s.title) {
                    ForEach(MetricRegistry.metrics(in: s).filter { available.contains($0.id) }) { m in
                        NavigationLink { MetricDetailView(metric: m) } label: {
                            Label(m.displayName, systemImage: m.symbol).foregroundStyle(Theme.accent(s))
                        }
                    }
                }
            }
        }
        .navigationTitle("Trends")
        .task(id: status.dataRevision) {
            let today = DayKey.today(services.calendar)
            var out: [(MetricType, PeriodComparison)] = []
            var avail = Set<MetricID>()
            for m in MetricRegistry.all {
                if (try? await services.store.latestAggregate(m.id)) != nil { avail.insert(m.id) }
            }
            for id in keyMetrics where avail.contains(id) {
                guard let m = MetricRegistry.type(id) else { continue }
                let rows = (try? await services.store.aggregates(id, period: .day, from: today.addingDays(-14), to: today)) ?? []
                let c = Trends.compare(rows, metric: m, period: .week, today: today)
                if c.current != nil { out.append((m, c)) }
            }
            comparisons = out
            available = avail
        }
    }
}
