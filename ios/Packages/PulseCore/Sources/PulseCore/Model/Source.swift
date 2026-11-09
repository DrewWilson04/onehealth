import Foundation

/// The app (or device integration) that wrote a sample to HealthKit.
public struct SourceRef: Hashable, Codable, Sendable {
    public var bundleId: String
    public var name: String
    public init(bundleId: String, name: String) {
        self.bundleId = bundleId
        self.name = name
    }
    /// Stable key used for priority lists and preferences.
    public var key: String { bundleId.isEmpty ? name : bundleId }

    /// "bundleId|name" — stored on aggregates so badges can show the vendor
    /// (Apple Watch and iPhone share the `com.apple.health.*` bundle prefix,
    /// only the name tells them apart).
    public var attribution: String { name.isEmpty ? bundleId : "\(bundleId)|\(name)" }

    public init(attribution: String) {
        if let i = attribution.firstIndex(of: "|") {
            self.init(bundleId: String(attribution[..<i]), name: String(attribution[attribution.index(after: i)...]))
        } else {
            self.init(bundleId: attribution, name: "")
        }
    }
}

/// Hardware that recorded a sample, when known.
public struct DeviceRef: Hashable, Codable, Sendable {
    public var name: String?
    public var model: String?
    public var manufacturer: String?
    public var hardwareVersion: String?
    public init(name: String? = nil, model: String? = nil, manufacturer: String? = nil, hardwareVersion: String? = nil) {
        self.name = name
        self.model = model
        self.manufacturer = manufacturer
        self.hardwareVersion = hardwareVersion
    }

    /// Parses the device description string found in Apple Health's export.xml,
    /// e.g. `<<HKDevice: 0x28>, name:Apple Watch, manufacturer:Apple Inc., model:Watch, hardware:Watch6,1, software:9.1>`.
    public static func parseExportDescription(_ s: String) -> DeviceRef? {
        guard !s.isEmpty else { return nil }
        var fields: [String: String] = [:]
        let keys = ["name", "manufacturer", "model", "hardware", "software", "localIdentifier", "UDIDeviceIdentifier", "firmware"]
        // Find "key:" tokens and slice values up to the next ", key:" or ">".
        var positions: [(key: String, range: Range<String.Index>)] = []
        for key in keys {
            var searchStart = s.startIndex
            while let r = s.range(of: "\(key):", range: searchStart..<s.endIndex) {
                // must be preceded by ", " or start
                let ok = r.lowerBound == s.startIndex || s[s.index(before: r.lowerBound)] == " "
                if ok { positions.append((key, r)); break }
                searchStart = r.upperBound
            }
        }
        positions.sort { $0.range.lowerBound < $1.range.lowerBound }
        for (i, p) in positions.enumerated() {
            let end: String.Index
            if i + 1 < positions.count {
                end = positions[i + 1].range.lowerBound
            } else {
                end = s.lastIndex(of: ">") ?? s.endIndex
            }
            var v = String(s[p.range.upperBound..<max(p.range.upperBound, end)])
            v = v.trimmingCharacters(in: .whitespaces)
            if v.hasSuffix(",") { v.removeLast() }
            fields[p.key] = v.trimmingCharacters(in: .whitespaces)
        }
        if fields.isEmpty { return nil }
        return DeviceRef(name: fields["name"], model: fields["model"], manufacturer: fields["manufacturer"], hardwareVersion: fields["hardware"])
    }
}

/// Recognised vendors, inferred from source/device strings. Used for the
/// "via Garmin" badge and the default source-priority heuristic.
public enum Vendor: String, Codable, Sendable, CaseIterable {
    case appleWatch, iPhone, garmin, whoop, oura, fitbit, polar, withings, coros, suunto, samsung, eightSleep, strava, pulseBoard, other

    public var displayName: String {
        switch self {
        case .appleWatch: return "Apple Watch"
        case .iPhone: return "iPhone"
        case .garmin: return "Garmin"
        case .whoop: return "WHOOP"
        case .oura: return "Oura"
        case .fitbit: return "Fitbit"
        case .polar: return "Polar"
        case .withings: return "Withings"
        case .coros: return "COROS"
        case .suunto: return "Suunto"
        case .samsung: return "Samsung"
        case .eightSleep: return "Eight Sleep"
        case .strava: return "Strava"
        case .pulseBoard: return AppBrandName.value
        case .other: return "Other"
        }
    }

    /// Default rank when the user has not ordered sources (lower wins).
    /// Wrist/ring wearables first, then phone, then manual, then other apps.
    public var defaultRank: Int {
        switch self {
        case .appleWatch: return 10
        case .garmin, .whoop, .oura, .fitbit, .polar, .coros, .suunto, .samsung: return 20
        case .withings, .eightSleep: return 25
        case .iPhone: return 30
        case .pulseBoard: return 35
        case .strava: return 40
        case .other: return 50
        }
    }

    public static func infer(source: SourceRef, device: DeviceRef?) -> Vendor {
        let hay = [source.bundleId, source.name, device?.name ?? "", device?.manufacturer ?? "", device?.model ?? ""]
            .joined(separator: " ").lowercased()
        if hay.contains(AppBrandName.bundlePrefixHint.lowercased()) && !AppBrandName.bundlePrefixHint.isEmpty { return .pulseBoard }
        if hay.contains("garmin") { return .garmin }
        if hay.contains("whoop") { return .whoop }
        if hay.contains("oura") { return .oura }
        if hay.contains("fitbit") || hay.contains("google fit") || hay.contains("com.google.android.apps.fitness") { return .fitbit }
        if hay.contains("polar") { return .polar }
        if hay.contains("withings") || hay.contains("nokia health") { return .withings }
        if hay.contains("coros") { return .coros }
        if hay.contains("suunto") { return .suunto }
        if hay.contains("samsung") || hay.contains("galaxy") { return .samsung }
        if hay.contains("eight sleep") || hay.contains("eightsleep") { return .eightSleep }
        if hay.contains("strava") { return .strava }
        if hay.contains("watch") && (hay.contains("apple") || source.bundleId.hasPrefix("com.apple.health")) { return .appleWatch }
        if let model = device?.model?.lowercased(), model.contains("watch") { return .appleWatch }
        if hay.contains("iphone") || (device?.model?.lowercased().contains("iphone") ?? false) { return .iPhone }
        if source.bundleId.hasPrefix("com.apple.health") { return .iPhone }
        return .other
    }
}

/// Brand name holder so PulseCore doesn't hardcode the product name. The app
/// sets this at launch from its Info.plist (`CFBundleDisplayName`).
public enum AppBrandName {
    nonisolated(unsafe) public static var value: String = "PulseBoard"
    /// Bundle-id prefix of our own app, used to recognise our own writes.
    nonisolated(unsafe) public static var bundlePrefixHint: String = ""
}
