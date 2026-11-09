import Foundation
import Observation
import PulseCore

/// Main-actor, observable ingestion state for the UI (backfill banner,
/// progress screen, "data changed" reloads).
@MainActor
@Observable
public final class IngestionStatus {
    public enum Phase: String, Sendable {
        case idle, authorizing, recent, history, complete, paused
    }

    public var phase: Phase = .idle
    /// 0...1 overall backfill progress.
    public var progress: Double = 0
    public var currentMetric: String?
    /// Oldest date ingested so far (for "History back to 2016" copy).
    public var oldestIngested: Date?
    public var lastError: String?
    /// Incremented whenever cached data changes; views observe it to reload.
    public var dataRevision: Int = 0
    public var lastSync: Date?

    public init() {}

    public var isBackfilling: Bool { phase == .recent || phase == .history }
}
