import SwiftUI
import Charts
import PulseCore
import PulseKit

/// Recent nights with stage breakdown.
struct SleepDetailView: View {
    @Environment(AppServices.self) private var services
    @Environment(IngestionStatus.self) private var status
    @State private var nights: [SleepNight] = []
    @State private var loaded = false

    var body: some View {
        List {
            if let last = nights.last {
                Section("Last night") {
                    Hypnogram(night: last).frame(height: 90)
                    StageBreakdown(night: last)
                    LabeledContent("In bed", value: Fmt.duration(minutes: last.inBedMinutes))
                    LabeledContent("Asleep", value: Fmt.duration(minutes: last.asleepMinutes))
                    if let e = last.efficiency { LabeledContent("Efficiency", value: "\(Int(e * 100))%") }
                    LabeledContent("Sources", value: last.sources.count > 1 ? "\(last.sources.count) devices merged" : "1 device")
                    if !last.hasStages {
                        Text("Your device didn't record sleep stages for this night.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Last 14 nights") {
                if nights.isEmpty && loaded {
                    ContentUnavailableView("No sleep data", systemImage: "bed.double", description: Text("Wear your watch or ring to bed, or log sleep in the Health app."))
                }
                Chart(nights, id: \.day) { n in
                    ForEach([SleepStage.deep, .core, .rem, .asleepUnspecified, .awake], id: \.self) { s in
                        if let m = n.stageMinutes[s], m > 0 {
                            BarMark(x: .value("Night", n.day.date(), unit: .day), y: .value("Hours", m / 60))
                                .foregroundStyle(by: .value("Stage", s.label))
                        }
                    }
                }
                .chartForegroundStyleScale(["Deep": Theme.sleepStageColor(.deep), "Core": Theme.sleepStageColor(.core),
                                            "REM": Theme.sleepStageColor(.rem), "Asleep": Theme.sleepStageColor(.asleepUnspecified),
                                            "Awake": Theme.sleepStageColor(.awake)])
                .frame(height: 200)
                .accessibilityChartDescriptor(MetricChartDescriptor(title: "Sleep", unit: "hours",
                                                                    points: nights.map { (Fmt.day($0.day), $0.asleepMinutes / 60) }))
                ForEach(nights.reversed(), id: \.day) { n in
                    LabeledContent(Fmt.day(n.day)) {
                        HStack {
                            Text(Fmt.duration(minutes: n.asleepMinutes)).monospacedDigit()
                            SourceBadge(sourceKey: n.primarySource.attribution)
                        }
                    }
                }
            }
        }
        .navigationTitle("Sleep")
        .task(id: status.dataRevision) {
            let cal = services.calendar
            let today = DayKey.today(cal)
            let s = (try? await services.store.samples(.sleep, from: today.addingDays(-15).date(cal), to: today.addingDays(1).date(cal))) ?? []
            let p = services.settings.sourcePriority.preferring(services.settings.preferredSources[.sleep])
            nights = SleepMerger.nights(s, priority: p, calendar: cal).filter { $0.day > today.addingDays(-14) }
            loaded = true
        }
    }
}

struct StageBreakdown: View {
    let night: SleepNight
    var body: some View {
        let stages: [SleepStage] = night.hasStages ? [.awake, .rem, .core, .deep] : [.awake, .asleepUnspecified]
        HStack {
            ForEach(stages, id: \.self) { s in
                VStack {
                    Text(s.label).font(.caption).foregroundStyle(Theme.sleepStageColor(s))
                    Text(Fmt.duration(minutes: night.stageMinutes[s] ?? 0)).font(.subheadline.monospacedDigit())
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
    }
}
