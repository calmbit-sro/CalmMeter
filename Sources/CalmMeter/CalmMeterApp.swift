import SwiftUI
import CalmMeterCore

/// Single shared store so both the SwiftUI scenes and the AppDelegate reference
/// the same polling state.
@MainActor
enum AppEnvironment {
    static let store: UsageStore = {
        SettingsKey.registerDefaults()
        let interval = UserDefaults.standard.double(forKey: SettingsKey.refreshInterval)
        return UsageStore(interval: interval > 0 ? interval : 60)
    }()
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Held for the app's lifetime to opt out of App Nap, which would otherwise
    /// suspend our poll timer while the menu-bar agent looks idle — leaving a
    /// transient error on screen indefinitely. `...AllowingIdleSystemSleep` still
    /// lets the Mac sleep normally to save power.
    private var activity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only agent: no Dock icon (also covered by LSUIElement in the
        // bundle, but set here so `swift run` behaves the same).
        NSApp.setActivationPolicy(.accessory)

        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Polling Claude Code usage"
        )

        // Recover promptly after the Mac wakes (timers don't fire during sleep).
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in await AppEnvironment.store.refreshNow() }
        }

        AppEnvironment.store.start()
    }
}

@main
struct CalmMeterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = AppEnvironment.store
    @AppStorage(SettingsKey.barDisplayMode) private var barModeRaw = BarDisplayMode.dotAndFiveHour.rawValue

    var body: some Scene {
        MenuBarExtra {
            MenuContent().environmentObject(store)
        } label: {
            BarLabel(
                usage: store.usage,
                hasError: store.lastError != nil,
                mode: BarDisplayMode(rawValue: barModeRaw) ?? .dotAndFiveHour,
                rules: UserDefaults.standard.colorRules
            )
        }
        .menuBarExtraStyle(.window)

        Window("Předvolby", id: "preferences") {
            PreferencesView().environmentObject(store)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
