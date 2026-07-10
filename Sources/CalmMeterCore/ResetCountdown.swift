import Foundation

/// Language-free breakdown of "time until reset". The UI turns this into a
/// localized string, so Core stays free of display language. Pure/testable.
public enum ResetCountdown {
    public enum Value: Equatable {
        case now
        case minutes(Int)
        case hoursMinutes(Int, Int)
        case days(Int, Int)
    }

    public static func value(until date: Date?, now: Date) -> Value? {
        guard let date else { return nil }
        let seconds = Int(date.timeIntervalSince(now))
        if seconds <= 0 { return .now }

        let minutes = seconds / 60
        let hours = minutes / 60
        let days = hours / 24

        if days >= 1 { return .days(days, hours % 24) }
        if hours >= 1 { return .hoursMinutes(hours, minutes % 60) }
        return .minutes(max(1, minutes))
    }
}
