import SwiftUI
import PulseCore
import PulseKit

/// Pro: add, remove, resize and reorder dashboard cards.
struct DashboardEditView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var cards: [DashboardCard] = []

    var body: some View {
        List {
            Section {
                ForEach($cards) { $card in
                    HStack {
                        Image(systemName: Self.symbol(card.kind)).foregroundStyle(Self.tint(card.kind)).frame(width: 28)
                        Text(Self.title(card.kind))
                        Spacer()
                        Picker("Size", selection: $card.size) {
                            Text("Small").tag(DashboardCard.Size.small)
                            Text("Wide").tag(DashboardCard.Size.medium)
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                }
                .onMove { cards.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { cards.remove(atOffsets: $0) }
            } header: {
                Text("On your dashboard")
            } footer: {
                Text("Drag to reorder. Wide cards span two columns.")
            }

            Section("Add") {
                ForEach(available, id: \.self) { kind in
                    Button {
                        cards.append(DashboardCard(kind: kind, size: Self.defaultSize(kind)))
                    } label: {
                        Label(Self.title(kind), systemImage: Self.symbol(kind))
                    }
                }
            }
            Section {
                Button("Reset to default", role: .destructive) { cards = DashboardLayout.default.cards }
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Edit Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { settings.setDashboardLayout(DashboardLayout(cards: cards)); dismiss() }
            }
        }
        .onAppear { cards = settings.dashboardLayout.cards }
    }

    private var available: [DashboardCard.Kind] {
        let present = Set(cards.map(\.kind))
        let specials: [DashboardCard.Kind] = [.rings, .sleepNight, .goals, .insights, .challenge] + ScoreKind.allCases.map { .score($0) }
        let metrics = MetricRegistry.all.filter { $0.kind != .ecg }.map { DashboardCard.Kind.metric($0.id) }
        return (specials + metrics).filter { !present.contains($0) }
    }

    static func defaultSize(_ k: DashboardCard.Kind) -> DashboardCard.Size {
        switch k {
        case .rings, .sleepNight, .goals, .insights, .challenge: return .medium
        default: return .small
        }
    }

    static func title(_ k: DashboardCard.Kind) -> String {
        switch k {
        case .metric(let id): return MetricRegistry.type(id)?.displayName ?? id.rawValue
        case .score(let s): return s.title
        case .rings: return "Activity Rings"
        case .sleepNight: return "Last Night"
        case .challenge: return "Active Challenge"
        case .insights: return "Insights"
        case .goals: return "Goals"
        }
    }

    static func symbol(_ k: DashboardCard.Kind) -> String {
        switch k {
        case .metric(let id): return MetricRegistry.type(id)?.symbol ?? "square"
        case .score(let s): return s.symbol
        case .rings: return "circle.circle"
        case .sleepNight: return "bed.double.fill"
        case .challenge: return "trophy.fill"
        case .insights: return "sparkles"
        case .goals: return "target"
        }
    }

    static func tint(_ k: DashboardCard.Kind) -> Color {
        switch k {
        case .metric(let id): return Theme.accent(MetricRegistry.type(id)?.section ?? .activity)
        case .score: return Theme.bluishGreen
        case .rings: return Theme.vermillion
        case .sleepNight: return Theme.blue
        default: return Theme.orange
        }
    }
}
