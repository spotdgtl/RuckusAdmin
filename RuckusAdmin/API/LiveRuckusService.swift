import Foundation

/// Talks to a real Unleashed controller. Request bodies mirror what the stock web UI
/// (`dashboard.js`) sends, so they behave exactly like the equivalent clicks in the browser.
final class LiveRuckusService: RuckusService {
    private let session: RuckusSession
    let displayHost: String

    init(host: String, username: String, password: String) throws {
        session = try RuckusSession(host: host, username: username, password: password)
        displayHost = session.host
    }

    func setLogger(_ logger: (@Sendable (RequestLogEntry) -> Void)?) async {
        await session.setLogger(logger)
    }

    func connect() async throws {
        try await session.login()
    }

    func disconnect() async {
        await session.logout()
    }

    // MARK: Reads

    func fetchSnapshot() async throws -> ControllerSnapshot {
        async let dashboard = session.send(AjaxRequest(
            action: .getstat, component: "stamgr",
            rootAttributes: ["caller": "unleashed_web"],
            body: "<wlan LEVEL='1' PERIOD='3600'/><ap LEVEL='1' PERIOD='3600'/><apsummary/>"
        ))
        // Queried on its own: inside the combined dashboard request the controller returns a
        // slimmer client record without signal strength (dBm) and noise floor.
        async let clientList = session.send(AjaxRequest(
            action: .getstat, component: "stamgr", body: "<client LEVEL='2' client-type='3'/>"
        ))
        async let apDetails = session.send(AjaxRequest(
            action: .getstat, component: "stamgr", body: "<ap LEVEL='2'/>"
        ))
        async let apConfig = session.send(AjaxRequest(
            action: .getconf, component: "ap-list", rootAttributes: ["DECRYPT_X": "false"]
        ))
        async let wlanConfig = session.send(AjaxRequest(
            action: .getconf, component: "wlansvc-list", rootAttributes: ["DECRYPT_X": "false"]
        ))
        async let system = session.send(AjaxRequest(
            action: .getstat, component: "system",
            body: "<sysinfo/><identity/><mgmt-ip/><time/><unleashed-network/><mesh-policy/><admin/><internal-gateway/>"
        ))
        async let systemStats = session.send(AjaxRequest(
            action: .getstat, component: "stamgr", body: "<system LEVEL='1'/>"
        ))
        async let connectStatus = session.send(AjaxRequest(
            action: .docmd, component: "system",
            rootAttributes: ["xcmd": "get-connect-status"],
            body: "<xcmd cmd='get-connect-status'/>"
        ))

        let dashboardResponse = try await dashboard
        let clientResponse = try await clientList
        let detailsResponse = try await apDetails
        let apConfigResponse = try await apConfig
        let wlanConfigResponse = try await wlanConfig
        let systemResponse = try await system
        let systemStatsResponse = try await systemStats
        let connectResponse = try? await connectStatus

        let summaryNode = dashboardResponse.element("apsummary")
        var snapshot = ControllerSnapshot()
        snapshot.system = RuckusParsers.systemInfo(
            stat: systemResponse.response,
            connect: connectResponse?.response,
            summary: summaryNode
        )
        snapshot.totals = RuckusParsers.totals(from: systemStatsResponse.element("system"))
        snapshot.summary = RuckusParsers.summary(from: summaryNode)
        snapshot.accessPoints = RuckusParsers.accessPoints(
            config: apConfigResponse.elements("ap"),
            stats: dashboardResponse.element("apstamgr-stat")?.all("ap") ?? [],
            details: detailsResponse.element("apstamgr-stat")?.all("ap") ?? []
        )
        snapshot.clients = RuckusParsers.clients(from: clientResponse.element("apstamgr-stat")?.all("client") ?? [])
        snapshot.wlans = RuckusParsers.wlans(
            config: wlanConfigResponse.elements("wlansvc"),
            stats: dashboardResponse.element("apstamgr-stat")?.all("wlan") ?? []
        )
        snapshot.fetchedAt = Date()
        LiveRuckusService.fillRadioClientCounts(&snapshot)
        return snapshot
    }

    /// Two cheap requests: AP/fleet statistics and the client list.
    func fetchLiveStats() async throws -> LiveStats {
        async let stats = session.send(AjaxRequest(
            action: .getstat, component: "stamgr",
            rootAttributes: ["caller": "unleashed_web"],
            body: "<ap LEVEL='1' PERIOD='3600'/><apsummary/><system LEVEL='1'/>"
        ))
        async let clientList = session.send(AjaxRequest(
            action: .getstat, component: "stamgr", body: "<client LEVEL='2' client-type='3'/>"
        ))
        let statsResponse = try await stats
        let clientResponse = try await clientList
        var live = LiveStats()
        live.clients = RuckusParsers.clients(from: clientResponse.element("apstamgr-stat")?.all("client") ?? [])
        live.accessPointStats = RuckusParsers.accessPoints(
            config: [], stats: statsResponse.element("apstamgr-stat")?.all("ap") ?? [], details: []
        )
        live.totals = RuckusParsers.totals(from: statsResponse.element("apstamgr-stat")?.first("system"))
        live.summary = RuckusParsers.summary(from: statsResponse.element("apsummary"))
        live.sampledAt = Date()
        return live
    }

    static func fillRadioClientCounts(_ snapshot: inout ControllerSnapshot) {
        for index in snapshot.accessPoints.indices {
            let ap = snapshot.accessPoints[index]
            let clients = snapshot.clients.filter { $0.apMAC == ap.mac }
            for radioIndex in ap.radios.indices {
                let band = ap.radios[radioIndex].band
                snapshot.accessPoints[index].radios[radioIndex].clientCount = clients.filter { $0.band == band }.count
            }
            if snapshot.accessPoints[index].clientCount == 0 {
                snapshot.accessPoints[index].clientCount = clients.count
            }
        }
    }

    func fetchEvents(limit: Int) async throws -> [ControllerEvent] {
        let eventUpdater = AjaxRequest.makeUpdater(component: "eventd")
        let alarmUpdater = AjaxRequest.makeUpdater(component: "eventd")
        async let events = session.send(AjaxRequest(
            action: .getstat, component: "eventd",
            rootAttributes: ["shard-request": "true"],
            body: "<xevent ap='*' sortBy='time' sortDirection='-1'/><pieceStat start='0' number='\(limit)' pid='1' requestId='\(eventUpdater)'/>",
            updater: eventUpdater
        ))
        async let alarms = session.send(AjaxRequest(
            action: .getstat, component: "eventd",
            rootAttributes: ["shard-request": "true"],
            body: "<alarm ap='*' sortBy='time' sortDirection='-1'/><pieceStat start='0' number='\(limit)' pid='1' requestId='\(alarmUpdater)'/>",
            updater: alarmUpdater
        ))
        let eventsResponse = try await events
        let alarmsResponse = try await alarms
        let parsedEvents = RuckusParsers.events(from: eventsResponse.elements("xevent"), kind: .event)
        let parsedAlarms = RuckusParsers.events(from: alarmsResponse.elements("alarm"), kind: .alarm)
        return (parsedAlarms + parsedEvents).sorted { $0.time > $1.time }
    }

    func fetchNeighbors() async throws -> [NeighborNetwork] {
        let response = try await session.send(AjaxRequest(
            action: .getstat, component: "stamgr", body: "<rogue LEVEL='1'/>"
        ))
        return RuckusParsers.neighbors(from: response.elements("rogue"))
    }

    // MARK: Actions (mirroring dashboard.js)

    func restartAccessPoint(mac: String) async throws {
        _ = try await session.send(AjaxRequest(
            action: .docmd, component: "stamgr",
            rootAttributes: ["xcmd": "reset", "check-ability": "2"],
            body: "<xcmd cmd='reset' tag='ap' ap='\(XMLNode.escape(mac))'/>"
        ))
    }

    func blockClient(mac: String, hostname: String) async throws {
        _ = try await session.send(AjaxRequest(
            action: .docmd, component: "stamgr",
            rootAttributes: ["xcmd": "block", "check-ability": "10"],
            body: "<xcmd cmd='block' tag='client'><client client='\(XMLNode.escape(mac))' acl-id='1' hostname='\(XMLNode.escape(hostname))'/></xcmd>"
        ))
    }

    func unblockClient(mac: String) async throws {
        let aclResponse = try await session.send(AjaxRequest(
            action: .getconf, component: "acl-list", rootAttributes: ["DECRYPT_X": "false"]
        ))
        let acls = aclResponse.elements("acl")
        guard let systemACL = acls.first(where: { $0["name"] == "System" }) ?? acls.first(where: { $0["id"] == "1" }) else {
            throw RuckusError.unexpectedResponse("The System ACL was not found, so the client cannot be unblocked.")
        }
        let target = mac.lowercased()
        let remaining = systemACL.all("deny").filter { ($0["mac"] ?? "").lowercased() != target }
        let denyXML = remaining.map { deny in
            let attrs = deny.attributes.sorted { $0.key < $1.key }
                .map { " \($0.key)='\(XMLNode.escape($0.value))'" }.joined()
            return "<deny\(attrs)/>"
        }.joined()
        let id = systemACL["id"] ?? "1"
        let description = systemACL["description"] ?? "System"
        _ = try await session.send(AjaxRequest(
            action: .updobj, component: "acl-list",
            body: "<acl id='\(XMLNode.escape(id))' name='System' description='\(XMLNode.escape(description))' default-mode='allow' EDITABLE='false'>\(denyXML)</acl>"
        ))
    }

    func disconnectClient(mac: String) async throws {
        _ = try await session.send(AjaxRequest(
            action: .docmd, component: "stamgr",
            rootAttributes: ["xcmd": "delete", "check-ability": "2"],
            body: "<xcmd cmd='delete' tag='client' client='\(XMLNode.escape(mac))'/>"
        ))
    }

    func renameClient(mac: String, name: String) async throws {
        _ = try await session.send(AjaxRequest(
            action: .docmd, component: "stamgr",
            rootAttributes: ["xcmd": "rename"],
            body: "<xcmd cmd='rename' tag='client' client='\(XMLNode.escape(mac))' rename='\(XMLNode.escape(name))'/>"
        ))
    }

    func setClientFavourite(mac: String, isFavourite: Bool) async throws {
        _ = try await session.send(AjaxRequest(
            action: .docmd, component: "stamgr",
            rootAttributes: ["xcmd": "stamgr"],
            body: "<xcmd cmd='favourite' tag='client' enable='\(isFavourite ? "1" : "0")' client='\(XMLNode.escape(mac))'/>"
        ))
    }

    func setWLANEnabled(id: String, enabled: Bool) async throws {
        _ = try await session.send(AjaxRequest(
            action: .updobj, component: "wlansvc-list",
            body: "<wlansvc id='\(XMLNode.escape(id))' enable-type='\(enabled ? "0" : "1")' IS_PARTIAL='true'/>"
        ))
    }

    func sendRaw(xml: String, path: String) async throws -> AjaxResponse {
        try await session.sendRaw(xml: xml, path: path)
    }

    // MARK: Configuration

    func fetchSystemConfig(elements: [String], action: AjaxRequest.Action) async throws -> XMLNode {
        let body = elements.map { "<\($0)/>" }.joined()
        let response = try await session.send(AjaxRequest(action: action, component: "system", body: body))
        return response.response ?? response.root
    }

    func applySystemConfig(body: String) async throws {
        _ = try await session.send(AjaxRequest(action: .setconf, component: "system", body: body))
    }

    func fetchListRows(component: String, element: String, action: AjaxRequest.Action, decrypt: Bool, statBody: String?, idAttribute: String) async throws -> [ListRow] {
        let response: AjaxResponse
        if let statBody {
            response = try await session.send(AjaxRequest(action: .getstat, component: component, body: statBody))
        } else {
            response = try await session.send(AjaxRequest(action: action, component: component, rootAttributes: ["DECRYPT_X": decrypt ? "true" : "false"]))
        }
        return LiveRuckusService.rows(from: response.elements(element), idAttribute: idAttribute)
    }

    static func rows(from nodes: [XMLNode], idAttribute: String) -> [ListRow] {
        nodes.enumerated().map { index, node in
            let id = node[idAttribute].flatMap { $0.isEmpty ? nil : $0 } ?? node["mac"] ?? node["name"] ?? "row-\(index)"
            return ListRow(id: id, attributes: RuckusParsers.cleanedAttributes(node.attributes), children: node.children)
        }
    }

    func addObject(component: String, body: String) async throws {
        _ = try await session.send(AjaxRequest(action: .addobj, component: component, body: body))
    }

    func updateObject(component: String, body: String) async throws {
        _ = try await session.send(AjaxRequest(action: .updobj, component: component, body: body))
    }

    func deleteObject(component: String, body: String) async throws {
        _ = try await session.send(AjaxRequest(action: .delobj, component: component, body: body))
    }

    func runCommand(component: String, xcmd: String, body: String, rootAttributes: [String: String]) async throws -> AjaxResponse {
        var attrs = rootAttributes
        attrs["xcmd"] = xcmd
        return try await session.send(AjaxRequest(action: .docmd, component: component, rootAttributes: attrs, body: body))
    }

    func downloadFile(path: String) async throws -> Data {
        let (data, http) = try await session.get(path: path)
        guard (200..<300).contains(http.statusCode) else {
            throw RuckusError.httpStatus(http.statusCode, body: String(decoding: data.prefix(500), as: UTF8.self))
        }
        return data
    }

    func adminAction(command: String, parameters: [String: String]) async throws -> String {
        var query = parameters
        query["cmd"] = command
        let (data, http) = try await session.get(path: "/admin/webPage/system/admin/admin_performed.jsp", query: query)
        let text = String(decoding: data, as: UTF8.self)
        guard (200..<300).contains(http.statusCode) else {
            throw RuckusError.httpStatus(http.statusCode, body: text)
        }
        return text
    }
}
