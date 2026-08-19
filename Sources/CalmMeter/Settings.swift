import SwiftUI
import CalmMeterCore

/// What the compact menu-bar item renders.
enum BarDisplayMode: String, CaseIterable, Identifiable {
    case dotAndFiveHour   // ● 23%
    case fiveHourOnly     // 23%
    case fiveAndSeven     // 23% · 3%
    case dotOnly          // ●

    var id: String { rawValue }
    var label: String {
        switch self {
        case .dotAndFiveHour: return Localized.string("barmode.dot_5h")
        case .fiveHourOnly:   return Localized.string("barmode.5h")
        case .fiveAndSeven:   return Localized.string("barmode.5h_7d")
        case .dotOnly:        return Localized.string("barmode.dot")
        }
    }
}

/// Persisted user preferences. UserDefaults keys are shared with `@AppStorage`
/// in the views; this enum is the single source of truth for key names + defaults.
enum SettingsKey {
    static let barDisplayMode = "barDisplayMode"
    static let refreshInterval = "refreshInterval"
    static let showPerModel = "showPerModel"
    static let launchAtLogin = "launchAtLogin"
    static let greenMax = "colorGreenMax"
    static let orangeMax = "colorOrangeMax"
    static let checkForUpdates = "checkForUpdates"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            barDisplayMode: BarDisplayMode.dotAndFiveHour.rawValue,
            refreshInterval: 60.0,
            showPerModel: false,
            launchAtLogin: true,
            greenMax: 60.0,
            orangeMax: 85.0,
            checkForUpdates: true,
        ])
    }
}

/// Maps a utilization percentage to a colour using the user's thresholds,
/// with the API-reported severity able to override upward.
struct ColorRules {
    var greenMax: Double
    var orangeMax: Double

    /// Ordered worst-last so the two signals can be combined with `max`.
    /// SE-0266 synthesizes `Comparable` from the declaration order.
    private enum Level: Comparable {
        case green, orange, red

        var color: Color {
            switch self {
            case .green: return .green
            case .orange: return .orange
            case .red: return .red
            }
        }
    }

    /// AIDEV-NOTE: severity may only raise the level, never lower it — checking it
    /// first and returning early let a `warning` repaint a past-red percentage orange.
    func color(percent: Double, severity: Severity = .normal) -> Color {
        let byPercent: Level = percent >= orangeMax ? .red : (percent >= greenMax ? .orange : .green)
        let bySeverity: Level
        switch severity {
        case .critical: bySeverity = .red
        case .warning: bySeverity = .orange
        case .normal, .unknown: bySeverity = .green
        }
        return max(byPercent, bySeverity).color
    }
}

extension UserDefaults {
    var colorRules: ColorRules {
        ColorRules(
            greenMax: double(forKey: SettingsKey.greenMax),
            orangeMax: double(forKey: SettingsKey.orangeMax)
        )
    }
}
