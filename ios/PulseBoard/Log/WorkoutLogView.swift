import SwiftUI
import PulseCore
import PulseKit

/// Workout with optional energy/distance and strength sets (reps × weight).
struct WorkoutLogView: View {
    @Environment(AppServices.self) private var services
    @Environment(SettingsStore.self) private var settings

    @State private var activity = "traditionalStrengthTraining"
    @State private var start = Date().addingTimeInterval(-3600)
    @State private var minutes = 45.0
    @State private var energy: Double?
    @State private var distance: Double?
    @State private var sets: [ExerciseSet] = []
    @State private var newExercise = ""
    @State private var newReps = 10
    @State private var newWeight: Double?

    private let activities = ["traditionalStrengthTraining", "functionalStrengthTraining", "running", "walking", "cycling",
                              "swimming", "hiking", "yoga", "highIntensityIntervalTraining", "rowing", "elliptical",
                              "pilates", "coreTraining", "dance", "other"]
    private var isStrength: Bool { activity.contains("StrengthTraining") || activity == "coreTraining" }
    private var isDistance: Bool { ["running", "walking", "cycling", "swimming", "hiking", "rowing"].contains(activity) }

    var body: some View {
        let u = UnitPrefs(settings.preferences)
        Form {
            Section {
                Picker("Type", selection: $activity) {
                    ForEach(activities, id: \.self) { a in
                        Label(WorkoutStyle.name(a), systemImage: WorkoutStyle.symbol(a)).tag(a)
                    }
                }
                DatePicker("Start", selection: $start)
                Stepper("Duration: \(Int(minutes)) min", value: $minutes, in: 1...600, step: 5)
                TextField("Active energy (kcal, optional)", value: $energy, format: .number).keyboardType(.decimalPad)
                if isDistance {
                    TextField("Distance (\(u.distanceUnit), optional)", value: $distance, format: .number).keyboardType(.decimalPad)
                }
            }
            if isStrength {
                Section {
                    ForEach(sets) { s in
                        LabeledContent(s.exercise) {
                            Text("\(s.reps) × \(s.weightKg.map { "\(($0 / (u.imperial ? 0.45359237 : 1)).formatted(.number.precision(.fractionLength(0...1)))) \(u.weightUnit)" } ?? "BW")")
                        }
                    }
                    .onDelete { sets.remove(atOffsets: $0) }
                    TextField("Exercise", text: $newExercise)
                    Stepper("Reps: \(newReps)", value: $newReps, in: 1...100)
                    TextField("Weight (\(u.weightUnit), blank = bodyweight)", value: $newWeight, format: .number).keyboardType(.decimalPad)
                    Button("Add set") {
                        sets.append(ExerciseSet(exercise: newExercise.isEmpty ? "Exercise" : newExercise, reps: newReps,
                                                weightKg: newWeight.map(u.toKg)))
                    }
                    if let last = sets.last {
                        Button("Repeat last set") { sets.append(ExerciseSet(exercise: last.exercise, reps: last.reps, weightKg: last.weightKg)) }
                    }
                } header: {
                    Text("Sets")
                } footer: {
                    Text("Sets are stored with the workout in Apple Health (as workout metadata), so they stay with it on all your devices.")
                }
            }
        }
        .logForm("Log Workout", canSave: minutes > 0) {
            try await services.writer.logWorkout(activityType: activity, start: start, durationMinutes: minutes, energyKcal: energy,
                                                 distanceMeters: distance.map(u.toMeters), sets: sets)
            await services.didWrite([.workout, .activeEnergy])
        }
    }
}
