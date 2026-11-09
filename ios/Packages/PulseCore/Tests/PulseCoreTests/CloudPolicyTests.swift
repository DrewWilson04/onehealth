import XCTest
@testable import PulseCore

final class CloudPolicyTests: XCTestCase {
    func testOnlyConfigurationSyncs() {
        for k in ["preferences", "preferredSources", "sourcePriority", "dashboardLayout", "goal.abc", "meal.xyz", "challenge.c1"] {
            XCTAssertTrue(CloudPolicy.isAllowedInCloud(k), k)
        }
        for k in ["samples", "sample.123", "aggregate.steps", "score.readiness", "custom.mood", "food.log.1", "randomKey"] {
            XCTAssertFalse(CloudPolicy.isAllowedInCloud(k), k)
        }
    }

    func testGrayAreaToggles() {
        XCTAssertFalse(CloudPolicy.isAllowedInCloud("goal.1", syncGoals: false))
        XCTAssertFalse(CloudPolicy.isAllowedInCloud("meal.1", syncMealTemplates: false))
        XCTAssertTrue(CloudPolicy.isAllowedInCloud("dashboardLayout", syncGoals: false, syncMealTemplates: false))
    }
}
