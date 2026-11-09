import SwiftUI
import PulseCore
import PulseKit

/// Challenges hub. In this phase every challenge is a local preview with
/// clearly labelled sample participants (no server). The UI only talks to
/// `ChallengeService` / `LeaderboardService`, so a real backend can be
/// swapped in later without UI changes.
struct ChallengesHomeView: View {
    @Environment(AppServices.self) private var services
    @Environment(EntitlementManager.self) private var entitlements
    @Environment(SettingsStore.self) private var settings
    @State private var joined: [Challenge] = []
    @State private var discover: [Challenge] = []
    @State private var kind: ChallengeKind? = nil
    @State private var creating = false
    @State private var showPaywall = false
    @State private var region = RegionProvider()

    var body: some View {
        Group {
            if PulseKitConfig.challengesPreviewEnabled {
                list
            } else {
                ContentUnavailableView("Challenges are coming soon", systemImage: "trophy",
                                       description: Text("Compete with friends using a fair, device-agnostic Activity Score."))
            }
        }
        .navigationTitle("Challenges")
    }

    private var list: some View {
        List {
            Section {
                Label("Preview — sample participants", systemImage: "eye")
                    .font(.subheadline.weight(.semibold))
                Text("Online challenges aren't live yet. Leaderboards use generated sample participants so you can try the experience. Your data never leaves this device.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !joined.isEmpty {
                Section("Your challenges") {
                    ForEach(joined) { c in
                        NavigationLink { ChallengeDetailView(challenge: c) } label: { ChallengeRow(challenge: c) }
                    }
                }
            }
            Section {
                Picker("Type", selection: $kind) {
                    Text("All").tag(ChallengeKind?.none)
                    ForEach([ChallengeKind.friends, .local, .global], id: \.self) { Text($0.title).tag(Optional($0)) }
                }
                .pickerStyle(.segmented)
                if kind == .local {
                    HStack {
                        Label(region.region ?? settings.preferences.challengeRegion ?? "Set your city or region", systemImage: "location")
                        Spacer()
                        Button("Use my area") { region.request() }.font(.caption)
                    }
                    if let e = region.error { Text(e).font(.caption).foregroundStyle(.secondary) }
                    Text("Only your city/region is used — never precise location.").font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(discover) { c in
                    NavigationLink { ChallengeDetailView(challenge: c) } label: { ChallengeRow(challenge: c) }
                }
                if discover.isEmpty { Text("No other challenges right now.").foregroundStyle(.secondary) }
            } header: {
                Text("Discover")
            }
            Section {
                Button {
                    if entitlements.isEnabled(.createCustomChallenges) { creating = true } else { showPaywall = true }
                } label: {
                    Label("Create a custom challenge", systemImage: entitlements.isEnabled(.createCustomChallenges) ? "plus.circle.fill" : "lock.fill")
                }
            } footer: {
                Text("Scores use the device-agnostic Activity Score so Apple Watch, Garmin, WHOOP, Oura and Fitbit users compete fairly. Manual entries and estimated values never count.")
            }
        }
        .sheet(isPresented: $creating, onDismiss: { Task { await load() } }) { NavigationStack { CreateChallengeView() } }
        .sheet(isPresented: $showPaywall) { PaywallView(highlight: .createCustomChallenges) }
        .task(id: kind) { await load() }
        .onChange(of: region.region) { _, r in
            if let r { settings.update { $0.challengeRegion = r } }
            Task { await load() }
        }
        .refreshable { await load() }
    }

    private func load() async {
        joined = (try? await services.challenges.joined()) ?? []
        discover = (try? await services.challenges.discover(kind: kind, region: settings.preferences.challengeRegion)) ?? []
    }
}

struct ChallengeRow: View {
    let challenge: Challenge
    var body: some View {
        HStack {
            Image(systemName: icon).font(.title3).foregroundStyle(Theme.orange).frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(challenge.title).font(.headline)
                Text("\(challenge.metric.title) · \(challenge.kind.title)\(challenge.region.map { " · \($0)" } ?? "")")
                    .font(.caption).foregroundStyle(.secondary)
                Text("\(Fmt.day(challenge.start)) – \(Fmt.day(challenge.end)) · \(challenge.participantCount.formatted()) people")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }
    private var icon: String {
        switch challenge.kind {
        case .friends: return "person.2.fill"
        case .local: return "building.2.fill"
        case .global: return "globe"
        case .custom: return "star.fill"
        }
    }
}

struct ChallengeDetailView: View {
    let challenge: Challenge
    @Environment(AppServices.self) private var services
    @State private var membership: ChallengeMembership?
    @State private var board: [LeaderboardEntry] = []
    @State private var todayInputs: ActivityInputs?
    @State private var share = false
    @State private var loading = true

    var body: some View {
        List {
            Section {
                LabeledContent("Ranks on", value: challenge.metric.title)
                LabeledContent("Scoring", value: rulesText)
                LabeledContent("Dates", value: "\(Fmt.day(challenge.start)) – \(Fmt.day(challenge.end))")
                if let r = challenge.region { LabeledContent("Area", value: r) }
            }
            if let m = membership {
                Section {
                    Toggle("Share my score", isOn: $share)
                        .onChange(of: share) { _, v in Task { try? await services.challenges.setSharing(challenge.id, shareScore: v) } }
                } footer: {
                    Text(m.shareScore || share
                         ? "Only one aggregated score per day is shared for this challenge — never raw health data, sources or precise location."
                         : "Off: your score stays on this device. Sharing is opt-in per challenge.")
                }
                if let i = todayInputs, challenge.metric == .activityScore {
                    Section("Today's Activity Score") {
                        let b = ActivityScore.breakdown(i)
                        LabeledContent("Steps", value: "\(b.steps.formatted(.number.precision(.fractionLength(0...1)))) / 30")
                        LabeledContent("Active minutes", value: "\(b.activeMinutes.formatted(.number.precision(.fractionLength(0...1)))) / 30")
                        LabeledContent("Intensity", value: "\(b.intensity.formatted(.number.precision(.fractionLength(0...1)))) / 25")
                        LabeledContent("Sleep", value: "\(Int(b.sleep)) / 15")
                        LabeledContent("Total", value: "\(b.total.formatted(.number.precision(.fractionLength(0...1)))) / 100").bold()
                    }
                }
            }
            Section {
                if loading { ProgressView() }
                ForEach(board) { e in
                    HStack {
                        Text("\(e.rank)").font(.headline.monospacedDigit()).frame(width: 32)
                        Image(systemName: e.symbol).foregroundStyle(e.isCurrentUser ? Theme.orange : .secondary)
                        Text(e.displayName).fontWeight(e.isCurrentUser ? .bold : .regular)
                        Spacer()
                        Text(scoreText(e.score)).monospacedDigit()
                    }
                    .listRowBackground(e.isCurrentUser ? Theme.orange.opacity(0.12) : nil)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Rank \(e.rank), \(e.displayName), \(scoreText(e.score))")
                }
            } header: {
                Text(membership == nil ? "Leaderboard preview" : "Leaderboard")
            } footer: {
                if challenge.isPreview { Text("Preview — participants other than you are generated samples.") }
            }
            Section {
                if membership == nil {
                    Button("Join challenge") {
                        Task { try? await services.challenges.join(challenge.id, shareScore: false); await load() }
                    }
                } else {
                    Button("Leave challenge", role: .destructive) {
                        Task { try? await services.challenges.leave(challenge.id); await load() }
                    }
                }
            }
        }
        .navigationTitle(challenge.title)
        .task { await load() }
    }

    private var rulesText: String {
        let agg: String
        switch challenge.rules.aggregation {
        case .total: agg = "Total"
        case .dailyAverage: agg = "Daily average"
        case .bestDay: agg = "Best day"
        }
        return agg + (challenge.rules.dailyCap.map { ", max \(Int($0).formatted())/day" } ?? "")
    }

    private func scoreText(_ v: Double) -> String {
        switch challenge.metric {
        case .sleepTarget: return "\(Int(v)) nights"
        case .steps: return Int(v).formatted()
        default: return v.formatted(.number.precision(.fractionLength(0...1)))
        }
    }

    private func load() async {
        let today = DayKey.today(services.calendar)
        membership = await services.challenges.membership(challenge.id)
        share = membership?.shareScore ?? false
        let daily = membership == nil ? [:] : await services.challengeData.dailyValues(challenge, today: today)
        if membership != nil {
            todayInputs = await services.challengeData.inputs(for: today)
            if share {
                // Aggregated daily values only (TODO(server-sync): real upload).
                let scores = daily.map { DailyChallengeScore(challengeID: challenge.id, day: $0.key, value: $0.value) }
                try? await services.challenges.submit(scores)
            }
        }
        board = (try? await services.challenges.leaderboard(for: challenge, myDaily: daily, today: today)) ?? []
        loading = false
    }
}

struct CreateChallengeView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var metric: ChallengeMetric = .activityScore
    @State private var aggregation: ChallengeRules.Aggregation = .total
    @State private var days = 7
    @State private var cap: Double?

    var body: some View {
        Form {
            TextField("Name", text: $title)
            Picker("Metric", selection: $metric) { ForEach(ChallengeMetric.allCases, id: \.self) { Text($0.title).tag($0) } }
            Picker("Scoring", selection: $aggregation) {
                Text("Total").tag(ChallengeRules.Aggregation.total)
                Text("Daily average").tag(ChallengeRules.Aggregation.dailyAverage)
                Text("Best day").tag(ChallengeRules.Aggregation.bestDay)
            }
            Stepper("Length: \(days) days", value: $days, in: 1...60)
            TextField("Daily cap (optional)", value: $cap, format: .number).keyboardType(.numberPad)
            Section {
                Text("Friends can join with a link once online challenges launch. For now this is a preview with sample participants.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("New Challenge")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") {
                    let today = DayKey.today(services.calendar)
                    let c = Challenge(title: title.isEmpty ? "My Challenge" : title, kind: .custom, metric: metric, start: today,
                                      end: today.addingDays(days - 1), rules: ChallengeRules(aggregation: aggregation, dailyCap: cap))
                    Task { _ = try? await services.challenges.create(c); dismiss() }
                }
            }
        }
    }
}
