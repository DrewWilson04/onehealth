import Foundation

/// The single gate for every Pro feature. The StoreKit 2 implementation lives
/// in PulseKit; tests and previews can use `StaticEntitlements`.
@MainActor
public protocol EntitlementService: AnyObject {
    var isPro: Bool { get }
    func isEnabled(_ feature: Feature) -> Bool
}

public extension EntitlementService {
    func isEnabled(_ feature: Feature) -> Bool { !feature.isPro || isPro }
}

@MainActor
public final class StaticEntitlements: EntitlementService {
    public var isPro: Bool
    public init(isPro: Bool) { self.isPro = isPro }
}

/// Product catalog shared by the paywall and tests.
public enum ProPlan: String, CaseIterable, Sendable {
    case monthly, yearly

    /// Reference prices (USD) for copy only — the paywall always shows
    /// StoreKit's localized `displayPrice`.
    public var referencePriceUSD: Decimal { self == .monthly ? 2.99 : 29.99 }

    /// Yearly savings vs 12 × monthly, rounded down to a whole percent.
    public static func yearlySavingsPercent(monthly: Decimal, yearly: Decimal) -> Int {
        let m = NSDecimalNumber(decimal: monthly).doubleValue * 12
        let y = NSDecimalNumber(decimal: yearly).doubleValue
        guard m > 0, y < m else { return 0 }
        return Int(((m - y) / m * 100).rounded(.down))
    }
}
