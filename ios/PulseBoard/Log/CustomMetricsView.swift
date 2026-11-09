import SwiftUI
import PulseCore
import PulseKit

/// Metrics with no HealthKit type (e.g. "Mood", "Supplements"). Stored on
/// this device only — never written to HealthKit or iCloud.
struct CustomMetricsView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var defs: [CustomMetricDefinition] = []
    @State private var selected: CustomMetricDefinition?
    @State private var value: Double?
    @State private var date = Date()
    @State private var newName = ""
    @State private var newUnit = ""
    @State private var newAgg = "sum"

    var body: some View {
        Form {
            Section {
                Label("Custom metrics are stored on this device only. They don't sync to your other devices.", systemImage: "iphone")
                    .font(.footnote)
            }
            if !defs.isEmpty {
                Section("Log a value") {
                    Picker("Metric", selection: $selected) {
                        Text("Choose…").tag(CustomMetricDefinition?.none)
                        ForEach(defs) { d in Text(d.name).tag(Optional(d)) }
                    }
                    TextField("Value\(selected.map { " (\($0.unitLabel))" } ?? "")", value: $value, format: .number).keyboardType(.decimalPad)
                    DatePicker("Time", selection: $date)
                    Button("Save value") {
                        guard let d = selected, let v = value else { return }
                        Task { await services.logCustom(d, value: v, at: date); dismiss() }
                    }
                    .disabled(selected == nil || value == nil)
                }
            }
            Section("New metric") {
                TextField("Name (e.g. Mood, Coffee cups)", text: $newName)
                TextField("Unit label (e.g. 1–5, cups)", text: $newUnit)
                Picker("Daily value", selection: $newAgg) {
                    Text("Total").tag("sum")
                    Text("Average").tag("average")
                    Text("Latest").tag("latest")
                }
                Button("Create") {
                    let d = CustomMetricDefinition(name: newName, unitLabel: newUnit, aggregation: newAgg)
                    Task {
                        try? await services.store.addCustomMetric(d)
                        defs = (try? await services.store.customMetrics()) ?? []
                        selected = d
                        newName = ""; newUnit = ""
                    }
                }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if !defs.isEmpty {
                Section("Your metrics") {
                    ForEach(defs) { d in LabeledContent(d.name, value: d.unitLabel) }
                        .onDelete { idx in
                            let ids = idx.map { defs[$0].id }
                            Task {
                                for id in ids { try? await services.store.deleteCustomMetric(id: id) }
                                defs = (try? await services.store.customMetrics()) ?? []
                            }
                        }
                }
            }
        }
        .navigationTitle("Custom Metrics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        .task {
            defs = (try? await services.store.customMetrics()) ?? []
            selected = defs.first
        }
    }
}
