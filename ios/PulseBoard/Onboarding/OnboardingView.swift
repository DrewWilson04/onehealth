import SwiftUI
import PulseCore
import PulseKit

/// First-run flow: what we read, that it stays on-device, how sync works,
/// then the HealthKit permission sheet.
struct OnboardingView: View {
    @Environment(AppServices.self) private var services
    var onFinish: () -> Void

    @State private var page = 0
    @State private var requesting = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcome.tag(0)
                whatWeRead.tag(1)
                howSyncWorks.tag(2)
                connect.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button(action: advance) {
                Text(page < 3 ? "Continue" : (requesting ? "Connecting…" : "Connect Apple Health"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(requesting)
            .padding()
            .accessibilityHint(page < 3 ? "Shows the next onboarding page" : "Opens the Apple Health permission sheet")
        }
        .alert("Couldn't connect", isPresented: .constant(error != nil), actions: {
            Button("OK") { error = nil }
        }, message: { Text(error ?? "") })
    }

    private func advance() {
        if page < 3 { withAnimation { page += 1 }; return }
        requesting = true
        Task {
            do {
                try await services.requestHealthAccess()
                onFinish()
            } catch {
                self.error = error.localizedDescription
            }
            requesting = false
        }
    }

    private var welcome: some View {
        OnboardingPage(symbol: "square.grid.2x2.fill", tint: Theme.blue, title: "Welcome to \(PulseKitConfig.appName)",
                       subtitle: "All your health data in one dashboard — from Apple Watch, Garmin, WHOOP, Oura, Fitbit and any app that writes to Apple Health.") {
            Label("Private by design: no account, no servers.", systemImage: "lock.shield.fill")
            Label("Works with every device that syncs to Apple Health.", systemImage: "applewatch.radiowaves.left.and.right")
            Label("Your own readiness, sleep, strain and energy estimates.", systemImage: "gauge.with.dots.needle.67percent")
        }
    }

    private var whatWeRead: some View {
        OnboardingPage(symbol: "heart.text.square.fill", tint: Theme.vermillion, title: "What we read",
                       subtitle: "On the next screen Apple Health asks which data to share. You can change this anytime in Settings → Health → Data Access & Devices.") {
            ForEach(DashboardSection.allCases) { s in
                Label {
                    VStack(alignment: .leading) {
                        Text(s.title).font(.subheadline.weight(.semibold))
                        Text(MetricRegistry.metrics(in: s).prefix(5).map(\.displayName).joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: Theme.symbol(s)).foregroundStyle(Theme.accent(s))
                }
            }
        }
    }

    private var howSyncWorks: some View {
        OnboardingPage(symbol: "icloud.and.arrow.up.fill", tint: Theme.bluishGreen, title: "Your data stays on your devices",
                       subtitle: "Nothing is uploaded to us — there is no \(PulseKitConfig.appName) server.") {
            Label("Food, water, workouts and weight you log are saved to Apple Health, which syncs them across your iPhone, iPad and Apple Watch.", systemImage: "heart.fill")
            Label("Only settings, goals, layouts and saved meals sync through your private iCloud.", systemImage: "icloud")
            Label("Custom metrics stay on this device only.", systemImage: "iphone")
            Label("Health data is never sold, shared or used for ads.", systemImage: "hand.raised.fill")
        }
    }

    private var connect: some View {
        OnboardingPage(symbol: "arrow.down.circle.fill", tint: Theme.orange, title: "Import your history",
                       subtitle: "We load the last 30 days first so you can start right away, then fill in older history in the background. Keep the app open for the fastest import.") {
            Label("Recent data appears within seconds.", systemImage: "bolt.fill")
            Label("Full history can take a few minutes for 10+ years.", systemImage: "clock.arrow.circlepath")
            Label("Not medical advice — scores are our own estimates.", systemImage: "info.circle")
        }
    }
}

private struct OnboardingPage<Content: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: symbol)
                    .font(.system(size: 56))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                    .padding(.top, 40)
                Text(title).font(.largeTitle.bold())
                Text(subtitle).font(.body).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 14) { content }
                    .font(.subheadline)
                    .padding(.top, 8)
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.bottom, 60)
            .frame(maxWidth: .infinity)
        }
    }
}
