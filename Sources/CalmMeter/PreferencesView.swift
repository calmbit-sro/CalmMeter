import SwiftUI
import CalmMeterCore

struct PreferencesView: View {
    @EnvironmentObject var store: UsageStore
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var updates: UpdateStore
    @Environment(\.openWindow) private var openWindow

    @AppStorage(SettingsKey.barDisplayMode) private var barModeRaw = BarDisplayMode.dotAndFiveHour.rawValue
    @AppStorage(SettingsKey.refreshInterval) private var refreshInterval = 60.0
    @AppStorage(SettingsKey.showPerModel) private var showPerModel = false
    @AppStorage(SettingsKey.launchAtLogin) private var launchAtLogin = true
    @AppStorage(SettingsKey.greenMax) private var greenMax = 60.0
    @AppStorage(SettingsKey.orangeMax) private var orangeMax = 85.0
    @AppStorage(SettingsKey.checkForUpdates) private var checkForUpdates = true

    private let intervals: [(String, Double)] = [("30 s", 30), ("60 s", 60), ("5 min", 300)]

    var body: some View {
        Form {
            Section("Menu bar") {
                Picker("Format", selection: $barModeRaw) {
                    ForEach(BarDisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                Toggle("Per-model breakdown in menu", isOn: $showPerModel)
            }

            Section("Refresh") {
                Picker("Interval", selection: $refreshInterval) {
                    ForEach(intervals, id: \.1) { Text($0.0).tag($0.1) }
                }
                .onChange(of: refreshInterval) { store.setInterval($0) }
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { LoginItem.setEnabled($0) }
            }

            Section("Colour thresholds") {
                Stepper(value: $greenMax, in: 10...orangeMax, step: 5) {
                    LabeledContent("Green below", value: "\(Int(greenMax)) %")
                }
                Stepper(value: $orangeMax, in: greenMax...100, step: 5) {
                    LabeledContent("Orange below", value: "\(Int(orangeMax)) %")
                }
                Text(Localized.string("threshold.above_red", Int(orangeMax)))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $checkForUpdates)
                HStack {
                    Button("update.check_now") {
                        Task { await updates.checkNow() }
                    }
                    .disabled(updates.manualStatus == .checking)
                    Spacer()
                    manualCheckStatus
                }
            }

            Section("Account") {
                if let email = auth.accountEmail {
                    LabeledContent("account.signed_in_as", value: email.isEmpty ? "—" : email)
                    Button("account.sign_out") {
                        Task {
                            await auth.signOut()
                            await store.refreshNow()
                        }
                    }
                } else {
                    Text("account.fallback_hint")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("account.sign_in") {
                        openWindow(id: "signin")
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
            }

            Section("About") {
                LabeledContent("Version", value: AppInfo.versionString)
                Link("GitHub", destination: AppInfo.repoURL)
                Button("welcome.show_again") {
                    openWindow(id: "welcome")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            // Reconcile the toggle with the actual system state on open.
            launchAtLogin = LoginItem.isEnabled
        }
    }

    /// Inline outcome of the manual check. A found update wins over the last
    /// manual status — the row doubles as the download link.
    @ViewBuilder private var manualCheckStatus: some View {
        if let release = updates.available {
            Button {
                NSWorkspace.shared.open(release.url)
            } label: {
                Label(
                    Localized.string("update.available", release.version.description),
                    systemImage: "arrow.down.circle"
                )
            }
            .buttonStyle(.link)
            .font(.caption)
        } else {
            switch updates.manualStatus {
            case .checking:
                ProgressView().controlSize(.small)
            case .upToDate:
                Label(Localized.string("update.up_to_date", AppInfo.shortVersion), systemImage: "checkmark.circle")
                    .font(.caption).foregroundStyle(.secondary)
            case .failed:
                Label("update.check_failed", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary)
            case nil:
                EmptyView()
            }
        }
    }
}
