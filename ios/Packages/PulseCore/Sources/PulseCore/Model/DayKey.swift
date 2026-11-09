import Foundation

/// A calendar day in the user's local time zone. Daily aggregates, scores,
/// goals and streaks are keyed by DayKey ("yyyy-MM-dd").
public struct DayKey: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, calendar: Calendar) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    public init?(string: String) {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public func start(in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    public func interval(in calendar: Calendar) -> DateInterval {
        let s = start(in: calendar)
        let e = calendar.date(byAdding: .day, value: 1, to: s)!
        return DateInterval(start: s, end: e)
    }

    public func adding(days: Int, calendar: Calendar) -> DayKey {
        DayKey(calendar.date(byAdding: .day, value: days, to: start(in: calendar).addingTimeInterval(12 * 3600))!, calendar: calendar)
    }

    /// Days between two keys (b - a), timezone-safe.
    public static func daysBetween(_ a: DayKey, _ b: DayKey) -> Int {
        b.julianDay - a.julianDay
    }

    /// Julian day number (proleptic Gregorian) — DST-safe day arithmetic.
    public var julianDay: Int {
        let a = (14 - month) / 12
        let y = year + 4800 - a
        let m = month + 12 * a - 3
        return day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
    }

    public init(julianDay jd: Int) {
        let a = jd + 32044
        let b = (4 * a + 3) / 146097
        let c = a - 146097 * b / 4
        let d = (4 * c + 3) / 1461
        let e = c - 1461 * d / 4
        let m = (5 * e + 2) / 153
        self.init(year: 100 * b + d - 4800 + m / 10, month: m + 3 - 12 * (m / 10), day: e - (153 * m + 2) / 5 + 1)
    }

    public func addingDays(_ n: Int) -> DayKey { DayKey(julianDay: julianDay + n) }

    /// ISO weekday 1 = Monday ... 7 = Sunday.
    public var isoWeekday: Int { ((julianDay % 7) + 7) % 7 + 1 }

    /// Monday of this ISO week.
    public var weekStart: DayKey { addingDays(-(isoWeekday - 1)) }
    public var monthStart: DayKey { DayKey(year: year, month: month, day: 1) }
    public var yearStart: DayKey { DayKey(year: year, month: 1, day: 1) }

    public static func < (a: DayKey, b: DayKey) -> Bool { a.julianDay < b.julianDay }

    public init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let k = DayKey(string: s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad DayKey \(s)"))
        }
        self = k
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }

    public static func range(_ from: DayKey, through to: DayKey) -> [DayKey] {
        guard from <= to else { return [] }
        return (from.julianDay...to.julianDay).map { DayKey(julianDay: $0) }
    }
}

public extension Calendar {
    /// Gregorian calendar fixed to a time zone (default: current).
    static func pulse(_ tz: TimeZone = .current) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = tz
        c.firstWeekday = 2
        return c
    }
}
