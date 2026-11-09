// A small but realistic export.xml covering the element types we parse.
export const SAMPLE_EXPORT = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE HealthData [
<!ELEMENT HealthData (ExportDate,Me,(Record|Correlation|Workout|ActivitySummary|ClinicalRecord)*)>
<!ATTLIST HealthData locale CDATA #REQUIRED>
<!ELEMENT Record ((MetadataEntry|HeartRateVariabilityMetadataList)*)>
]>
<HealthData locale="en_US">
 <ExportDate value="2024-03-12 09:00:00 +0000"/>
 <Me HKCharacteristicTypeIdentifierDateOfBirth="1990-05-01" HKCharacteristicTypeIdentifierBiologicalSex="HKBiologicalSexFemale" HKCharacteristicTypeIdentifierBloodType="HKBloodTypeNotSet"/>
 <Record type="HKQuantityTypeIdentifierStepCount" sourceName="Alex's Apple Watch" sourceVersion="10.3" device="&lt;&lt;HKDevice: 0x1&gt;, name:Apple Watch, manufacturer:Apple Inc., model:Watch, hardware:Watch7,5, software:10.3&gt;" unit="count" creationDate="2024-03-10 09:01:00 +0000" startDate="2024-03-10 08:00:00 +0000" endDate="2024-03-10 09:00:00 +0000" value="600"/>
 <Record type="HKQuantityTypeIdentifierStepCount" sourceName="Alex's iPhone" sourceVersion="17.4" device="&lt;&lt;HKDevice: 0x2&gt;, name:iPhone, manufacturer:Apple Inc., model:iPhone, hardware:iPhone15,2, software:17.4&gt;" unit="count" creationDate="2024-03-10 09:01:00 +0000" startDate="2024-03-10 08:00:00 +0000" endDate="2024-03-10 09:00:00 +0000" value="550"/>
 <Record type="HKQuantityTypeIdentifierStepCount" sourceName="Alex's iPhone" unit="count" startDate="2024-03-10 12:00:00 +0000" endDate="2024-03-10 12:30:00 +0000" value="300"/>
 <Record type="HKQuantityTypeIdentifierHeartRate" sourceName="Alex's Apple Watch" unit="count/min" startDate="2024-03-10 08:10:00 +0000" endDate="2024-03-10 08:10:00 +0000" value="70">
  <MetadataEntry key="HKMetadataKeyHeartRateMotionContext" value="0"/>
 </Record>
 <Record type="HKQuantityTypeIdentifierHeartRate" sourceName="Alex's Apple Watch" unit="count/min" startDate="2024-03-10 08:20:00 +0000" endDate="2024-03-10 08:20:00 +0000" value="90"/>
 <Record type="HKQuantityTypeIdentifierHeartRate" sourceName="WHOOP" unit="count/min" startDate="2024-03-10 08:20:00 +0000" endDate="2024-03-10 08:20:00 +0000" value="200"/>
 <Record type="HKQuantityTypeIdentifierHeartRateVariabilitySDNN" sourceName="Alex's Apple Watch" unit="ms" startDate="2024-03-10 04:00:00 +0000" endDate="2024-03-10 04:01:00 +0000" value="48.5">
  <HeartRateVariabilityMetadataList>
   <InstantaneousBeatsPerMinute bpm="58" time="4:00:01.00 AM"/>
  </HeartRateVariabilityMetadataList>
 </Record>
 <Record type="HKQuantityTypeIdentifierBodyMass" sourceName="Health" unit="lb" startDate="2024-03-10 07:00:00 +0000" endDate="2024-03-10 07:00:00 +0000" value="180">
  <MetadataEntry key="HKWasUserEntered" value="1"/>
 </Record>
 <Record type="HKCategoryTypeIdentifierSleepAnalysis" sourceName="Alex's Apple Watch" startDate="2024-03-09 23:00:00 +0000" endDate="2024-03-10 03:00:00 +0000" value="HKCategoryValueSleepAnalysisAsleepCore"/>
 <Record type="HKCategoryTypeIdentifierSleepAnalysis" sourceName="Alex's Apple Watch" startDate="2024-03-10 03:00:00 +0000" endDate="2024-03-10 04:00:00 +0000" value="HKCategoryValueSleepAnalysisAsleepDeep"/>
 <Record type="HKCategoryTypeIdentifierSleepAnalysis" sourceName="Oura" device="&lt;&lt;HKDevice: 0x3&gt;, name:Oura Ring, manufacturer:Oura, model:Gen3&gt;" startDate="2024-03-09 22:50:00 +0000" endDate="2024-03-10 05:00:00 +0000" value="HKCategoryValueSleepAnalysisAsleepCore"/>
 <Record type="HKQuantityTypeIdentifierUnknownMadeUp" sourceName="X" unit="count" startDate="2024-03-10 07:00:00 +0000" endDate="2024-03-10 07:00:00 +0000" value="1"/>
 <Correlation type="HKCorrelationTypeIdentifierFood" sourceName="PulseBoard" startDate="2024-03-10 12:00:00 +0000" endDate="2024-03-10 12:00:00 +0000">
  <MetadataEntry key="HKFoodType" value="Oats, banana"/>
  <Record type="HKQuantityTypeIdentifierDietaryEnergyConsumed" sourceName="PulseBoard" unit="kcal" startDate="2024-03-10 12:00:00 +0000" endDate="2024-03-10 12:00:00 +0000" value="380">
   <MetadataEntry key="HKFoodType" value="Oats, banana"/>
  </Record>
 </Correlation>
 <Record type="HKQuantityTypeIdentifierDietaryEnergyConsumed" sourceName="PulseBoard" unit="kcal" startDate="2024-03-10 12:00:00 +0000" endDate="2024-03-10 12:00:00 +0000" value="380">
  <MetadataEntry key="HKFoodType" value="Oats, banana"/>
 </Record>
 <Workout workoutActivityType="HKWorkoutActivityTypeRunning" duration="45" durationUnit="min" sourceName="Alex's Apple Watch" startDate="2024-03-10 18:00:00 +0000" endDate="2024-03-10 18:45:00 +0000">
  <MetadataEntry key="HKIndoorWorkout" value="0"/>
  <WorkoutStatistics type="HKQuantityTypeIdentifierActiveEnergyBurned" startDate="2024-03-10 18:00:00 +0000" endDate="2024-03-10 18:45:00 +0000" sum="410" unit="kcal"/>
  <WorkoutStatistics type="HKQuantityTypeIdentifierHeartRate" startDate="2024-03-10 18:00:00 +0000" endDate="2024-03-10 18:45:00 +0000" average="152" minimum="110" maximum="175" unit="count/min"/>
  <WorkoutRoute sourceName="Alex's Apple Watch" startDate="2024-03-10 18:00:00 +0000" endDate="2024-03-10 18:45:00 +0000">
   <FileReference path="/workout-routes/route_2024-03-10_6.45pm.gpx"/>
  </WorkoutRoute>
 </Workout>
 <Workout workoutActivityType="HKWorkoutActivityTypeRunning" duration="46" durationUnit="min" totalDistance="7.0" totalDistanceUnit="km" totalEnergyBurned="420" totalEnergyBurnedUnit="kcal" sourceName="Connect" device="&lt;&lt;HKDevice: 0x4&gt;, name:Forerunner 965, manufacturer:Garmin, model:Forerunner 965&gt;" startDate="2024-03-10 18:00:00 +0000" endDate="2024-03-10 18:46:00 +0000"/>
 <ActivitySummary dateComponents="2024-03-10" activeEnergyBurned="512.3" activeEnergyBurnedGoal="500" activeEnergyBurnedUnit="kcal" appleMoveTime="0" appleMoveTimeGoal="0" appleExerciseTime="52" appleExerciseTimeGoal="30" appleStandHours="11" appleStandHoursGoal="12"/>
</HealthData>
`;
