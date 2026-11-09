import SwiftUI
import PulseCore
import PulseKit

/// Pro: CSV / PDF export for any date range. Files are generated on-device
/// and shared with the system share sheet — nothing is uploaded.
struct ExportView: View {
    @Environment(AppServices.self) private var services
    @Environment(EntitlementManager.self) private var entitlements

    enum Format: String, CaseIterable, Identifiable {
        case dailyCSV = "Daily summary (CSV)", samplesCSV = "Raw samples (CSV)", scoresCSV = "Scores (CSV)", pdf = "PDF report"
        var id: String { rawValue }
    }

    @State private var format: Format = .dailyCSV
    @State private var start = Calendar.current.date(byAdding: .day, value: -29, to: Date())!
    @State private var end = Date()
    @State private var sections: Set<DashboardSection> = Set(DashboardSection.allCases)
    @State private var fileURL: URL?
    @State private var working = false
    @State private var error: String?
    @State private var showPaywall = false

    var body: some View {
        Form {
            if !entitlements.isEnabled(.export) {
                Section {
                    Label("CSV and PDF export is part of Pro.", systemImage: "lock.fill")
                    Button("See Pro") { showPaywall = true }
                }
            }
            Section("Range") {
                HStack {
                    ForEach([7, 30, 90, 365], id: \.self) { d in
                        Button(d == 365 ? "1Y" : "\(d)D") {
                            start = Calendar.current.date(byAdding: .day, value: -(d - 1), to: Date())!
                            end = Date()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                DatePicker("From", selection: $start, in: ...end, displayedComponents: .date)
                DatePicker("To", selection: $end, in: start...Date(), displayedComponents: .date)
            }
            Section("Format") {
                Picker("Format", selection: $format) { ForEach(Format.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.inline)
                    .labelsHidden()
            }
            if format != .scoresCSV {
                Section("Include") {
                    ForEach(DashboardSection.allCases) { s in
                        Toggle(s.title, isOn: Binding(get: { sections.contains(s) }, set: { on in
                            if on { sections.insert(s) } else { sections.remove(s) }
                        }))
                    }
                }
            }
            Section {
                Button(working ? "Preparing…" : "Create export") { Task { await create() } }
                    .disabled(working || !entitlements.isEnabled(.export) || sections.isEmpty)
                if let url = fileURL {
                    ShareLink(item: url) { Label("Share \(url.lastPathComponent)", systemImage: "square.and.arrow.up") }
                }
            } footer: {
                Text("Exports are created on this device. Only share them with people and apps you trust.")
            }
        }
        .navigationTitle("Export")
        .sheet(isPresented: $showPaywall) { PaywallView(highlight: .export) }
        .alert("Export failed", isPresented: .constant(error != nil)) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }

    private var metrics: [MetricType] {
        MetricRegistry.all.filter { sections.contains($0.section) && $0.kind != .ecg }
    }

    private func create() async {
        working = true
        defer { working = false }
        let cal = services.calendar
        let from = DayKey(start, calendar: cal), to = DayKey(end, calendar: cal)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        do {
            switch format {
            case .dailyCSV:
                var rows: [MetricID: [DailyAggregate]] = [:]
                var withData: [MetricType] = []
                for m in metrics {
                    let r = (try? await services.store.aggregates(m.id, period: .day, from: from, to: to)) ?? []
                    if !r.isEmpty { rows[m.id] = r; withData.append(m) }
                }
                fileURL = try write(CSVExporter.dailySummary(metrics: withData, rows: rows, from: from, to: to),
                                    CSVExporter.fileName("daily", from: from, to: to), dir)
            case .samplesCSV:
                var all: [Sample] = []
                for m in metrics where !m.isHighVolume {
                    all += (try? await services.store.samples(m.id, from: from.date(cal), to: to.addingDays(1).date(cal))) ?? []
                }
                fileURL = try write(CSVExporter.samples(all), CSVExporter.fileName("samples", from: from, to: to), dir)
            case .scoresCSV:
                var results: [ScoreResult] = []
                for k in ScoreKind.allCases { results += await services.scoreService.history(k, from: from, to: to) }
                fileURL = try write(CSVExporter.scores(results, from: from, to: to), CSVExporter.fileName("scores", from: from, to: to), dir)
            case .pdf:
                fileURL = try await PDFReportRenderer.render(services: services, metrics: metrics, from: from, to: to, directory: dir)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func write(_ text: String, _ name: String, _ dir: URL) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try text.data(using: .utf8)!.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }
}
