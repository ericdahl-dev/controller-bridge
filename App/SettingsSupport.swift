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

/// The Coordinator keeps one OSC sender for its life; this one lets Settings point it at another host or port.
final class SwappableOSCSender: OSCSender {
    private let current: Mutex<UDPOSCSender>

    init(host: String, port: Int) throws(UDPError) {
        current = Mutex(try UDPOSCSender(host: host, port: port))
    }

    /// Opens the new destination first, so a bad host leaves the old one working.
    func change(host: String, port: Int) throws(UDPError) {
        let sender = try UDPOSCSender(host: host, port: port)
        current.withLock { $0 = sender }
    }

    func send(_ message: OSCMessage) {
        current.withLock { $0 }.send(message)
    }
}

/// Start at login, through the system login-item service. Off until the DJ turns it on; not kept in user defaults,
/// because the system owns it and the DJ can change it in System Settings too.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}
