import Foundation

/// Stable, platform-neutral metric identifier. Raw values are persisted (local
/// DB, CloudKit settings, web IndexedDB) and must never change once shipped.
public struct MetricID: RawRepresentable, Hashable, Codable, Sendable, Comparable, CustomStringConvertible, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ raw: String) { self.rawValue = raw }
    public init(stringLiteral value: String) { self.rawValue = value }
    public var description: String { rawValue }
    public static func < (lhs: MetricID, rhs: MetricID) -> Bool { lhs.rawValue < rhs.rawValue }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

public extension MetricID {
    // Activity & Workouts
    static let steps: MetricID = "steps"
    static let distanceWalkingRunning: MetricID = "distanceWalkingRunning"
    static let distanceCycling: MetricID = "distanceCycling"
    static let distanceSwimming: MetricID = "distanceSwimming"
    static let activeEnergy: MetricID = "activeEnergy"
    static let basalEnergy: MetricID = "basalEnergy"
    static let exerciseTime: MetricID = "exerciseTime"
    static let standTime: MetricID = "standTime"
    static let standHour: MetricID = "standHour"
    static let flightsClimbed: MetricID = "flightsClimbed"
    static let physicalEffort: MetricID = "physicalEffort"
    static let runningSpeed: MetricID = "runningSpeed"
    static let runningPower: MetricID = "runningPower"
    static let cyclingPower: MetricID = "cyclingPower"
    static let workout: MetricID = "workout"

    // Sleep & Recovery
    static let sleep: MetricID = "sleep"
    static let mindfulMinutes: MetricID = "mindfulMinutes"
    static let timeInDaylight: MetricID = "timeInDaylight"
    static let wristTemperature: MetricID = "wristTemperature"
    static let breathingDisturbances: MetricID = "breathingDisturbances"

    // Heart & Vitals
    static let heartRate: MetricID = "heartRate"
    static let restingHeartRate: MetricID = "restingHeartRate"
    static let walkingHeartRate: MetricID = "walkingHeartRate"
    static let hrv: MetricID = "hrv"
    static let heartRateRecovery: MetricID = "heartRateRecovery"
    static let oxygenSaturation: MetricID = "oxygenSaturation"
    static let respiratoryRate: MetricID = "respiratoryRate"
    static let bloodPressureSystolic: MetricID = "bloodPressureSystolic"
    static let bloodPressureDiastolic: MetricID = "bloodPressureDiastolic"
    static let vo2Max: MetricID = "vo2Max"
    static let bodyTemperature: MetricID = "bodyTemperature"
    static let bloodGlucose: MetricID = "bloodGlucose"
    static let afibBurden: MetricID = "afibBurden"
    static let ecg: MetricID = "ecg"
    static let highHeartRateEvent: MetricID = "highHeartRateEvent"
    static let lowHeartRateEvent: MetricID = "lowHeartRateEvent"
    static let irregularRhythmEvent: MetricID = "irregularRhythmEvent"
    static let environmentalAudio: MetricID = "environmentalAudio"
    static let headphoneAudio: MetricID = "headphoneAudio"

    // Body & Nutrition
    static let bodyMass: MetricID = "bodyMass"
    static let bodyMassIndex: MetricID = "bodyMassIndex"
    static let bodyFat: MetricID = "bodyFat"
    static let leanBodyMass: MetricID = "leanBodyMass"
    static let height: MetricID = "height"
    static let waist: MetricID = "waist"
    static let dietaryEnergy: MetricID = "dietaryEnergy"
    static let protein: MetricID = "protein"
    static let carbohydrates: MetricID = "carbohydrates"
    static let fat: MetricID = "fat"
    static let fiber: MetricID = "fiber"
    static let sugar: MetricID = "sugar"
    static let sodium: MetricID = "sodium"
    static let caffeine: MetricID = "caffeine"
    static let water: MetricID = "water"

    /// Custom, user-defined metrics are namespaced `custom.<uuid>` and never
    /// leave the device.
    static func custom(_ id: String) -> MetricID { MetricID("custom.\(id)") }
    var isCustom: Bool { rawValue.hasPrefix("custom.") }
}
