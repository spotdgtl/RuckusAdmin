import Foundation

/// Connection preferences persisted in `UserDefaults`. The password lives in the Keychain.
struct ConnectionSettings: Equatable, Sendable {
    var host = ""
    var username = "admin"
    var pollInterval: Double = 20
    var rememberPassword = true
    var autoConnect = true
    var liveMode = false
    var liveInterval: Double = 3

    private enum Key {
        static let liveMode = "controller.liveMode"
        static let liveInterval = "controller.liveInterval"
        static let host = "controller.host"
        static let username = "controller.username"
        static let pollInterval = "controller.pollInterval"
        static let rememberPassword = "controller.rememberPassword"
        static let autoConnect = "controller.autoConnect"
    }

    static func load(from defaults: UserDefaults = .standard) -> ConnectionSettings {
        var settings = ConnectionSettings()
        if let host = defaults.string(forKey: Key.host), !host.isEmpty { settings.host = host }
        if let username = defaults.string(forKey: Key.username), !username.isEmpty { settings.username = username }
        let interval = defaults.double(forKey: Key.pollInterval)
        if interval >= 5 { settings.pollInterval = interval }
        if defaults.object(forKey: Key.rememberPassword) != nil {
            settings.rememberPassword = defaults.bool(forKey: Key.rememberPassword)
        }
        if defaults.object(forKey: Key.autoConnect) != nil {
            settings.autoConnect = defaults.bool(forKey: Key.autoConnect)
        }
        settings.liveMode = defaults.bool(forKey: Key.liveMode)
        let live = defaults.double(forKey: Key.liveInterval)
        if live >= 1 { settings.liveInterval = live }
        return settings
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(host, forKey: Key.host)
        defaults.set(username, forKey: Key.username)
        defaults.set(pollInterval, forKey: Key.pollInterval)
        defaults.set(rememberPassword, forKey: Key.rememberPassword)
        defaults.set(autoConnect, forKey: Key.autoConnect)
        defaults.set(liveMode, forKey: Key.liveMode)
        defaults.set(liveInterval, forKey: Key.liveInterval)
    }
}
