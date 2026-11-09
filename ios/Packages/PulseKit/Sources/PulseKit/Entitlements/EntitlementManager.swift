import Foundation
import Observation
import PulseCore

/// Placeholder until Milestone 7 (StoreKit 2). Everything is Free.
@MainActor
@Observable
public final class EntitlementManager {
    public private(set) var isPro = false
    public init() {}
    public func isEnabled(_ feature: Feature) -> Bool { Feature.freeFeatures.contains(feature) || isPro }
}
