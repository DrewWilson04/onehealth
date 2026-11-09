import Foundation
import SwiftData

/// One synced setting. Key-value JSON records keep CloudKit merges simple:
/// each logical item (a goal, a meal template, the dashboard layout...) is its
/// own record, so concurrent edits on two devices rarely collide; when they
/// do, the newest `updatedAt` wins (see SettingsStore.dedupe).
///
/// CloudKit requirements for SwiftData models: every attribute has a default
/// or is optional, and no `.unique` constraints.
///
/// ONLY non-health configuration may be stored here (guideline 5.1.3(ii)).
@Model
public final class SettingRecord {
    public var key: String = ""
    public var json: Data = Data()
    public var updatedAt: Date = Date.distantPast
    public var deviceName: String = ""

    public init(key: String, json: Data, deviceName: String) {
        self.key = key
        self.json = json
        self.updatedAt = Date()
        self.deviceName = deviceName
    }
}
