import SwiftUI
import CalmMeterCore

/// Thin glue: runs the Core `UpdateChecker` shortly after launch and then once
/// a day, honouring the user's toggle. Failures stay silent by design — the
/// menu row simply doesn't appear.
@MainActor
final class UpdateStore: ObservableObject {
    @Published private(set) var available: ReleaseInfo?
    /// Outcome of the last manual "Check now"; nil = never asked / result
    /// superseded. `available` stays the single source for "there IS an update".
    @Published private(set) var manualStatus: ManualStatus?

    enum ManualStatus: Equatable {
        case checking
        case upToDate
        case failed
    }

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

    /// User-initiated check: runs regardless of the automatic-check toggle and
    /// reports all three outcomes. Clearing `available` on `.upToDate` covers
    /// "updated since the menu row appeared".
    func checkNow() async {
        guard manualStatus != .checking else { return }
        manualStatus = .checking
        switch await checker.checkDetailed(currentVersion: AppInfo.shortVersion) {
        case .updateAvailable(let release):
            available = release
            manualStatus = nil
        case .upToDate:
            available = nil
            manualStatus = .upToDate
        case .failed:
            manualStatus = .failed
        }
    }
}
