import SwiftUI
import PulseCore

/// A grid where children can span 1 or 2 columns. Column count adapts to the
/// available width (2 on iPhone, 3–5 on iPad / landscape).
struct AdaptiveCardGrid: Layout {
    var minColumnWidth: CGFloat = 165
    var spacing: CGFloat = 12

    struct Span: LayoutValueKey { static let defaultValue = 1 }

    private func columns(for width: CGFloat) -> Int {
        max(2, Int((width + spacing) / (minColumnWidth + spacing)))
    }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (frames: [CGRect], height: CGFloat) {
        let cols = columns(for: width)
        let colWidth = (width - spacing * CGFloat(cols - 1)) / CGFloat(cols)
        var frames: [CGRect] = []
        var x = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sv in subviews {
            let span = min(cols, sv[Span.self])
            if x + span > cols {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            let w = colWidth * CGFloat(span) + spacing * CGFloat(span - 1)
            let h = sv.sizeThatFits(ProposedViewSize(width: w, height: nil)).height
            frames.append(CGRect(x: CGFloat(x) * (colWidth + spacing), y: y, width: w, height: h))
            rowHeight = max(rowHeight, h)
            x += span
        }
        return (frames, subviews.isEmpty ? 0 : y + rowHeight)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 360
        return CGSize(width: width, height: arrange(width, subviews).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (frames, _) = arrange(bounds.width, subviews)
        for (sv, f) in zip(subviews, frames) {
            sv.place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY), proposal: ProposedViewSize(width: f.width, height: f.height))
        }
    }
}

extension View {
    func gridSpan(_ span: Int) -> some View { layoutValue(key: AdaptiveCardGrid.Span.self, value: span) }
}

/// Standard card chrome.
struct CardContainer<Content: View>: View {
    var tint: Color = .accentColor
    @ViewBuilder var content: Content
    var body: some View {
        content
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(tint.opacity(0.18), lineWidth: 1)
            }
    }
}

/// "via Garmin" badge.
struct SourceBadge: View {
    let sourceKey: String?
    var body: some View {
        if let sourceKey, let name = Self.vendorName(sourceKey) {
            Text("via \(name)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityLabel("Source: \(name)")
        }
    }

    static func vendorName(_ attribution: String) -> String? {
        let src = SourceRef(attribution: attribution)
        let vendor = Vendor.infer(source: src, device: nil)
        return vendor == .other ? (src.name.isEmpty ? nil : src.name) : vendor.displayName
    }
}

/// Small "Estimated" pill for gap-filled values.
struct EstimatedBadge: View {
    var confidence: Confidence?
    var body: some View {
        Label("Estimated\(confidence.map { " · \($0.rawValue) confidence" } ?? "")", systemImage: "wand.and.stars")
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Theme.yellow.opacity(0.25), in: Capsule())
            .accessibilityLabel("Estimated value\(confidence.map { ", \($0.rawValue) confidence" } ?? "")")
    }
}
