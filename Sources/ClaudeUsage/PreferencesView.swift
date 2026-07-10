import SwiftUI
import ClaudeUsageCore

struct PreferencesView: View {
    @EnvironmentObject var store: UsageStore

    @AppStorage(SettingsKey.barDisplayMode) private var barModeRaw = BarDisplayMode.dotAndFiveHour.rawValue
    @AppStorage(SettingsKey.refreshInterval) private var refreshInterval = 60.0
    @AppStorage(SettingsKey.showPerModel) private var showPerModel = false
    @AppStorage(SettingsKey.launchAtLogin) private var launchAtLogin = true
    @AppStorage(SettingsKey.greenMax) private var greenMax = 60.0
    @AppStorage(SettingsKey.orangeMax) private var orangeMax = 85.0

    private let intervals: [(String, Double)] = [("30 s", 30), ("60 s", 60), ("5 min", 300)]

    var body: some View {
        Form {
            Section("Zobrazení v liště") {
                Picker("Formát", selection: $barModeRaw) {
                    ForEach(BarDisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                Toggle("Rozpad po modelech v menu", isOn: $showPerModel)
            }

            Section("Obnovování") {
                Picker("Interval", selection: $refreshInterval) {
                    ForEach(intervals, id: \.1) { Text($0.0).tag($0.1) }
                }
                .onChange(of: refreshInterval) { store.setInterval($0) }
            }

            Section("Spuštění") {
                Toggle("Spouštět při přihlášení", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { LoginItem.setEnabled($0) }
            }

            Section("Barevné prahy (% využití)") {
                Stepper(value: $greenMax, in: 10...orangeMax, step: 5) {
                    LabeledContent("Zelená pod", value: "\(Int(greenMax)) %")
                }
                Stepper(value: $orangeMax, in: greenMax...100, step: 5) {
                    LabeledContent("Oranžová pod", value: "\(Int(orangeMax)) %")
                }
                Text("Nad \(Int(orangeMax)) % je červená.")
                    .font(.caption).foregroundStyle(.secondary)
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
}
