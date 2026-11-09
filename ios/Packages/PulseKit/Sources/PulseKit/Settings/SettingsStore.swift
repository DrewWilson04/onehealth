import Foundation
import Observation
import SwiftData
import PulseCore
#if canImport(UIKit)
import UIKit
#endif

/// What may sync to iCloud. Goals and meal templates are a 5.1.3 gray area
/// (configuration, not health records). Users can turn them off in
/// Settings → iCloud Sync; the choice is per device (UserDefaults).
public enum SettingsSync {
    public static var syncGoals: Bool {
        get { UserDefaults.standard.object(forKey: "sync.goals") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "sync.goals") }
    }
    public static var syncMealTemplates: Bool {
        get { UserDefaults.standard.object(forKey: "sync.meals") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "sync.meals") }
    }
}

/// Settings, goals, widget layouts, meal templates, preferred sources and
/// challenge configs. Backed by SwiftData; the synced store mirrors to the
/// user's CloudKit *private* database. Local-only keys go to a separate
/// non-synced store.
@MainActor
@Observable
public final class SettingsStore {
    public enum Keys {
        public static let preferences = "preferences"
        public static let preferredSources = "preferredSources"
        public static let sourcePriority = "sourcePriority"
        public static let dashboardLayout = "dashboardLayout"
        public static let goalPrefix = "goal."
        public static let mealPrefix = "meal."
        public static let challengePrefix = "challenge."
    }

    public enum SyncState: Equatable, Sendable {
        case local, syncing, upToDate(Date), unavailable(String)
    }

    let synced: ModelContainer
    let local: ModelContainer
    private let deviceName: String
    public let cloudKitContainerID: String?
    public private(set) var isCloudBacked = false

    // Observable, decoded values.
    public private(set) var preferences = UserPreferences()
    public private(set) var preferredSources: [MetricID: String] = [:]
    public private(set) var sourcePriority = SourcePriority.default
    public private(set) var dashboardLayout = DashboardLayout.default
    public private(set) var goals: [Goal] = Goal.defaults
    public private(set) var mealTemplates: [MealTemplate] = []
    public private(set) var challengeConfigs: [String: Data] = [:]
    public var syncState: SyncState = .local
    /// Bumped on every change (local or remote) so observers can react.
    public private(set) var revision = 0

    public init(cloudKitContainer: String?, inMemory: Bool = false) {
        #if canImport(UIKit) && !os(watchOS)
        deviceName = UIDevice.current.name
        #else
        deviceName = "Apple Watch"
        #endif
        cloudKitContainerID = cloudKitContainer
        let schema = Schema([SettingRecord.self])
        var cloudOK = false
        func make(_ name: String, cloud: ModelConfiguration.CloudKitDatabase, isCloud: Bool) -> ModelContainer {
            let config = ModelConfiguration(name, schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: cloud)
            if let c = try? ModelContainer(for: schema, configurations: [config]) {
                if isCloud { cloudOK = true }
                return c
            }
            // CloudKit unavailable (e.g. missing entitlement in a dev build) →
            // fall back to a local store; the app keeps working.
            let fallback = ModelConfiguration(name, schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
            return try! ModelContainer(for: schema, configurations: [fallback])
        }
        if let id = cloudKitContainer, !id.isEmpty, !inMemory {
            synced = make("SettingsSynced", cloud: .private(id), isCloud: true)
        } else {
            synced = make("SettingsSynced", cloud: .none, isCloud: false)
        }
        isCloudBacked = cloudOK
        syncState = cloudOK ? .syncing : .local
        local = make("SettingsLocal", cloud: .none, isCloud: false)
        reload()
        observeRemoteChanges()
    }

    // MARK: Generic KV

    /// Every write is checked against `CloudPolicy`: anything not allow-listed
    /// as non-health configuration goes to the local-only store.
    private func container(for key: String) -> ModelContainer {
        CloudPolicy.isAllowedInCloud(key, syncGoals: SettingsSync.syncGoals, syncMealTemplates: SettingsSync.syncMealTemplates)
            ? synced : local
    }

    /// Moves records between the synced and local stores after the user
    /// changes what syncs (e.g. turns off goal sync → goals leave iCloud).
    public func applySyncPolicy() {
        for (from, to) in [(synced, local), (local, synced)] {
            let ctx = from.mainContext
            let all = (try? ctx.fetch(FetchDescriptor<SettingRecord>())) ?? []
            for r in all where container(for: r.key) === to {
                to.mainContext.insert(SettingRecord(key: r.key, json: r.json, deviceName: r.deviceName))
                ctx.delete(r)
            }
            try? ctx.save()
            try? to.mainContext.save()
        }
        reload()
    }

    private func records(_ ctx: ModelContext, key: String) -> [SettingRecord] {
        let fd = FetchDescriptor<SettingRecord>(predicate: #Predicate { $0.key == key },
                                                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        return (try? ctx.fetch(fd)) ?? []
    }

    public func value<T: Decodable>(_ type: T.Type, key: String) -> T? {
        let ctx = container(for: key).mainContext
        guard let r = records(ctx, key: key).first else { return nil }
        return try? JSONDecoder().decode(T.self, from: r.json)
    }

    public func set<T: Encodable>(_ value: T, key: String) {
        let ctx = container(for: key).mainContext
        guard let data = try? JSONEncoder().encode(value) else { return }
        let existing = records(ctx, key: key)
        if let first = existing.first {
            first.json = data
            first.updatedAt = Date()
            first.deviceName = deviceName
            existing.dropFirst().forEach(ctx.delete)
        } else {
            ctx.insert(SettingRecord(key: key, json: data, deviceName: deviceName))
        }
        try? ctx.save()
        reload()
    }

    public func remove(key: String) {
        let ctx = container(for: key).mainContext
        records(ctx, key: key).forEach(ctx.delete)
        try? ctx.save()
        reload()
    }

    private func all<T: Decodable>(_ type: T.Type, prefix: String) -> [T] {
        var out: [String: (Date, T)] = [:]
        for c in [synced, local] {
            let fd = FetchDescriptor<SettingRecord>(predicate: #Predicate { $0.key.starts(with: prefix) })
            for r in (try? c.mainContext.fetch(fd)) ?? [] {
                guard let v = try? JSONDecoder().decode(T.self, from: r.json) else { continue }
                if let e = out[r.key], e.0 >= r.updatedAt { continue }
                out[r.key] = (r.updatedAt, v)
            }
        }
        return out.sorted { $0.key < $1.key }.map(\.value.1)
    }

    /// Removes duplicate records for the same key (two devices created the
    /// same key while offline). Newest wins.
    public func dedupe() {
        for c in [synced, local] {
            let ctx = c.mainContext
            let all = (try? ctx.fetch(FetchDescriptor<SettingRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))) ?? []
            var seen = Set<String>()
            for r in all {
                if seen.contains(r.key) { ctx.delete(r) } else { seen.insert(r.key) }
            }
            try? ctx.save()
        }
    }

    public func reload() {
        preferences = value(UserPreferences.self, key: Keys.preferences) ?? UserPreferences()
        let prefs = value([String: String].self, key: Keys.preferredSources) ?? [:]
        preferredSources = Dictionary(uniqueKeysWithValues: prefs.map { (MetricID($0.key), $0.value) })
        sourcePriority = value(SourcePriority.self, key: Keys.sourcePriority) ?? .default
        dashboardLayout = value(DashboardLayout.self, key: Keys.dashboardLayout) ?? .default
        let g = all(Goal.self, prefix: Keys.goalPrefix)
        goals = g.isEmpty && value(Bool.self, key: "goalsInitialized") != true ? Goal.defaults : g
        mealTemplates = all(MealTemplate.self, prefix: Keys.mealPrefix)
        revision += 1
    }

    // MARK: Typed setters

    public func update(_ change: (inout UserPreferences) -> Void) {
        var p = preferences
        change(&p)
        set(p, key: Keys.preferences)
    }

    public func setPreferredSource(_ key: String?, for metric: MetricID) {
        var raw = Dictionary(uniqueKeysWithValues: preferredSources.map { ($0.key.rawValue, $0.value) })
        raw[metric.rawValue] = key
        set(raw, key: Keys.preferredSources)
    }

    public func setSourcePriority(_ p: SourcePriority) { set(p, key: Keys.sourcePriority) }
    public func setDashboardLayout(_ l: DashboardLayout) { set(l, key: Keys.dashboardLayout) }

    public func saveGoal(_ goal: Goal) {
        if value(Bool.self, key: "goalsInitialized") != true {
            // Materialize defaults the first time the user edits goals.
            set(true, key: "goalsInitialized")
            for d in Goal.defaults where d.id != goal.id { set(d, key: Keys.goalPrefix + d.id) }
        }
        set(goal, key: Keys.goalPrefix + goal.id)
    }

    public func deleteGoal(_ id: String) {
        if value(Bool.self, key: "goalsInitialized") != true {
            set(true, key: "goalsInitialized")
            for d in Goal.defaults where d.id != id { set(d, key: Keys.goalPrefix + d.id) }
        }
        remove(key: Keys.goalPrefix + id)
    }

    public func saveMealTemplate(_ t: MealTemplate) { set(t, key: Keys.mealPrefix + t.id) }
    public func deleteMealTemplate(_ id: String) { remove(key: Keys.mealPrefix + id) }

    public func challengeConfig<T: Decodable>(_ type: T.Type, id: String) -> T? { value(T.self, key: Keys.challengePrefix + id) }
    public func challengeConfigs<T: Decodable>(_ type: T.Type) -> [T] { all(T.self, prefix: Keys.challengePrefix) }
    public func saveChallengeConfig<T: Encodable>(_ v: T, id: String) { set(v, key: Keys.challengePrefix + id) }

    // MARK: Remote changes

    private func observeRemoteChanges() {
        // SwiftData + CloudKit posts NSPersistentStoreRemoteChange when the
        // mirror imports changes from another device.
        NotificationCenter.default.addObserver(forName: Notification.Name("NSPersistentStoreRemoteChangeNotification"),
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.dedupe()
                self?.reload()
                self?.syncState = .upToDate(Date())
            }
        }
    }
}
