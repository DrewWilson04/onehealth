import Foundation

/// For discrete metrics (heart rate, HRV, SpO₂, weight) HealthKit statistics
/// average across *all* sources, which mixes devices with different
/// methodologies (e.g. WHOOP/Oura write RMSSD-style values into the SDNN type).
/// We instead pick ONE source per window:
/// 1. the user's preferred source for the metric, if it has data in the window;
/// 2. otherwise the source with the most samples in the window;
/// 3. ties broken by `SourcePriority`.
public enum DiscreteSourceSelector {
    public static func select(_ samples: [Sample], preferredSourceKey: String?, priority: SourcePriority) -> [Sample] {
        guard !samples.isEmpty else { return [] }
        if let pref = preferredSourceKey {
            let p = samples.filter { $0.source.key == pref || $0.source.name == pref }
            if !p.isEmpty { return p }
        }
        var counts: [String: (Int, Sample)] = [:]
        for s in samples {
            let k = s.source.key
            counts[k] = ((counts[k]?.0 ?? 0) + 1, counts[k]?.1 ?? s)
        }
        let best = counts.max { a, b in
            if a.value.0 != b.value.0 { return a.value.0 < b.value.0 }
            // a is "less" if it has lower priority (higher rank)
            return priority.isHigher(b.value.1.source, b.value.1.device, than: a.value.1.source, a.value.1.device)
        }!.key
        return samples.filter { $0.source.key == best }
    }
}
