import Foundation
import ServiceManagement

/// Wraps SMAppService for launch-at-login. Only works when running as a proper
/// registered .app bundle; during `swift run` it may throw — we swallow that.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return true
        } catch {
            NSLog("LoginItem: failed to set launch-at-login: \(error)")
            return false
        }
    }
}
