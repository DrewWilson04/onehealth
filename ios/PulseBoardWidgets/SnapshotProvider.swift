import WidgetKit
import SwiftUI
import AppIntents
import PulseCore

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    var metric: MetricID = .steps
}

/// Widgets only read the App Group snapshot written by the app.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: .now, snapshot: .sample) }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? .sample : (AppGroup.readSnapshot() ?? .sample)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: .now, snapshot: AppGroup.readSnapshot())
        // The app reloads timelines when data changes; this is a fallback.
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60))))
    }
}

enum WidgetMetricOption: String, AppEnum {
    case steps, activeEnergy, exerciseTime, distanceWalkingRunning, sleep, restingHeartRate, hrv, bodyMass, water, dietaryEnergy

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Metric"
    static let caseDisplayRepresentations: [WidgetMetricOption: DisplayRepresentation] = [
        .steps: "Steps", .activeEnergy: "Active Energy", .exerciseTime: "Exercise Minutes",
        .distanceWalkingRunning: "Distance", .sleep: "Sleep", .restingHeartRate: "Resting Heart Rate",
        .hrv: "HRV", .bodyMass: "Weight", .water: "Water", .dietaryEnergy: "Calories Eaten",
    ]
}

struct SelectMetricIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Metric"
    static let description = IntentDescription("Pick the metric to show.")

    @Parameter(title: "Metric", default: .steps)
    var metric: WidgetMetricOption
}

struct MetricIntentProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: .now, snapshot: .sample) }

    func snapshot(for configuration: SelectMetricIntent, in context: Context) async -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: context.isPreview ? .sample : (AppGroup.readSnapshot() ?? .sample),
                      metric: MetricID(configuration.metric.rawValue))
    }

    func timeline(for configuration: SelectMetricIntent, in context: Context) async -> Timeline<SnapshotEntry> {
        let e = SnapshotEntry(date: .now, snapshot: AppGroup.readSnapshot(), metric: MetricID(configuration.metric.rawValue))
        return Timeline(entries: [e], policy: .after(.now.addingTimeInterval(30 * 60)))
    }
}

/// Shown when the user isn't Pro, or before the app has written data.
struct WidgetGate<Content: View>: View {
    let snapshot: WidgetSnapshot?
    @ViewBuilder var content: (WidgetSnapshot) -> Content

    var body: some View {
        if let s = snapshot, s.isPro {
            content(s)
        } else if snapshot == nil {
            VStack(spacing: 4) {
                Image(systemName: "heart.text.square").font(.title2)
                Text("Open the app to load your data").font(.caption).multilineTextAlignment(.center)
            }
        } else {
            VStack(spacing: 4) {
                Image(systemName: "lock.fill").font(.title3)
                Text("Widgets are part of Pro").font(.caption).multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
        }
    }
}

func accent(_ section: String) -> Color {
    Theme.accent(DashboardSection(rawValue: section) ?? .activity)
}
