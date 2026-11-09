import SwiftUI
import StoreKit
import PulseCore
import PulseKit

/// Pro paywall. Shows localized StoreKit prices, trial terms only when the
/// user is eligible, auto-renew terms, Restore, Terms and Privacy links
/// (App Review 3.1.2).
struct PaywallView: View {
    var highlight: Feature? = nil
    @Environment(EntitlementManager.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selected: String?
    @State private var trialEligible: [String: Bool] = [:]
    @State private var message: String?

    private let proFeatures: [(Feature, String)] = [
        (.fullHistoryTrends, "chart.xyaxis.line"), (.customWidgetGrid, "square.grid.3x3.square"),
        (.homeScreenWidgets, "apps.iphone"), (.lockScreenWidgets, "lock.rectangle.on.rectangle"),
        (.export, "square.and.arrow.up"), (.strainScore, "flame.circle"), (.energyScore, "battery.75percent"),
        (.fullScoreHistory, "calendar"), (.aiInsights, "sparkles"), (.createCustomChallenges, "trophy"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: "star.circle.fill").font(.system(size: 48)).foregroundStyle(Theme.orange).accessibilityHidden(true)
                        Text("\(PulseKitConfig.appName) Pro").font(.largeTitle.bold())
                        Text("Everything in Free, plus:").foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(proFeatures, id: \.0) { f, symbol in
                            Label {
                                Text(f.title).fontWeight(f == highlight ? .bold : .regular)
                            } icon: {
                                Image(systemName: symbol).foregroundStyle(f == highlight ? Theme.orange : Theme.blue)
                            }
                            .accessibilityElement(children: .combine)
                        }
                        if !PulseKitConfig.aiSupportedHint {
                            Text("AI insights require an Apple Intelligence-capable device.").font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    if store.products.isEmpty {
                        if let e = store.loadError { Text(e).foregroundStyle(.secondary) } else { ProgressView() }
                    } else {
                        VStack(spacing: 10) {
                            ForEach(store.products, id: \.id) { p in planButton(p) }
                        }
                    }

                    Button(action: purchase) {
                        Text(ctaTitle).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(selectedProduct == nil || store.purchaseInProgress)

                    Text(legalText).font(.caption2).foregroundStyle(.secondary)

                    HStack {
                        Button("Restore Purchases") {
                            Task {
                                do { try await store.restore(); message = store.isPro ? "Purchases restored." : "No active subscription found." }
                                catch { message = error.localizedDescription }
                            }
                        }
                        Spacer()
                        Link("Terms of Use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                        Text("·").foregroundStyle(.secondary)
                        Link("Privacy", destination: PulseKitConfig.privacyPolicyURL)
                    }
                    .font(.footnote)

                    Label("Your health data is never sold, shared with third parties or used for advertising.", systemImage: "hand.raised.fill")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Not now") { dismiss() } } }
            .alert("Pro", isPresented: .constant(message != nil)) { Button("OK") { message = nil } } message: { Text(message ?? "") }
            .task {
                if store.products.isEmpty { await store.loadProducts() }
                selected = selected ?? store.yearly?.id ?? store.products.first?.id
                for p in store.products { trialEligible[p.id] = await store.isEligibleForTrial(p) }
            }
            .onChange(of: store.isPro) { _, pro in if pro { dismiss() } }
        }
    }

    private var selectedProduct: Product? { store.products.first { $0.id == selected } }

    private func planButton(_ p: Product) -> some View {
        let isYearly = p.id == store.yearly?.id
        let savings: Int = {
            guard isYearly, let m = store.monthly else { return 0 }
            return ProPlan.yearlySavingsPercent(monthly: m.price, yearly: p.price)
        }()
        return Button { selected = p.id } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(isYearly ? "Yearly" : "Monthly").font(.headline)
                        if savings > 0 {
                            Text("Save \(savings)%").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Theme.bluishGreen.opacity(0.2), in: Capsule())
                        }
                    }
                    Text(trialEligible[p.id] == true ? "1 month free, then \(p.displayPrice)/\(isYearly ? "year" : "month")"
                                                     : "\(p.displayPrice)/\(isYearly ? "year" : "month")")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: selected == p.id ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected == p.id ? Theme.blue : .secondary)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 14).strokeBorder(selected == p.id ? Theme.blue : Color.secondary.opacity(0.3), lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected == p.id ? .isSelected : [])
    }

    private var ctaTitle: String {
        guard let p = selectedProduct else { return "Continue" }
        return trialEligible[p.id] == true ? "Start 1-Month Free Trial" : "Subscribe for \(p.displayPrice)"
    }

    private var legalText: String {
        guard let p = selectedProduct else { return "" }
        let period = p.id == store.yearly?.id ? "year" : "month"
        let trial = trialEligible[p.id] == true ? "After the 1-month free trial, " : ""
        return "\(trial)\(p.displayPrice) per \(period), billed to your Apple ID. The subscription renews automatically unless cancelled at least 24 hours before the end of the current period. Manage or cancel anytime in Settings → Apple ID → Subscriptions."
    }

    private func purchase() {
        guard let p = selectedProduct else { return }
        Task {
            do {
                switch try await store.purchase(p) {
                case .purchased: dismiss()
                case .pending: message = "Purchase pending approval."
                case .cancelled: break
                }
            } catch {
                message = error.localizedDescription
            }
        }
    }
}

/// Settings → Subscription.
struct SubscriptionSettingsView: View {
    @Environment(EntitlementManager.self) private var store
    @State private var showPaywall = false
    @State private var showManage = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Plan", value: store.isPro ? (store.activeProductID == store.yearly?.id ? "Pro Yearly" : "Pro Monthly") : "Free")
                if store.isInTrial { LabeledContent("Status", value: "Free trial") }
                if let e = store.expirationDate {
                    LabeledContent(store.willAutoRenew ? "Renews" : "Expires", value: e.formatted(date: .abbreviated, time: .omitted))
                }
            }
            Section {
                if store.isPro {
                    Button("Manage Subscription") { showManage = true }
                } else {
                    Button("See Pro plans") { showPaywall = true }
                }
                Button("Restore Purchases") {
                    Task {
                        do { try await store.restore(); message = store.isPro ? "Restored." : "No active subscription found." }
                        catch { message = error.localizedDescription }
                    }
                }
            }
            #if DEBUG
            Section("Debug") {
                Toggle("Simulate Pro", isOn: Binding(get: { store.debugForcePro }, set: { store.debugForcePro = $0 }))
            }
            #endif
        }
        .navigationTitle("Subscription")
        .manageSubscriptionsSheet(isPresented: $showManage)
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .alert("Subscription", isPresented: .constant(message != nil)) { Button("OK") { message = nil } } message: { Text(message ?? "") }
    }
}
