import Foundation

/// Severity as reported by the API, mapped to a stable ordering so we can pick
/// the "worst" limit for the menu-bar glyph colour.
public enum Severity: String, Codable, Comparable, Sendable {
    case normal
    case warning
    case critical
    case unknown

    public init(apiValue: String?) {
        switch apiValue?.lowercased() {
        case "normal": self = .normal
        case "warning", "warn", "moderate": self = .warning
        case "critical", "severe", "exceeded", "blocked": self = .critical
        default: self = .unknown
        }
    }

    private var rank: Int {
        switch self {
        case .normal: return 0
        case .unknown: return 1
        case .warning: return 2
        case .critical: return 3
        }
    }

    public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rank < rhs.rank }
}

/// A single rate-limit window (5-hour session or 7-day) as returned by
/// `GET /api/oauth/usage` under the `five_hour` / `seven_day` keys.
public struct UsageWindow: Codable, Equatable, Sendable {
    public let utilization: Double
    public let resetsAtRaw: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAtRaw = "resets_at"
    }

    public var resetsAt: Date? { UsageDate.parse(resetsAtRaw) }

    public init(utilization: Double, resetsAtRaw: String?) {
        self.utilization = utilization
        self.resetsAtRaw = resetsAtRaw
    }
}

/// Model scope for a per-model limit (e.g. weekly Opus).
public struct LimitScope: Codable, Equatable, Sendable {
    public struct Model: Codable, Equatable, Sendable {
        public let displayName: String?
        enum CodingKeys: String, CodingKey { case displayName = "display_name" }
    }
    public let model: Model?
}

/// One entry of the `limits` array — the same primitives Claude Code's `/usage`
/// renders. `is_active` marks the window currently governing the session.
public struct UsageLimit: Codable, Equatable, Sendable {
    public let kind: String
    public let group: String?
    public let percent: Double
    public let severityRaw: String?
    public let resetsAtRaw: String?
    public let scope: LimitScope?
    public let isActive: Bool?

    enum CodingKeys: String, CodingKey {
        case kind, group, percent, scope
        case severityRaw = "severity"
        case resetsAtRaw = "resets_at"
        case isActive = "is_active"
    }

    public var severity: Severity { Severity(apiValue: severityRaw) }
    public var resetsAt: Date? { UsageDate.parse(resetsAtRaw) }
    /// Human label preferring the model display name for scoped limits.
    public var label: String { scope?.model?.displayName ?? kind }
}

/// The `spend` object (usage-credit / overage spend), when enabled.
public struct UsageSpend: Codable, Equatable, Sendable {
    public struct Money: Codable, Equatable, Sendable {
        public let amountMinor: Int
        public let currency: String
        public let exponent: Int
        enum CodingKeys: String, CodingKey {
            case amountMinor = "amount_minor"
            case currency, exponent
        }
        public var amount: Double { Double(amountMinor) / pow(10, Double(exponent)) }
    }
    public let used: Money?
    public let percent: Double?
    public let enabled: Bool?
}

/// Top-level decoded response of `GET /api/oauth/usage`.
public struct Usage: Codable, Equatable, Sendable {
    public let fiveHour: UsageWindow?
    public let sevenDay: UsageWindow?
    public let sevenDayOpus: UsageWindow?
    public let sevenDaySonnet: UsageWindow?
    public let limits: [UsageLimit]?
    public let spend: UsageSpend?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
        case limits, spend
    }

    /// Worst severity across active limits — drives the menu-bar colour.
    public var overallSeverity: Severity {
        (limits ?? []).map(\.severity).max() ?? .normal
    }

    /// Per-model weekly limits worth showing (non-null utilization / present in `limits`).
    public var perModelLimits: [UsageLimit] {
        (limits ?? []).filter { $0.scope?.model?.displayName != nil }
    }
}

/// Tolerant ISO-8601 parsing: the API emits fractional seconds and a
/// `+00:00` offset, but we fall back gracefully for other shapes.
public enum UsageDate {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public static func parse(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return withFraction.date(from: raw) ?? plain.date(from: raw)
    }
}
