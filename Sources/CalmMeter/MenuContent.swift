import SwiftUI
import CalmMeterCore

/// A labelled utilization bar (used for 5h, 7d and per-model rows).
struct UsageBar: View {
    let title: String
    let percent: Double?
    let resetsAt: Date?
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer()
                Text(percent.map { "\(Int($0.rounded()))%" } ?? "–")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    Capsule().fill(color)
                        .frame(width: geo.size.width * CGFloat(min(max((percent ?? 0) / 100, 0), 1)))
                }
            }
            .frame(height: 6)
            if let reset = ResetCountdown.string(until: resetsAt, now: Date()) {
                Text("reset \(reset)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The popover content of the menu-bar item.
struct MenuContent: View {
    @EnvironmentObject var store: UsageStore
    @Environment(\.openWindow) private var openWindow
    @AppStorage(SettingsKey.showPerModel) private var showPerModel = false

    private var rules: ColorRules { UserDefaults.standard.colorRules }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let usage = store.usage {
                windows(usage)
                if showPerModel, !usage.perModelLimits.isEmpty {
                    Divider()
                    perModel(usage)
                }
                if let spend = usage.spend, spend.enabled == true, let used = spend.used {
                    Divider()
                    HStack {
                        Text("Spend").font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text(String(format: "%.2f %@", used.amount, used.currency))
                            .font(.system(size: 12).monospacedDigit())
                    }
                }
            } else if store.isLoading {
                Text("Načítám…").foregroundStyle(.secondary).font(.system(size: 12))
            }

            if let err = store.lastError {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(store.usage == nil ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 280)
    }

    private var header: some View {
        HStack {
            Text("Claude Usage").font(.system(size: 13, weight: .semibold))
            Spacer()
            Button { Task { await store.refreshNow() } } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Obnovit teď")
            .disabled(store.isLoading)
        }
    }

    private func windows(_ usage: Usage) -> some View {
        VStack(spacing: 12) {
            UsageBar(
                title: "5h okno",
                percent: usage.fiveHour?.utilization,
                resetsAt: usage.fiveHour?.resetsAt,
                color: rules.color(percent: usage.fiveHour?.utilization ?? 0, severity: usage.overallSeverity)
            )
            UsageBar(
                title: "Týden",
                percent: usage.sevenDay?.utilization,
                resetsAt: usage.sevenDay?.resetsAt,
                color: rules.color(percent: usage.sevenDay?.utilization ?? 0)
            )
        }
    }

    private func perModel(_ usage: Usage) -> some View {
        VStack(spacing: 10) {
            ForEach(Array(usage.perModelLimits.enumerated()), id: \.offset) { _, limit in
                UsageBar(
                    title: limit.label,
                    percent: limit.percent,
                    resetsAt: limit.resetsAt,
                    color: rules.color(percent: limit.percent, severity: limit.severity)
                )
            }
        }
    }

    private var footer: some View {
        HStack {
            if let updated = store.lastUpdated {
                Text("Aktualizováno \(updated.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Předvolby…") {
                openWindow(id: "preferences")
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(.borderless)
            Button("Ukončit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
        }
        .font(.system(size: 11))
    }
}
