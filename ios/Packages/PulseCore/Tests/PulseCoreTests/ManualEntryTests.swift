import XCTest
@testable import PulseCore

final class ManualEntryTests: XCTestCase {
    func testSetsRoundTripThroughWorkoutMetadata() {
        let sets = [ExerciseSet(exercise: "Squat", reps: 5, weightKg: 100), ExerciseSet(exercise: "Pull-up", reps: 8)]
        let json = ExerciseSet.encode(sets)
        let decoded = ExerciseSet.decode(json)
        XCTAssertEqual(decoded, sets)
        XCTAssertEqual(ExerciseSet.volume(decoded), 500)
        XCTAssertEqual(ExerciseSet.decode(nil), [])
        XCTAssertEqual(ExerciseSet.decode("not json"), [])

        // Sets travel in workout metadata and are readable after normalization.
        let w = Normalizer(ownBundleIdPrefix: "com.example.pulseboard").normalizeWorkout(
            activityType: "traditionalStrengthTraining", start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 2700),
            durationMinutes: 45, energyKcal: nil, distanceMeters: nil, hasRoute: false, sourceName: "PulseBoard",
            sourceBundleId: "com.example.pulseboard", device: nil, metadata: [WorkoutInfo.setsKey: json, "HKWasUserEntered": "1"], uuid: "W")
        XCTAssertTrue(w.isManual)
        XCTAssertFalse(w.isCompetitionEligible)
        XCTAssertEqual(ExerciseSet.decode(w.metadata?[WorkoutInfo.setsKey]).count, 2)
    }

    func testFoodMacroKcal() {
        let f = FoodEntry(name: "Oats", date: Date(), kcal: 380, protein: 13, carbs: 68, fat: 7, meal: .breakfast)
        let expected: Double = 52 + 272 + 63
        XCTAssertEqual(f.macroKcal, expected)
        let t = MealTemplate(name: "Breakfast", items: [f, f])
        XCTAssertEqual(t.totalKcal, 760)
    }

    func testCustomMetricAggregatesLocally() {
        let def = CustomMetricDefinition(name: "Coffee", unitLabel: "cups", aggregation: "sum")
        XCTAssertTrue(def.metricID.isCustom)
        XCTAssertNil(def.metricType.healthKitIdentifier, "custom metrics are never written to HealthKit")
        let cal = Calendar.pulse(TimeZone(identifier: "UTC")!)
        let d = Fixtures.iso("2024-03-10T08:00:00Z")
        let samples = [def.sample(value: 1, date: d), def.sample(value: 2, date: d.addingTimeInterval(3600))]
        XCTAssertTrue(samples.allSatisfy(\.isManual))
        let rows = Aggregator.daily(def.metricType, samples: samples, options: .init(calendar: cal))
        XCTAssertEqual(rows.count, 1)
        XCTAssertClose(rows[0].sum, 3)

        let mood = CustomMetricDefinition(name: "Mood", unitLabel: "1-5", aggregation: "average")
        let m = [mood.sample(value: 2, date: d), mood.sample(value: 4, date: d)]
        XCTAssertClose(Aggregator.daily(mood.metricType, samples: m, options: .init(calendar: cal))[0].average, 3)
    }

    func testGoalProgress() {
        let g = Goal(metric: .steps, target: 10_000)
        XCTAssertEqual(g.progress(5000), 0.5)
        XCTAssertTrue(g.isMet(10_000))
        let cap = Goal(metric: .caffeine, target: 400, direction: .atMost)
        XCTAssertTrue(cap.isMet(300))
        XCTAssertFalse(cap.isMet(500))
        XCTAssertEqual(cap.progress(300), 1)
        XCTAssertEqual(cap.progress(600), 0.5)
    }
}
