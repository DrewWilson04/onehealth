import Foundation

/// Kinds of derived scores (see /docs/scores.md).
public enum ScoreKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case readiness, sleep, strain, energy
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .readiness: return "Readiness"
        case .sleep: return "Sleep Score"
        case .strain: return "Strain"
        case .energy: return "Energy"
        }
    }
    public var symbol: String {
        switch self {
        case .readiness: return "gauge.with.dots.needle.67percent"
        case .sleep: return "moon.stars.fill"
        case .strain: return "flame.circle"
        case .energy: return "battery.75percent"
        }
    }
}

/// A card on the customizable home grid.
public struct DashboardCard: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: Codable, Sendable, Hashable {
        case metric(MetricID)
        case score(ScoreKind)
        case rings
        case sleepNight
        case challenge
        case insights
        case goals
    }
    public enum Size: String, Codable, Sendable, CaseIterable {
        case small, medium, large
        /// Grid column span on the adaptive layout.
        public var span: Int { self == .small ? 1 : 2 }
    }
    public var id: String
    public var kind: Kind
    public var size: Size

    public init(id: String = UUID().uuidString, kind: Kind, size: Size = .small) {
        self.id = id
        self.kind = kind
        self.size = size
    }
}

public struct DashboardLayout: Codable, Sendable, Hashable {
    public var cards: [DashboardCard]
    public init(cards: [DashboardCard]) { self.cards = cards }

    /// Free tier and first launch: a fixed, sensible layout.
    public static let `default` = DashboardLayout(cards: [
        DashboardCard(id: "rings", kind: .rings, size: .medium),
        DashboardCard(id: "readiness", kind: .score(.readiness)),
        DashboardCard(id: "sleepScore", kind: .score(.sleep)),
        DashboardCard(id: "strain", kind: .score(.strain)),
        DashboardCard(id: "energy", kind: .score(.energy)),
        DashboardCard(id: "steps", kind: .metric(.steps)),
        DashboardCard(id: "activeEnergy", kind: .metric(.activeEnergy)),
        DashboardCard(id: "sleepNight", kind: .sleepNight, size: .medium),
        DashboardCard(id: "rhr", kind: .metric(.restingHeartRate)),
        DashboardCard(id: "hrv", kind: .metric(.hrv)),
        DashboardCard(id: "weight", kind: .metric(.bodyMass)),
        DashboardCard(id: "water", kind: .metric(.water)),
        DashboardCard(id: "goals", kind: .goals, size: .medium),
    ])
}
