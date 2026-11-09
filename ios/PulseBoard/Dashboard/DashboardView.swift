import SwiftUI
import PulseCore
import PulseKit

/// Today: adaptive card grid (2 columns on iPhone, more on iPad).
struct DashboardView: View {
    @Environment(AppServices.self) private var services
    @Environment(IngestionStatus.self) private var status
    @Environment(SettingsStore.self) private var settings
    @Environment(EntitlementManager.self) private var entitlements
    @State private var model = DashboardModel()
    @State private var goals = GoalsModel()
    @State private var editing = false
    @State private var showPaywall = false

    /// Free users get the default layout; the custom grid is Pro.
    private var layout: DashboardLayout {
        entitlements.isEnabled(.customWidgetGrid) ? settings.dashboardLayout : .default
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                BackfillBanner()
                if !model.limited.isEmpty { LimitedAccessBanner(limited: model.limited) }

                if !model.loaded {
                    loadingGrid
                } else if !model.hasAnyData && !status.isBackfilling {
                    ContentUnavailableView {
                        Label("No health data yet", systemImage: "heart.text.square")
                    } description: {
                        Text("Once your iPhone, Apple Watch or another device writes to Apple Health, your dashboard fills in here.")
                    } actions: {
                        NavigationLink("Check permissions") { PermissionsView() }
                    }
                } else {
                    AdaptiveCardGrid {
                        ForEach(layout.cards) { card in
                            cardView(card).gridSpan(card.size.span)
                        }
                    }
                    sectionLinks
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Today")
        .toolbar {
            Button {
                if entitlements.isEnabled(.customWidgetGrid) { editing = true } else { showPaywall = true }
            } label: {
                Label("Edit dashboard", systemImage: "square.grid.3x3.square")
            }
        }
        .sheet(isPresented: $editing) { NavigationStack { DashboardEditView() } }
        .sheet(isPresented: $showPaywall) { PaywallView(highlight: .customWidgetGrid) }
        .refreshable {
            await services.ingestion.refreshAll()
            await load()
        }
        .task(id: "\(status.dataRevision)-\(settings.revision)") { await load() }
        .task { await model.loadAccess(services: services) }
    }

    private func load() async {
        let ids = layout.cards.compactMap { c -> MetricID? in
            if case .metric(let id) = c.kind { return id }
            return nil
        }
        await model.load(services: services, metricIDs: ids)
        await goals.load(services: services)
        if services.todayScores.isEmpty { await services.refreshScores() }
    }

    @ViewBuilder
    func cardView(_ card: DashboardCard) -> some View {
        switch card.kind {
        case .metric(let id):
            if let m = MetricRegistry.type(id) {
                NavigationLink { MetricDetailView(metric: m) } label: {
                    MetricCardView(metric: m, snapshot: model.metrics[id], size: card.size)
                }
                .buttonStyle(.plain)
            }
        case .rings:
            RingsCardView(rings: model.rings)
        case .sleepNight:
            NavigationLink { SleepDetailView() } label: { SleepNightCardView(night: model.lastNight) }
                .buttonStyle(.plain)
        case .goals:
            NavigationLink { GoalsView() } label: { GoalsCardView(rows: goals.rows) }
                .buttonStyle(.plain)
        case .score(let kind):
            let locked = (kind == .strain && !entitlements.isEnabled(.strainScore)) || (kind == .energy && !entitlements.isEnabled(.energyScore))
            if locked {
                Button { showPaywall = true } label: { ScoreCardView(kind: kind, result: nil, locked: true) }.buttonStyle(.plain)
            } else {
                NavigationLink { ScoreDetailView(kind: kind) } label: {
                    ScoreCardView(kind: kind, result: services.todayScores[kind], locked: false)
                }
                .buttonStyle(.plain)
            }
        default:
            EmptyView()
        }
    }

    private var sectionLinks: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Browse").font(.title3.bold()).padding(.top, 8)
            AdaptiveCardGrid(minColumnWidth: 240) {
                ForEach(DashboardSection.allCases) { s in
                    NavigationLink { SectionView(section: s) } label: {
                        HStack {
                            Image(systemName: Theme.symbol(s)).font(.title3).foregroundStyle(Theme.accent(s)).frame(width: 30)
                            Text(s.title).font(.headline)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var loadingGrid: some View {
        AdaptiveCardGrid {
            ForEach(0..<6, id: \.self) { _ in
                CardContainer { VStack(alignment: .leading) { Text("Loading metric"); Text("0000").font(.title2) } }
                    .redacted(reason: .placeholder)
            }
        }
        .accessibilityLabel("Loading")
    }
}

/// Shown when some sections have no data (possibly denied permission).
struct LimitedAccessBanner: View {
    let limited: [DashboardSection: [MetricID]]
    @State private var dismissed = false

    var body: some View {
        if !dismissed {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.shield.fill").foregroundStyle(Theme.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Some sections are limited").font(.subheadline.weight(.semibold))
                    Text(limited.keys.sorted { $0.rawValue < $1.rawValue }.map(\.title).joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary)
                    NavigationLink("How to enable access") { PermissionsView() }.font(.caption.weight(.semibold))
                }
                Spacer()
                Button { dismissed = true } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .accessibilityLabel("Dismiss")
            }
            .padding()
            .background(Theme.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}
