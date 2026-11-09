import Foundation
import Observation
import StoreKit
import PulseCore

/// StoreKit 2 implementation of `EntitlementService`.
/// - One subscription group: Pro Monthly / Pro Yearly, each with a 1-month
///   free introductory offer (eligibility handled by StoreKit — one intro
///   offer per subscription group per Apple ID).
/// - Verification is on-device (`VerificationResult`); no server.
@MainActor
@Observable
public final class EntitlementManager: EntitlementService {
    public private(set) var isPro = false
    public private(set) var products: [Product] = []
    public private(set) var activeProductID: String?
    public private(set) var expirationDate: Date?
    public private(set) var willAutoRenew = true
    public private(set) var isInTrial = false
    public private(set) var loadError: String?
    public var purchaseInProgress = false

    #if DEBUG
    /// Debug-only override for UI work without StoreKit.
    public var debugForcePro = false { didSet { Task { await refresh() } } }
    #endif

    public let productIDs: [String]
    private var updatesTask: Task<Void, Never>?

    public init() {
        let monthly = (Bundle.main.object(forInfoDictionaryKey: "PBProductMonthly") as? String) ?? "pulseboard.pro.monthly"
        let yearly = (Bundle.main.object(forInfoDictionaryKey: "PBProductYearly") as? String) ?? "pulseboard.pro.yearly"
        productIDs = [monthly, yearly]
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let t) = update { await t.finish() }
                await self?.refresh()
            }
        }
        Task { await refresh(); await loadProducts() }
    }

    public var monthly: Product? { products.first { $0.id == productIDs[0] } }
    public var yearly: Product? { products.first { $0.id == productIDs[1] } }

    public func loadProducts() async {
        do {
            products = try await Product.products(for: productIDs).sorted { $0.price > $1.price }
            loadError = products.isEmpty ? "Subscriptions are unavailable right now." : nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Recomputes entitlement from current, verified transactions.
    public func refresh() async {
        var pro = false
        var active: String?
        var expires: Date?
        var trial = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result, productIDs.contains(t.productID), t.revocationDate == nil else { continue }
            if let e = t.expirationDate, e < Date() { continue }
            pro = true
            active = t.productID
            expires = t.expirationDate
            trial = t.offer?.type == .introductory
        }
        #if DEBUG
        if debugForcePro { pro = true }
        #endif
        isPro = pro
        activeProductID = active
        expirationDate = expires
        isInTrial = trial
        if let p = products.first(where: { $0.id == active }), let statuses = try? await p.subscription?.status {
            for s in statuses {
                if case .verified(let info) = s.renewalInfo { willAutoRenew = info.willAutoRenew }
            }
        }
    }

    public enum PurchaseOutcome { case purchased, pending, cancelled }

    public func purchase(_ product: Product) async throws -> PurchaseOutcome {
        purchaseInProgress = true
        defer { purchaseInProgress = false }
        switch try await product.purchase() {
        case .success(let verification):
            guard case .verified(let t) = verification else { throw StoreKitError.notEntitled }
            await t.finish()
            await refresh()
            return .purchased
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    /// "Restore Purchases" — syncs with the App Store (may prompt sign-in).
    public func restore() async throws {
        try await AppStore.sync()
        await refresh()
    }

    public func isEligibleForTrial(_ product: Product) async -> Bool {
        guard let sub = product.subscription, sub.introductoryOffer != nil else { return false }
        return await sub.isEligibleForIntroOffer
    }

    public func isEnabled(_ feature: Feature) -> Bool { !feature.isPro || isPro }
}
