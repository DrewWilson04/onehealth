import SwiftUI
import Charts
import PulseCore

struct SleepNightCardView: View {
    let night: SleepNight?

    var body: some View {
        CardContainer(tint: Theme.blue) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Last night", systemImage: "bed.double.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.blue)
                if let n = night {
                    HStack(alignment: .firstTextBaseline) {
                        Text(Fmt.duration(minutes: n.asleepMinutes)).font(.title2.bold().monospacedDigit())
                        Text("asleep").font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        if let e = n.efficiency {
                            Text("\(Int(e * 100))% efficient").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Hypnogram(night: n).frame(height: 54)
                    HStack {
                        Text("\(n.sleepOnset.formatted(date: .omitted, time: .shortened)) – \(n.wakeTime.formatted(date: .omitted, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        SourceBadge(sourceKey: n.primarySource.attribution)
                    }
                } else {
                    Text("No sleep recorded last night").font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Stage timeline (awake on top, deep at the bottom).
struct Hypnogram: View {
    let night: SleepNight

    private func level(_ s: SleepStage) -> Int {
        switch s {
        case .awake: return 3
        case .rem: return 2
        case .core, .asleepUnspecified: return 1
        case .deep: return 0
        case .inBed: return 3
        }
    }

    var body: some View {
        Chart(Array(night.segments.enumerated()), id: \.offset) { _, seg in
            let stage = SleepStage(rawValue: Int(seg.value)) ?? .asleepUnspecified
            RectangleMark(xStart: .value("Start", seg.start), xEnd: .value("End", seg.end),
                          yStart: .value("Level", level(stage)), yEnd: .value("Level", level(stage) + 1))
                .foregroundStyle(Theme.sleepStageColor(stage))
        }
        .chartYAxis(.hidden)
        .chartXAxis(.hidden)
        .chartYScale(domain: 0...4)
        .accessibilityLabel(stageSummary)
    }

    private var stageSummary: String {
        let order: [SleepStage] = [.awake, .rem, .core, .deep, .asleepUnspecified]
        return order.compactMap { s in
            guard let m = night.stageMinutes[s], m > 0 else { return nil }
            return "\(s.label) \(Fmt.duration(minutes: m))"
        }.joined(separator: ", ")
    }
}
