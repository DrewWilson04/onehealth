import Foundation

/// RFC 4180 CSV exports. Numbers use "." decimals and no grouping; dates are
/// ISO-8601 (days as yyyy-MM-dd) so files open cleanly in any spreadsheet.
public enum CSVExporter {
    public static func escape(_ s: String) -> String {
        if s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }

    public static func number(_ v: Double?, digits: Int = 2) -> String {
        guard let v, v.isFinite else { return "" }
        var s = String(format: "%.\(digits)f", v)
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        return s == "-0" ? "0" : s
    }

    static func line(_ fields: [String]) -> String { fields.map(escape).joined(separator: ",") }

    /// Wide daily summary: one row per day, one column per metric.
    /// Estimated values are suffixed in a companion "<metric> estimated" column
    /// only when the range contains any.
    public static func dailySummary(metrics: [MetricType], rows: [MetricID: [DailyAggregate]], from: DayKey, to: DayKey) -> String {
        var header = ["date"]
        var hasEstimated: [MetricID: Bool] = [:]
        for m in metrics {
            let ul = unitLabel(m)
            header.append(ul.isEmpty ? m.displayName : "\(m.displayName) (\(ul))")
            if rows[m.id]?.contains(where: \.isEstimated) == true {
                hasEstimated[m.id] = true
                header.append("\(m.displayName) estimated")
            }
        }
        var out = [line(header)]
        let index = rows.mapValues { Dictionary($0.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a }) }
        for d in DayKey.range(from, through: to) {
            var f = [d.description]
            for m in metrics {
                let r = index[m.id]?[d]
                f.append(number(r?.value(for: m.dailyStatistic)))
                if hasEstimated[m.id] == true { f.append(r?.isEstimated == true ? "yes" : "") }
            }
            out.append(line(f))
        }
        return out.joined(separator: "\r\n") + "\r\n"
    }

    static func unitLabel(_ m: MetricType) -> String {
        switch m.unit {
        case .stageCode: return "min"
        case .eventCode: return m.dailyStatistic == .durationMinutes ? "min" : "count"
        default: return m.unit.symbol
        }
    }

    /// Long-format raw samples (one row per sample, every schema field).
    public static func samples(_ samples: [Sample]) -> String {
        let iso = ISO8601DateFormatter()
        var out = [line(["id", "type", "value", "unit", "start", "end", "source", "source_bundle_id", "device", "is_manual", "is_estimated", "metadata"])]
        for s in samples.sorted(by: { ($0.start, $0.id) < ($1.start, $1.id) }) {
            let meta = (s.metadata ?? [:]).sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ";")
            out.append(line([s.id, s.type.rawValue, number(s.value, digits: 4), s.unit.rawValue, iso.string(from: s.start), iso.string(from: s.end),
                             s.source.name, s.source.bundleId, s.device?.name ?? s.device?.model ?? "",
                             s.isManual ? "true" : "false", s.isEstimated ? "true" : "false", meta]))
        }
        return out.joined(separator: "\r\n") + "\r\n"
    }

    /// Daily derived scores.
    public static func scores(_ results: [ScoreResult], from: DayKey, to: DayKey) -> String {
        var out = [line(["date", "readiness", "sleep_score", "strain", "energy", "estimated"])]
        let byDay = Dictionary(grouping: results, by: \.day)
        for d in DayKey.range(from, through: to) {
            let rs = byDay[d] ?? []
            func v(_ k: ScoreKind) -> String { number(rs.first { $0.kind == k }?.value, digits: 1) }
            out.append(line([d.description, v(.readiness), v(.sleep), v(.strain), v(.energy), rs.contains(where: \.isEstimated) ? "yes" : ""]))
        }
        return out.joined(separator: "\r\n") + "\r\n"
    }

    public static func fileName(_ kind: String, from: DayKey, to: DayKey, app: String = AppBrandName.value) -> String {
        "\(app)-\(kind)-\(from)_to_\(to).csv".replacingOccurrences(of: " ", with: "")
    }
}
