import Foundation
import Observation
import HealthKit
import WidgetKit
import PulseCore
import PulseKit

/// Watch state: live stats from the watch's own HealthKit store, plus derived
/// scores / goals / challenge standing synced from the iPhone.
@MainActor
@Observable
final class WatchModel {
    var snapshot: WidgetSnapshot?
    var steps: Double?
    var activeEnergy: Double?
    var heartRate: Double?
    var rings: ActivityRings?
    var authorized = false
    var lastLogged: String?

    let provider = HealthKitProvider()
    let writer: HealthWriter
    let calendar = Calendar.pulse()

    init() {
        PulseKitConfig.bootstrap()
        writer = HealthWriter(store: provider.store)
    }

    func start() async {
        WatchBridge.shared.onSnapshot = { s in
            Task { @MainActor in
                self.snapshot = s
                AppGroup.writeSnapshot(s)
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
        WatchBridge.shared.activate()
        snapshot = WatchBridge.shared.latestReceived() ?? AppGroup.readSnapshot()
        do {
            try await provider.requestAuthorization(read: [.steps, .activeEnergy, .heartRate, .exerciseTime, .restingHeartRate],
                                                    write: [.water])
            authorized = true
        } catch {
            authorized = false
        }
        await refresh()
    }

    func refresh() async {
        let today = DayKey.today(calendar)
        let iv = today.interval(in: calendar)
        steps = try? await provider.dailyAggregates(of: .steps, in: iv, policy: .merged, calendar: calendar).first?.sum
        activeEnergy = try? await provider.dailyAggregates(of: .activeEnergy, in: iv, policy: .merged, calendar: calendar).first?.sum
        let hr = try? await provider.samples(of: .heartRate, in: DateInterval(start: Date().addingTimeInterval(-3600), end: Date()))
        heartRate = hr?.last?.value ?? snapshot?.latestHeartRate
        rings = (try? await provider.activityRings(days: 1, calendar: calendar))?[today] ?? snapshot?.rings
        // Keep complications fresh with the watch's own step count.
        if var s = snapshot ?? AppGroup.readSnapshot() {
            if let st = steps, let i = s.metrics.firstIndex(where: { $0.id == MetricID.steps.rawValue }) {
                s.metrics[i].value = st
                s.metrics[i].formatted = st.formatted(.number.precision(.fractionLength(0)))
                if let g = s.metrics[i].goal, g > 0 { s.metrics[i].progress = st / g }
            }
            s.rings = rings ?? s.rings
            AppGroup.writeSnapshot(s)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    func logWater(_ ml: Double) async {
        do {
            try await writer.log(.water, value: ml, at: Date())
            lastLogged = "Logged \(Int(ml)) mL"
        } catch {
            lastLogged = error.localizedDescription
        }
    }
}
