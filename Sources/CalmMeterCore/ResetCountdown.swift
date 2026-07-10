import Foundation

/// Formats "time until reset" for the dropdown, e.g. "za 3 h 12 min" / "za 2 dny".
/// Pure and deterministic given `now`, so it is unit-testable.
public enum ResetCountdown {
    public static func string(until date: Date?, now: Date) -> String? {
        guard let date else { return nil }
        let seconds = Int(date.timeIntervalSince(now))
        if seconds <= 0 { return "teď" }

        let minutes = seconds / 60
        let hours = minutes / 60
        let days = hours / 24

        if days >= 1 {
            let remHours = hours % 24
            return remHours > 0 ? "za \(days) d \(remHours) h" : "za \(days) d"
        }
        if hours >= 1 {
            let remMin = minutes % 60
            return remMin > 0 ? "za \(hours) h \(remMin) min" : "za \(hours) h"
        }
        return "za \(max(1, minutes)) min"
    }
}
