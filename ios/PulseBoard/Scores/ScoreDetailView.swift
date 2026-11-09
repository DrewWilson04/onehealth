import SwiftUI
import Charts
import PulseCore
import PulseKit

struct ScoreDetailView: View {
    let kind: ScoreKind
    @Environment(AppServices.self) private var services
    @Environment(EntitlementManager.self) private var entitlements
    @Environment(IngestionStatus.self) private var status
    @State private var history: [ScoreResult] = []
    @State private var showPaywall = false

    private var result: ScoreResult? { services.todayScores[kind] }
    private var fullHistory: Bool { entitlements.isEnabled(.fullScoreHistory) }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    if let v = result?.value {
                        Text(kind == .strain ? v.formatted(.number.precision(.fractionLength(1))) : "\(Int(v.rounded()))")
                            .font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(kind == .strain ? Theme.orange : Theme.scoreColor(v))
                        Text(result?.label ?? "").font(.title3.weight(.semibold))
                    } else {
                        Text("Not enough data").font(.title2.bold())
                        if let r = result?.reason { Text(r).foregroundStyle(.secondary) }
                    }
                    HStack {
                        Label("Confidence: \(result?.confidence.rawValue.capitalized ?? "—")", systemImage: "checkmark.seal")
                        if result?.isEstimated == true { EstimatedBadge(confidence: result?.confidence) }
                    }
                    .font(.caption)
                }
                .accessibilityElement(children: .combine)
            } footer: {
                Text("\(PulseKitConfig.appName)'s own estimate from your raw data — not equivalent to WHOOP, Garmin or Oura scores. Not medical advice.")
            }

            if kind == .energy, let series = result?.series, series.count > 1 { energyChart(series) }
            if kind == .strain, let r = result { strainDetails(r) }

            if let comps = result?.components, !comps.isEmpty {
                Section("What went into it") {
                    ForEach(comps, id: \.name) { c in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(c.name).font(.subheadline.weight(.semibold))
                                if c.isEstimated { Image(systemName: "wand.and.stars").foregroundStyle(Theme.orange).accessibilityLabel("estimated") }
                                Spacer()
                                Text("\(Int(c.score.rounded()))").monospacedDigit()
                                Text("· \(Int((c.weight * 100).rounded()))%").font(.caption).foregroundStyle(.secondary)
                            }
                            ProgressView(value: c.score, total: 100).tint(Theme.scoreColor(c.score))
                            if let raw = c.raw { Text(componentDetail(c, raw: raw)).font(.caption).foregroundStyle(.secondary) }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            Section("Inputs") {
                ForEach(result?.inputsUsed ?? [], id: \.self) { Label($0, systemImage: "checkmark.circle.fill").foregroundStyle(Theme.bluishGreen) }
                ForEach(result?.missingInputs ?? [], id: \.self) { Label($0, systemImage: "minus.circle").foregroundStyle(.secondary) }
            }

            Section {
                if history.isEmpty {
                    Text("History builds up as you wear your devices.").foregroundStyle(.secondary)
                } else {
                    Chart(history.filter { $0.value != nil }, id: \.day) { r in
                        LineMark(x: .value("Day", r.day.date(), unit: .day), y: .value(kind.title, r.value!))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(Theme.bluishGreen)
                        PointMark(x: .value("Day", r.day.date(), unit: .day), y: .value(kind.title, r.value!))
                            .foregroundStyle(r.isEstimated ? Theme.orange : Theme.bluishGreen)
                            .symbolSize(18)
                    }
                    .chartYScale(domain: kind == .strain ? 0...21 : 0...100)
                    .frame(height: 180)
                    .accessibilityChartDescriptor(MetricChartDescriptor(title: kind.title, unit: "",
                                                                        points: history.compactMap { r in r.value.map { (Fmt.day(r.day), $0) } }))
                }
                if !fullHistory {
                    Button("See full history with Pro") { showPaywall = true }
                }
            } header: {
                Text(fullHistory ? "Last 90 days" : "Last 30 days")
            }

            Section { NavigationLink("How this score works") { AboutScoresView() } }
        }
        .navigationTitle(kind.title)
        .sheet(isPresented: $showPaywall) { PaywallView(highlight: .fullScoreHistory) }
        .task(id: status.dataRevision) {
            let today = DayKey.today(services.calendar)
            history = await services.scoreService.history(kind, from: today.addingDays(fullHistory ? -89 : -29), to: today)
        }
    }

    private func componentDetail(_ c: ScoreComponent, raw: Double) -> String {
        switch c.name {
        case "HRV": return "\(Int(raw)) ms vs baseline \(c.baseline.map { "\(Int($0)) ms" } ?? "—")"
        case "Resting HR": return "\(Int(raw)) bpm vs baseline \(c.baseline.map { "\(Int($0)) bpm" } ?? "—")"
        case "Duration": return "\(Fmt.duration(minutes: raw)) of \(Fmt.duration(minutes: c.baseline ?? 480)) goal"
        case "Efficiency": return "\(Int(raw))% of time in bed asleep"
        case "Consistency": return "Bed/wake times vary by ±\(Int(raw)) min"
        default: return ""
        }
    }

    private func energyChart(_ series: [Double]) -> some View {
        Section("Today") {
            Chart(Array(series.enumerated()), id: \.offset) { i, v in
                AreaMark(x: .value("Time", i), y: .value("Energy", v))
                    .foregroundStyle(LinearGradient(colors: [Theme.bluishGreen.opacity(0.5), Theme.bluishGreen.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Time", i), y: .value("Energy", v)).foregroundStyle(Theme.bluishGreen)
            }
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .frame(height: 160)
            .accessibilityLabel("Energy through the day, from \(Int(series.first ?? 0)) to \(Int(series.last ?? 0))")
            if let r = result {
                LabeledContent("Charged overnight to", value: "\(Int(r.extras["start"] ?? 0))")
                LabeledContent("Drained today", value: "\(Int(r.extras["drained"] ?? 0))")
                LabeledContent("Recharged while resting", value: "\(Int(r.extras["charged"] ?? 0))")
            }
        }
    }

    private func strainDetails(_ r: ScoreResult) -> some View {
        Section("Training load") {
            if let acwr = r.extras["acwr"] {
                LabeledContent("Acute : chronic ratio", value: acwr.formatted(.number.precision(.fractionLength(2))))
                Text(StrainScorer.status(acwr: acwr).title).font(.subheadline.weight(.semibold))
                Gauge(value: min(2, acwr), in: 0...2) { Text("Load ratio") } currentValueLabel: { Text(acwr.formatted(.number.precision(.fractionLength(2)))) }
                    .tint(Gradient(colors: [Theme.skyBlue, Theme.bluishGreen, Theme.orange, Theme.vermillion]))
            } else {
                Text("Training balance appears after 14 days of heart-rate data.").foregroundStyle(.secondary)
            }
            if let t = r.extras["trimp"] { LabeledContent("TRIMP today", value: "\(Int(t))") }
            ForEach(1...5, id: \.self) { z in
                if let m = r.extras["zone\(z)"], m >= 1 { LabeledContent("Zone \(z)", value: Fmt.duration(minutes: m)) }
            }
        }
    }
}
