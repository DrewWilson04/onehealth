import Foundation

public enum MealSlot: String, Codable, Sendable, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

/// A logged food item (written to HealthKit as an HKCorrelation of nutrients).
public struct FoodEntry: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var date: Date
    public var kcal: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    public var fiber: Double?
    public var sugar: Double?
    public var sodium: Double?
    public var meal: MealSlot

    public init(id: String = UUID().uuidString, name: String, date: Date, kcal: Double, protein: Double, carbs: Double,
                fat: Double, fiber: Double? = nil, sugar: Double? = nil, sodium: Double? = nil, meal: MealSlot) {
        self.id = id
        self.name = name
        self.date = date
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.fiber = fiber
        self.sugar = sugar
        self.sodium = sodium
        self.meal = meal
    }

    /// Kcal implied by macros (4/4/9) — used to sanity-check entries.
    public var macroKcal: Double { protein * 4 + carbs * 4 + fat * 9 }
}

/// A saved meal template: foods + macros only, NOT tied to any consumption
/// event. Synced via CloudKit as user configuration.
/// NOTE (guideline 5.1.3 gray area): templates contain nutrition values but
/// no personal health record. If you want zero iCloud exposure, set
/// `SettingsSync.syncMealTemplates = false` to keep them local-only.
public struct MealTemplate: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var items: [FoodEntry]
    public init(id: String = UUID().uuidString, name: String, items: [FoodEntry]) {
        self.id = id
        self.name = name
        self.items = items
    }
    public var totalKcal: Double { items.reduce(0) { $0 + $1.kcal } }
}

/// One strength set. Stored as JSON in HKWorkout metadata (`PulseBoardSets`)
/// because HealthKit has no sets/reps/weight sample types.
public struct ExerciseSet: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var exercise: String
    public var reps: Int
    public var weightKg: Double?
    public var durationSeconds: Double?
    public init(id: String = UUID().uuidString, exercise: String, reps: Int, weightKg: Double? = nil, durationSeconds: Double? = nil) {
        self.id = id
        self.exercise = exercise
        self.reps = reps
        self.weightKg = weightKg
        self.durationSeconds = durationSeconds
    }

    public static func encode(_ sets: [ExerciseSet]) -> String {
        (try? String(data: JSONEncoder().encode(sets), encoding: .utf8)) ?? "[]"
    }
    public static func decode(_ s: String?) -> [ExerciseSet] {
        guard let s, let d = s.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([ExerciseSet].self, from: d)) ?? []
    }
    /// Total volume (reps × kg).
    public static func volume(_ sets: [ExerciseSet]) -> Double {
        sets.reduce(0) { $0 + Double($1.reps) * ($1.weightKg ?? 0) }
    }
}

/// User-defined metric (no HealthKit type) — stays on this device only.
public struct CustomMetricDefinition: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var unitLabel: String
    public var symbol: String
    public var aggregation: String
    public init(id: String = UUID().uuidString, name: String, unitLabel: String, symbol: String = "star", aggregation: String = "sum") {
        self.id = id
        self.name = name
        self.unitLabel = unitLabel
        self.symbol = symbol
        self.aggregation = aggregation
    }
    public var metricID: MetricID { .custom(id) }
}
