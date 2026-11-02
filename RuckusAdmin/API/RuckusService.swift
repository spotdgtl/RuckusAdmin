import Foundation

struct EthernetPort: Sendable, Hashable, Identifiable {
    var id: String
    var name: String
    var interfaceName: String
    var speed: String
    var isUp: Bool
    var inBytes: Int64
    var outBytes: Int64
    var mac: String
}

/// Network-wide counters from `<system LEVEL='1'/>` in the station manager.
struct ControllerTotals: Sendable, Hashable {
    var accessPointCount = 0
    var clientCount = 0
    var rogueCount = 0
    var rxBytesTotal: Int64 = 0
    var txBytesTotal: Int64 = 0
    var rxBytesToday: Int64 = 0
    var txBytesToday: Int64 = 0
    var rxBytesLastHour: Int64 = 0
    var txBytesLastHour: Int64 = 0
    var averageRSSI: Int?
    var apRebootsToday = 0
    var heartbeatLossesToday = 0
    var ethernetPorts: [EthernetPort] = []
}

/// The `<apsummary>` element: fleet counts plus a one-minute traffic history.
struct APSummary: Sendable, Hashable {
    var connected = 0
    var disconnected = 0
    var maxAccessPoints: Int?
    var maxClients: Int?
    var history = TrafficHistory()
    var historyByBand: [RadioBand: TrafficHistory] = [:]
}

struct ControllerSnapshot: Sendable {
    var system = SystemInfo()
    var accessPoints: [AccessPoint] = []
    var clients: [WirelessClient] = []
    var wlans: [WLAN] = []
    var totals = ControllerTotals()
    var summary = APSummary()
    var fetchedAt = Date()
}

/// The lightweight statistics polled by Live mode (two requests, no configuration reads).
struct LiveStats: Sendable {
    var clients: [WirelessClient] = []
    var accessPointStats: [AccessPoint] = []
    var totals = ControllerTotals()
    var summary = APSummary()
    var sampledAt = Date()
}

/// Throughput derived from consecutive byte-counter samples.
struct LiveSample: Sendable, Hashable, Identifiable {
    var id: Date { time }
    var time: Date
    var downloadBitsPerSecond: Double
    var uploadBitsPerSecond: Double
}

struct ClientRate: Sendable, Hashable {
    var downloadBitsPerSecond: Double
    var uploadBitsPerSecond: Double
}

struct RequestLogEntry: Sendable, Identifiable {
    var id = UUID()
    var timestamp = Date()
    var path: String
    var requestXML: String
    var responseText: String
    var status: Int
    var duration: TimeInterval
    var error: String?
}

/// Everything the UI needs from a controller. `LiveRuckusService` talks to a real
/// Unleashed network; `DemoRuckusService` serves generated data.
protocol RuckusService: Sendable {
    var displayHost: String { get }
    func connect() async throws
    func disconnect() async
    func fetchSnapshot() async throws -> ControllerSnapshot
    func fetchLiveStats() async throws -> LiveStats
    func fetchEvents(limit: Int) async throws -> [ControllerEvent]
    func fetchNeighbors() async throws -> [NeighborNetwork]
    func restartAccessPoint(mac: String) async throws
    func blockClient(mac: String, hostname: String) async throws
    func unblockClient(mac: String) async throws
    func disconnectClient(mac: String) async throws
    func renameClient(mac: String, name: String) async throws
    func setClientFavourite(mac: String, isFavourite: Bool) async throws
    func setWLANEnabled(id: String, enabled: Bool) async throws
    func sendRaw(xml: String, path: String) async throws -> AjaxResponse
    // Configuration
    func fetchSystemConfig(elements: [String], action: AjaxRequest.Action) async throws -> XMLNode
    func applySystemConfig(body: String) async throws
    func fetchListRows(component: String, element: String, action: AjaxRequest.Action, decrypt: Bool, statBody: String?, idAttribute: String) async throws -> [ListRow]
    func addObject(component: String, body: String) async throws
    func updateObject(component: String, body: String) async throws
    func deleteObject(component: String, body: String) async throws
    func runCommand(component: String, xcmd: String, body: String, rootAttributes: [String: String]) async throws -> AjaxResponse
    func downloadFile(path: String) async throws -> Data
    func adminAction(command: String, parameters: [String: String]) async throws -> String
    func setLogger(_ logger: (@Sendable (RequestLogEntry) -> Void)?) async
}
