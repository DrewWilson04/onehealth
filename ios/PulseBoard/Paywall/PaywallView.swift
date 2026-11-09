import SwiftUI
import PulseCore

// Placeholder — implemented in Milestone 7 (StoreKit 2).
struct PaywallView: View {
    var highlight: Feature? = nil
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ContentUnavailableView("Pro", systemImage: "star.circle.fill", description: Text("\(highlight?.title ?? "This feature") is part of Pro."))
                .toolbar { Button("Close") { dismiss() } }
        }
    }
}
