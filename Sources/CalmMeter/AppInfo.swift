import Foundation
import CalmMeterCore

/// App metadata + localized formatting of the dynamic strings Core hands us as
/// data. Static UI labels are localized directly via SwiftUI `Text` (main-bundle
/// `.strings`); this file covers the pieces that need interpolation or mapping.
enum AppInfo {
    /// e.g. "1.0.0 (1)"
    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    /// Public source repository.
    static let repoURL = URL(string: "https://github.com/calmbit-sro/CalmMeter")!
}

enum Localized {
    static func string(_ key: String, _ args: CVarArg...) -> String {
        let format = NSLocalizedString(key, comment: "")
        return args.isEmpty ? format : String(format: format, arguments: args)
    }

    /// "resets in 3h 12m" / "reset za 3 h 12 min"
    static func reset(_ value: ResetCountdown.Value) -> String {
        switch value {
        case .now:
            return string("reset.now")
        case .minutes(let m):
            return string("reset.in_minutes", m)
        case .hoursMinutes(let h, let m):
            return m > 0 ? string("reset.in_hours_minutes", h, m) : string("reset.in_hours", h)
        case .days(let d, let h):
            return h > 0 ? string("reset.in_days_hours", d, h) : string("reset.in_days", d)
        }
    }

    static func updatedAt(_ date: Date) -> String {
        string("updated_at", date.formatted(date: .omitted, time: .shortened))
    }

    static func error(_ kind: UsageErrorKind) -> String {
        switch kind {
        case .offline:      return string("error.offline")
        case .notLoggedIn:  return string("error.not_logged_in")
        case .unauthorized: return string("error.unauthorized")
        case .rateLimited:  return string("error.rate_limited")
        case .server(let c): return string("error.server", c)
        case .unknown:      return string("error.unknown")
        }
    }
}
