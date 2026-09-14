import Foundation
import ServiceManagement

/// "Open at Login", through the API macOS actually wants.
///
/// `SMAppService.mainApp` is the Ventura-and-later replacement for a hand-written
/// LaunchAgent plist: macOS owns the registration, shows the app under System
/// Settings › General › Login Items where the user expects to find it, and
/// removes it when the app is deleted. Nothing is written to
/// ~/Library/LaunchAgents.
///
/// It only works for a real app bundle with a bundle identifier, so a
/// `swift run` build reports the toggle as unavailable rather than failing at
/// the user.
enum LoginItem {
    static var isSupported: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    static var isEnabled: Bool {
        guard isSupported else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    /// Returns the state that actually took effect, which is not always the one
    /// asked for: the user can have the item disabled in System Settings, and
    /// registering then reports `.requiresApproval`.
    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        guard isSupported else { return false }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("AI Usage: could not change the login item: \(error.localizedDescription)")
        }
        return isEnabled
    }

    /// Whether macOS is waiting for the user to allow the item in System
    /// Settings — worth saying out loud, since the switch looks ignored.
    static var needsApproval: Bool {
        isSupported && SMAppService.mainApp.status == .requiresApproval
    }
}
