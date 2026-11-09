import SwiftUI
import PulseCore
import PulseKit

enum AppTab: Hashable {
    case today, trends, log, insights, challenges, settings
}

struct RootView: View {
    @Environment(AppServices.self) private var services
    @Environment(AIAvailability.self) private var ai
    @State private var onboarded = AppServices.shared.hasCompletedOnboarding
    @State private var tab: AppTab = .today

    var body: some View {
        Group {
            if onboarded {
                mainTabs
            } else {
                OnboardingView { onboarded = true }
            }
        }
    }

    /// `.sidebarAdaptable`: tab bar on iPhone, sidebar + multi-column content on iPad.
    private var mainTabs: some View {
        TabView(selection: $tab) {
            Tab("Today", systemImage: "square.grid.2x2.fill", value: AppTab.today) {
                NavigationStack { DashboardView() }
            }
            Tab("Trends", systemImage: "chart.xyaxis.line", value: AppTab.trends) {
                NavigationStack { TrendsHomeView() }
            }
            Tab("Log", systemImage: "plus.circle.fill", value: AppTab.log) {
                NavigationStack { LogHomeView() }
            }
            // AI insights are hidden entirely on devices without Apple Intelligence.
            if ai.isAvailable {
                Tab("Insights", systemImage: "sparkles", value: AppTab.insights) {
                    NavigationStack { InsightsView() }
                }
            }
            Tab("Challenges", systemImage: "trophy.fill", value: AppTab.challenges) {
                NavigationStack { ChallengesHomeView() }
            }
            Tab("Settings", systemImage: "gearshape.fill", value: AppTab.settings) {
                NavigationStack { SettingsView() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}
