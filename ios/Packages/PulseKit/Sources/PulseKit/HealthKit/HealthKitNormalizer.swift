import Foundation
import HealthKit
import PulseCore

/// HKSample → PulseCore `Sample`, via the shared `RawSample` + `Normalizer`
/// so iOS and the web importer apply identical rules.
public struct HealthKitNormalizer: Sendable {
    public let normalizer: Normalizer

    public init(ownBundleIdPrefix: String = AppBrandName.bundlePrefixHint) {
        normalizer = Normalizer(ownBundleIdPrefix: ownBundleIdPrefix)
    }

    public func normalize(_ hk: HKSample, as metric: MetricType) -> Sample? {
        let source = hk.sourceRevision.source
        let device = hk.device.map {
            DeviceRef(name: $0.name, model: $0.model, manufacturer: $0.manufacturer, hardwareVersion: $0.hardwareVersion)
        }
        let meta = Self.stringify(hk.metadata)

        if let w = hk as? HKWorkout {
            let energy = w.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
            let distanceTypes: [HKQuantityTypeIdentifier] = [.distanceWalkingRunning, .distanceCycling, .distanceSwimming, .distanceDownhillSnowSports]
            let distance = distanceTypes.lazy.compactMap { w.statistics(for: HKQuantityType($0))?.sumQuantity()?.doubleValue(for: .meter()) }.first
            let hr = w.statistics(for: HKQuantityType(.heartRate))?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            return normalizer.normalizeWorkout(
                activityType: HKMapping.activityName(w.workoutActivityType), start: w.startDate, end: w.endDate,
                durationMinutes: w.duration / 60, energyKcal: energy, distanceMeters: distance, averageHeartRate: hr,
                hasRoute: false, // routes are fetched lazily in the workout detail view
                sourceName: source.name, sourceBundleId: source.bundleIdentifier, device: device,
                metadata: meta, uuid: w.uuid.uuidString)
        }

        var raw = RawSample(typeIdentifier: metric.healthKitIdentifier ?? "", value: nil, unit: nil,
                            start: hk.startDate, end: hk.endDate, sourceName: source.name,
                            sourceBundleId: source.bundleIdentifier, device: device, metadata: meta,
                            uuid: hk.uuid.uuidString)

        if let q = hk as? HKQuantitySample, let (unit, unitString) = HKMapping.hkUnit(for: metric.unit) {
            guard q.quantity.is(compatibleWith: unit) else { return nil }
            raw.value = q.quantity.doubleValue(for: unit)
            raw.unit = unitString
        } else if let c = hk as? HKCategorySample {
            raw.value = Double(c.value)
        } else if let ecg = hk as? HKElectrocardiogram {
            raw.value = ecg.averageHeartRate?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            raw.metadata["classification"] = Self.ecgClassification(ecg.classification)
            raw.metadata["symptomsStatus"] = ecg.symptomsStatus == .present ? "present" : (ecg.symptomsStatus == .none ? "none" : "notSet")
        } else {
            return nil
        }
        return normalizer.normalize(raw).sample
    }

    static func ecgClassification(_ c: HKElectrocardiogram.Classification) -> String {
        switch c {
        case .sinusRhythm: return "sinusRhythm"
        case .atrialFibrillation: return "atrialFibrillation"
        case .inconclusiveLowHeartRate: return "inconclusiveLowHeartRate"
        case .inconclusiveHighHeartRate: return "inconclusiveHighHeartRate"
        case .inconclusivePoorReading: return "inconclusivePoorReading"
        case .inconclusiveOther: return "inconclusiveOther"
        case .unrecognized: return "unrecognized"
        case .notSet: return "notSet"
        @unknown default: return "unknown"
        }
    }

    /// HealthKit metadata is `[String: Any]`; we keep a string map.
    /// HKMetadataKeyWasUserEntered is preserved as "HKWasUserEntered" = "1".
    static func stringify(_ m: [String: Any]?) -> [String: String] {
        guard let m else { return [:] }
        var out: [String: String] = [:]
        for (k, v) in m {
            switch v {
            case let s as String: out[k] = s
            case let n as NSNumber: out[k] = n.stringValue
            case let d as Date: out[k] = ISO8601DateFormatter().string(from: d)
            case let q as HKQuantity: out[k] = q.description
            default: continue
            }
        }
        return out
    }
}
