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

    // NOTE: MenuBarExtra only reliably renders Text and Image (SF Symbols) in
    // its label — a raw SwiftUI Shape like Circle() silently doesn't draw. Use
    // the "circle.fill" symbol so the status dot actually appears (and keeps its
    // severity colour via foregroundStyle).
    private var dot: some View {
        Image(systemName: "circle.fill")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 7, height: 7)
            .foregroundStyle(dotColor)
    }

    private func pct(_ value: Double?) -> String {
        guard let value else { return "–" }
        return "\(Int(value.rounded()))%"
    }
}
