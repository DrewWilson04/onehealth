import Foundation

/// The single source of truth for which metrics the app knows about.
/// Mirrors /docs/metrics.md and web/src/core/metrics.ts — keep in sync
/// (the shared fixture `docs/fixtures/metrics_registry.json` is checked by
/// tests on both platforms).
public enum MetricRegistry {
    private static func q(_ s: String) -> String { "HKQuantityTypeIdentifier\(s)" }
    private static func c(_ s: String) -> String { "HKCategoryTypeIdentifier\(s)" }

    public static let all: [MetricType] = [
        // MARK: Activity & Workouts
        MetricType(id: .steps, displayName: "Steps", unit: .count, kind: .cumulative, dailyStatistic: .sum, section: .activity, healthKitIdentifier: q("StepCount"), isHighVolume: true, higherIsBetter: true, symbol: "figure.walk"),
        MetricType(id: .distanceWalkingRunning, displayName: "Walking + Running Distance", unit: .meter, kind: .cumulative, dailyStatistic: .sum, section: .activity, healthKitIdentifier: q("DistanceWalkingRunning"), isHighVolume: true, higherIsBetter: true, symbol: "figure.run"),
        MetricType(id: .distanceCycling, displayName: "Cycling Distance", unit: .meter, kind: .cumulative, dailyStatistic: .sum, section: .activity, healthKitIdentifier: q("DistanceCycling"), higherIsBetter: true, symbol: "figure.outdoor.cycle"),
        MetricType(id: .distanceSwimming, displayName: "Swimming Distance", unit: .meter, kind: .cumulative, dailyStatistic: .sum, section: .activity, healthKitIdentifier: q("DistanceSwimming"), higherIsBetter: true, symbol: "figure.pool.swim"),
        MetricType(id: .activeEnergy, displayName: "Active Energy", unit: .kcal, kind: .cumulative, dailyStatistic: .sum, section: .activity, healthKitIdentifier: q("ActiveEnergyBurned"), isHighVolume: true, higherIsBetter: true, symbol: "flame.fill"),
        MetricType(id: .basalEnergy, displayName: "Resting Energy", unit: .kcal, kind: .cumulative, dailyStatistic: .sum, section: .activity, healthKitIdentifier: q("BasalEnergyBurned"), isHighVolume: true, symbol: "flame"),
        MetricType(id: .exerciseTime, displayName: "Exercise Minutes", unit: .minute, kind: .cumulative, dailyStatistic: .sum, section: .activity, healthKitIdentifier: q("AppleExerciseTime"), higherIsBetter: true, symbol: "figure.highintensity.intervaltraining"),
        MetricType(id: .standTime, displayName: "Stand Minutes", unit: .minute, kind: .cumulative, dailyStatistic: .sum, section: .activity, healthKitIdentifier: q("AppleStandTime"), higherIsBetter: true, symbol: "figure.stand"),
        MetricType(id: .standHour, displayName: "Stand Hours", unit: .eventCode, kind: .category, dailyStatistic: .count, section: .activity, healthKitIdentifier: c("AppleStandHour"), higherIsBetter: true, symbol: "figure.stand.line.dotted.figure.stand"),
        MetricType(id: .flightsClimbed, displayName: "Flights Climbed", unit: .count, kind: .cumulative, dailyStatistic: .sum, section: .activity, healthKitIdentifier: q("FlightsClimbed"), higherIsBetter: true, symbol: "figure.stairs"),
        MetricType(id: .physicalEffort, displayName: "Physical Effort", unit: .met, kind: .discrete, dailyStatistic: .average, section: .activity, healthKitIdentifier: q("PhysicalEffort"), isHighVolume: true, symbol: "bolt.heart"),
        MetricType(id: .runningSpeed, displayName: "Running Speed", unit: .metersPerSecond, kind: .discrete, dailyStatistic: .average, section: .activity, healthKitIdentifier: q("RunningSpeed"), isHighVolume: true, higherIsBetter: true, symbol: "speedometer"),
        MetricType(id: .runningPower, displayName: "Running Power", unit: .watt, kind: .discrete, dailyStatistic: .average, section: .activity, healthKitIdentifier: q("RunningPower"), isHighVolume: true, higherIsBetter: true, symbol: "bolt"),
        MetricType(id: .cyclingPower, displayName: "Cycling Power", unit: .watt, kind: .discrete, dailyStatistic: .average, section: .activity, healthKitIdentifier: q("CyclingPower"), isHighVolume: true, higherIsBetter: true, symbol: "bolt.circle"),
        MetricType(id: .workout, displayName: "Workouts", unit: .minute, kind: .workout, dailyStatistic: .durationMinutes, section: .activity, healthKitIdentifier: "HKWorkoutTypeIdentifier", isWritable: true, higherIsBetter: true, symbol: "dumbbell.fill"),

        // MARK: Sleep & Recovery
        MetricType(id: .sleep, displayName: "Sleep", unit: .stageCode, kind: .category, dailyStatistic: .durationMinutes, section: .sleep, healthKitIdentifier: c("SleepAnalysis"), isWritable: true, higherIsBetter: true, symbol: "bed.double.fill"),
        MetricType(id: .mindfulMinutes, displayName: "Mindful Minutes", unit: .eventCode, kind: .category, dailyStatistic: .durationMinutes, section: .sleep, healthKitIdentifier: c("MindfulSession"), isWritable: true, higherIsBetter: true, symbol: "brain.head.profile"),
        MetricType(id: .timeInDaylight, displayName: "Time in Daylight", unit: .minute, kind: .cumulative, dailyStatistic: .sum, section: .sleep, healthKitIdentifier: q("TimeInDaylight"), higherIsBetter: true, symbol: "sun.max.fill"),
        MetricType(id: .wristTemperature, displayName: "Sleeping Wrist Temp.", unit: .celsius, kind: .discrete, dailyStatistic: .average, section: .sleep, healthKitIdentifier: q("AppleSleepingWristTemperature"), symbol: "thermometer.variable"),
        MetricType(id: .breathingDisturbances, displayName: "Breathing Disturbances", unit: .count, kind: .discrete, dailyStatistic: .average, section: .sleep, healthKitIdentifier: q("AppleSleepingBreathingDisturbances"), higherIsBetter: false, symbol: "lungs"),

        // MARK: Heart & Vitals
        MetricType(id: .heartRate, displayName: "Heart Rate", unit: .bpm, kind: .discrete, dailyStatistic: .average, section: .heart, healthKitIdentifier: q("HeartRate"), isHighVolume: true, symbol: "heart.fill"),
        MetricType(id: .restingHeartRate, displayName: "Resting Heart Rate", unit: .bpm, kind: .discrete, dailyStatistic: .average, section: .heart, healthKitIdentifier: q("RestingHeartRate"), higherIsBetter: false, symbol: "heart"),
        MetricType(id: .walkingHeartRate, displayName: "Walking HR Average", unit: .bpm, kind: .discrete, dailyStatistic: .average, section: .heart, healthKitIdentifier: q("WalkingHeartRateAverage"), higherIsBetter: false, symbol: "figure.walk.motion"),
        MetricType(id: .hrv, displayName: "Heart Rate Variability", unit: .millisecond, kind: .discrete, dailyStatistic: .average, section: .heart, healthKitIdentifier: q("HeartRateVariabilitySDNN"), higherIsBetter: true, symbol: "waveform.path.ecg"),
        MetricType(id: .heartRateRecovery, displayName: "Cardio Recovery", unit: .bpm, kind: .discrete, dailyStatistic: .average, section: .heart, healthKitIdentifier: q("HeartRateRecoveryOneMinute"), higherIsBetter: true, symbol: "arrow.down.heart"),
        MetricType(id: .oxygenSaturation, displayName: "Blood Oxygen", unit: .percent, kind: .discrete, dailyStatistic: .average, section: .heart, healthKitIdentifier: q("OxygenSaturation"), higherIsBetter: true, symbol: "drop.degreesign"),
        MetricType(id: .respiratoryRate, displayName: "Respiratory Rate", unit: .bpm, kind: .discrete, dailyStatistic: .average, section: .heart, healthKitIdentifier: q("RespiratoryRate"), symbol: "lungs.fill"),
        MetricType(id: .bloodPressureSystolic, displayName: "Systolic BP", unit: .mmHg, kind: .discrete, dailyStatistic: .average, section: .heart, healthKitIdentifier: q("BloodPressureSystolic"), isWritable: true, higherIsBetter: false, symbol: "heart.text.square"),
        MetricType(id: .bloodPressureDiastolic, displayName: "Diastolic BP", unit: .mmHg, kind: .discrete, dailyStatistic: .average, section: .heart, healthKitIdentifier: q("BloodPressureDiastolic"), isWritable: true, higherIsBetter: false, symbol: "heart.text.square"),
        MetricType(id: .vo2Max, displayName: "Cardio Fitness (VO₂ max)", unit: .vo2, kind: .discrete, dailyStatistic: .latest, section: .heart, healthKitIdentifier: q("VO2Max"), higherIsBetter: true, symbol: "lungs"),
        MetricType(id: .bodyTemperature, displayName: "Body Temperature", unit: .celsius, kind: .discrete, dailyStatistic: .average, section: .heart, healthKitIdentifier: q("BodyTemperature"), isWritable: true, symbol: "thermometer.medium"),
        MetricType(id: .bloodGlucose, displayName: "Blood Glucose", unit: .mgPerDL, kind: .discrete, dailyStatistic: .average, section: .heart, healthKitIdentifier: q("BloodGlucose"), isWritable: true, symbol: "drop.fill"),
        MetricType(id: .afibBurden, displayName: "AFib History", unit: .percent, kind: .discrete, dailyStatistic: .latest, section: .heart, healthKitIdentifier: q("AtrialFibrillationBurden"), higherIsBetter: false, symbol: "waveform.path.ecg.rectangle"),
        MetricType(id: .ecg, displayName: "ECG Recordings", unit: .bpm, kind: .ecg, dailyStatistic: .count, section: .heart, healthKitIdentifier: "HKDataTypeIdentifierElectrocardiogram", symbol: "waveform.path.ecg.rectangle.fill"),
        MetricType(id: .highHeartRateEvent, displayName: "High HR Notifications", unit: .eventCode, kind: .category, dailyStatistic: .count, section: .heart, healthKitIdentifier: c("HighHeartRateEvent"), higherIsBetter: false, symbol: "exclamationmark.triangle"),
        MetricType(id: .lowHeartRateEvent, displayName: "Low HR Notifications", unit: .eventCode, kind: .category, dailyStatistic: .count, section: .heart, healthKitIdentifier: c("LowHeartRateEvent"), higherIsBetter: false, symbol: "exclamationmark.triangle"),
        MetricType(id: .irregularRhythmEvent, displayName: "Irregular Rhythm Notifications", unit: .eventCode, kind: .category, dailyStatistic: .count, section: .heart, healthKitIdentifier: c("IrregularHeartRhythmEvent"), higherIsBetter: false, symbol: "exclamationmark.triangle.fill"),
        MetricType(id: .environmentalAudio, displayName: "Environmental Sound", unit: .decibel, kind: .discrete, dailyStatistic: .average, section: .heart, healthKitIdentifier: q("EnvironmentalAudioExposure"), isHighVolume: true, higherIsBetter: false, symbol: "ear"),
        MetricType(id: .headphoneAudio, displayName: "Headphone Audio", unit: .decibel, kind: .discrete, dailyStatistic: .average, section: .heart, healthKitIdentifier: q("HeadphoneAudioExposure"), isHighVolume: true, higherIsBetter: false, symbol: "headphones"),

        // MARK: Body & Nutrition
        MetricType(id: .bodyMass, displayName: "Weight", unit: .kilogram, kind: .discrete, dailyStatistic: .latest, section: .body, healthKitIdentifier: q("BodyMass"), isWritable: true, symbol: "scalemass.fill"),
        MetricType(id: .bodyMassIndex, displayName: "BMI", unit: .count, kind: .discrete, dailyStatistic: .latest, section: .body, healthKitIdentifier: q("BodyMassIndex"), isWritable: true, symbol: "figure"),
        MetricType(id: .bodyFat, displayName: "Body Fat", unit: .percent, kind: .discrete, dailyStatistic: .latest, section: .body, healthKitIdentifier: q("BodyFatPercentage"), isWritable: true, symbol: "percent"),
        MetricType(id: .leanBodyMass, displayName: "Lean Body Mass", unit: .kilogram, kind: .discrete, dailyStatistic: .latest, section: .body, healthKitIdentifier: q("LeanBodyMass"), isWritable: true, symbol: "figure.strengthtraining.traditional"),
        MetricType(id: .height, displayName: "Height", unit: .centimeter, kind: .discrete, dailyStatistic: .latest, section: .body, healthKitIdentifier: q("Height"), isWritable: true, symbol: "ruler"),
        MetricType(id: .waist, displayName: "Waist", unit: .centimeter, kind: .discrete, dailyStatistic: .latest, section: .body, healthKitIdentifier: q("WaistCircumference"), isWritable: true, symbol: "lines.measurement.horizontal"),
        MetricType(id: .dietaryEnergy, displayName: "Calories Eaten", unit: .kcal, kind: .cumulative, dailyStatistic: .sum, section: .body, healthKitIdentifier: q("DietaryEnergyConsumed"), isWritable: true, symbol: "fork.knife"),
        MetricType(id: .protein, displayName: "Protein", unit: .gram, kind: .cumulative, dailyStatistic: .sum, section: .body, healthKitIdentifier: q("DietaryProtein"), isWritable: true, symbol: "p.circle"),
        MetricType(id: .carbohydrates, displayName: "Carbs", unit: .gram, kind: .cumulative, dailyStatistic: .sum, section: .body, healthKitIdentifier: q("DietaryCarbohydrates"), isWritable: true, symbol: "c.circle"),
        MetricType(id: .fat, displayName: "Fat", unit: .gram, kind: .cumulative, dailyStatistic: .sum, section: .body, healthKitIdentifier: q("DietaryFatTotal"), isWritable: true, symbol: "f.circle"),
        MetricType(id: .fiber, displayName: "Fiber", unit: .gram, kind: .cumulative, dailyStatistic: .sum, section: .body, healthKitIdentifier: q("DietaryFiber"), isWritable: true, symbol: "leaf"),
        MetricType(id: .sugar, displayName: "Sugar", unit: .gram, kind: .cumulative, dailyStatistic: .sum, section: .body, healthKitIdentifier: q("DietarySugar"), isWritable: true, symbol: "cube"),
        MetricType(id: .sodium, displayName: "Sodium", unit: .milligram, kind: .cumulative, dailyStatistic: .sum, section: .body, healthKitIdentifier: q("DietarySodium"), isWritable: true, symbol: "s.circle"),
        MetricType(id: .caffeine, displayName: "Caffeine", unit: .milligram, kind: .cumulative, dailyStatistic: .sum, section: .body, healthKitIdentifier: q("DietaryCaffeine"), isWritable: true, symbol: "cup.and.saucer.fill"),
        MetricType(id: .water, displayName: "Water", unit: .milliliter, kind: .cumulative, dailyStatistic: .sum, section: .body, healthKitIdentifier: q("DietaryWater"), isWritable: true, higherIsBetter: true, symbol: "drop"),
    ]

    private static let byID: [MetricID: MetricType] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    private static let byHK: [String: MetricType] = Dictionary(uniqueKeysWithValues: all.compactMap { m in m.healthKitIdentifier.map { ($0, m) } })

    public static func type(_ id: MetricID) -> MetricType? { byID[id] }
    public static func type(healthKitIdentifier: String) -> MetricType? { byHK[healthKitIdentifier] }
    public static func metrics(in section: DashboardSection) -> [MetricType] { all.filter { $0.section == section } }
    public static var writable: [MetricType] { all.filter(\.isWritable) }
}
