import Foundation

/// A generated multi-AP network for previews and for trying the app without a controller.
actor DemoRuckusService: RuckusService {
    nonisolated let displayHost = "demo"

    private var logger: (@Sendable (RequestLogEntry) -> Void)?
    private var rng = SeededGenerator(seed: 0x5EED)
    private var tick = 0
    private var startedAt = Date()
    private var accessPoints: [AccessPoint]
    private var clients: [WirelessClient]
    private var wlans: [WLAN]
    private var history: [TrafficSample]
    private var events: [ControllerEvent]
    private var restartingUntil: [String: Int] = [:]
    private var removedClients: [(WirelessClient, Int)] = []

    init() {
        var rng = SeededGenerator(seed: 0x5EED)
        accessPoints = DemoRuckusService.makeAccessPoints()
        clients = DemoRuckusService.makeClients(rng: &rng)
        wlans = DemoRuckusService.makeWLANs()
        history = DemoRuckusService.makeHistory(rng: &rng)
        events = DemoRuckusService.makeEvents()
        self.rng = rng
    }

    func setLogger(_ logger: (@Sendable (RequestLogEntry) -> Void)?) {
        self.logger = logger
    }

    func connect() async throws {
        try await Task.sleep(for: .milliseconds(300))
    }

    func disconnect() {}

    // MARK: Reads

    func fetchSnapshot() async throws -> ControllerSnapshot {
        tick += 1
        advance()
        var snapshot = ControllerSnapshot()
        snapshot.system = systemInfo()
        snapshot.accessPoints = accessPoints
        snapshot.clients = clients
        snapshot.wlans = wlans.map { wlan in
            var copy = wlan
            copy.clientCount = clients.filter { $0.wlanID == wlan.id }.count
            copy.state = wlan.isEnabled ? "enabled" : "disabled"
            return copy
        }
        snapshot.totals = totals()
        snapshot.summary = summary()
        snapshot.fetchedAt = Date()
        LiveRuckusService.fillRadioClientCounts(&snapshot)
        log(path: "/admin/_cmdstat.jsp", request: "<ajax-request action='getstat' comp='stamgr' updater='demo'/>",
            response: "<ajax-response><response type='object' id='demo'><apstamgr-stat/></response></ajax-response>")
        return snapshot
    }

    func fetchLiveStats() async throws -> LiveStats {
        tick += 1
        advance()
        var live = LiveStats()
        live.clients = clients
        live.accessPointStats = accessPoints
        live.totals = totals()
        live.summary = summary()
        return live
    }

    func fetchEvents(limit: Int) async throws -> [ControllerEvent] {
        Array(events.sorted { $0.time > $1.time }.prefix(limit))
    }

    func fetchNeighbors() async throws -> [NeighborNetwork] {
        let aps = accessPoints
        let seeds: [(String, RadioBand, Int, String, Int, Bool)] = [
            ("NETGEAR42", .ghz2_4, 1, "802.11g/n", 38, true), ("TommysHouse", .ghz2_4, 6, "802.11g/n", 52, true),
            ("TommysIoT", .ghz2_4, 6, "802.11g/n", 50, true), ("PrinterSetup-7F", .ghz2_4, 11, "802.11g/n", 23, true),
            ("", .ghz2_4, 1, "802.11g/n", 12, true), ("CoffeeShop-Guest", .ghz2_4, 9, "802.11g/n", 18, false),
            ("Ring-Setup", .ghz2_4, 3, "802.11g/n", 9, false), ("Neighbours5G", .ghz5, 44, "802.11a/n/ac", 21, true),
            ("TommysHouse", .ghz5, 100, "802.11a/n/ac", 33, true), ("Office-2", .ghz5, 157, "802.11a/n/ac", 14, true),
            ("Demo Office", .ghz5, 36, "802.11a/n/ac", 60, true), ("Demo Office", .ghz2_4, 1, "802.11g/n", 58, true),
        ]
        return seeds.enumerated().map { index, seed in
            var neighbor = NeighborNetwork(mac: String(format: "9c:05:d6:%02x:%02x:%02x", index, 0xc5 + index, 0x10 * index + 2))
            neighbor.ssid = seed.0
            neighbor.band = seed.1
            neighbor.channel = seed.2
            neighbor.radioType = seed.3
            neighbor.isEncrypted = seed.5
            neighbor.rogueType = "AP"
            neighbor.lastSeen = Date().addingTimeInterval(-Double(index * 90))
            neighbor.detections = [NeighborDetection(apMAC: aps[0].mac, apName: aps[0].name, rssi: seed.4, lastSeen: neighbor.lastSeen)]
            if seed.0 == "Demo Office" { neighbor.mac = String(format: "f0:3e:90:11:aa:%02x", 0x18 + index); neighbor.detections.append(NeighborDetection(apMAC: aps[1].mac, apName: aps[1].name, rssi: seed.4 - 20, lastSeen: neighbor.lastSeen)) }
            return neighbor
        }
    }

    // MARK: Actions

    func restartAccessPoint(mac: String) async throws {
        guard let index = accessPoints.firstIndex(where: { $0.mac == mac }) else { throw RuckusError.apiFailure(message: "Unknown AP", raw: "") }
        accessPoints[index].state = .disconnected
        restartingUntil[mac] = tick + 2
        addEvent(message: "AP[\(mac)] is restarting (demo)", severity: .medium, apMAC: mac, apName: accessPoints[index].name)
    }

    func blockClient(mac: String, hostname: String) async throws {
        guard let index = clients.firstIndex(where: { $0.mac == mac }) else { return }
        clients[index].isBlocked = true
        clients[index].isAuthorized = false
        addEvent(message: "Client[\(mac)] was blocked by admin (demo)", severity: .medium, apMAC: clients[index].apMAC, apName: clients[index].apName)
    }

    func unblockClient(mac: String) async throws {
        guard let index = clients.firstIndex(where: { $0.mac == mac }) else { return }
        clients[index].isBlocked = false
        clients[index].isAuthorized = true
    }

    func disconnectClient(mac: String) async throws {
        guard let index = clients.firstIndex(where: { $0.mac == mac }) else { return }
        let client = clients.remove(at: index)
        removedClients.append((client, tick + 4))
        addEvent(message: "Client[\(mac)] disconnected by admin (demo)", severity: .low, apMAC: client.apMAC, apName: client.apName)
    }

    func renameClient(mac: String, name: String) async throws {
        guard let index = clients.firstIndex(where: { $0.mac == mac }) else { return }
        clients[index].hostname = name
    }

    func setClientFavourite(mac: String, isFavourite: Bool) async throws {
        guard let index = clients.firstIndex(where: { $0.mac == mac }) else { return }
        clients[index].isFavourite = isFavourite
    }

    func setWLANEnabled(id: String, enabled: Bool) async throws {
        guard let index = wlans.firstIndex(where: { $0.id == id }) else { return }
        wlans[index].enableType = enabled ? "0" : "1"
        if !enabled {
            let affected = clients.filter { $0.wlanID == id }
            clients.removeAll { $0.wlanID == id }
            for client in affected { removedClients.append((client, tick + 6)) }
        }
    }

    func sendRaw(xml: String, path: String) async throws -> AjaxResponse {
        let raw = "<ajax-response><response type=\"object\" id=\"demo\"><xmsg type=\"0\" msg=\"Demo mode: request accepted but not executed.\"/></response></ajax-response>"
        let root = try XMLTreeParser.parse(raw)
        log(path: path, request: xml, response: raw)
        return AjaxResponse(requestXML: xml, raw: raw, root: root, duration: 0.01)
    }

    // MARK: Configuration (kept in memory)

    private var demoConfig: [String: [String: String]] = [
        "identity": ["name": "Demo Network", "domain": ""],
        "sysinfo": ["version": "200.15.6.212 build 27", "display-model": "R750", "serial": "982103001234", "uptime": "1000"],
        "unleashed-network": ["unleashed-network-token": "un9821030012341749553652654"],
        "ap-policy": ["prefer-master": "0", "prefer-second-master": "0", "master-focus-controller": "false", "allow-all": "true"],
        "mgmt-ip": ["by-dhcp": "true", "ip": "192.168.8.172", "netmask": "255.255.255.0", "gateway": "192.168.8.1", "dns1": "192.168.8.1", "dns2": ""],
        "internal-gateway": ["enabled": "true", "ip": "192.168.10.1", "netmask": "255.255.255.0"],
        "WAN": ["mode": "dhcp"], "dhcps": ["enabled": "true", "ip-start": "192.168.10.2", "ip-end": "192.168.10.250", "netmask": "255.255.255.0", "lease": "12h", "dns1": "", "dns2": ""],
        "mgmt-vlan": ["enabled": "false", "vlan-id": ""],
        "time": ["time": "\(Int(Date().timeIntervalSince1970))", "by-ntp": "true", "ntp1": "ntp.ruckuswireless.com", "timezone": "GMT-0", "daylight-saving": "true"],
        "adv-radio": ["country": "US", "use-dfs-channels": "1", "only-centrino-channels": "0", "indoor-channel-allow": "0"],
        "mesh-policy": ["enabled": "true", "mesh-radio-id": "1", "zt-mesh": "enabled", "detect-hops": "disabled", "hops-warn-threshold": "3", "detect-fanout": "disabled", "fan-out-threshold": "3"],
        "admin": ["username": "admin", "lang": "en_US", "idletimeout": "30", "auth-by": "local"],
        "snmp": ["enabled": "false", "ro-community": "public", "rw-community": "private", "sys-contact": "", "sys-location": ""],
        "snmpv3": ["enabled": "false"], "snmp-trap": ["enabled": "false", "ver": "2", "password": "public", "ip1": "", "ip2": "", "ip3": ""],
        "tr069": ["tr069enable": "false", "url": "", "informinterval": "3"], "log": ["level": "1", "enable-remote-log": "false", "remote-log-server": ""],
        "remote-mgmt": ["tcp-ports": "443,80", "udp-ports": "", "icmp": "false"], "pubnub": ["enabled": "false"], "aws-sns": ["enabled": "true"],
        "mdnsproxyrule-enable-ap": ["enabled": "false"],
        "guest-access": ["auth-by": "guestpass", "valid": "7", "countdown-by-issued": "false", "self-service": "true", "title": "Welcome to Guest WiFi !", "show-tou": "false", "tou": "Terms of use", "redirect": "orig", "redirect-url": ""],
        "self-heal": ["auto-ap-channel": "enabled", "channelfly-2_4G": "disabled", "auto-ap-channel-5G": "enabled", "channelfly-5G": "disabled", "auto-ap-bandwidth": "enabled", "auto-ap-power": "disabled"],
        "background-scan": ["enabled": "true", "sleep": "300", "enabled_5g": "true", "sleep_5g": "300"],
        "band-balancing": ["enabled": "false", "percent-2_4g": "25"], "scand": ["enabled": "true"],
        "wips": ["rogue-reporting": "true", "malicious-reporting": "false"], "ips": ["auto-probe-limit": "disabled", "auto-authfail-block": "disabled", "auto-authfail-blocktime": "30"], "dhcpp": ["enabled": "false"],
    ]
    private var demoLists: [String: [ListRow]] = [
        "role-list": [ListRow(id: "1", attributes: ["id": "1", "name": "Default", "description": "Allow Access to All WLANs", "can-generate-pass": "true", "allow-all-wlansvc": "true"], children: [])],
        "user-list": [ListRow(id: "1", attributes: ["id": "1", "name": "graham", "full-name": "Graham", "role-id": "1"], children: [])],
        "authsvr-list": [ListRow(id: "1", attributes: ["id": "1", "type": "local", "name": "Local Database", "EDITABLE": "false"], children: []),
                         ListRow(id: "2", attributes: ["id": "2", "type": "guestpass", "name": "Guest Accounts", "EDITABLE": "false"], children: [])],
        "acl-list": [ListRow(id: "1", attributes: ["id": "1", "name": "System", "description": "System", "default-mode": "allow", "EDITABLE": "false"], children: [])],
        "mesh-list": [ListRow(id: "1", attributes: ["id": "1", "name": "Mesh-982103001234-170", "mesh-radio-id": "1"], children: [])],
        "timezone-list": [ListRow(id: "5", attributes: ["id": "5", "key": "GMT+8", "value": "(GMT -8:00) Pacific Time (US & Canada)"], children: []),
                          ListRow(id: "8", attributes: ["id": "8", "key": "GMT+5", "value": "(GMT -5:00) Eastern Time (US & Canada)"], children: []),
                          ListRow(id: "13", attributes: ["id": "13", "key": "GMT-0", "value": "(GMT) Greenwich Mean Time, London"], children: [])],
    ]

    func fetchSystemConfig(elements: [String], action: AjaxRequest.Action) async throws -> XMLNode {
        var children: [XMLNode] = []
        for element in elements {
            var node = XMLNode(name: element, attributes: demoConfig[element] ?? [:])
            if element == "snmpv3" {
                node.children = [XMLNode(name: "snmpusr", attributes: ["role": "rouser", "name": "", "auth": "MD5", "priv": "DES"]),
                                 XMLNode(name: "snmpusr", attributes: ["role": "rwuser", "name": "", "auth": "MD5", "priv": "DES"])]
            }
            if element == "client-load-balancing" {
                node.children = [XMLNode(name: "radio", attributes: ["radio-id": "0", "enabled": "false", "adjust-threshold": "30"]),
                                 XMLNode(name: "radio", attributes: ["radio-id": "1", "enabled": "false", "adjust-threshold": "23"])]
            }
            children.append(node)
        }
        return XMLNode(name: "response", children: children)
    }

    func applySystemConfig(body: String) async throws {
        let root = try XMLTreeParser.parse("<setconf>\(body)</setconf>")
        for child in root.children {
            var attrs = demoConfig[child.name] ?? [:]
            for (key, value) in child.attributes where key != "IS_PARTIAL" { attrs[key] = value }
            demoConfig[child.name] = attrs
        }
        log(path: "/admin/_conf.jsp", request: "<ajax-request action='setconf' comp='system' updater='demo'>\(body)</ajax-request>",
            response: "<ajax-response><response type='object' id='demo'><xmsg type='0' msg=''/></response></ajax-response>")
    }

    func fetchListRows(component: String, element: String, action: AjaxRequest.Action, decrypt: Bool, statBody: String?, idAttribute: String) async throws -> [ListRow] {
        demoLists[component] ?? []
    }

    func addObject(component: String, body: String) async throws {
        let node = try XMLTreeParser.parse(body)
        var attrs = node.attributes
        let id = String((demoLists[component]?.count ?? 0) + 1)
        attrs["id"] = id
        demoLists[component, default: []].append(ListRow(id: id, attributes: attrs, children: node.children))
    }

    func updateObject(component: String, body: String) async throws {
        let node = try XMLTreeParser.parse(body)
        guard let id = node["id"], let index = demoLists[component]?.firstIndex(where: { $0.id == id }) else { return }
        for (key, value) in node.attributes where key != "IS_PARTIAL" { demoLists[component]![index].attributes[key] = value }
    }

    func deleteObject(component: String, body: String) async throws {
        let node = try XMLTreeParser.parse(body)
        guard let id = node["id"] else { return }
        demoLists[component]?.removeAll { $0.id == id }
    }

    func runCommand(component: String, xcmd: String, body: String, rootAttributes: [String: String]) async throws -> AjaxResponse {
        let raw = "<ajax-response><response type=\"object\" id=\"demo\"><xmsg type=\"0\" msg=\"\" res=\"Demo mode: \(xcmd) accepted but not executed.\"/></response></ajax-response>"
        return AjaxResponse(requestXML: body, raw: raw, root: try XMLTreeParser.parse(raw), duration: 0.01)
    }

    func downloadFile(path: String) async throws -> Data {
        Data("Demo mode: no file available for \(path)\n".utf8)
    }

    func adminAction(command: String, parameters: [String: String]) async throws -> String {
        "Demo mode: '\(command)' would have been sent to admin_performed.jsp."
    }

    // MARK: Simulation

    private func advance() {
        // Bring restarted APs back and re-admit disconnected clients.
        for (mac, until) in restartingUntil where tick >= until {
            if let index = accessPoints.firstIndex(where: { $0.mac == mac }) {
                accessPoints[index].state = .connected
                accessPoints[index].uptime = 30
                accessPoints[index].lastSeen = Date()
            }
            restartingUntil[mac] = nil
        }
        let ready = removedClients.filter { $0.1 <= tick }
        removedClients.removeAll { $0.1 <= tick }
        for (client, _) in ready where !clients.contains(where: { $0.mac == client.mac }) {
            var copy = client
            copy.firstAssociated = Date()
            clients.append(copy)
        }

        for index in accessPoints.indices where accessPoints[index].isOnline {
            accessPoints[index].uptime = (accessPoints[index].uptime ?? 0) + 20
            accessPoints[index].lastSeen = Date()
            accessPoints[index].cpuUtilization = Double(Int.random(in: 2...18, using: &rng))
        }
        for index in clients.indices {
            let delta = Int64.random(in: 10_000...4_000_000, using: &rng)
            clients[index].rxBytes = (clients[index].rxBytes ?? 0) + delta / 4
            clients[index].txBytes = (clients[index].txBytes ?? 0) + delta
            if let rssi = clients[index].rssi {
                clients[index].rssi = max(8, min(60, rssi + Int.random(in: -2...2, using: &rng)))
                clients[index].signalDBm = -96 + clients[index].rssi!
            }
        }
        let last = history.last?.time ?? Date()
        if Date().timeIntervalSince(last) >= 60 {
            history.append(TrafficSample(
                time: last.addingTimeInterval(60),
                rxBytes: Int64.random(in: 200_000...3_000_000, using: &rng),
                txBytes: Int64.random(in: 2_000_000...60_000_000, using: &rng)
            ))
            if history.count > 10 { history.removeFirst(history.count - 10) }
        }
    }

    private func systemInfo() -> SystemInfo {
        var info = SystemInfo()
        info.name = "Demo Network"
        info.model = "R750"
        info.version = "200.15.6.212 build 27"
        info.serial = "982103001234"
        info.unleashedID = "un9821030012341749553652654"
        info.uptime = 86_400 * 12 + Date().timeIntervalSince(startedAt)
        info.managementIP = "192.168.10.1"
        info.managementNetmask = "255.255.255.0"
        info.managementByDHCP = false
        info.wanIP = "192.168.8.172"
        info.gateway = "192.168.8.1"
        info.dns = "192.168.8.1"
        info.internetConnected = true
        info.maxAccessPoints = 25
        info.maxClients = 512
        info.countryCode = "US"
        return info
    }

    private func totals() -> ControllerTotals {
        var totals = ControllerTotals()
        totals.accessPointCount = accessPoints.count
        totals.clientCount = clients.count
        totals.rogueCount = 7
        totals.rxBytesTotal = clients.reduce(0) { $0 + ($1.rxBytes ?? 0) } * 40
        totals.txBytesTotal = clients.reduce(0) { $0 + ($1.txBytes ?? 0) } * 40
        totals.rxBytesToday = totals.rxBytesTotal / 12
        totals.txBytesToday = totals.txBytesTotal / 12
        totals.rxBytesLastHour = totals.rxBytesTotal / 200
        totals.txBytesLastHour = totals.txBytesTotal / 200
        totals.averageRSSI = 38
        totals.apRebootsToday = 1
        totals.ethernetPorts = [
            EthernetPort(id: "0", name: "Port1", interfaceName: "eth0", speed: "1000Mbps", isUp: true, inBytes: 9_120_442_210, outBytes: 2_401_990_211, mac: "f0:3e:90:12:34:01"),
            EthernetPort(id: "1", name: "Port2", interfaceName: "eth1", speed: "100Mbps", isUp: false, inBytes: 0, outBytes: 0, mac: "f0:3e:90:12:34:02"),
        ]
        return totals
    }

    private func summary() -> APSummary {
        var summary = APSummary()
        summary.connected = accessPoints.filter(\.isOnline).count
        summary.disconnected = accessPoints.count - summary.connected
        summary.maxAccessPoints = 25
        summary.maxClients = 512
        summary.history = TrafficHistory(samples: history)
        summary.historyByBand = [
            .ghz5: TrafficHistory(samples: history.map { TrafficSample(time: $0.time, rxBytes: $0.rxBytes * 3 / 4, txBytes: $0.txBytes * 3 / 4) }),
            .ghz2_4: TrafficHistory(samples: history.map { TrafficSample(time: $0.time, rxBytes: $0.rxBytes / 4, txBytes: $0.txBytes / 4) }),
        ]
        return summary
    }

    private func addEvent(message: String, severity: EventSeverity, apMAC: String, apName: String) {
        events.insert(ControllerEvent(
            id: UUID().uuidString, kind: .event, time: Date(), severity: severity,
            severityCode: String(severity.rawValue), category: "system", message: message,
            messageKey: "MSG_demo", apMAC: apMAC, apName: apName, clientMAC: "", alarmName: "", occurrences: nil
        ), at: 0)
    }

    private func log(path: String, request: String, response: String) {
        logger?(RequestLogEntry(path: path, requestXML: request, responseText: response, status: 200, duration: 0.02, error: nil))
    }

    // MARK: Seed data

    private static func makeAccessPoints() -> [AccessPoint] {
        func ap(mac: String, name: String, model: String, ip: String, location: String, role: String, uptime: TimeInterval,
                channels: (String, String), online: Bool = true, uplink: String = "wired") -> AccessPoint {
            var ap = AccessPoint(mac: mac)
            ap.name = name
            ap.model = model
            ap.ip = ip
            ap.netmask = "255.255.255.0"
            ap.gateway = "192.168.10.1"
            ap.ipType = "DHCP"
            ap.location = location
            ap.firmware = "200.15.6.212.27"
            ap.serial = "98210300" + String(mac.suffix(4)).replacingOccurrences(of: ":", with: "")
            ap.state = online ? .connected : .disconnected
            ap.role = role
            ap.meshState = uplink == "wired" ? "root" : "map"
            ap.meshUplinkType = uplink
            ap.meshDepth = uplink == "wired" ? 0 : 1
            ap.uptime = online ? uptime : nil
            ap.lastSeen = online ? Date() : Date().addingTimeInterval(-3_700)
            ap.firstJoined = Date().addingTimeInterval(-86_400 * 300)
            ap.cpuUtilization = 6
            ap.memoryAvailableKB = 171_000
            ap.memoryTotalKB = 470_956
            ap.lastRebootReason = "power cycle detect"
            ap.rebootCount = 3
            ap.supports11ac = true
            ap.supports11ax = model.hasPrefix("R7") || model.hasPrefix("R6")
            ap.poeMode = "802.3at"
            ap.lanRxBytes = 129_183_196
            ap.lanTxBytes = 25_902_975
            ap.radios = [
                Radio(radioType: "11ng", band: .ghz2_4, channel: channels.0, channelization: "20", txPower: "Full"),
                Radio(radioType: ap.supports11ax ? "11ax" : "11ac", band: .ghz5, channel: channels.1, channelization: "80", txPower: "Full"),
            ]
            ap.interfaces = [
                NetworkInterface(name: "eth0", macAddress: mac, speed: "1000", isUp: online, inOctets: 129_183_196, outOctets: 25_902_975),
                NetworkInterface(name: "eth1", macAddress: mac, speed: "0", isUp: false, inOctets: 0, outOctets: 0),
            ]
            return ap
        }
        return [
            ap(mac: "f0:3e:90:11:aa:10", name: "Office Core", model: "R750", ip: "192.168.10.1", location: "Server room", role: "master", uptime: 86_400 * 12 + 3_600 * 4, channels: ("1", "36")),
            ap(mac: "f0:3e:90:11:aa:20", name: "Reception", model: "R510", ip: "192.168.10.12", location: "Front desk", role: "member", uptime: 86_400 * 12, channels: ("6", "100")),
            ap(mac: "f0:3e:90:11:aa:30", name: "Warehouse", model: "R610", ip: "192.168.10.13", location: "Warehouse mezzanine", role: "member", uptime: 86_400 * 3 + 1_200, channels: ("11", "149"), uplink: "wireless"),
            ap(mac: "f0:3e:90:11:aa:40", name: "Workshop", model: "R710", ip: "192.168.10.14", location: "Workshop", role: "member", uptime: 0, channels: ("1", "44"), online: false),
        ]
    }

    private static func makeClients(rng: inout SeededGenerator) -> [WirelessClient] {
        struct Seed { let name: String; let os: String; let type: String; let model: String; let ap: Int; let wlan: String; let band: RadioBand }
        let seeds: [Seed] = [
            Seed(name: "Grahams-MacBook-Pro", os: "Mac OS", type: "Laptop", model: "Apple MacBook Pro", ap: 0, wlan: "1", band: .ghz5),
            Seed(name: "iPhone-15", os: "iOS", type: "Smartphone", model: "Apple iPhone", ap: 0, wlan: "1", band: .ghz5),
            Seed(name: "Pixel-8", os: "Android", type: "Smartphone", model: "Google Pixel", ap: 1, wlan: "1", band: .ghz5),
            Seed(name: "HP-LaserJet", os: "Printer", type: "Printer", model: "HP LaserJet Pro", ap: 1, wlan: "3", band: .ghz2_4),
            Seed(name: "Sonos-Kitchen", os: "Linux", type: "Speaker", model: "Sonos One", ap: 1, wlan: "3", band: .ghz2_4),
            Seed(name: "Ring-Doorbell", os: "Embedded", type: "Camera", model: "Ring Video Doorbell", ap: 1, wlan: "3", band: .ghz2_4),
            Seed(name: "iPad-Studio", os: "iPadOS", type: "Tablet", model: "Apple iPad Pro", ap: 0, wlan: "1", band: .ghz5),
            Seed(name: "ThinkPad-X1", os: "Windows", type: "Laptop", model: "Lenovo ThinkPad", ap: 2, wlan: "1", band: .ghz5),
            Seed(name: "Apple-TV", os: "tvOS", type: "Media player", model: "Apple TV 4K", ap: 0, wlan: "1", band: .ghz5),
            Seed(name: "Nest-Thermostat", os: "Embedded", type: "IoT", model: "Google Nest", ap: 2, wlan: "3", band: .ghz2_4),
            Seed(name: "Galaxy-S24", os: "Android", type: "Smartphone", model: "Samsung Galaxy", ap: 2, wlan: "2", band: .ghz5),
            Seed(name: "DESKTOP-7Q2", os: "Windows", type: "Desktop", model: "Dell OptiPlex", ap: 0, wlan: "1", band: .ghz5),
            Seed(name: "Kindle", os: "Android", type: "Tablet", model: "Amazon Kindle", ap: 1, wlan: "2", band: .ghz2_4),
            Seed(name: "PS5", os: "Embedded", type: "Game console", model: "Sony PlayStation 5", ap: 2, wlan: "1", band: .ghz5),
            Seed(name: "Visitor-iPhone", os: "iOS", type: "Smartphone", model: "Apple iPhone", ap: 1, wlan: "2", band: .ghz5),
        ]
        let aps = makeAccessPoints()
        let wlanNames = ["1": "Demo Office", "2": "Demo Guest", "3": "Demo IoT"]
        return seeds.enumerated().map { index, seed in
            let ap = aps[seed.ap]
            var client = WirelessClient(mac: String(format: "3a:8e:1b:%02x:%02x:%02x", 0x30 + index, 0xb9 + index, 0x10 + index * 7))
            client.ip = "192.168.10.\(20 + index)"
            client.hostname = seed.name
            client.apMAC = ap.mac
            client.apName = ap.name
            client.ssid = wlanNames[seed.wlan] ?? ""
            client.wlanID = seed.wlan
            client.osDescription = seed.os
            client.deviceType = seed.type
            client.model = seed.model
            client.rssi = Int.random(in: 12...55, using: &rng)
            client.signalDBm = -96 + (client.rssi ?? 30)
            client.noiseFloor = -96
            client.healthLevel = (client.rssi ?? 0) > 35 ? "Excellent" : ((client.rssi ?? 0) > 20 ? "Moderate" : "Poor")
            client.band = seed.band
            client.channel = seed.band == .ghz5 ? (ap.radios.last?.channel ?? "36") : (ap.radios.first?.channel ?? "1")
            client.radioType = seed.band == .ghz5 ? "11ax" : "11ng"
            client.authMethod = "Open"
            client.encryption = seed.wlan == "2" ? "none" : "WPA2"
            client.vlan = seed.wlan == "2" ? "20" : "1"
            client.firstAssociated = Date().addingTimeInterval(-Double(Int.random(in: 600...86_400 * 3, using: &rng)))
            client.rxBytes = Int64.random(in: 2_000_000...900_000_000, using: &rng)
            client.txBytes = Int64.random(in: 10_000_000...6_000_000_000, using: &rng)
            client.rxPackets = (client.rxBytes ?? 0) / 900
            client.txPackets = (client.txBytes ?? 0) / 1_200
            client.isFavourite = index == 0
            client.isIoT = seed.wlan == "3"
            return client
        }
    }

    private static func makeWLANs() -> [WLAN] {
        var main = WLAN(id: "1")
        main.name = "Demo Office"
        main.ssid = "Demo Office"
        main.description = "Staff network"
        main.usage = "user"
        main.authentication = "open"
        main.encryption = "wpa2"
        main.cipher = "aes"
        main.vlanID = "1"
        main.maxClientsPerRadio = 100
        main.wifi6 = true
        main.createdAt = Date().addingTimeInterval(-86_400 * 400)

        var guest = WLAN(id: "2")
        guest.name = "Demo Guest"
        guest.ssid = "Demo Guest"
        guest.description = "Visitors, captive portal"
        guest.usage = "guest"
        guest.isGuest = true
        guest.authentication = "open"
        guest.encryption = "none"
        guest.vlanID = "20"
        guest.maxClientsPerRadio = 50
        guest.clientIsolation = true
        guest.createdAt = Date().addingTimeInterval(-86_400 * 380)

        var iot = WLAN(id: "3")
        iot.name = "Demo IoT"
        iot.ssid = "Demo IoT"
        iot.description = "2.4 GHz devices"
        iot.usage = "user"
        iot.authentication = "open"
        iot.encryption = "wpa2"
        iot.cipher = "aes"
        iot.vlanID = "30"
        iot.maxClientsPerRadio = 100
        iot.isHidden = true
        iot.createdAt = Date().addingTimeInterval(-86_400 * 120)
        return [main, guest, iot]
    }

    private static func makeHistory(rng: inout SeededGenerator) -> [TrafficSample] {
        let now = Date(timeIntervalSince1970: (Date().timeIntervalSince1970 / 60).rounded(.down) * 60)
        return (0..<10).reversed().map { offset in
            TrafficSample(
                time: now.addingTimeInterval(-Double(offset) * 60),
                rxBytes: Int64.random(in: 200_000...3_000_000, using: &rng),
                txBytes: Int64.random(in: 2_000_000...60_000_000, using: &rng)
            )
        }
    }

    private static func makeEvents() -> [ControllerEvent] {
        let aps = makeAccessPoints()
        let now = Date()
        func event(_ minutesAgo: Double, _ severity: EventSeverity, _ message: String, ap: AccessPoint, kind: ControllerEvent.Kind = .event, alarm: String = "") -> ControllerEvent {
            ControllerEvent(
                id: UUID().uuidString, kind: kind, time: now.addingTimeInterval(-minutesAgo * 60), severity: severity,
                severityCode: String(severity.rawValue), category: "system", message: message, messageKey: "MSG_demo",
                apMAC: ap.mac, apName: ap.name, clientMAC: "", alarmName: alarm, occurrences: kind == .alarm ? 1 : nil
            )
        }
        return [
            event(4, .low, "Client[3a:8e:1b:31:ba:17] joins WLAN[Demo Office] from AP[Office Core]", ap: aps[0]),
            event(17, .low, "Radio [5G] of AP[Reception] changed channel to 100 (interference)", ap: aps[1]),
            event(42, .high, "AP[Workshop] heartbeat lost", ap: aps[3], kind: .alarm, alarm: "AP Lost Heartbeat"),
            event(42, .high, "AP[Workshop] has disconnected", ap: aps[3]),
            event(90, .medium, "Rogue AP detected on channel 6 (SSID: FreeWiFi)", ap: aps[2], kind: .alarm, alarm: "Rogue AP Detected"),
            event(140, .low, "Client[Visitor-iPhone] authenticated via guest pass", ap: aps[1]),
            event(260, .low, "AP[Warehouse] mesh uplink changed to AP[Office Core]", ap: aps[2]),
            event(470, .medium, "AP[Warehouse] joins with uptime [164] s and last disconnected reason [AP Restart : power cycle detect]", ap: aps[2]),
            event(1_300, .low, "Admin[admin] logged in from 192.168.10.56", ap: aps[0]),
            event(2_900, .low, "System configuration backup completed", ap: aps[0]),
        ]
    }
}

/// Small deterministic generator so the demo network looks the same every launch.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
