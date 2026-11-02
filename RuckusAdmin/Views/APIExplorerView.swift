import SwiftUI

struct APIPreset: Identifiable {
    var id: String { name }
    var name: String
    var path: String
    var xml: String

    static let all: [APIPreset] = [
        APIPreset(name: "Dashboard stats (WLANs, APs, clients)", path: "/admin/_cmdstat.jsp",
                  xml: "<ajax-request action='getstat' caller='unleashed_web' updater='stamgr.0.1' comp='stamgr'>\n  <wlan LEVEL='1' PERIOD='3600'/>\n  <ap LEVEL='1' PERIOD='3600'/>\n  <client LEVEL='1' client-type='3'/>\n  <apsummary/>\n</ajax-request>"),
        APIPreset(name: "Access point details", path: "/admin/_cmdstat.jsp",
                  xml: "<ajax-request action='getstat' updater='stamgr.0.2' comp='stamgr'>\n  <ap LEVEL='2'/>\n</ajax-request>"),
        APIPreset(name: "Clients (detailed)", path: "/admin/_cmdstat.jsp",
                  xml: "<ajax-request action='getstat' updater='stamgr.0.3' comp='stamgr'>\n  <client LEVEL='2' client-type='3'/>\n</ajax-request>"),
        APIPreset(name: "System info", path: "/admin/_cmdstat.jsp",
                  xml: "<ajax-request action='getstat' updater='system.0.4' comp='system'>\n  <sysinfo/><identity/><mgmt-ip/><time/><unleashed-network/><mesh-policy/><admin/>\n</ajax-request>"),
        APIPreset(name: "Network totals", path: "/admin/_cmdstat.jsp",
                  xml: "<ajax-request action='getstat' updater='stamgr.0.5' comp='stamgr'>\n  <system LEVEL='1'/>\n</ajax-request>"),
        APIPreset(name: "Mesh view", path: "/admin/_cmdstat.jsp",
                  xml: "<ajax-request action='getstat' updater='stamgr.0.6' comp='stamgr'>\n  <meshview/>\n</ajax-request>"),
        APIPreset(name: "Internet connection status", path: "/admin/_cmdstat.jsp",
                  xml: "<ajax-request action='docmd' xcmd='get-connect-status' updater='system.0.7' comp='system'>\n  <xcmd cmd='get-connect-status'/>\n</ajax-request>"),
        APIPreset(name: "Events (latest 50)", path: "/admin/_cmdstat.jsp",
                  xml: "<ajax-request action='getstat' shard-request='true' updater='eventd.0.8' comp='eventd'>\n  <xevent ap='*' sortBy='time' sortDirection='-1'/>\n  <pieceStat start='0' number='50' pid='1' requestId='eventd.0.8'/>\n</ajax-request>"),
        APIPreset(name: "Alarms", path: "/admin/_cmdstat.jsp",
                  xml: "<ajax-request action='getstat' shard-request='true' updater='eventd.0.9' comp='eventd'>\n  <alarm ap='*' sortBy='time' sortDirection='-1'/>\n  <pieceStat start='0' number='50' pid='1' requestId='eventd.0.9'/>\n</ajax-request>"),
        APIPreset(name: "AP configuration list", path: "/admin/_conf.jsp",
                  xml: "<ajax-request action='getconf' DECRYPT_X='false' updater='ap-list.0.10' comp='ap-list'/>"),
        APIPreset(name: "WLAN configuration list", path: "/admin/_conf.jsp",
                  xml: "<ajax-request action='getconf' DECRYPT_X='false' updater='wlansvc-list.0.11' comp='wlansvc-list'/>"),
        APIPreset(name: "AP groups", path: "/admin/_conf.jsp",
                  xml: "<ajax-request action='getconf' DECRYPT_X='false' updater='apgroup-list.0.12' comp='apgroup-list'/>"),
        APIPreset(name: "Access control lists (blocked clients)", path: "/admin/_conf.jsp",
                  xml: "<ajax-request action='getconf' DECRYPT_X='false' updater='acl-list.0.13' comp='acl-list'/>"),
        APIPreset(name: "System configuration (WAN, guest access)", path: "/admin/_conf.jsp",
                  xml: "<ajax-request action='getconf' updater='system.0.14' comp='system'>\n  <WAN/><mgmt-ip/><guest-access/><internal-gateway/><adv-radio/>\n</ajax-request>"),
        APIPreset(name: "Firmware / upgrade state", path: "/admin/_cmdstat.jsp",
                  xml: "<ajax-request action='docmd' xcmd='unleashed_query_upgrade_state' updater='system.0.15' comp='system'>\n  <xcmd cmd='unleashed_query_upgrade_state'/>\n</ajax-request>"),
    ]
}

struct APIExplorerView: View {
    @Environment(ControllerStore.self) private var store
    @State private var path = "/admin/_cmdstat.jsp"
    @State private var requestXML = APIPreset.all[0].xml
    @State private var responseText = ""
    @State private var statusLine = ""
    @State private var isSending = false
    @State private var confirmMutating = false
    @State private var selectedLog: RequestLogEntry.ID?

    private var isMutating: Bool {
        let lower = requestXML.lowercased()
        return ["action='setconf'", "action='updobj'", "action='addobj'", "action='delobj'", "action='delallobj'",
                "action=\"setconf\"", "action=\"updobj\"", "action=\"addobj\"", "action=\"delobj\"", "action=\"delallobj\""]
            .contains { lower.contains($0) }
            || (lower.contains("action='docmd'") && !lower.contains("get-connect-status") && !lower.contains("unleashed_query_upgrade_state") && !lower.contains("unleashed_get_upgrade_image_info"))
    }

    var body: some View {
        HSplitView {
            requestPane
                .frame(minWidth: 380)
            responsePane
                .frame(minWidth: 380)
        }
        .navigationTitle("API Explorer")
        .navigationSubtitle(store.isDemo ? "Demo mode: requests are not sent" : "Raw access to the controller's AJAX API")
        .confirmationDialog("Send a request that changes configuration?", isPresented: $confirmMutating, titleVisibility: .visible) {
            Button("Send", role: .destructive) { send() }
        } message: {
            Text("This request uses a mutating action. Make sure the XML is exactly what you intend.")
        }
    }

    private var requestPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("Endpoint", selection: $path) {
                    Text("_cmdstat.jsp — statistics & commands").tag("/admin/_cmdstat.jsp")
                    Text("_conf.jsp — configuration").tag("/admin/_conf.jsp")
                }
                .labelsHidden()
                Menu {
                    ForEach(APIPreset.all) { preset in
                        Button(preset.name) {
                            requestXML = preset.xml
                            path = preset.path
                        }
                    }
                } label: {
                    Label("Presets", systemImage: "list.bullet.rectangle")
                }
                .fixedSize()
            }
            TextEditor(text: $requestXML)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
            HStack {
                if isMutating {
                    Label("Mutating request", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
                Spacer()
                Button {
                    if isMutating { confirmMutating = true } else { send() }
                } label: {
                    HStack {
                        if isSending { ProgressView().controlSize(.small) }
                        Text("Send")
                    }
                    .frame(minWidth: 70)
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(isSending || requestXML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("Tip: ⌘↩ sends. The updater attribute is echoed back as the response id; for sharded event requests it must match requestId.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
    }

    private var responsePane: some View {
        VSplitView {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Response")
                        .font(.headline)
                    Spacer()
                    Text(statusLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ScrollView([.vertical, .horizontal]) {
                    Text(responseText.isEmpty ? "Send a request to see the controller's reply." : responseText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(responseText.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
            }
            .padding(14)
            .frame(minHeight: 200)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Recent requests")
                        .font(.headline)
                    Text("(\(store.requestLog.count))")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") { store.clearLog() }
                        .buttonStyle(.borderless)
                        .disabled(store.requestLog.isEmpty)
                }
                List(store.requestLog, selection: $selectedLog) { entry in
                    HStack(spacing: 8) {
                        StatusDot(color: entry.error == nil ? .green : .red, size: 7)
                        Text(Format.time(entry.timestamp))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(entry.path.replacingOccurrences(of: "/admin/", with: ""))
                            .font(.caption)
                        Text(summary(of: entry.requestXML))
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.0f ms", entry.duration * 1000))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(entry.id)
                }
                .listStyle(.inset)
                .onChange(of: selectedLog) { _, newValue in
                    guard let entry = store.requestLog.first(where: { $0.id == newValue }) else { return }
                    requestXML = entry.requestXML
                    path = entry.path
                    responseText = prettyPrint(entry.responseText)
                    statusLine = entry.error.map { "Error: \($0)" } ?? String(format: "HTTP %d · %.0f ms", entry.status, entry.duration * 1000)
                }
            }
            .padding(14)
            .frame(minHeight: 160)
        }
    }

    private func summary(of xml: String) -> String {
        guard let root = try? XMLTreeParser.parse(xml) else { return xml.prefix(60).description }
        let action = root["action"] ?? ""
        let comp = root["comp"] ?? ""
        let children = root.children.map(\.name).joined(separator: ", ")
        return "\(action) \(comp) \(children.isEmpty ? "" : "· \(children)")"
    }

    private func prettyPrint(_ text: String) -> String {
        guard let root = try? XMLTreeParser.parse(text) else { return text }
        return root.prettyPrinted()
    }

    private func send() {
        isSending = true
        let xml = requestXML
        let endpoint = path
        Task {
            do {
                let response = try await store.sendRaw(xml: xml, path: endpoint)
                responseText = response.root.prettyPrinted()
                statusLine = String(format: "OK · %.0f ms · %d bytes", response.duration * 1000, response.raw.utf8.count)
            } catch {
                responseText = (error as? RuckusError)?.rawBody.map(prettyPrint) ?? ""
                statusLine = "Error: \(error.localizedDescription)"
            }
            isSending = false
        }
    }
}
