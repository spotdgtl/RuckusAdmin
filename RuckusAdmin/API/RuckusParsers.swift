import Foundation

/// Maps the controller's XML into the app's models. Attribute names below were taken
/// from live responses of Unleashed 200.15; lookups fall back to older spellings where
/// known so the parsers degrade gracefully on other firmware.
enum RuckusParsers {
    // MARK: Primitive helpers

    static func int(_ value: String?) -> Int? {
        guard let value else { return nil }
        return Int(value.trimmingCharacters(in: .whitespaces))
    }

    static func int64(_ value: String?) -> Int64? {
        guard let value else { return nil }
        return Int64(value.trimmingCharacters(in: .whitespaces))
    }

    static func double(_ value: String?) -> Double? {
        guard let value else { return nil }
        return Double(value.trimmingCharacters(in: .whitespaces))
    }

    static func bool(_ value: String?) -> Bool {
        guard let value else { return false }
        return ["true", "1", "enabled", "yes", "on"].contains(value.lowercased())
    }

    static func date(_ value: String?) -> Date? {
        guard let seconds = double(value), seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    static func mac(_ value: String?) -> String {
        (value ?? "").lowercased().trimmingCharacters(in: .whitespaces)
    }

    /// Drops attributes that carry secrets (the controller happily returns WPA passphrases).
    static func cleanedAttributes(_ attributes: [String: String]) -> [String: String] {
        attributes.filter { key, _ in
            let lower = key.lowercased()
            return !(lower.contains("passphrase") || lower.contains("password") || lower.contains("psk") || lower.hasPrefix("x-"))
        }
    }

    // MARK: History

    static func history(from node: XMLNode?) -> (all: TrafficHistory, byBand: [RadioBand: TrafficHistory]) {
        guard let node else { return (TrafficHistory(), [:]) }
        var byBand: [RadioBand: TrafficHistory] = [:]
        var overall: TrafficHistory?
        for (key, value) in node.attributes where key.hasPrefix("rx-bytes") {
            let suffix = String(key.dropFirst("rx-bytes".count))
            let tx = node.attributes["tx-bytes" + suffix]
            let parsed = TrafficHistory.parse(rx: value, tx: tx)
            if suffix.isEmpty {
                overall = parsed
            } else {
                let bandKey = suffix.hasPrefix("-") ? String(suffix.dropFirst()) : suffix
                let band = RadioBand(rawValue: bandKey.lowercased()) ?? .unknown
                byBand[band] = parsed
            }
        }
        let all = overall ?? TrafficHistory.sum(Array(byBand.values))
        return (all, byBand)
    }

    // MARK: System

    static func systemInfo(stat: XMLNode?, connect: XMLNode?, summary: XMLNode?) -> SystemInfo {
        var info = SystemInfo()
        if let stat {
            let sysinfo = stat.firstDescendant(named: "sysinfo")
            let identity = stat.firstDescendant(named: "identity")
            let mgmt = stat.firstDescendant(named: "mgmt-ip")
            let network = stat.firstDescendant(named: "unleashed-network")
            info.name = identity?["name"] ?? ""
            info.version = sysinfo?.attr("version", "version-num") ?? ""
            info.serial = sysinfo?["serial"] ?? ""
            info.model = (sysinfo?.attr("display-model", "model") ?? "").uppercased()
            info.uptime = double(sysinfo?["uptime"])
            info.maxAccessPoints = int(sysinfo?.attr("max_connect_ap", "maxap"))
            info.managementIP = mgmt?["ip"] ?? ""
            info.managementNetmask = mgmt?["netmask"] ?? ""
            info.managementByDHCP = bool(mgmt?["by-dhcp"])
            info.gateway = mgmt?["gateway"] ?? ""
            info.dns = [mgmt?["dns1"], mgmt?["dns2"]].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
            info.unleashedID = network?["unleashed-network-token"] ?? ""
            info.countryCode = stat.firstDescendant(named: "adv-radio")?["country"] ?? ""
            if let gateway = stat.firstDescendant(named: "internal-gateway") {
                info.gatewayModeEnabled = bool(gateway["enabled"])
                info.wanPort = gateway["wan-port"] ?? ""
            }
            var raw: [String: String] = [:]
            for child in stat.children + (stat.first("response")?.children ?? []) {
                for (key, value) in child.attributes {
                    raw["\(child.name).\(key)"] = value
                }
            }
            info.raw = cleanedAttributes(raw)
        }
        if let connect {
            let xmsg = connect.firstDescendant(named: "xmsg") ?? connect
            info.internetConnected = xmsg["connected"].map { $0 == "1" }
            info.wanIP = xmsg["ip"] ?? ""
            if info.gateway.isEmpty { info.gateway = xmsg["gateway"] ?? "" }
            if info.dns.isEmpty { info.dns = xmsg["dns1"] ?? "" }
        }
        if let summary {
            info.maxAccessPoints = int(summary["max-aps"]) ?? info.maxAccessPoints
            info.maxClients = int(summary["max-clients"])
        }
        return info
    }

    static func totals(from node: XMLNode?) -> ControllerTotals {
        var totals = ControllerTotals()
        guard let node else { return totals }
        totals.accessPointCount = int(node["num-ap"]) ?? 0
        totals.clientCount = int(node.attr("num-sta", "assoc-stas")) ?? 0
        totals.rogueCount = int(node["num-rogue"]) ?? 0
        totals.rxBytesTotal = int64(node["total-rx-bytes"]) ?? 0
        totals.txBytesTotal = int64(node["total-tx-bytes"]) ?? 0
        totals.rxBytesToday = int64(node["rx-bytes-d"]) ?? 0
        totals.txBytesToday = int64(node["tx-bytes-d"]) ?? 0
        totals.rxBytesLastHour = int64(node["rx-bytes-h"]) ?? 0
        totals.txBytesLastHour = int64(node["tx-bytes-h"]) ?? 0
        totals.averageRSSI = int(node["avg-rssi"])
        totals.apRebootsToday = int(node["ap-reboot-day"]) ?? 0
        totals.heartbeatLossesToday = int(node["hb-loss-day"]) ?? 0
        totals.ethernetPorts = node.all("eth").map { eth in
            EthernetPort(
                id: eth["portid"] ?? eth["ethname"] ?? UUID().uuidString,
                name: eth["name"] ?? eth["ethname"] ?? "Port",
                interfaceName: eth["ethname"] ?? "",
                speed: eth["ethspeed"] ?? "",
                isUp: (eth["state"] ?? "").lowercased() == "up",
                inBytes: int64(eth["inbytes"]) ?? 0,
                outBytes: int64(eth["outbytes"]) ?? 0,
                mac: mac(eth["mac"])
            )
        }
        return totals
    }

    static func summary(from node: XMLNode?) -> APSummary {
        var summary = APSummary()
        guard let node else { return summary }
        summary.connected = int(node.attr("connected-num", "connnected-num")) ?? 0
        summary.disconnected = int(node.attr("disconnected-num", "disconnnected-num")) ?? 0
        summary.maxAccessPoints = int(node["max-aps"])
        summary.maxClients = int(node["max-clients"])
        let parsed = history(from: node.first("history"))
        summary.history = parsed.all
        summary.historyByBand = parsed.byBand
        return summary
    }

    // MARK: Access points

    static func accessPoints(config: [XMLNode], stats: [XMLNode], details: [XMLNode]) -> [AccessPoint] {
        var byMAC: [String: AccessPoint] = [:]
        var order: [String] = []

        func existing(_ key: String) -> AccessPoint {
            if let ap = byMAC[key] { return ap }
            order.append(key)
            return AccessPoint(mac: key)
        }

        for node in config {
            let key = mac(node["mac"])
            guard !key.isEmpty else { continue }
            var ap = existing(key)
            ap.name = node["devname"] ?? node["name"] ?? ap.name
            ap.description = node["description"] ?? ap.description
            ap.location = node["location"] ?? ap.location
            if let model = node["model"], !model.isEmpty { ap.model = model.uppercased() }
            if let ip = node["ip"], !ip.isEmpty { ap.ip = ip }
            if let netmask = node["netmask"], !netmask.isEmpty { ap.netmask = netmask }
            if let gateway = node["gateway"], !gateway.isEmpty { ap.gateway = gateway }
            if let serial = node["serial"], !serial.isEmpty { ap.serial = serial }
            if let version = node["version"], !version.isEmpty {
                let build = node["build-version"].map { ".\($0)" } ?? ""
                ap.firmware = version + build
            }
            ap.approved = node["approved"].map(bool) ?? true
            ap.groupID = node["group-id"] ?? ap.groupID
            ap.supports11ac = bool(node["support-11ac"])
            ap.supports11ax = bool(node["support-11ax"])
            ap.raw.merge(cleanedAttributes(node.attributes)) { _, new in new }
            byMAC[key] = ap
        }

        for node in stats {
            let key = mac(node["mac"])
            guard !key.isEmpty else { continue }
            var ap = existing(key)
            applyCommonStats(node, to: &ap)
            let radios = node.all("radio")
            if !radios.isEmpty {
                ap.radios = radios.map { radio in
                    let band = RadioBand.from(band: radio["radio-band"], radioType: radio["radio-type"])
                    return Radio(
                        radioType: radio["radio-type"] ?? "",
                        band: band,
                        channel: radio["channel"] ?? "",
                        channelization: radio["channelization"] ?? "",
                        txPower: txPower(for: band, in: node),
                        clientCount: nil,
                        isEnabled: radio["enabled"].map(bool) ?? true
                    )
                }.sorted { $0.band < $1.band }
            }
            let parsed = history(from: node.first("history"))
            if !parsed.all.isEmpty { ap.history = parsed.all }
            for index in ap.radios.indices {
                if let bandHistory = parsed.byBand[ap.radios[index].band] {
                    ap.radios[index].history = bandHistory
                }
            }
            byMAC[key] = ap
        }

        for node in details {
            let key = mac(node["mac"])
            guard !key.isEmpty else { continue }
            var ap = existing(key)
            applyCommonStats(node, to: &ap)
            ap.uptime = double(node["uptime"]) ?? ap.uptime
            ap.memoryAvailableKB = int(node["mem_avail"]) ?? ap.memoryAvailableKB
            ap.memoryTotalKB = int(node["mem_total"]) ?? ap.memoryTotalKB
            ap.cpuUtilization = double(node["cpu_util"]) ?? ap.cpuUtilization
            ap.lanRxBytes = int64(node["lan_stats_rx_byte"]) ?? ap.lanRxBytes
            ap.lanTxBytes = int64(node["lan_stats_tx_byte"]) ?? ap.lanTxBytes
            ap.wlanTxBytes = int64(node["sta_tx_byte"]) ?? ap.wlanTxBytes
            ap.wlanRxBytes = int64(node["sta_rx_byte"]) ?? ap.wlanRxBytes
            ap.clientCount = int(node.attr("num-sta", "assoc-stas")) ?? ap.clientCount
            ap.rogueCount = int(node["num-rogue"]) ?? ap.rogueCount
            ap.firstJoined = date(node.attr("firstAssoc", "first-assoc")) ?? ap.firstJoined
            ap.lastRebootReason = node["last-reboot-reason"] ?? ap.lastRebootReason
            ap.rebootCount = int(node["total-boot-counter"]) ?? ap.rebootCount
            ap.ledOff = bool(node["led-off"])
            ap.poeMode = node["poe-mode-str"] ?? ap.poeMode
            if let temperature = node["current-temperature"], temperature.lowercased() != "unavailable" {
                ap.temperature = temperature
            }
            ap.ipType = node["ip-type"] ?? ap.ipType
            ap.externalIP = node["external-ip"] ?? ap.externalIP
            if let netmask = node["netmask"], !netmask.isEmpty { ap.netmask = netmask }
            if let gateway = node["gateway"], !gateway.isEmpty { ap.gateway = gateway }
            ap.interfaces = node.all("if").map { iface in
                NetworkInterface(
                    name: iface["if-name"] ?? iface["if-descr"] ?? "if",
                    macAddress: mac(iface["if-physAddress"]),
                    speed: iface["if-speed"] ?? "",
                    isUp: iface["if-operStatus"] == "1",
                    inOctets: int64(iface["if-inOctets"]) ?? 0,
                    outOctets: int64(iface["if-outOctets"]) ?? 0
                )
            }
            if ap.radios.isEmpty {
                ap.radios = synthesizedRadios(from: node)
            }
            byMAC[key] = ap
        }

        return order.compactMap { byMAC[$0] }
    }

    private static func applyCommonStats(_ node: XMLNode, to ap: inout AccessPoint) {
        if let name = node.attr("devname", "ap-name"), !name.isEmpty { ap.name = name }
        if let model = node.attr("display-model", "oem-model", "model"), !model.isEmpty { ap.model = model.uppercased() }
        if let ip = node["ip"], !ip.isEmpty { ap.ip = ip }
        if let firmware = node["firmware-version"], !firmware.isEmpty { ap.firmware = firmware }
        if let serial = node.attr("serial-number", "serial"), !serial.isEmpty { ap.serial = serial }
        if let approved = node["approved"] { ap.approved = bool(approved) }
        ap.state = APConnectionState.from(state: node["state"], approved: ap.approved)
        ap.role = node["role"] ?? ap.role
        ap.meshState = node["mesh-state"] ?? ap.meshState
        ap.meshUplinkType = node["mesh-uplink-type"] ?? ap.meshUplinkType
        ap.meshDepth = int(node["mesh-depth"]) ?? ap.meshDepth
        ap.groupID = node["group-id"] ?? ap.groupID
        ap.lastSeen = date(node["last-seen"]) ?? ap.lastSeen
        ap.clientCount = int(node.attr("assoc-stas", "num-sta")) ?? ap.clientCount
        ap.description = node["description"].flatMap { $0.isEmpty ? nil : $0 } ?? ap.description
        ap.location = node["location"].flatMap { $0.isEmpty ? nil : $0 } ?? ap.location
        if node["support-11ac"] != nil { ap.supports11ac = bool(node["support-11ac"]) }
        if node["support-11ax"] != nil { ap.supports11ax = bool(node["support-11ax"]) }
        ap.raw.merge(cleanedAttributes(node.attributes)) { _, new in new }
    }

    private static func txPower(for band: RadioBand, in node: XMLNode) -> String {
        let key: String
        switch band {
        case .ghz2_4: key = "tx-power-11ng"
        case .ghz5: key = "tx-power-11na"
        case .ghz6: key = "tx-power-11ax-6g"
        case .unknown: return ""
        }
        guard let value = node[key] else { return "" }
        return value == "0" ? "Full" : "-\(value) dB"
    }

    private static func synthesizedRadios(from node: XMLNode) -> [Radio] {
        var radios: [Radio] = []
        if let channel = node["channel-11ng"] {
            radios.append(Radio(radioType: "11ng", band: .ghz2_4, channel: channel,
                                channelization: node["channelization-11ng"] ?? "", txPower: txPower(for: .ghz2_4, in: node)))
        }
        if let channel = node["channel-11na"] {
            radios.append(Radio(radioType: node["support-11ac"] == "true" ? "11ac" : "11na", band: .ghz5, channel: channel,
                                channelization: node["channelization-11na"] ?? "", txPower: txPower(for: .ghz5, in: node)))
        }
        return radios
    }

    // MARK: Clients

    static func clients(from nodes: [XMLNode]) -> [WirelessClient] {
        nodes.compactMap { node in
            let key = mac(node["mac"])
            guard !key.isEmpty else { return nil }
            var client = WirelessClient(mac: key)
            client.ip = node["ip"] ?? ""
            client.ipv6 = node["ipv6"] ?? ""
            client.hostname = node["hostname"] ?? ""
            client.username = node["user"] ?? ""
            client.apMAC = mac(node["ap"])
            client.apName = node["ap-name"] ?? ""
            client.ssid = node.attr("ssid", "wlan") ?? ""
            client.wlanID = node["wlan-id"] ?? ""
            client.osDescription = node["dvcinfo"] ?? ""
            client.deviceType = node["dvctype"] ?? ""
            client.model = node["model"] ?? ""
            client.rssi = int(node["rssi"])
            client.signalDBm = int(node["received-signal-strength"])
            client.noiseFloor = int(node["noise-floor"])
            client.healthLevel = node.attr("display-health-level", "rssi-level") ?? ""
            client.channel = node["channel"] ?? ""
            client.radioType = node.attr("radio-type-text", "radio-type") ?? ""
            client.band = RadioBand.from(band: node["radio-band"], radioType: node["radio-type"])
            client.authMethod = node["auth-method"] ?? ""
            client.encryption = node["encryption"] ?? ""
            client.vlan = node["vlan"] ?? ""
            client.firstAssociated = date(node["first-assoc"])
            client.isAuthorized = (node["status"] ?? "1") == "1"
            client.isBlocked = node["blocked"] == "1"
            client.isFavourite = node["favourite"] == "1"
            client.isIoT = node["iot"] == "1"
            client.rxBytes = int64(node.attr("total-rx-bytes", "rx-bytes"))
            client.txBytes = int64(node.attr("total-tx-bytes", "tx-bytes"))
            client.rxPackets = int64(node.attr("total-rx-pkts", "rx-pkts"))
            client.txPackets = int64(node.attr("total-tx-pkts", "tx-pkts"))
            client.raw = cleanedAttributes(node.attributes)
            return client
        }
    }

    // MARK: WLANs

    static func wlans(config: [XMLNode], stats: [XMLNode]) -> [WLAN] {
        var byID: [String: WLAN] = [:]
        var order: [String] = []

        for node in config {
            guard let id = node["id"], !id.isEmpty else { continue }
            if byID[id] == nil { order.append(id) }
            var wlan = byID[id] ?? WLAN(id: id)
            wlan.name = node["name"] ?? wlan.name
            wlan.ssid = node["ssid"] ?? wlan.ssid
            wlan.description = node["description"] ?? wlan.description
            wlan.usage = node["usage"] ?? wlan.usage
            wlan.isGuest = bool(node["is-guest"]) || wlan.usage == "guest"
            wlan.authentication = node["authentication"] ?? wlan.authentication
            wlan.encryption = node["encryption"] ?? wlan.encryption
            wlan.cipher = node.first("wpa")?["cipher"] ?? wlan.cipher
            wlan.vlanID = node["vlan-id"] ?? wlan.vlanID
            wlan.enableType = node["enable-type"] ?? wlan.enableType
            wlan.maxClientsPerRadio = int(node["max-clients-per-radio"])
            wlan.clientIsolation = bool(node["client-isolation"])
            wlan.wifi6 = bool(node["wifi6"])
            wlan.isHidden = bool(node["close-system"])
            wlan.createdAt = date(node["create-time"])
            wlan.raw.merge(cleanedAttributes(node.attributes)) { _, new in new }
            byID[id] = wlan
        }

        for node in stats {
            guard let id = node["id"], !id.isEmpty else { continue }
            if byID[id] == nil { order.append(id) }
            var wlan = byID[id] ?? WLAN(id: id)
            if wlan.ssid.isEmpty { wlan.ssid = node["ssid"] ?? "" }
            if wlan.name.isEmpty { wlan.name = node["ssid"] ?? "" }
            wlan.clientCount = int(node["assoc-stas"]) ?? wlan.clientCount
            wlan.state = node["state"] ?? wlan.state
            let parsed = history(from: node.first("history"))
            if !parsed.all.isEmpty { wlan.history = parsed.all }
            byID[id] = wlan
        }

        return order.compactMap { byID[$0] }
    }

    // MARK: Neighbours (background-scan "rogue" list)

    static func neighbors(from nodes: [XMLNode]) -> [NeighborNetwork] {
        nodes.compactMap { node in
            let key = mac(node["mac"])
            guard !key.isEmpty else { return nil }
            var neighbor = NeighborNetwork(mac: key)
            neighbor.ssid = node["ssid"] ?? ""
            neighbor.band = RadioBand.from(band: node["radio-band"], radioType: node["radio-type"])
            neighbor.channel = int(node["channel"]) ?? 0
            neighbor.radioType = node.attr("radio-type", "ieee80211-radio-type") ?? ""
            neighbor.isEncrypted = (node["is-open"] ?? "").lowercased() != "open"
            neighbor.rogueType = node["rogue-type"] ?? ""
            neighbor.lastSeen = date(node["last-seen"])
            neighbor.detections = node.all("detection").map { detection in
                NeighborDetection(
                    apMAC: mac(detection["ap"]),
                    apName: detection["sys-name"] ?? "",
                    rssi: int(detection["rssi"]) ?? 0,
                    lastSeen: date(detection["last-seen"])
                )
            }
            neighbor.raw = cleanedAttributes(node.attributes)
            return neighbor
        }
    }

    // MARK: Events

    static func events(from nodes: [XMLNode], kind: ControllerEvent.Kind) -> [ControllerEvent] {
        nodes.enumerated().map { index, node in
            let time = date(node["time"]) ?? Date.distantPast
            let message = node.attr("lmsg", "msg") ?? ""
            let digest = "\(kind.rawValue)|\(node["time"] ?? "")|\(node["msg"] ?? "")|\(node["ap"] ?? "")|\(index)"
            return ControllerEvent(
                id: digest,
                kind: kind,
                time: time,
                severity: EventSeverity.from(code: node["severity"]),
                severityCode: node["severity"] ?? "",
                category: node["c"] ?? "",
                message: message,
                messageKey: node["msg"] ?? "",
                apMAC: mac(node["ap"]),
                apName: node["ap-name"] ?? "",
                clientMAC: mac(node.attr("client", "sta", "user-mac")),
                alarmName: node["name"] ?? "",
                occurrences: int(node["occurs"]),
                raw: cleanedAttributes(node.attributes)
            )
        }
    }
}
