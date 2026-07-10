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

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            barDisplayMode: BarDisplayMode.dotAndFiveHour.rawValue,
            refreshInterval: 60.0,
            showPerModel: false,
            launchAtLogin: true,
            greenMax: 60.0,
            orangeMax: 85.0,
        ])
    }
}

/// Maps a utilization percentage to a colour using the user's thresholds,
/// with the API-reported severity able to override upward.
struct ColorRules {
    var greenMax: Double
    var orangeMax: Double

    func color(percent: Double, severity: Severity = .normal) -> Color {
        if severity == .critical { return .red }
        if severity == .warning { return .orange }
        if percent >= orangeMax { return .red }
        if percent >= greenMax { return .orange }
        return .green
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
