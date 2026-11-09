import SwiftUI
import PulseCore
import PulseKit

/// Metric vs imperial input, from Settings or the device locale.
struct UnitPrefs {
    let imperial: Bool
    init(_ p: UserPreferences) {
        switch p.unitSystem {
        case .metric: imperial = false
        case .imperial: imperial = true
        case .automatic: imperial = Locale.current.measurementSystem == .us
        }
    }
    var weightUnit: String { imperial ? "lb" : "kg" }
    func toKg(_ v: Double) -> Double { imperial ? v * 0.45359237 : v }
    var volumeUnit: String { imperial ? "fl oz" : "mL" }
    func toML(_ v: Double) -> Double { imperial ? v * 29.5735295625 : v }
    var distanceUnit: String { imperial ? "mi" : "km" }
    func toMeters(_ v: Double) -> Double { imperial ? v * 1609.344 : v * 1000 }
}

/// Shared save/cancel/error chrome for log forms.
struct LogFormChrome: ViewModifier {
    let title: String
    let canSave: Bool
    let save: () async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false
    @State private var error: String?

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") {
                        saving = true
                        Task {
                            do { try await save(); dismiss() } catch { self.error = error.localizedDescription }
                            saving = false
                        }
                    }
                    .disabled(!canSave || saving)
                }
            }
            .alert("Couldn't save", isPresented: .constant(error != nil)) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }
}

extension View {
    func logForm(_ title: String, canSave: Bool, save: @escaping () async throws -> Void) -> some View {
        modifier(LogFormChrome(title: title, canSave: canSave, save: save))
    }
}

// MARK: Water

struct WaterLogView: View {
    @Environment(AppServices.self) private var services
    @Environment(SettingsStore.self) private var settings
    @State private var amount: Double?
    @State private var date = Date()

    var body: some View {
        let u = UnitPrefs(settings.preferences)
        let presets: [Double] = u.imperial ? [8, 12, 16, 24] : [150, 250, 500, 750]
        Form {
            Section("Quick add") {
                HStack {
                    ForEach(presets, id: \.self) { p in
                        Button("\(Int(p)) \(u.volumeUnit)") { amount = p }
                            .buttonStyle(.bordered)
                            .tint(amount == p ? Theme.skyBlue : .secondary)
                    }
                }
            }
            Section {
                TextField("Amount (\(u.volumeUnit))", value: $amount, format: .number).keyboardType(.decimalPad)
                DatePicker("Time", selection: $date)
            }
        }
        .logForm("Water", canSave: (amount ?? 0) > 0) {
            try await services.writer.log(.water, value: u.toML(amount ?? 0), at: date)
            await services.didWrite([.water])
        }
    }
}

// MARK: Weight

struct WeightLogView: View {
    @Environment(AppServices.self) private var services
    @Environment(SettingsStore.self) private var settings
    @State private var weight: Double?
    @State private var bodyFat: Double?
    @State private var date = Date()

    var body: some View {
        let u = UnitPrefs(settings.preferences)
        Form {
            TextField("Weight (\(u.weightUnit))", value: $weight, format: .number).keyboardType(.decimalPad)
            TextField("Body fat % (optional)", value: $bodyFat, format: .number).keyboardType(.decimalPad)
            DatePicker("Time", selection: $date)
        }
        .logForm("Weight", canSave: (weight ?? 0) > 0) {
            try await services.writer.log(.bodyMass, value: u.toKg(weight ?? 0), at: date)
            var written: [MetricID] = [.bodyMass]
            if let bf = bodyFat, bf > 0, bf < 80 {
                try await services.writer.log(.bodyFat, value: bf, at: date)
                written.append(.bodyFat)
            }
            await services.didWrite(written)
        }
    }
}

// MARK: Blood pressure

struct BloodPressureLogView: View {
    @Environment(AppServices.self) private var services
    @State private var sys: Double?
    @State private var dia: Double?
    @State private var date = Date()

    var body: some View {
        Form {
            TextField("Systolic (mmHg)", value: $sys, format: .number).keyboardType(.numberPad)
            TextField("Diastolic (mmHg)", value: $dia, format: .number).keyboardType(.numberPad)
            DatePicker("Time", selection: $date)
        }
        .logForm("Blood Pressure", canSave: (sys ?? 0) > (dia ?? 0) && (dia ?? 0) > 0) {
            try await services.writer.logBloodPressure(systolic: sys ?? 0, diastolic: dia ?? 0, at: date)
            await services.didWrite([.bloodPressureSystolic, .bloodPressureDiastolic])
        }
    }
}

// MARK: Mindful / Sleep

struct MindfulLogView: View {
    @Environment(AppServices.self) private var services
    @State private var minutes = 10.0
    @State private var date = Date().addingTimeInterval(-600)

    var body: some View {
        Form {
            Stepper("\(Int(minutes)) minutes", value: $minutes, in: 1...180)
            DatePicker("Started", selection: $date)
        }
        .logForm("Mindful Minutes", canSave: true) {
            try await services.writer.logMindful(start: date, minutes: minutes)
            await services.didWrite([.mindfulMinutes])
        }
    }
}

struct SleepLogView: View {
    @Environment(AppServices.self) private var services
    @State private var bed = Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: Date().addingTimeInterval(-86_400)) ?? Date()
    @State private var wake = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date()

    var body: some View {
        Form {
            DatePicker("Fell asleep", selection: $bed)
            DatePicker("Woke up", selection: $wake)
            Text("Manually logged sleep is used for your dashboard but has no stages.").font(.caption).foregroundStyle(.secondary)
        }
        .logForm("Sleep", canSave: wake > bed && wake.timeIntervalSince(bed) < 20 * 3600) {
            try await services.writer.logSleep(bedtime: bed, wake: wake)
            await services.didWrite([.sleep])
        }
    }
}
