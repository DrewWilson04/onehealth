import Foundation
import HealthKit
import PulseCore

/// Maps PulseCore metrics/units to HealthKit types/units.
public enum HKMapping {
    /// HealthKit object type for a metric (nil if the OS doesn't support it).
    public static func objectType(for metric: MetricType) -> HKObjectType? {
        guard let id = metric.healthKitIdentifier else { return nil }
        switch metric.kind {
        case .cumulative, .discrete:
            return HKObjectType.quantityType(forIdentifier: HKQuantityTypeIdentifier(rawValue: id))
        case .category:
            return HKObjectType.categoryType(forIdentifier: HKCategoryTypeIdentifier(rawValue: id))
        case .workout:
            return HKObjectType.workoutType()
        case .ecg:
            return HKObjectType.electrocardiogramType()
        }
    }

    public static func sampleType(for metric: MetricType) -> HKSampleType? {
        objectType(for: metric) as? HKSampleType
    }

    public static func quantityType(for metric: MetricType) -> HKQuantityType? {
        objectType(for: metric) as? HKQuantityType
    }

    /// The HKUnit to read a quantity in, and the unit string PulseCore's
    /// `UnitConverter` understands for that HKUnit.
    public static func hkUnit(for unit: MetricUnit) -> (HKUnit, String)? {
        switch unit {
        case .count: return (.count(), "count")
        case .kcal: return (.kilocalorie(), "kcal")
        case .meter: return (.meter(), "m")
        case .centimeter: return (.meterUnit(with: .centi), "cm")
        case .minute: return (.minute(), "min")
        case .second: return (.second(), "s")
        case .bpm: return (HKUnit.count().unitDivided(by: .minute()), "count/min")
        case .millisecond: return (.secondUnit(with: .milli), "ms")
        case .percent: return (.percent(), "%")
        case .mmHg: return (.millimeterOfMercury(), "mmHg")
        case .vo2:
            return (HKUnit.literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute())), "ml/(kg*min)")
        case .kilogram: return (.gramUnit(with: .kilo), "kg")
        case .gram: return (.gram(), "g")
        case .milligram: return (.gramUnit(with: .milli), "mg")
        case .milliliter: return (.literUnit(with: .milli), "mL")
        case .celsius: return (.degreeCelsius(), "degC")
        case .decibel: return (.decibelAWeightedSoundPressureLevel(), "dBASPL")
        case .metersPerSecond: return (HKUnit.meter().unitDivided(by: .second()), "m/s")
        case .watt: return (.watt(), "W")
        case .met:
            return (HKUnit.kilocalorie().unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .hour())), "kcal/(kg·hr)")
        case .mgPerDL: return (HKUnit(from: "mg/dL"), "mg/dL")
        case .stageCode, .eventCode: return nil
        }
    }

    /// Converts a canonical PulseCore value back into an HKQuantity (writes).
    /// Percent is canonical 0–100 but HealthKit expects a fraction.
    public static func quantity(_ value: Double, for metric: MetricType) -> HKQuantity? {
        guard let (unit, _) = hkUnit(for: metric.unit) else { return nil }
        let v = metric.unit == .percent ? value / 100 : value
        return HKQuantity(unit: unit, doubleValue: v)
    }

    /// Every type we request read access for. Deliberately *not* every type
    /// HealthKit offers (App Review 5.1.1 — request only what you use).
    /// Excluded on purpose: clinical health records (separate entitlement and
    /// review), vision prescriptions, and other types no screen uses.
    public static func readTypes(for metrics: [MetricType] = MetricRegistry.all) -> Set<HKObjectType> {
        var set = Set(metrics.compactMap(objectType(for:)))
        set.insert(HKSeriesType.workoutRoute())
        set.insert(HKObjectType.activitySummaryType())
        if let dob = HKObjectType.characteristicType(forIdentifier: .dateOfBirth) { set.insert(dob) }
        if let sex = HKObjectType.characteristicType(forIdentifier: .biologicalSex) { set.insert(sex) }
        return set
    }

    /// Types we write for manual entry. Food is written as an HKCorrelation of
    /// these nutrient types (correlation types themselves are not authorized).
    public static func writeTypes(for metrics: [MetricType] = MetricRegistry.writable) -> Set<HKSampleType> {
        Set(metrics.compactMap(sampleType(for:)))
    }

    /// Which metrics get HealthKit background delivery. Kept small for battery:
    /// everything else refreshes when the app is foregrounded.
    public static let backgroundDelivery: [(MetricID, HKUpdateFrequency)] = [
        (.steps, .hourly), (.activeEnergy, .hourly), (.exerciseTime, .hourly),
        (.workout, .immediate), (.sleep, .hourly), (.restingHeartRate, .hourly),
        (.hrv, .hourly), (.bodyMass, .daily), (.dietaryEnergy, .hourly), (.water, .hourly),
    ]

    public static func activityName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "running"
        case .walking: return "walking"
        case .cycling: return "cycling"
        case .swimming: return "swimming"
        case .hiking: return "hiking"
        case .yoga: return "yoga"
        case .traditionalStrengthTraining: return "traditionalStrengthTraining"
        case .functionalStrengthTraining: return "functionalStrengthTraining"
        case .highIntensityIntervalTraining: return "highIntensityIntervalTraining"
        case .rowing: return "rowing"
        case .elliptical: return "elliptical"
        case .stairClimbing: return "stairClimbing"
        case .dance: return "dance"
        case .pilates: return "pilates"
        case .coreTraining: return "coreTraining"
        case .crossTraining: return "crossTraining"
        case .mixedCardio: return "mixedCardio"
        case .tennis: return "tennis"
        case .soccer: return "soccer"
        case .basketball: return "basketball"
        case .golf: return "golf"
        case .downhillSkiing: return "downhillSkiing"
        case .snowboarding: return "snowboarding"
        case .crossCountrySkiing: return "crossCountrySkiing"
        case .climbing: return "climbing"
        case .martialArts: return "martialArts"
        case .boxing: return "boxing"
        case .mindAndBody: return "mindAndBody"
        case .cooldown: return "cooldown"
        case .flexibility: return "flexibility"
        case .paddleSports: return "paddleSports"
        case .surfingSports: return "surfingSports"
        case .swimBikeRun: return "swimBikeRun"
        case .wheelchairRunPace: return "wheelchairRunPace"
        case .wheelchairWalkPace: return "wheelchairWalkPace"
        case .pickleball: return "pickleball"
        default: return "other"
        }
    }

    public static func activityType(named name: String) -> HKWorkoutActivityType {
        switch name {
        case "running": return .running
        case "walking": return .walking
        case "cycling": return .cycling
        case "swimming": return .swimming
        case "hiking": return .hiking
        case "yoga": return .yoga
        case "traditionalStrengthTraining": return .traditionalStrengthTraining
        case "functionalStrengthTraining": return .functionalStrengthTraining
        case "highIntensityIntervalTraining": return .highIntensityIntervalTraining
        case "rowing": return .rowing
        case "elliptical": return .elliptical
        case "pilates": return .pilates
        case "coreTraining": return .coreTraining
        case "dance": return .dance
        case "crossTraining": return .crossTraining
        case "mixedCardio": return .mixedCardio
        default: return .other
        }
    }
}
