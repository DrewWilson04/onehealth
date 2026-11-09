import SwiftUI
import PulseCore
import PulseKit

struct GoalsView: View {
    @Environment(AppServices.self) private var services
    @Environment(SettingsStore.self) private var settings
    @Environment(IngestionStatus.self) private var status
    @State private var model = GoalsModel()
    @State private var editing: Goal?
    @State private var adding = false

    var body: some View {
        List {
            ForEach(model.rows) { row in
                Button { editing = row.goal } label: { GoalRow(row: row) }
                    .buttonStyle(.plain)
            }
            .onDelete { idx in
                idx.map { model.rows[$0].goal.id }.forEach(settings.deleteGoal)
            }
            if model.rows.isEmpty {
                ContentUnavailableView("No goals", systemImage: "target", description: Text("Add a target for any metric to track progress and streaks."))
            }
        }
        .navigationTitle("Goals")
        .toolbar { Button { adding = true } label: { Label("Add goal", systemImage: "plus") } }
        .sheet(item: $editing) { g in NavigationStack { GoalEditor(goal: g) } }
        .sheet(isPresented: $adding) { NavigationStack { GoalEditor(goal: nil) } }
        .task(id: "\(status.dataRevision)-\(settings.revision)") { await model.load(services: services) }
    }
}

struct GoalRow: View {
    let row: GoalsModel.Row
    var body: some View {
        let accent = Theme.accent(row.metric.section)
        HStack(spacing: 14) {
            RingsView(rings: [.init(id: row.goal.id, label: row.metric.displayName, progress: row.streak.progress, color: accent)], lineWidth: 7)
                .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.metric.displayName).font(.headline)
                Text("\(Fmt.value(row.streak.currentValue, metric: row.metric)) of \(row.goal.direction == .atMost ? "≤ " : "")\(Fmt.value(row.goal.target, metric: row.metric))\(row.goal.period == .week ? " this week" : " today")")
                    .font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    ForEach(Array(row.streak.recent.enumerated()), id: \.offset) { _, met in
                        Circle().fill(met ? accent : Color.secondary.opacity(0.25)).frame(width: 7, height: 7)
                    }
                }
                .accessibilityHidden(true)
            }
            Spacer()
            VStack {
                Label("\(row.streak.current)", systemImage: "flame.fill")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(row.streak.current > 0 ? Theme.orange : .secondary)
                Text("best \(row.streak.longest)").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.metric.displayName) goal, \(Int(row.streak.progress * 100)) percent, current streak \(row.streak.current) \(row.goal.period == .day ? "days" : "weeks"), longest \(row.streak.longest)")
    }
}

struct GoalEditor: View {
    let goal: Goal?
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var metric: MetricID = .steps
    @State private var target: Double?
    @State private var period: GoalPeriod = .day
    @State private var direction: GoalDirection = .atLeast

    private var goalMetrics: [MetricType] {
        MetricRegistry.all.filter { [.cumulative, .discrete, .category, .workout].contains($0.kind) && $0.id != .heartRate }
    }

    var body: some View {
        Form {
            Picker("Metric", selection: $metric) {
                ForEach(goalMetrics) { m in Text(m.displayName).tag(m.id) }
            }
            Picker("Direction", selection: $direction) {
                Text("At least").tag(GoalDirection.atLeast)
                Text("At most").tag(GoalDirection.atMost)
            }
            .pickerStyle(.segmented)
            TextField("Target (\(MetricRegistry.type(metric).map { unitHint($0) } ?? ""))", value: $target, format: .number)
                .keyboardType(.decimalPad)
            Picker("Period", selection: $period) {
                Text("Daily").tag(GoalPeriod.day)
                Text("Weekly").tag(GoalPeriod.week)
            }
            .pickerStyle(.segmented)
        }
        .navigationTitle(goal == nil ? "New Goal" : "Edit Goal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    var g = goal ?? Goal(metric: metric, target: target ?? 0)
                    g.metric = metric; g.target = target ?? 0; g.period = period; g.direction = direction
                    settings.saveGoal(g)
                    dismiss()
                }
                .disabled((target ?? 0) <= 0)
            }
        }
        .onAppear {
            if let goal { metric = goal.metric; target = goal.target; period = goal.period; direction = goal.direction }
        }
    }

    private func unitHint(_ m: MetricType) -> String {
        switch m.unit {
        case .stageCode, .minute: return "minutes"
        case .count: return m.id == .steps ? "steps" : "count"
        default: return m.unit.symbol
        }
    }
}

/// Dashboard card: up to four goals as rings with streak flames.
struct GoalsCardView: View {
    let rows: [GoalsModel.Row]
    var body: some View {
        CardContainer(tint: Theme.orange) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Goals", systemImage: "target").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.orange)
                if rows.isEmpty {
                    Text("Add goals in Settings → Goals").font(.subheadline).foregroundStyle(.secondary)
                }
                HStack(alignment: .top) {
                    ForEach(rows.prefix(4)) { r in
                        VStack(spacing: 4) {
                            RingsView(rings: [.init(id: r.id, label: r.metric.displayName, progress: r.streak.progress, color: Theme.accent(r.metric.section))], lineWidth: 6)
                                .frame(width: 48, height: 48)
                                .overlay { Image(systemName: r.metric.symbol).font(.caption).foregroundStyle(Theme.accent(r.metric.section)) }
                            Text(r.metric.displayName).font(.caption2).lineLimit(1)
                            if r.streak.current > 0 {
                                Label("\(r.streak.current)", systemImage: "flame.fill").font(.caption2.monospacedDigit()).foregroundStyle(Theme.orange)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(r.metric.displayName), \(Int(r.streak.progress * 100)) percent, streak \(r.streak.current)")
                    }
                }
            }
        }
    }
}
