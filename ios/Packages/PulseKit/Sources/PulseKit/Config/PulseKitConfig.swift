import Foundation
import PulseCore

/// Build-time configuration, read from the host target's Info.plist. All
/// values originate in ios/Config/AppConfig.xcconfig — the single place to
/// rename the app or change identifiers.
public enum PulseKitConfig {
    private static func string(_ key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String) ?? ""
    }

    public static var appName: String {
        let n = string("CFBundleDisplayName")
        return n.isEmpty ? "PulseBoard" : n
    }
    /// e.g. "com.example" — used to recognise our own HealthKit writes.
    public static var bundleIdPrefix: String { string("PBBundleIdPrefix") }
    public static var appGroup: String { string("PBAppGroup") }
    public static var iCloudContainer: String { string("PBICloudContainer") }
    /// Mock challenges with seeded participants (Debug/TestFlight only).
    public static var challengesPreviewEnabled: Bool { string("PBChallengesPreview") == "YES" }
    public static var backfillTaskIdentifier: String { "\(bundleIdPrefix).pulseboard.backfill" }
    public static var refreshTaskIdentifier: String { "\(bundleIdPrefix).pulseboard.refresh" }

    /// Call once at launch so PulseCore uses the configured brand/bundle.
    public static func bootstrap() {
        AppBrandName.value = appName
        AppBrandName.bundlePrefixHint = bundleIdPrefix.isEmpty ? "" : "\(bundleIdPrefix).pulseboard"
    }
}
