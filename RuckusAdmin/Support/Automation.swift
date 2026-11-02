import Foundation

/// Headless mode for scripting and testing:
///
///     RuckusAdmin --set network-management log.level=2
///
/// Connects with the stored credentials, loads the named settings page, applies the given
/// `path.attribute=value` assignments through the same code the UI uses, reads the page back,
/// prints what happened (including the raw request and reply) and exits.
struct AutomationCommand {
    struct Assignment {
        var path: String
        var key: String
        var value: String
    }

    var pageID: String
    var assignments: [Assignment]

    static func parse(_ arguments: [String]) -> AutomationCommand? {
        guard let index = arguments.firstIndex(of: "--set"), index + 1 < arguments.count else { return nil }
        let pageID = arguments[index + 1]
        var assignments: [Assignment] = []
        for argument in arguments[(index + 2)...] {
            guard let equals = argument.lastIndex(of: "="), let dot = argument[..<equals].lastIndex(of: ".") else { continue }
            assignments.append(Assignment(
                path: String(argument[..<dot]),
                key: String(argument[argument.index(after: dot)..<equals]),
                value: String(argument[argument.index(after: equals)...])
            ))
        }
        return AutomationCommand(pageID: pageID, assignments: assignments)
    }
}

@MainActor
enum LiveProbe {
    /// `--probe-live`: takes two samples a few seconds apart and prints which counters changed.
    static func run(store: ControllerStore) async {
        var lines: [String] = []
        defer {
            print(lines.joined(separator: "\n"))
            fflush(stdout)
            exit(0)
        }
        for _ in 0..<60 where !store.isConnected { try? await Task.sleep(for: .milliseconds(500)) }
        guard store.isConnected else { lines.append("ERROR not connected"); return }
        func sample() async -> [String: String] {
            var out: [String: String] = [:]
            do {
                let aps = try await store.runCommandRaw(action: .getstat, component: "stamgr", body: "<ap LEVEL='2'/>")
                for ap in aps.elements("ap") {
                    let mac = ap["mac"] ?? "?"
                    for key in ["sta_tx_byte", "sta_rx_byte", "lan_stats_rx_byte", "lan_stats_tx_byte", "uptime-updatetime", "last-seen"] {
                        out["ap \(mac) \(key)"] = ap[key] ?? "-"
                    }
                    for iface in ap.all("if") {
                        let name = iface["if-name"] ?? "?"
                        out["ap \(mac) if \(name) in"] = iface["if-inOctets"] ?? "-"
                        out["ap \(mac) if \(name) out"] = iface["if-outOctets"] ?? "-"
                    }
                }
                let clients = try await store.runCommandRaw(action: .getstat, component: "stamgr", body: "<client LEVEL='2' client-type='3'/>")
                for client in clients.elements("client") {
                    let mac = client["mac"] ?? "?"
                    for key in ["total-rx-bytes", "total-tx-bytes", "total-rx-pkts", "total-tx-pkts", "rssi", "num-interval-stats"] {
                        out["client \(mac) \(key)"] = client[key] ?? "-"
                    }
                }
                let system = try await store.runCommandRaw(action: .getstat, component: "stamgr", body: "<system LEVEL='1'/>")
                if let node = system.element("system") {
                    for key in ["rx-bytes", "tx-bytes", "total-rx-bytes", "total-tx-bytes", "last-update-timestamp"] {
                        out["system \(key)"] = node[key] ?? "-"
                    }
                    for eth in node.all("eth") {
                        out["system eth \(eth["ethname"] ?? "?") in"] = eth["inbytes"] ?? "-"
                        out["system eth \(eth["ethname"] ?? "?") out"] = eth["outbytes"] ?? "-"
                    }
                }
            } catch {
                out["error"] = error.localizedDescription
            }
            return out
        }
        let first = await sample()
        let t0 = Date()
        try? await Task.sleep(for: .seconds(5))
        let second = await sample()
        let elapsed = Date().timeIntervalSince(t0)
        lines.append(String(format: "elapsed %.1f s", elapsed))
        for key in first.keys.sorted() {
            let a = first[key] ?? "-"
            let b = second[key] ?? "-"
            lines.append("\(a == b ? "same   " : "CHANGED") \(key): \(a) -> \(b)")
        }
    }
}

@MainActor
enum AutomationRunner {
    static func run(_ command: AutomationCommand, store: ControllerStore) async {
        var lines: [String] = []
        defer {
            print(lines.joined(separator: "\n"))
            fflush(stdout)
            exit(0)
        }
        // Wait for the automatic connection (Keychain password) to settle.
        for _ in 0..<60 where !store.isConnected {
            if case .failed(let message) = store.phase {
                lines.append("ERROR connection failed: \(message)")
                return
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        guard store.isConnected else {
            lines.append("ERROR not connected (no stored password?)")
            return
        }
        guard let page = SettingsCatalog.allConfigPages.first(where: { $0.id == command.pageID }) else {
            lines.append("ERROR unknown page '\(command.pageID)'. Known: \(SettingsCatalog.allConfigPages.map(\.id).joined(separator: ", "))")
            return
        }
        do {
            let original = try await store.loadConfig(page)
            lines.append("BEFORE " + describe(original, page: page, keys: command.assignments))
            var values = original
            for assignment in command.assignments {
                values[assignment.path, assignment.key] = assignment.value
            }
            let logCountBefore = store.requestLog.count
            try await store.applyConfig(page, values: values, original: original)
            let newEntries = store.requestLog.prefix(max(0, store.requestLog.count - logCountBefore))
            for entry in newEntries.reversed() where entry.requestXML.contains("action='setconf'") || entry.requestXML.contains("action='updobj'") {
                lines.append("REQUEST  " + entry.requestXML)
                lines.append("RESPONSE " + entry.responseText.replacingOccurrences(of: "\n", with: " ").prefix(400))
                if let error = entry.error { lines.append("ERROR " + error) }
            }
            let reloaded = try await store.loadConfig(page)
            lines.append("AFTER  " + describe(reloaded, page: page, keys: command.assignments))
        } catch {
            lines.append("ERROR \(error.localizedDescription)")
        }
    }

    private static func describe(_ values: ConfigValues, page: ConfigPageSpec, keys: [AutomationCommand.Assignment]) -> String {
        keys.map { "\($0.path).\($0.key)=\(values[$0.path, $0.key])" }.joined(separator: " ")
    }
}
