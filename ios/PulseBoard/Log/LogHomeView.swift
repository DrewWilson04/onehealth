import SwiftUI
import PulseCore
import PulseKit

/// Manual logging hub. Entries go to Apple Health (except custom metrics).
struct LogHomeView: View {
    @Environment(AppServices.self) private var services
    @Environment(IngestionStatus.self) private var status
    @State private var recent: [Sample] = []
    @State private var nutrition: [MetricID: Double] = [:]
    @State private var sheet: LogKind?
    @State private var error: String?

    enum LogKind: String, Identifiable, CaseIterable {
        case food, water, workout, weight, bloodPressure, mindful, sleep, custom
        var id: String { rawValue }
        var title: String {
            switch self {
            case .food: return "Food"
            case .water: return "Water"
            case .workout: return "Workout"
            case .weight: return "Weight"
            case .bloodPressure: return "Blood Pressure"
            case .mindful: return "Mindful"
            case .sleep: return "Sleep"
            case .custom: return "Custom"
            }
        }
        var symbol: String {
            switch self {
            case .food: return "fork.knife"
            case .water: return "drop.fill"
            case .workout: return "dumbbell.fill"
            case .weight: return "scalemass.fill"
            case .bloodPressure: return "heart.text.square.fill"
            case .mindful: return "brain.head.profile"
            case .sleep: return "bed.double.fill"
            case .custom: return "star.fill"
            }
        }
        var tint: Color {
            switch self {
            case .food, .weight, .custom: return Theme.bluishGreen
            case .water: return Theme.skyBlue
            case .workout: return Theme.orange
            case .bloodPressure: return Theme.vermillion
            case .mindful, .sleep: return Theme.blue
            }
        }
    }

    var body: some View {
        List {
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 12)], spacing: 12) {
                    ForEach(LogKind.allCases) { k in
                        Button { sheet = k } label: {
                            VStack(spacing: 6) {
                                Image(systemName: k.symbol).font(.title2).foregroundStyle(k.tint)
                                Text(k.title).font(.caption.weight(.medium)).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity, minHeight: 72)
                            .background(k.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Log \(k.title)")
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Today's nutrition") {
                NutritionSummary(values: nutrition)
            }

            Section {
                if recent.isEmpty {
                    Text("Entries you log appear here.").foregroundStyle(.secondary)
                }
                ForEach(recent) { s in
                    ManualEntryRow(sample: s)
                        .swipeActions {
                            if s.source.bundleId != "local" {
                                Button("Delete", role: .destructive) { Task { await delete(s) } }
                            }
                        }
                }
            } header: {
                Text("Recent entries")
            } footer: {
                Text("Saved to Apple Health and synced to your other devices by Apple. Manual entries never count toward challenges.")
            }
        }
        .navigationTitle("Log")
        .sheet(item: $sheet) { k in
            NavigationStack { form(for: k) }
        }
        .alert("Couldn't delete", isPresented: .constant(error != nil)) { Button("OK") { error = nil } } message: { Text(error ?? "") }
        .task(id: status.dataRevision) { await load() }
    }

    @ViewBuilder private func form(for k: LogKind) -> some View {
        switch k {
        case .food: FoodLogView()
        case .water: WaterLogView()
        case .workout: WorkoutLogView()
        case .weight: WeightLogView()
        case .bloodPressure: BloodPressureLogView()
        case .mindful: MindfulLogView()
        case .sleep: SleepLogView()
        case .custom: CustomMetricsView()
        }
    }

    private func load() async {
        recent = (try? await services.store.manualSamples(limit: 30)) ?? []
        let today = DayKey.today(services.calendar)
        var n: [MetricID: Double] = [:]
        for id in [MetricID.dietaryEnergy, .protein, .carbohydrates, .fat, .water] {
            n[id] = (try? await services.store.aggregates(id, period: .day, from: today, to: today))?.first?.sum
        }
        nutrition = n
    }

    private func delete(_ s: Sample) async {
        do {
            try await services.writer.delete(id: s.id, metric: s.type)
            _ = try? await services.store.deleteSamples(ids: [s.id])
            await services.didWrite([s.type])
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct NutritionSummary: View {
    let values: [MetricID: Double]
    var body: some View {
        HStack {
            item("Calories", values[.dietaryEnergy], "kcal", Theme.bluishGreen)
            item("Protein", values[.protein], "g", Theme.blue)
            item("Carbs", values[.carbohydrates], "g", Theme.orange)
            item("Fat", values[.fat], "g", Theme.reddishPurple)
            item("Water", values[.water].map { $0 / 1000 }, "L", Theme.skyBlue)
        }
    }
    private func item(_ title: String, _ v: Double?, _ unit: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(color)
            Text(v.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? "—").font(.subheadline.bold().monospacedDigit())
            Text(unit).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct ManualEntryRow: View {
    let sample: Sample
    var body: some View {
        let m = MetricRegistry.type(sample.type)
        HStack {
            Image(systemName: m?.symbol ?? "star.fill").foregroundStyle(Theme.accent(m?.section ?? .body)).frame(width: 28)
            VStack(alignment: .leading) {
                Text(sample.metadata?["HKFoodType"] ?? m?.displayName ?? sample.metadata?["unitLabel"] ?? "Custom")
                Text(sample.start.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(m.map { Fmt.value(sample.type == .workout ? sample.value : sample.value, metric: $0) } ?? sample.value.formatted())
                .monospacedDigit()
            if sample.source.bundleId == "local" {
                Image(systemName: "iphone").font(.caption).foregroundStyle(.secondary).accessibilityLabel("On this device only")
            }
        }
        .accessibilityElement(children: .combine)
    }
}
