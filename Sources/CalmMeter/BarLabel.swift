import SwiftUI
import CalmMeterCore

/// The compact view shown in the menu bar. Pure function of usage + settings.
struct BarLabel: View {
    let usage: Usage?
    let hasError: Bool
    let mode: BarDisplayMode
    let rules: ColorRules

    private var fiveHour: Double? { usage?.fiveHour?.utilization }
    private var sevenDay: Double? { usage?.sevenDay?.utilization }
    private var severity: Severity { usage?.overallSeverity ?? .normal }

    private var dotColor: Color {
        if hasError { return .secondary }
        return rules.color(percent: fiveHour ?? 0, severity: severity)
    }

    var body: some View {
        HStack(spacing: 4) {
            if hasError && usage == nil {
                Image(systemName: "exclamationmark.triangle.fill")
            } else {
                switch mode {
                case .dotOnly:
                    dot
                case .fiveHourOnly:
                    Text(pct(fiveHour))
                case .fiveAndSeven:
                    Text("\(pct(fiveHour)) · \(pct(sevenDay))")
                case .dotAndFiveHour:
                    dot
                    Text(pct(fiveHour))
                }
            }
        }
    }

    private var dot: some View {
        Circle().fill(dotColor).frame(width: 8, height: 8)
    }

    private func pct(_ value: Double?) -> String {
        guard let value else { return "–" }
        return "\(Int(value.rounded()))%"
    }
}
