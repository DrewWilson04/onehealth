import Foundation

/// Canonical units. Every `Sample` is stored in exactly one canonical unit per
/// metric so that iOS and web aggregate identically. See /docs/metrics.md.
public enum MetricUnit: String, Codable, Sendable, CaseIterable {
    case count
    case kcal
    case meter = "m"
    case centimeter = "cm"
    case minute = "min"
    case second = "s"
    case bpm = "count/min"
    case millisecond = "ms"
    case percent = "%"
    case mmHg
    case vo2 = "mL/(kg·min)"
    case kilogram = "kg"
    case gram = "g"
    case milligram = "mg"
    case milliliter = "mL"
    case celsius = "degC"
    case decibel = "dBASPL"
    case metersPerSecond = "m/s"
    case watt = "W"
    case met = "kcal/(kg·hr)"
    case mgPerDL = "mg/dL"
    case stageCode = "stage"   // categorical sleep stage code (see SleepStage)
    case eventCode = "event"   // categorical event (stand hour, HR event, ...)

    /// Short label for UI.
    public var symbol: String {
        switch self {
        case .count: return ""
        case .kcal: return "kcal"
        case .meter: return "m"
        case .centimeter: return "cm"
        case .minute: return "min"
        case .second: return "s"
        case .bpm: return "bpm"
        case .millisecond: return "ms"
        case .percent: return "%"
        case .mmHg: return "mmHg"
        case .vo2: return "mL/kg/min"
        case .kilogram: return "kg"
        case .gram: return "g"
        case .milligram: return "mg"
        case .milliliter: return "mL"
        case .celsius: return "°C"
        case .decibel: return "dB"
        case .metersPerSecond: return "m/s"
        case .watt: return "W"
        case .met: return "MET"
        case .mgPerDL: return "mg/dL"
        case .stageCode, .eventCode: return ""
        }
    }
}

/// Converts a raw value expressed in an arbitrary HealthKit / export.xml unit
/// string into the metric's canonical unit. Returns nil if the unit is unknown
/// or incompatible.
public enum UnitConverter {
    public static func convert(_ value: Double, from unitString: String, to target: MetricUnit) -> Double? {
        let u = unitString.trimmingCharacters(in: .whitespaces)
        switch target {
        case .count:
            return (u == "count" || u.isEmpty) ? value : nil
        case .stageCode, .eventCode:
            return value
        case .kcal:
            switch u {
            case "kcal", "Cal", "Kcal": return value
            case "cal": return value / 1000
            case "kJ": return value / 4.184
            case "J": return value / 4184
            default: return nil
            }
        case .meter:
            switch u {
            case "m": return value
            case "km": return value * 1000
            case "cm": return value / 100
            case "mm": return value / 1000
            case "mi": return value * 1609.344
            case "yd": return value * 0.9144
            case "ft": return value * 0.3048
            case "in": return value * 0.0254
            default: return nil
            }
        case .centimeter:
            switch u {
            case "cm": return value
            case "m": return value * 100
            case "mm": return value / 10
            case "in": return value * 2.54
            case "ft": return value * 30.48
            default: return nil
            }
        case .minute:
            switch u {
            case "min": return value
            case "s": return value / 60
            case "hr", "h": return value * 60
            case "ms": return value / 60_000
            default: return nil
            }
        case .second:
            switch u {
            case "s": return value
            case "min": return value * 60
            case "ms": return value / 1000
            default: return nil
            }
        case .bpm:
            switch u {
            case "count/min", "bpm", "/min": return value
            case "count/s": return value * 60
            default: return nil
            }
        case .millisecond:
            switch u {
            case "ms": return value
            case "s": return value * 1000
            default: return nil
            }
        case .percent:
            // HealthKit (and export.xml) store percentages as fractions 0...1
            // under the unit "%". Canonical storage is 0...100.
            switch u {
            case "%": return value * 100
            default: return nil
            }
        case .mmHg:
            switch u {
            case "mmHg": return value
            case "kPa": return value * 7.50062
            default: return nil
            }
        case .vo2:
            switch u {
            case "mL/min·kg", "ml/(kg*min)", "mL/(kg·min)", "ml/kg*min", "mL/kg/min", "ml/min·kg": return value
            default: return nil
            }
        case .kilogram:
            switch u {
            case "kg": return value
            case "g": return value / 1000
            case "lb": return value * 0.45359237
            case "st": return value * 6.35029318
            case "oz": return value * 0.028349523125
            default: return nil
            }
        case .gram:
            switch u {
            case "g": return value
            case "kg": return value * 1000
            case "mg": return value / 1000
            case "mcg", "µg": return value / 1_000_000
            case "oz": return value * 28.349523125
            default: return nil
            }
        case .milligram:
            switch u {
            case "mg": return value
            case "g": return value * 1000
            case "mcg", "µg": return value / 1000
            default: return nil
            }
        case .milliliter:
            switch u {
            case "mL", "ml": return value
            case "L", "l": return value * 1000
            case "fl_oz_us", "fl_oz_US": return value * 29.5735295625
            case "fl_oz_imp": return value * 28.4130625
            case "cup_us", "cup_US": return value * 236.5882365
            default: return nil
            }
        case .celsius:
            switch u {
            case "degC": return value
            case "degF": return (value - 32) * 5 / 9
            case "K": return value - 273.15
            default: return nil
            }
        case .decibel:
            return u == "dBASPL" ? value : nil
        case .metersPerSecond:
            switch u {
            case "m/s": return value
            case "km/hr", "km/h": return value / 3.6
            case "mi/hr", "mph": return value * 0.44704
            default: return nil
            }
        case .watt:
            return u == "W" ? value : nil
        case .met:
            switch u {
            case "kcal/hr·kg", "kcal/(kg·hr)", "kcal/(kg*hr)", "kcal/hr*kg": return value
            default: return nil
            }
        case .mgPerDL:
            switch u {
            case "mg/dL": return value
            case "mmol<180.15588000005408>/L", "mmol/L": return value * 18.0156
            default: return nil
            }
        }
    }
}
