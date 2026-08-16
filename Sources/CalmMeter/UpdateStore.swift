import SwiftUI
import CalmMeterCore

/// Thin glue: runs the Core `UpdateChecker` shortly after launch and then once
/// a day, honouring the user's toggle. Failures stay silent by design — the
/// menu row simply doesn't appear.
@MainActor
final class UpdateStore: ObservableObject {
    @Published private(set) var available: ReleaseInfo?

    private let checker = UpdateChecker()
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        Task {
            // Let the first usage poll own the launch; updates are background niceness.
            try? await Task.sleep(for: .seconds(5))
            while !Task.isCancelled {
                if UserDefaults.standard.bool(forKey: SettingsKey.checkForUpdates) {
                    available = await checker.check(currentVersion: AppInfo.shortVersion)
                }
                try? await Task.sleep(for: .seconds(86_400))
            }
        }
    }
}
