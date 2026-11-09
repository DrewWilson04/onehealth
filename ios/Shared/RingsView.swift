import SwiftUI
import PulseCore

/// Concentric progress rings (move / exercise / stand, or any goals).
struct RingsView: View {
    struct Ring: Identifiable {
        let id: String
        let label: String
        let progress: Double
        let color: Color
    }
    let rings: [Ring]
    var lineWidth: CGFloat = 12

    var body: some View {
        ZStack {
            ForEach(Array(rings.enumerated()), id: \.element.id) { i, ring in
                let inset = CGFloat(i) * (lineWidth + 3)
                Circle()
                    .stroke(ring.color.opacity(0.18), lineWidth: lineWidth)
                    .padding(inset)
                Circle()
                    .trim(from: 0, to: min(1, max(0.001, ring.progress)))
                    .stroke(ring.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(inset)
                if ring.progress > 1 {
                    // Overflow lap indicator.
                    Circle()
                        .trim(from: 0, to: min(1, ring.progress - 1))
                        .stroke(ring.color.opacity(0.6), style: StrokeStyle(lineWidth: lineWidth * 0.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(inset)
                }
            }
        }
        .padding(lineWidth / 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rings.map { "\($0.label) \(Int($0.progress * 100)) percent" }.joined(separator: ", "))
    }
}

extension RingsView {
    init(activity r: ActivityRings, lineWidth: CGFloat = 12) {
        self.init(rings: [
            Ring(id: "move", label: "Move", progress: r.moveProgress, color: Theme.vermillion),
            Ring(id: "exercise", label: "Exercise", progress: r.exerciseProgress, color: Theme.bluishGreen),
            Ring(id: "stand", label: "Stand", progress: r.standProgress, color: Theme.skyBlue),
        ], lineWidth: lineWidth)
    }
}
