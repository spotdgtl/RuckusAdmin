import Foundation
import Observation

struct PendingCertificate: Equatable, Sendable {
    var host: String
    var expected: String
    var actual: String
}

struct BandCount: Identifiable, Hashable, Sendable {
    var id: RadioBand { band }
    var band: RadioBand
    var count: Int
}

/// Owns the connection to one controller, polls it, and exposes the latest data to the UI.
@MainActor
@Observable
final class ControllerStore {
    enum Phase: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    var phase: Phase = .disconnected
    var isDemo = false
    var snapshot = ControllerSnapshot()
    var hasSnapshot = false
    var events: [ControllerEvent] = []
    var neighbors: [NeighborNetwork] = []
    /// Navigation requests from the dashboard: the target view consumes and clears them.
    var focusAccessPointMAC: String?
    var focusClientMAC: String?
    var focusAlarmsOnly = false
    /// Live mode: throughput derived from byte counters sampled every few seconds.
    var liveSamples: [LiveSample] = []
    var clientRates: [String: ClientRate] = [:]
    var lastLiveSample: Date?
    @ObservationIgnored private var liveTask: Task<Void, Never>?
    @ObservationIgnored private var previousLive: (time: Date, clients: [String: (Int64, Int64)], rx: Int64, tx: Int64)?
    @ObservationIgnored private var clientCounterHistory: [String: (time: Date, rx: Int64, tx: Int64)] = [:]
    /// Which Ethernet port(s) the live throughput is measured on.
    var liveSource = ""
    var lastUpdated: Date?
    var lastError: String?
    var isRefreshing = false
    var consecutiveFailures = 0
    var requestLog: [RequestLogEntry] = []
    var pendingCertificate: PendingCertificate?
    var settings: ConnectionSettings {
        didSet { settings.save() }
    }

    @ObservationIgnored private var service: (any RuckusService)?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var refreshCount = 0

    var isLive: Bool { settings.liveMode && isConnected }

    init() {
        settings = ConnectionSettings.load()
    }

    // MARK: Derived data

    var system: SystemInfo { snapshot.system }
    var accessPoints: [AccessPoint] { snapshot.accessPoints }
    var clients: [WirelessClient] { snapshot.clients }
    var wlans: [WLAN] { snapshot.wlans }
    var totals: ControllerTotals { snapshot.totals }
    var summary: APSummary { snapshot.summary }
    var alarms: [ControllerEvent] { events.filter { $0.kind == .alarm } }
    var isConnected: Bool { phase == .connected }

    var displayName: String {
        if isDemo { return "Demo network" }
        return system.name.isEmpty ? settings.host : system.name
    }

    var onlineAccessPointCount: Int {
        accessPoints.filter(\.isOnline).count
    }

    func clients(forAccessPoint mac: String) -> [WirelessClient] {
        clients.filter { $0.apMAC == mac }
    }

    func clients(forWLAN wlan: WLAN) -> [WirelessClient] {
        clients.filter { ($0.wlanID == wlan.id && !wlan.id.isEmpty) || $0.ssid == wlan.ssid }
    }

    func accessPoint(mac: String) -> AccessPoint? {
        accessPoints.first { $0.mac == mac }
    }

    var clientsByBand: [BandCount] {
        RadioBand.allCases.compactMap { band in
            let count = clients.filter { $0.band == band }.count
            return count > 0 ? BandCount(band: band, count: count) : nil
        }
    }

    // MARK: Connection lifecycle

    /// Reconnects at launch using the password stored in the Keychain, when there is one.
    func connectIfPossible() async {
        guard phase == .disconnected, settings.autoConnect,
              !settings.host.isEmpty, !settings.username.isEmpty else { return }
        let host = settings.host
        let username = settings.username
        let password = await Task.detached(priority: .userInitiated) {
            KeychainStore.password(host: host, username: username)
        }.value
        guard let password, phase == .disconnected else { return }
        await connect(host: host, username: username, password: password, rememberPassword: true)
    }

    func connect(host: String, username: String, password: String, rememberPassword: Bool) async {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        pollTask?.cancel()
        phase = .connecting
        lastError = nil
        pendingCertificate = nil
        isDemo = false
        settings.host = host
        settings.username = username
        settings.rememberPassword = rememberPassword

        do {
            let live = try LiveRuckusService(host: host, username: username, password: password)
            await live.setLogger { [weak self] entry in
                Task { @MainActor in self?.appendLog(entry) }
            }
            try await live.connect()
            service = live
            if rememberPassword {
                try? KeychainStore.savePassword(password, host: host, username: username)
            } else {
                KeychainStore.deletePassword(host: host, username: username)
            }
            phase = .connected
            startPolling()
            if settings.liveMode { startLive() }
        } catch let error as RuckusError {
            if case .certificateMismatch(let host, let expected, let actual) = error {
                pendingCertificate = PendingCertificate(host: host, expected: expected, actual: actual)
            }
            phase = .failed(error.localizedDescription)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func trustPendingCertificate(password: String) async {
        guard let pending = pendingCertificate else { return }
        CertificateTrustStore.shared.trust(fingerprint: pending.actual, for: pending.host)
        pendingCertificate = nil
        await connect(host: settings.host, username: settings.username, password: password, rememberPassword: settings.rememberPassword)
    }

    func startDemo() {
        pollTask?.cancel()
        let demo = DemoRuckusService()
        service = demo
        isDemo = true
        lastError = nil
        pendingCertificate = nil
        phase = .connected
        Task { [weak self] in
            await demo.setLogger { entry in
                Task { @MainActor in self?.appendLog(entry) }
            }
        }
        startPolling()
        if settings.liveMode { startLive() }
    }

    func disconnect() async {
        pollTask?.cancel()
        pollTask = nil
        stopLive()
        liveSamples = []
        lastLiveSample = nil
        if let service {
            await service.disconnect()
        }
        service = nil
        phase = .disconnected
        isDemo = false
        hasSnapshot = false
        snapshot = ControllerSnapshot()
        events = []
        neighbors = []
        lastUpdated = nil
        lastError = nil
        consecutiveFailures = 0
    }

    func forgetStoredPassword() {
        KeychainStore.deletePassword(host: settings.host, username: settings.username)
    }

    var hasStoredPassword: Bool {
        KeychainStore.hasPassword(host: settings.host, username: settings.username)
    }

    private func startPolling() {
        pollTask?.cancel()
        refreshCount = 0
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                let interval = max(5, self.settings.pollInterval)
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func restartPolling() {
        guard isConnected else { return }
        startPolling()
    }

    // MARK: Live mode

    func setLiveMode(_ enabled: Bool) {
        settings.liveMode = enabled
        if enabled { startLive() } else { stopLive() }
    }

    private func startLive() {
        liveTask?.cancel()
        previousLive = nil
        liveSamples = []
        clientRates = [:]
        guard isConnected else { return }
        liveTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.liveTick()
                let interval = max(1, self.settings.liveInterval)
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    private func stopLive() {
        liveTask?.cancel()
        liveTask = nil
        previousLive = nil
        clientRates = [:]
        clientCounterHistory = [:]
    }

    private func liveTick() async {
        guard let service, isConnected, !isRefreshing else { return }
        do {
            let live = try await service.fetchLiveStats()
            applyLiveStats(live)
        } catch {
            handle(error)
        }
    }

    private func applyLiveStats(_ live: LiveStats) {
        // Merge lightweight AP stats into the existing (detailed) access points.
        var aps = snapshot.accessPoints
        for stat in live.accessPointStats {
            guard let index = aps.firstIndex(where: { $0.mac == stat.mac }) else { continue }
            aps[index].state = stat.state
            aps[index].lastSeen = stat.lastSeen ?? aps[index].lastSeen
            aps[index].clientCount = stat.clientCount
            if !stat.radios.isEmpty { aps[index].radios = stat.radios }
            if !stat.history.isEmpty { aps[index].history = stat.history }
        }
        snapshot.accessPoints = aps
        snapshot.clients = live.clients
        snapshot.totals = live.totals
        snapshot.summary = live.summary
        LiveRuckusService.fillRadioClientCounts(&snapshot)
        hasSnapshot = true
        lastUpdated = live.sampledAt
        lastLiveSample = live.sampledAt

        // Real-time throughput: the master AP's Ethernet port counters are the only values the
        // controller updates on every request (wireless and client counters refresh about once
        // a minute). In gateway mode the WAN port carries all internet traffic.
        let ports = live.totals.ethernetPorts.filter(\.isUp)
        let selected: [EthernetPort]
        if system.gatewayModeEnabled, let wan = ports.first(where: { $0.interfaceName == system.wanPort }) {
            selected = [wan]
        } else {
            selected = ports
        }
        let inBytes = selected.reduce(Int64(0)) { $0 + $1.inBytes }
        let outBytes = selected.reduce(Int64(0)) { $0 + $1.outBytes }
        if let previous = previousLive {
            let seconds = live.sampledAt.timeIntervalSince(previous.time)
            if seconds >= 0.5 {
                let down = Double(max(0, inBytes - previous.rx)) * 8 / seconds
                let up = Double(max(0, outBytes - previous.tx)) * 8 / seconds
                liveSamples.append(LiveSample(time: live.sampledAt, downloadBitsPerSecond: down, uploadBitsPerSecond: up))
                if liveSamples.count > 240 {
                    liveSamples.removeFirst(liveSamples.count - 240)
                }
            }
        }
        previousLive = (live.sampledAt, [:], inBytes, outBytes)
        liveSource = selected.map(\.name).joined(separator: " + ")

        // Per-client rates: counters change roughly once a minute, so compute the average
        // over the interval between two changes and keep it until the next change.
        for client in live.clients {
            let rx = client.rxBytes ?? 0
            let tx = client.txBytes ?? 0
            if let tracked = clientCounterHistory[client.mac] {
                if rx != tracked.rx || tx != tracked.tx {
                    let seconds = live.sampledAt.timeIntervalSince(tracked.time)
                    if seconds >= 1 {
                        clientRates[client.mac] = ClientRate(
                            downloadBitsPerSecond: Double(max(0, tx - tracked.tx)) * 8 / seconds,
                            uploadBitsPerSecond: Double(max(0, rx - tracked.rx)) * 8 / seconds
                        )
                    }
                    clientCounterHistory[client.mac] = (live.sampledAt, rx, tx)
                }
            } else {
                clientCounterHistory[client.mac] = (live.sampledAt, rx, tx)
            }
        }
        let present = Set(live.clients.map(\.mac))
        clientCounterHistory = clientCounterHistory.filter { present.contains($0.key) }
        clientRates = clientRates.filter { present.contains($0.key) }
    }

    // MARK: Refresh

    func refresh(includeEvents: Bool = false) async {
        guard let service, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let fresh = try await service.fetchSnapshot()
            snapshot = fresh
            hasSnapshot = true
            lastUpdated = Date()
            lastError = nil
            consecutiveFailures = 0
            refreshCount += 1
            if includeEvents || refreshCount % 3 == 1 {
                await refreshEvents()
            }
            if refreshCount % 3 == 2 || (refreshCount == 1 && neighbors.isEmpty) {
                await refreshNeighbors()
            }
        } catch {
            handle(error)
        }
    }

    func refreshEvents() async {
        guard let service else { return }
        do {
            events = try await service.fetchEvents(limit: 300)
        } catch {
            handle(error)
        }
    }

    func refreshNeighbors() async {
        guard let service else { return }
        do {
            var fresh = try await service.fetchNeighbors()
            let ownSSIDs = Set(wlans.map(\.ssid).filter { !$0.isEmpty })
            let ownPrefixes = Set(accessPoints.map { String($0.mac.prefix(11)) })
            for index in fresh.indices {
                let prefix = String(fresh[index].mac.prefix(11))
                fresh[index].isOwnNetwork = ownSSIDs.contains(fresh[index].ssid) && ownPrefixes.contains(prefix)
            }
            neighbors = fresh.sorted { $0.bestSignal > $1.bestSignal }
        } catch {
            handle(error)
        }
    }

    private func handle(_ error: Error) {
        consecutiveFailures += 1
        lastError = error.localizedDescription
        guard let ruckusError = error as? RuckusError else { return }
        switch ruckusError {
        case .invalidCredentials, .sessionExpired:
            pollTask?.cancel()
            stopLive()
            phase = .failed(ruckusError.localizedDescription)
        case .certificateMismatch(let host, let expected, let actual):
            pendingCertificate = PendingCertificate(host: host, expected: expected, actual: actual)
            pollTask?.cancel()
            phase = .failed(ruckusError.localizedDescription)
        default:
            break
        }
    }

    // MARK: Actions

    private func requireService() throws -> any RuckusService {
        guard let service else { throw RuckusError.notLoggedIn }
        return service
    }

    func serviceForTools() throws -> any RuckusService {
        try requireService()
    }

    func restartAccessPoint(_ ap: AccessPoint) async throws {
        try await requireService().restartAccessPoint(mac: ap.mac)
        await refresh()
    }

    func blockClient(_ client: WirelessClient) async throws {
        try await requireService().blockClient(mac: client.mac, hostname: client.hostname)
        await refresh()
    }

    func unblockClient(_ client: WirelessClient) async throws {
        try await requireService().unblockClient(mac: client.mac)
        await refresh()
    }

    func disconnectClient(_ client: WirelessClient) async throws {
        try await requireService().disconnectClient(mac: client.mac)
        await refresh()
    }

    func renameClient(_ client: WirelessClient, to name: String) async throws {
        try await requireService().renameClient(mac: client.mac, name: name)
        await refresh()
    }

    func setFavourite(_ client: WirelessClient, _ isFavourite: Bool) async throws {
        try await requireService().setClientFavourite(mac: client.mac, isFavourite: isFavourite)
        await refresh()
    }

    func setWLAN(_ wlan: WLAN, enabled: Bool) async throws {
        try await requireService().setWLANEnabled(id: wlan.id, enabled: enabled)
        await refresh()
    }

    func sendRaw(xml: String, path: String) async throws -> AjaxResponse {
        try await requireService().sendRaw(xml: xml, path: path)
    }

    // MARK: Configuration pages

    func loadConfig(_ spec: ConfigPageSpec) async throws -> ConfigValues {
        let service = try requireService()
        let root = try await service.fetchSystemConfig(elements: spec.readElements, action: spec.readAction)
        var lists: [String: XMLNode] = [:]
        for read in spec.listReads {
            let rows = try await service.fetchListRows(component: read.component, element: read.element, action: .getconf, decrypt: read.decrypt, statBody: nil, idAttribute: "id")
            if let first = rows.first {
                lists[read.alias] = XMLNode(name: read.element, attributes: first.attributes, children: first.children)
            }
        }
        return ConfigPath.read(spec: spec, from: root, lists: lists)
    }

    func applyConfig(_ spec: ConfigPageSpec, values: ConfigValues, original: ConfigValues) async throws {
        let service = try requireService()
        var systemBody = ""
        for write in spec.writes {
            let xml = ConfigPath.xml(for: write, spec: spec, values: values, original: original)
            guard !xml.isEmpty else { continue }
            switch write.kind {
            case .systemSetconf:
                systemBody += xml
            case .updobj(let component):
                try await service.updateObject(component: component, body: xml)
            }
        }
        if !systemBody.isEmpty {
            try await service.applySystemConfig(body: systemBody)
        }
        await refresh()
    }

    func loadOptions(_ options: DynamicOptions) async throws -> [ConfigOption] {
        var result: [ConfigOption] = []
        if let none = options.includeNone { result.append(none) }
        switch options.source {
        case .accessPoints:
            result += accessPoints.map { ConfigOption($0.mac, "\($0.displayName) (\(Format.mac($0.mac)))") }
        case .list(let component, let element, let valueAttribute, let labelAttribute):
            let rows = try await requireService().fetchListRows(component: component, element: element, action: .getconf, decrypt: false, statBody: nil, idAttribute: valueAttribute)
            result += rows.map { ConfigOption($0[valueAttribute], $0[labelAttribute].isEmpty ? $0[valueAttribute] : $0[labelAttribute]) }
        }
        return result
    }

    func loadList(_ spec: ListPageSpec) async throws -> [ListRow] {
        try await requireService().fetchListRows(component: spec.component, element: spec.element, action: spec.readAction,
                                                 decrypt: spec.decrypt, statBody: spec.statBody, idAttribute: spec.idAttribute)
    }

    func addRow(_ spec: ListPageSpec, values: [String: String]) async throws {
        let attrs = values.sorted { $0.key < $1.key }.filter { !$0.value.isEmpty || !$0.key.hasPrefix("x-") }.map { ($0.key, $0.value) }
        try await requireService().addObject(component: spec.component, body: "<\(spec.element)\(ConfigPath.attributeString(attrs))/>")
    }

    func updateRow(_ spec: ListPageSpec, row: ListRow, values: [String: String]) async throws {
        var attrs: [(String, String)] = [(spec.idAttribute, row.id)]
        for (key, value) in values.sorted(by: { $0.key < $1.key }) where key != spec.idAttribute {
            if key.hasPrefix("x-") && value.isEmpty { continue }
            attrs.append((key, value))
        }
        attrs.append(("IS_PARTIAL", "true"))
        try await requireService().updateObject(component: spec.component, body: "<\(spec.element)\(ConfigPath.attributeString(attrs))/>")
    }

    func deleteRow(_ spec: ListPageSpec, row: ListRow) async throws {
        try await requireService().deleteObject(component: spec.component, body: "<\(spec.element) \(spec.idAttribute)='\(XMLNode.escape(row.id))'/>")
    }

    /// Sends any read request (used by diagnostics and probes).
    func runCommandRaw(action: AjaxRequest.Action, component: String, body: String) async throws -> AjaxResponse {
        let request = AjaxRequest(action: action, component: component, body: body)
        return try await sendRaw(xml: request.xml(updater: AjaxRequest.makeUpdater(component: component)), path: action.path)
    }

    func runCommand(component: String, xcmd: String, body: String, rootAttributes: [String: String] = [:]) async throws -> AjaxResponse {
        try await requireService().runCommand(component: component, xcmd: xcmd, body: body, rootAttributes: rootAttributes)
    }

    func downloadFile(path: String) async throws -> Data {
        try await requireService().downloadFile(path: path)
    }

    func adminAction(command: String, parameters: [String: String] = [:]) async throws -> String {
        try await requireService().adminAction(command: command, parameters: parameters)
    }

    // MARK: Request log

    func appendLog(_ entry: RequestLogEntry) {
        requestLog.insert(entry, at: 0)
        if requestLog.count > 200 {
            requestLog.removeLast(requestLog.count - 200)
        }
    }

    func clearLog() {
        requestLog.removeAll()
    }
}
