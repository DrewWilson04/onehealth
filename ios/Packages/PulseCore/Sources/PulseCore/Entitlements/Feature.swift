import Foundation

/// Every gated capability. All gating goes through `EntitlementService`.
public enum Feature: String, CaseIterable, Sendable, Codable {
    // Free
    case coreDashboard, trends30Days, basicGoals, streaks, manualLogging, readinessScore, sleepScore, joinChallenges
    // Pro
    case fullHistoryTrends, customWidgetGrid, homeScreenWidgets, lockScreenWidgets, export
    case strainScore, energyScore, fullScoreHistory, aiInsights, createCustomChallenges

    public static let freeFeatures: Set<Feature> = [.coreDashboard, .trends30Days, .basicGoals, .streaks, .manualLogging,
                                                    .readinessScore, .sleepScore, .joinChallenges]
    public var isPro: Bool { !Self.freeFeatures.contains(self) }

    public var title: String {
        switch self {
        case .coreDashboard: return "Dashboard"
        case .trends30Days: return "30-day trends"
        case .basicGoals: return "Goals"
        case .streaks: return "Streaks"
        case .manualLogging: return "Manual logging"
        case .readinessScore: return "Readiness score"
        case .sleepScore: return "Sleep Score"
        case .joinChallenges: return "Join challenges"
        case .fullHistoryTrends: return "Full-history trends"
        case .customWidgetGrid: return "Custom dashboard grid"
        case .homeScreenWidgets: return "Home Screen widgets"
        case .lockScreenWidgets: return "Lock Screen widgets"
        case .export: return "CSV & PDF export"
        case .strainScore: return "Strain & Training Load"
        case .energyScore: return "Energy score"
        case .fullScoreHistory: return "Full score history"
        case .aiInsights: return "AI insights"
        case .createCustomChallenges: return "Create custom challenges"
        }
    }

    /// Free tier trend window.
    public static let freeTrendDays = 30
}
