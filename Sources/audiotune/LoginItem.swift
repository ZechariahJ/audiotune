import Foundation
import ServiceManagement

/// Thin wrapper over SMAppService for the "Launch at Login" toggle (macOS 13+).
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Toggle login-at-startup. Returns the resulting enabled state.
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
        } catch {
            Log.msg("LoginItem: failed to set enabled=\(enabled): \(error.localizedDescription)")
        }
        return isEnabled
    }
}
