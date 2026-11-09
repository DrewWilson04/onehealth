# Metric registry

Source of truth: `ios/Packages/PulseCore/Sources/PulseCore/Model/MetricRegistry.swift`, mirrored by
`web/src/core/metrics.ts`. Ids are persisted and must never change.

The canonical units are listed in [schema.md](schema.md).

## Requested HealthKit access
- **Read:** every type below, plus workout routes, activity summaries (rings), date of birth (for max HR) and biological sex.
- **Write:** the types marked *Writable*. Food is written as an `HKCorrelationTypeIdentifierFood` grouping the nutrient samples.

### Deliberately not requested
App Review 5.1.1 asks apps to request only what they use.
- **Clinical health records.** These need a separate entitlement and extra review.
- **Vision prescriptions, medications, symptoms, cycle tracking, hearing tests, mobility metrics, UV exposure.** No screen uses them yet.

To add one later, add it to the registry and it will be requested automatically.

### Activity & Workouts

| id | Name | Unit | Kind | Daily stat | HealthKit identifier | Raw stored | Writable |
|---|---|---|---|---|---|---|---|
| `steps` | Steps | count | cumulative | sum | `HKQuantityTypeIdentifierStepCount` | no (aggregates only) |  |
| `distanceWalkingRunning` | Walking + Running Distance | meter | cumulative | sum | `HKQuantityTypeIdentifierDistanceWalkingRunning` | no (aggregates only) |  |
| `distanceCycling` | Cycling Distance | meter | cumulative | sum | `HKQuantityTypeIdentifierDistanceCycling` | yes |  |
| `distanceSwimming` | Swimming Distance | meter | cumulative | sum | `HKQuantityTypeIdentifierDistanceSwimming` | yes |  |
| `activeEnergy` | Active Energy | kcal | cumulative | sum | `HKQuantityTypeIdentifierActiveEnergyBurned` | no (aggregates only) |  |
| `basalEnergy` | Resting Energy | kcal | cumulative | sum | `HKQuantityTypeIdentifierBasalEnergyBurned` | no (aggregates only) |  |
| `exerciseTime` | Exercise Minutes | minute | cumulative | sum | `HKQuantityTypeIdentifierAppleExerciseTime` | yes |  |
| `standTime` | Stand Minutes | minute | cumulative | sum | `HKQuantityTypeIdentifierAppleStandTime` | yes |  |
| `standHour` | Stand Hours | eventCode | category | count | `HKCategoryTypeIdentifierAppleStandHour` | yes |  |
| `flightsClimbed` | Flights Climbed | count | cumulative | sum | `HKQuantityTypeIdentifierFlightsClimbed` | yes |  |
| `physicalEffort` | Physical Effort | met | discrete | average | `HKQuantityTypeIdentifierPhysicalEffort` | no (aggregates only) |  |
| `runningSpeed` | Running Speed | metersPerSecond | discrete | average | `HKQuantityTypeIdentifierRunningSpeed` | no (aggregates only) |  |
| `runningPower` | Running Power | watt | discrete | average | `HKQuantityTypeIdentifierRunningPower` | no (aggregates only) |  |
| `cyclingPower` | Cycling Power | watt | discrete | average | `HKQuantityTypeIdentifierCyclingPower` | no (aggregates only) |  |
| `workout` | Workouts | minute | workout | durationMinutes | `HKWorkoutTypeIdentifier` | yes | yes |

### Sleep & Recovery

| id | Name | Unit | Kind | Daily stat | HealthKit identifier | Raw stored | Writable |
|---|---|---|---|---|---|---|---|
| `sleep` | Sleep | stageCode | category | durationMinutes | `HKCategoryTypeIdentifierSleepAnalysis` | yes | yes |
| `mindfulMinutes` | Mindful Minutes | eventCode | category | durationMinutes | `HKCategoryTypeIdentifierMindfulSession` | yes | yes |
| `timeInDaylight` | Time in Daylight | minute | cumulative | sum | `HKQuantityTypeIdentifierTimeInDaylight` | yes |  |
| `wristTemperature` | Sleeping Wrist Temp. | celsius | discrete | average | `HKQuantityTypeIdentifierAppleSleepingWristTemperature` | yes |  |
| `breathingDisturbances` | Breathing Disturbances | count | discrete | average | `HKQuantityTypeIdentifierAppleSleepingBreathingDisturbances` | yes |  |

### Heart & Vitals

| id | Name | Unit | Kind | Daily stat | HealthKit identifier | Raw stored | Writable |
|---|---|---|---|---|---|---|---|
| `heartRate` | Heart Rate | bpm | discrete | average | `HKQuantityTypeIdentifierHeartRate` | no (aggregates only) |  |
| `restingHeartRate` | Resting Heart Rate | bpm | discrete | average | `HKQuantityTypeIdentifierRestingHeartRate` | yes |  |
| `walkingHeartRate` | Walking HR Average | bpm | discrete | average | `HKQuantityTypeIdentifierWalkingHeartRateAverage` | yes |  |
| `hrv` | Heart Rate Variability | millisecond | discrete | average | `HKQuantityTypeIdentifierHeartRateVariabilitySDNN` | yes |  |
| `heartRateRecovery` | Cardio Recovery | bpm | discrete | average | `HKQuantityTypeIdentifierHeartRateRecoveryOneMinute` | yes |  |
| `oxygenSaturation` | Blood Oxygen | percent | discrete | average | `HKQuantityTypeIdentifierOxygenSaturation` | yes |  |
| `respiratoryRate` | Respiratory Rate | bpm | discrete | average | `HKQuantityTypeIdentifierRespiratoryRate` | yes |  |
| `bloodPressureSystolic` | Systolic BP | mmHg | discrete | average | `HKQuantityTypeIdentifierBloodPressureSystolic` | yes | yes |
| `bloodPressureDiastolic` | Diastolic BP | mmHg | discrete | average | `HKQuantityTypeIdentifierBloodPressureDiastolic` | yes | yes |
| `vo2Max` | Cardio Fitness (VO₂ max) | vo2 | discrete | latest | `HKQuantityTypeIdentifierVO2Max` | yes |  |
| `bodyTemperature` | Body Temperature | celsius | discrete | average | `HKQuantityTypeIdentifierBodyTemperature` | yes | yes |
| `bloodGlucose` | Blood Glucose | mgPerDL | discrete | average | `HKQuantityTypeIdentifierBloodGlucose` | yes | yes |
| `afibBurden` | AFib History | percent | discrete | latest | `HKQuantityTypeIdentifierAtrialFibrillationBurden` | yes |  |
| `ecg` | ECG Recordings | bpm | ecg | count | `HKDataTypeIdentifierElectrocardiogram` | yes |  |
| `highHeartRateEvent` | High HR Notifications | eventCode | category | count | `HKCategoryTypeIdentifierHighHeartRateEvent` | yes |  |
| `lowHeartRateEvent` | Low HR Notifications | eventCode | category | count | `HKCategoryTypeIdentifierLowHeartRateEvent` | yes |  |
| `irregularRhythmEvent` | Irregular Rhythm Notifications | eventCode | category | count | `HKCategoryTypeIdentifierIrregularHeartRhythmEvent` | yes |  |
| `environmentalAudio` | Environmental Sound | decibel | discrete | average | `HKQuantityTypeIdentifierEnvironmentalAudioExposure` | no (aggregates only) |  |
| `headphoneAudio` | Headphone Audio | decibel | discrete | average | `HKQuantityTypeIdentifierHeadphoneAudioExposure` | no (aggregates only) |  |

### Body & Nutrition

| id | Name | Unit | Kind | Daily stat | HealthKit identifier | Raw stored | Writable |
|---|---|---|---|---|---|---|---|
| `bodyMass` | Weight | kilogram | discrete | latest | `HKQuantityTypeIdentifierBodyMass` | yes | yes |
| `bodyMassIndex` | BMI | count | discrete | latest | `HKQuantityTypeIdentifierBodyMassIndex` | yes | yes |
| `bodyFat` | Body Fat | percent | discrete | latest | `HKQuantityTypeIdentifierBodyFatPercentage` | yes | yes |
| `leanBodyMass` | Lean Body Mass | kilogram | discrete | latest | `HKQuantityTypeIdentifierLeanBodyMass` | yes | yes |
| `height` | Height | centimeter | discrete | latest | `HKQuantityTypeIdentifierHeight` | yes | yes |
| `waist` | Waist | centimeter | discrete | latest | `HKQuantityTypeIdentifierWaistCircumference` | yes | yes |
| `dietaryEnergy` | Calories Eaten | kcal | cumulative | sum | `HKQuantityTypeIdentifierDietaryEnergyConsumed` | yes | yes |
| `protein` | Protein | gram | cumulative | sum | `HKQuantityTypeIdentifierDietaryProtein` | yes | yes |
| `carbohydrates` | Carbs | gram | cumulative | sum | `HKQuantityTypeIdentifierDietaryCarbohydrates` | yes | yes |
| `fat` | Fat | gram | cumulative | sum | `HKQuantityTypeIdentifierDietaryFatTotal` | yes | yes |
| `fiber` | Fiber | gram | cumulative | sum | `HKQuantityTypeIdentifierDietaryFiber` | yes | yes |
| `sugar` | Sugar | gram | cumulative | sum | `HKQuantityTypeIdentifierDietarySugar` | yes | yes |
| `sodium` | Sodium | milligram | cumulative | sum | `HKQuantityTypeIdentifierDietarySodium` | yes | yes |
| `caffeine` | Caffeine | milligram | cumulative | sum | `HKQuantityTypeIdentifierDietaryCaffeine` | yes | yes |
| `water` | Water | milliliter | cumulative | sum | `HKQuantityTypeIdentifierDietaryWater` | yes | yes |
