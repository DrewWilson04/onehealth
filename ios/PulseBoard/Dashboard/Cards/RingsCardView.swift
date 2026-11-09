import SwiftUI
import PulseCore

struct RingsCardView: View {
    let rings: ActivityRings?

    var body: some View {
        CardContainer(tint: Theme.vermillion) {
            HStack(spacing: 16) {
                if let r = rings {
                    RingsView(activity: r, lineWidth: 11).frame(width: 96, height: 96)
                    VStack(alignment: .leading, spacing: 6) {
                        row("Move", "\(Int(r.move))/\(Int(r.moveGoal)) kcal", Theme.vermillion)
                        row("Exercise", "\(Int(r.exercise))/\(Int(r.exerciseGoal)) min", Theme.bluishGreen)
                        row("Stand", "\(Int(r.stand))/\(Int(r.standGoal)) h", Theme.skyBlue)
                    }
                } else {
                    Label("Activity rings appear when an Apple Watch is paired.", systemImage: "circle.circle")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func row(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(color)
            Text(value).font(.subheadline.monospacedDigit())
        }
        .accessibilityElement(children: .combine)
    }
}
