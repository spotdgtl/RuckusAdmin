import Foundation

// MARK: - Shared value types

enum RadioBand: String, Sendable, Hashable, CaseIterable, Comparable {
    case ghz2_4 = "2.4g"
    case ghz5 = "5g"
    case ghz6 = "6g"
    case unknown = "?"

    static func < (lhs: RadioBand, rhs: RadioBand) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    private var sortOrder: Int {
        switch self {
        case .ghz2_4: return 0
        case .ghz5: return 1
        case .ghz6: return 2
        case .unknown: return 3
        }
    }

    var label: String {
        switch self {
        case .ghz2_4: return "2.4 GHz"
        case .ghz5: return "5 GHz"
        case .ghz6: return "6 GHz"
        case .unknown: return "Unknown band"
        }
    }

    var shortLabel: String {
        switch self {
        case .ghz2_4: return "2.4G"
        case .ghz5: return "5G"
        case .ghz6: return "6G"
        case .unknown: return "?"
        }
    }

    /// Derives the band from the controller's `radio-band` or `radio-type` attributes.
    static func from(band: String?, radioType: String?) -> RadioBand {
        if let band, let known = RadioBand(rawValue: band.lowercased()) { return known }
        switch radioType?.lowercased() ?? "" {
        case "11ng", "11g", "11b", "11bg", "11bgn", "11ax-2.4g": return .ghz2_4
        case "11na", "11a", "11ac", "11an", "11ax", "11ax-5g": return .ghz5
        case "11ax-6g", "11be": return .ghz6
        default: return .unknown
        }
    }
}

/// A time series of byte counters as reported in the controller's `history` elements
/// (`"ts,value,ts,value,…"`, newest first).
struct TrafficSample: Sendable, Hashable, Identifiable {
    var id: Date { time }
    var time: Date
    var rxBytes: Int64
    var txBytes: Int64

    var totalBytes: Int64 { rxBytes + txBytes }
}

struct TrafficHistory: Sendable, Hashable {
    var samples: [TrafficSample] = []

    var isEmpty: Bool { samples.isEmpty }

    var totalRx: Int64 { samples.reduce(0) { $0 + $1.rxBytes } }
    var totalTx: Int64 { samples.reduce(0) { $0 + $1.txBytes } }

    /// Parses paired `rx` / `tx` attribute strings into samples sorted by time ascending.
    /// Entries with timestamps far in the past (the controller pads with placeholder
    /// buckets from an earlier boot) are dropped.
    static func parse(rx: String?, tx: String?) -> TrafficHistory {
        let rxPairs = pairs(from: rx)
        let txPairs = pairs(from: tx)
        var byTime: [TimeInterval: (Int64, Int64)] = [:]
        for (t, v) in rxPairs { byTime[t, default: (0, 0)].0 += v }
        for (t, v) in txPairs { byTime[t, default: (0, 0)].1 += v }
        guard let newest = byTime.keys.max() else { return TrafficHistory() }
        let horizon = newest - 7 * 24 * 3600
        let samples = byTime
            .filter { $0.key >= horizon }
            .map { TrafficSample(time: Date(timeIntervalSince1970: $0.key), rxBytes: $0.value.0, txBytes: $0.value.1) }
            .sorted { $0.time < $1.time }
        return TrafficHistory(samples: samples)
    }

    /// Merges several histories (for example per band) by summing values at equal timestamps.
    static func sum(_ histories: [TrafficHistory]) -> TrafficHistory {
        var byTime: [Date: (Int64, Int64)] = [:]
        for history in histories {
            for sample in history.samples {
                byTime[sample.time, default: (0, 0)].0 += sample.rxBytes
                byTime[sample.time, default: (0, 0)].1 += sample.txBytes
            }
        }
        let samples = byTime
            .map { TrafficSample(time: $0.key, rxBytes: $0.value.0, txBytes: $0.value.1) }
            .sorted { $0.time < $1.time }
        return TrafficHistory(samples: samples)
    }

    private static func pairs(from string: String?) -> [(TimeInterval, Int64)] {
        guard let string, !string.isEmpty else { return [] }
        let parts = string.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        var result: [(TimeInterval, Int64)] = []
        var index = 0
        while index + 1 < parts.count {
            if let t = Double(parts[index]), let v = Int64(parts[index + 1]) {
                result.append((t, v))
            }
            index += 2
        }
        return result
    }
}

// MARK: - System

struct SystemInfo: Sendable, Hashable {
    var name: String = ""
    var version: String = ""
    var serial: String = ""
    var model: String = ""
    var unleashedID: String = ""
    var uptime: TimeInterval?
    var managementIP: String = ""
    var managementNetmask: String = ""
    var managementByDHCP: Bool = false
    var wanIP: String = ""
    var gateway: String = ""
    var dns: String = ""
    var internetConnected: Bool?
    var maxAccessPoints: Int?
    var maxClients: Int?
    var countryCode: String = ""
    var meshSSID: String = ""
    var gatewayModeEnabled: Bool = false
    var wanPort: String = ""
    var raw: [String: String] = [:]
}

// MARK: - Access points

struct Radio: Sendable, Hashable, Identifiable {
    var id: String { "\(band.rawValue)-\(radioType)" }
    var radioType: String
    var band: RadioBand
    var channel: String
    var channelization: String
    var txPower: String
    var clientCount: Int?
    var isEnabled: Bool = true
    var history: TrafficHistory = TrafficHistory()
}

enum APConnectionState: String, Sendable, Hashable {
    case connected
    case disconnected
    case approvalPending
    case upgrading
    case provisioning
    case unknown

    var label: String {
        switch self {
        case .connected: return "Connected"
        case .disconnected: return "Disconnected"
        case .approvalPending: return "Approval pending"
        case .upgrading: return "Upgrading"
        case .provisioning: return "Provisioning"
        case .unknown: return "Unknown"
        }
    }

    /// Maps the controller's `state` attribute. `1` is connected; anything else is
    /// treated as offline unless it is one of the known transitional states.
    static func from(state: String?, approved: Bool) -> APConnectionState {
        guard let state else { return .unknown }
        switch state {
        case "1", "connected": return .connected
        case "0", "disconnected": return .disconnected
        case "2": return approved ? .disconnected : .approvalPending
        case "3": return .upgrading
        case "4": return .provisioning
        default:
            return state.lowercased().contains("connect") && !state.lowercased().contains("dis") ? .connected : .disconnected
        }
    }
}

struct NetworkInterface: Sendable, Hashable, Identifiable {
    var id: String { name }
    var name: String
    var macAddress: String
    var speed: String
    var isUp: Bool
    var inOctets: Int64
    var outOctets: Int64
}

struct AccessPoint: Sendable, Hashable, Identifiable {
    var id: String { mac }
    var mac: String
    var name: String = ""
    var description: String = ""
    var location: String = ""
    var model: String = ""
    var ip: String = ""
    var netmask: String = ""
    var gateway: String = ""
    var ipType: String = ""
    var externalIP: String = ""
    var firmware: String = ""
    var backupFirmware: String = ""
    var serial: String = ""
    var state: APConnectionState = .unknown
    var approved: Bool = true
    var role: String = ""
    var meshState: String = ""
    var meshUplinkType: String = ""
    var meshDepth: Int = 0
    var groupID: String = ""
    var uptime: TimeInterval?
    var lastSeen: Date?
    var firstJoined: Date?
    var clientCount: Int = 0
    var rogueCount: Int = 0
    var cpuUtilization: Double?
    var memoryAvailableKB: Int?
    var memoryTotalKB: Int?
    var temperature: String = ""
    var lastRebootReason: String = ""
    var rebootCount: Int?
    var supports11ac: Bool = false
    var supports11ax: Bool = false
    var ledOff: Bool = false
    var poeMode: String = ""
    var lanRxBytes: Int64?
    var lanTxBytes: Int64?
    var wlanRxBytes: Int64?
    var wlanTxBytes: Int64?
    var radios: [Radio] = []
    var interfaces: [NetworkInterface] = []
    var history: TrafficHistory = TrafficHistory()
    var raw: [String: String] = [:]

    var displayName: String { name.isEmpty ? mac : name }
    var isMaster: Bool { role.lowercased() == "master" }
    var isOnline: Bool { state == .connected }

    var memoryUsedFraction: Double? {
        guard let available = memoryAvailableKB, let total = memoryTotalKB, total > 0 else { return nil }
        return Double(total - available) / Double(total)
    }

    func radio(for band: RadioBand) -> Radio? {
        radios.first { $0.band == band }
    }
}

// MARK: - Clients

struct WirelessClient: Sendable, Hashable, Identifiable {
    var id: String { mac }
    var mac: String
    var ip: String = ""
    var ipv6: String = ""
    var hostname: String = ""
    var username: String = ""
    var apMAC: String = ""
    var apName: String = ""
    var ssid: String = ""
    var wlanID: String = ""
    var osDescription: String = ""
    var deviceType: String = ""
    var model: String = ""
    var rssi: Int?
    var signalDBm: Int?
    var noiseFloor: Int?
    var healthLevel: String = ""
    var channel: String = ""
    var radioType: String = ""
    var band: RadioBand = .unknown
    var authMethod: String = ""
    var encryption: String = ""
    var vlan: String = ""
    var firstAssociated: Date?
    var isAuthorized: Bool = true
    var isBlocked: Bool = false
    var isFavourite: Bool = false
    var isIoT: Bool = false
    var rxBytes: Int64?
    var txBytes: Int64?
    var rxPackets: Int64?
    var txPackets: Int64?
    var raw: [String: String] = [:]

    var displayName: String {
        if !hostname.isEmpty { return hostname }
        if !username.isEmpty { return username }
        return mac
    }

    /// Ruckus reports `rssi` as signal above the noise floor (SNR in dB), 0–100.
    var signalQuality: Double {
        guard let rssi else { return 0 }
        return min(1, max(0, Double(rssi) / 50))
    }

    var totalBytes: Int64 {
        (rxBytes ?? 0) + (txBytes ?? 0)
    }
}

// MARK: - WLANs

struct WLAN: Sendable, Hashable, Identifiable {
    var id: String
    var name: String = ""
    var ssid: String = ""
    var description: String = ""
    var usage: String = ""
    var isGuest: Bool = false
    var authentication: String = ""
    var encryption: String = ""
    var cipher: String = ""
    var vlanID: String = ""
    var enableType: String = "0"
    var maxClientsPerRadio: Int?
    var clientIsolation: Bool = false
    var wifi6: Bool = false
    var isHidden: Bool = false
    var createdAt: Date?
    var clientCount: Int = 0
    var state: String = ""
    var history: TrafficHistory = TrafficHistory()
    var raw: [String: String] = [:]

    /// `enable-type`: 0 = always on, 1 = always off, 2 = scheduled.
    var isEnabled: Bool { enableType != "1" }
    var isScheduled: Bool { enableType == "2" }

    var securitySummary: String {
        let auth = authentication.lowercased()
        let enc = encryption.lowercased()
        if enc == "none" || enc.isEmpty { return auth == "open" ? "Open" : auth.uppercased() }
        var parts: [String] = []
        switch enc {
        case "wpa2": parts.append("WPA2")
        case "wpa3": parts.append("WPA3")
        case "wpa23-mixed", "wpa2-wpa3", "wpa23mixed": parts.append("WPA2/WPA3")
        case "wpa-mixed", "wpamixed": parts.append("WPA/WPA2")
        case "wpa": parts.append("WPA")
        case "wep-64", "wep-128": parts.append("WEP")
        default: parts.append(encryption.uppercased())
        }
        if auth == "open" { parts.append("Personal") } else if auth == "eap" { parts.append("Enterprise") } else if !auth.isEmpty { parts.append(authentication.capitalized) }
        return parts.joined(separator: " ")
    }
}

// MARK: - Events and alarms

/// Unleashed reports `severity` as 1 (high), 2 (medium) or 3 (low).
enum EventSeverity: Int, Sendable, Hashable, Comparable, CaseIterable {
    case high = 1
    case medium = 2
    case low = 3
    case unknown = 9

    static func < (lhs: EventSeverity, rhs: EventSeverity) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        case .unknown: return "Unknown"
        }
    }

    static func from(code: String?) -> EventSeverity {
        guard let code, let value = Int(code), let severity = EventSeverity(rawValue: value) else { return .unknown }
        return severity
    }
}

struct ControllerEvent: Sendable, Hashable, Identifiable {
    enum Kind: String, Sendable { case event, alarm }

    var id: String
    var kind: Kind
    var time: Date
    var severity: EventSeverity
    var severityCode: String
    var category: String
    var message: String
    var messageKey: String
    var apMAC: String
    var apName: String
    var clientMAC: String
    var alarmName: String
    var occurrences: Int?
    var raw: [String: String] = [:]
}
