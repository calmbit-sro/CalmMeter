import SwiftUI
import CalmMeterCore

/// The compact view shown in the menu bar.
///
/// macOS renders a MenuBarExtra label as a *template* image — it recolours
/// everything to match the bar, so `.foregroundColor` on Text/Shapes is ignored
/// (percentages come out plain white/black). To keep our severity colours we
/// rasterize the content into a **non-template** NSImage and show that; a
/// non-template image with `.renderingMode(.original)` displays its real colours.
struct BarLabel: View {
    let usage: Usage?
    let hasError: Bool
    let mode: BarDisplayMode
    let rules: ColorRules

    var body: some View {
        Image(nsImage: rendered)
            .renderingMode(.original)
    }

    @MainActor private var rendered: NSImage {
        let renderer = ImageRenderer(content: LabelContent(usage: usage, hasError: hasError, mode: mode, rules: rules))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return NSImage(size: .zero) }
        image.isTemplate = false   // keep our colours instead of being tinted
        return image
    }
}

/// The actual visual (dot + coloured percentages). Rendered off-screen to an
/// image by `BarLabel`, so ordinary SwiftUI colours work here.
private struct LabelContent: View {
    let usage: Usage?
    let hasError: Bool
    let mode: BarDisplayMode
    let rules: ColorRules

    private var fiveHour: Double? { usage?.fiveHour?.utilization }
    private var sevenDay: Double? { usage?.sevenDay?.utilization }
    private var severity: Severity { usage?.overallSeverity ?? .normal }

    private var fiveHourColor: Color {
        hasError ? .secondary : rules.color(percent: fiveHour ?? 0, severity: severity)
    }
    private var weeklyColor: Color {
        hasError ? .secondary : rules.color(percent: sevenDay ?? 0)
    }

    var body: some View {
        HStack(spacing: 4) {
            if hasError && usage == nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                switch mode {
                case .dotOnly:
                    dot
                case .fiveHourOnly:
                    Text(pct(fiveHour)).foregroundColor(fiveHourColor)
                case .fiveAndSeven:
                    Text(pct(fiveHour)).foregroundColor(fiveHourColor)
                        + Text(" · ").foregroundColor(.secondary)
                        + Text(pct(sevenDay)).foregroundColor(weeklyColor)
                case .dotAndFiveHour:
                    dot
                    Text(pct(fiveHour)).foregroundColor(fiveHourColor)
                }
            }
        }
        .font(.system(size: 13, weight: .medium).monospacedDigit())
        .padding(.vertical, 1)
    }

    private var dot: some View {
        Circle().fill(fiveHourColor).frame(width: 7, height: 7)
    }

    private func pct(_ value: Double?) -> String {
        guard let value else { return "–" }
        return "\(Int(value.rounded()))%"
    }
}
