// Settings plumbing for the app (#19): user defaults, a swappable OSC sender and start at login. Not unit-tested: the
// settings model and its effects on the Coordinator are tested in ControllerBridgeKit; this is covered by the manual
// check in the PR.
import ControllerBridgeCore
import Foundation
import ServiceManagement
import Synchronization

/// Settings kept in the standard user defaults.
struct UserDefaultsStorage: SettingsStorage {
    func data(forKey key: String) -> Data? { UserDefaults.standard.data(forKey: key) }
    func set(_ data: Data, forKey key: String) { UserDefaults.standard.set(data, forKey: key) }
}

/// Start at login, through the system login-item service. Off until the DJ turns it on; not kept in user defaults,
/// because the system owns it and the DJ can change it in System Settings too.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}
