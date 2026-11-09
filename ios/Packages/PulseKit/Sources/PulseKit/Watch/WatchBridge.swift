import Foundation
import WatchConnectivity
import PulseCore

/// Phone ↔ Watch sync of the small derived snapshot (scores, goals, challenge
/// standing). Raw health data is NOT sent — the watch reads its own HealthKit
/// store, which Apple syncs. Uses application context (latest-wins, delivered
/// opportunistically) so it's battery friendly.
public final class WatchBridge: NSObject, WCSessionDelegate, @unchecked Sendable {
    public static let shared = WatchBridge()
    /// Called on the watch when a new snapshot arrives.
    public var onSnapshot: (@Sendable (WidgetSnapshot) -> Void)?

    public func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// iOS → watch.
    public func send(_ snapshot: WidgetSnapshot) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        #if os(iOS)
        guard WCSession.default.isPaired, WCSession.default.isWatchAppInstalled else { return }
        #endif
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        guard let data = try? e.encode(snapshot) else { return }
        try? WCSession.default.updateApplicationContext(["snapshot": data])
    }

    /// The most recent context already received (on watch launch).
    public func latestReceived() -> WidgetSnapshot? {
        guard WCSession.isSupported(), let data = WCSession.default.receivedApplicationContext["snapshot"] as? Data else { return nil }
        return Self.decode(data)
    }

    static func decode(_ data: Data) -> WidgetSnapshot? {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try? d.decode(WidgetSnapshot.self, from: data)
    }

    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if let data = applicationContext["snapshot"] as? Data, let s = Self.decode(data) { onSnapshot?(s) }
    }

    #if os(iOS)
    public func sessionDidBecomeInactive(_ session: WCSession) {}
    public func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
    #endif
}
