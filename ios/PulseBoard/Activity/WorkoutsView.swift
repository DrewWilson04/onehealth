import SwiftUI
import MapKit
import HealthKit
import PulseCore
import PulseKit

struct WorkoutsView: View {
    @Environment(AppServices.self) private var services
    @Environment(IngestionStatus.self) private var status
    @State private var workouts: [Sample] = []

    var body: some View {
        List {
            if workouts.isEmpty {
                ContentUnavailableView("No workouts", systemImage: "figure.run", description: Text("Workouts from any device or app appear here."))
            }
            ForEach(workouts) { w in
                NavigationLink { WorkoutDetailView(workout: w) } label: { WorkoutRow(workout: w) }
            }
        }
        .navigationTitle("Workouts")
        .task(id: status.dataRevision) {
            let now = Date()
            let s = (try? await services.store.samples(.workout, from: now.addingTimeInterval(-90 * 86_400), to: now)) ?? []
            workouts = WorkoutMerger.merge(s, priority: services.settings.sourcePriority).sorted { $0.start > $1.start }
        }
    }
}

struct WorkoutRow: View {
    let workout: Sample
    var body: some View {
        let info = WorkoutInfo(workout)
        HStack {
            Image(systemName: WorkoutStyle.symbol(info?.activityType ?? "other"))
                .font(.title3).foregroundStyle(Theme.orange).frame(width: 34)
            VStack(alignment: .leading) {
                Text(WorkoutStyle.name(info?.activityType ?? "other")).font(.headline)
                Text(workout.start.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(Fmt.duration(minutes: workout.value)).monospacedDigit()
                SourceBadge(sourceKey: workout.source.attribution)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct WorkoutDetailView: View {
    let workout: Sample
    @Environment(AppServices.self) private var services
    @State private var route: [CLLocationCoordinate2D] = []

    var body: some View {
        let info = WorkoutInfo(workout)
        let sets = ExerciseSet.decode(workout.metadata?[WorkoutInfo.setsKey])
        List {
            if route.count > 1 {
                Section {
                    Map {
                        MapPolyline(coordinates: route).stroke(Theme.orange, lineWidth: 4)
                    }
                    .frame(height: 220)
                    .listRowInsets(EdgeInsets())
                    .accessibilityLabel("Workout route map")
                }
            }
            Section {
                LabeledContent("Duration", value: Fmt.duration(minutes: workout.value))
                if let e = info?.energyKcal { LabeledContent("Active energy", value: "\(Int(e)) kcal") }
                if let d = info?.distanceMeters, let m = MetricRegistry.type(.distanceWalkingRunning) { LabeledContent("Distance", value: Fmt.value(d, metric: m)) }
                if let hr = info?.averageHeartRate { LabeledContent("Avg heart rate", value: "\(Int(hr)) bpm") }
                LabeledContent("Source", value: workout.source.name)
                if let merged = workout.metadata?[WorkoutInfo.mergedFromKey], !merged.isEmpty {
                    Text("Merged with \(merged.split(separator: ",").count) duplicate recording(s) from other apps.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if workout.isManual { Label("Logged manually", systemImage: "hand.point.up.left").font(.caption) }
            }
            if !sets.isEmpty {
                Section("Sets") {
                    ForEach(sets) { s in
                        LabeledContent(s.exercise) {
                            Text("\(s.reps) × \(s.weightKg.map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) kg" } ?? "bodyweight")")
                        }
                    }
                    LabeledContent("Total volume", value: "\(Int(ExerciseSet.volume(sets))) kg")
                }
            }
        }
        .navigationTitle(WorkoutStyle.name(info?.activityType ?? "other"))
        .task {
            guard let hk = try? await services.provider.hkWorkout(id: workout.id),
                  let pts = try? await services.provider.store.workoutRoute(for: hk) else { return }
            route = pts.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        }
    }
}

enum WorkoutStyle {
    static func name(_ type: String) -> String {
        switch type {
        case "traditionalStrengthTraining": return "Strength Training"
        case "functionalStrengthTraining": return "Functional Strength"
        case "highIntensityIntervalTraining": return "HIIT"
        case "mixedCardio": return "Mixed Cardio"
        case "coreTraining": return "Core Training"
        case "crossTraining": return "Cross Training"
        case "mindAndBody": return "Mind & Body"
        default:
            return type.prefix(1).uppercased() + type.dropFirst().replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
        }
    }

    static func symbol(_ type: String) -> String {
        switch type {
        case "running": return "figure.run"
        case "walking": return "figure.walk"
        case "cycling": return "figure.outdoor.cycle"
        case "swimming": return "figure.pool.swim"
        case "hiking": return "figure.hiking"
        case "yoga": return "figure.yoga"
        case "traditionalStrengthTraining", "functionalStrengthTraining": return "figure.strengthtraining.traditional"
        case "highIntensityIntervalTraining": return "figure.highintensity.intervaltraining"
        case "rowing": return "figure.rower"
        case "elliptical": return "figure.elliptical"
        case "dance": return "figure.dance"
        case "pilates": return "figure.pilates"
        case "tennis": return "figure.tennis"
        case "soccer": return "figure.soccer"
        case "basketball": return "figure.basketball"
        case "golf": return "figure.golf"
        default: return "figure.mixed.cardio"
        }
    }
}
