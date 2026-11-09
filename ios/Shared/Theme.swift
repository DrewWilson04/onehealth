import SwiftUI
import PulseCore

/// Design tokens shared by the app, widgets and watch.
/// Section accents and chart colors come from the Okabe–Ito palette, which
/// stays distinguishable for the common forms of color-vision deficiency.
enum Theme {
    // Okabe–Ito
    static let orange = Color(red: 0.902, green: 0.624, blue: 0.000)     // #E69F00
    static let skyBlue = Color(red: 0.337, green: 0.706, blue: 0.914)    // #56B4E9
    static let bluishGreen = Color(red: 0.000, green: 0.620, blue: 0.451) // #009E73
    static let yellow = Color(red: 0.941, green: 0.894, blue: 0.259)     // #F0E442
    static let blue = Color(red: 0.000, green: 0.447, blue: 0.698)       // #0072B2
    static let vermillion = Color(red: 0.835, green: 0.369, blue: 0.000) // #D55E00
    static let reddishPurple = Color(red: 0.800, green: 0.475, blue: 0.655) // #CC79A7

    /// Ordered categorical palette for multi-series charts.
    static let chartPalette: [Color] = [blue, orange, bluishGreen, vermillion, skyBlue, reddishPurple, yellow]

    static func accent(_ section: DashboardSection) -> Color {
        switch section {
        case .activity: return orange
        case .sleep: return blue
        case .heart: return vermillion
        case .body: return bluishGreen
        }
    }

    static func symbol(_ section: DashboardSection) -> String {
        switch section {
        case .activity: return "figure.run"
        case .sleep: return "bed.double.fill"
        case .heart: return "heart.fill"
        case .body: return "fork.knife"
        }
    }

    static func sleepStageColor(_ stage: SleepStage) -> Color {
        switch stage {
        case .awake: return orange
        case .rem: return skyBlue
        case .core: return blue
        case .deep: return Color(red: 0.10, green: 0.18, blue: 0.45)
        case .asleepUnspecified: return blue.opacity(0.7)
        case .inBed: return .gray.opacity(0.4)
        }
    }

    static func scoreColor(_ value: Double) -> Color {
        switch value {
        case ..<34: return vermillion
        case ..<67: return orange
        default: return bluishGreen
        }
    }
}

/// Formatting helpers (locale-aware via FormatStyle).
enum Fmt {
    static func value(_ v: Double?, metric: MetricType, compact: Bool = false) -> String {
        guard let v else { return "—" }
        switch metric.unit {
        case .count:
            return v.formatted(compact ? .number.notation(.compactName).precision(.fractionLength(0...1)) : .number.precision(.fractionLength(0)))
        case .meter:
            return Measurement(value: v, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0...1))))
        case .kilogram:
            return Measurement(value: v, unit: UnitMass.kilograms).formatted(.measurement(width: .abbreviated, usage: .personWeight, numberFormatStyle: .number.precision(.fractionLength(0...1))))
        case .centimeter:
            return Measurement(value: v, unit: UnitLength.centimeters).formatted(.measurement(width: .abbreviated, usage: .personHeight))
        case .celsius:
            return Measurement(value: v, unit: UnitTemperature.celsius).formatted(.measurement(width: .abbreviated, usage: .person, numberFormatStyle: .number.precision(.fractionLength(1))))
        case .milliliter:
            return Measurement(value: v, unit: UnitVolume.milliliters).formatted(.measurement(width: .abbreviated, usage: .liquid, numberFormatStyle: .number.precision(.fractionLength(0))))
        case .kcal:
            return "\(v.formatted(.number.precision(.fractionLength(0)))) kcal"
        case .stageCode:
            return duration(minutes: v)
        case .minute:
            return v >= 120 ? duration(minutes: v) : "\(v.formatted(.number.precision(.fractionLength(0)))) min"
        case .eventCode:
            return metric.dailyStatistic == .durationMinutes ? duration(minutes: v) : v.formatted(.number.precision(.fractionLength(0)))
        case .percent:
            return "\(v.formatted(.number.precision(.fractionLength(0...1))))%"
        default:
            let digits = (metric.unit == .millisecond || metric.unit == .bpm || metric.unit == .mmHg) ? 0 : 1
            return "\(v.formatted(.number.precision(.fractionLength(0...digits)))) \(metric.unit.symbol)".trimmingCharacters(in: .whitespaces)
        }
    }

    static func duration(minutes: Double) -> String {
        let total = Int(minutes.rounded())
        let h = total / 60, m = total % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    static func day(_ d: DayKey, calendar: Calendar = .pulse()) -> String {
        d.start(in: calendar).formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}
