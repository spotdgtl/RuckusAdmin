import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension ControllerStore {
    /// Sends arbitrary system configuration (used by pages that do not fit the declarative spec).
    func applySystemBody(_ body: String) async throws {
        try await requireServiceForTools().applySystemConfig(body: body)
    }

    private func requireServiceForTools() throws -> any RuckusService {
        // Mirrors the private helper in the store; kept here so tool views can reuse it.
        if isDemo || isConnected {
            return try serviceForTools()
        }
        throw RuckusError.notLoggedIn
    }
}

/// Saves data with a standard save panel. Must be called on the main actor.
@MainActor
func saveDataWithPanel(_ data: Data, suggestedName: String, contentType: UTType = .data) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = suggestedName
    panel.allowedContentTypes = [contentType]
    panel.canCreateDirectories = true
    if panel.runModal() == .OK, let url = panel.url {
        try? data.write(to: url)
    }
}

// MARK: - Preferences

struct PreferencesView: View {
    @Environment(ControllerStore.self) private var store
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isChanging = false
    @State private var message: String?
    @State private var errorText: String?

    private var canChange: Bool {
        !currentPassword.isEmpty && newPassword.count >= 4 && newPassword == confirmPassword && !isChanging
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ConfigPageView(spec: SettingsCatalog.preferences, embedded: true)
                Card("Admin password", subtitle: "Changes the password for \(store.settings.username) and reconnects this app with it.", systemImage: "key") {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 10) {
                        GridRow {
                            Text("Current password").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                            SecureField("", text: $currentPassword).textFieldStyle(.roundedBorder).frame(maxWidth: 320)
                        }
                        GridRow {
                            Text("New password").foregroundStyle(.secondary)
                            SecureField("", text: $newPassword).textFieldStyle(.roundedBorder).frame(maxWidth: 320)
                        }
                        GridRow {
                            Text("Confirm new password").foregroundStyle(.secondary)
                            SecureField("", text: $confirmPassword).textFieldStyle(.roundedBorder).frame(maxWidth: 320)
                        }
                    }
                    if let errorText { Label(errorText, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
                    if let message { Label(message, systemImage: "checkmark.circle").foregroundStyle(.green) }
                    HStack {
                        Spacer()
                        Button {
                            Task { await changePassword() }
                        } label: {
                            HStack { if isChanging { ProgressView().controlSize(.small) }; Text("Change password") }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canChange)
                    }
                }
            }
            .padding(20)
        }
    }

    private func changePassword() async {
        isChanging = true
        errorText = nil
        message = nil
        defer { isChanging = false }
        let username = store.settings.username
        let body = "<admin username='\(XMLNode.escape(username))' x-password='\(XMLNode.escape(newPassword))' x-oldpassword='\(XMLNode.escape(currentPassword))' auth-by='local' authsvr-id='none' fallback-local='true' IS_PARTIAL='true'/>"
        do {
            try await store.applySystemBody(body)
            message = "Password changed. Reconnecting…"
            let password = newPassword
            currentPassword = ""
            newPassword = ""
            confirmPassword = ""
            if !store.isDemo {
                await store.disconnect()
                await store.connect(host: store.settings.host, username: username, password: password, rememberPassword: store.settings.rememberPassword)
            }
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - Backup & Restore

struct BackupRestoreView: View {
    @Environment(ControllerStore.self) private var store
    @State private var busy = false
    @State private var resultText: String?
    @State private var errorText: String?
    @State private var confirmRestoreSaved = false
    @State private var confirmReboot = false
    @State private var showFactoryReset = false
    @State private var factoryConfirmation = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Backup & Restore").font(.title2.weight(.semibold))
                Card("Backup", subtitle: "Downloads the controller's configuration archive through the signed-in session.", systemImage: "externaldrive.badge.timemachine") {
                    Button {
                        Task { await saveBackup() }
                    } label: {
                        Label("Save backup…", systemImage: "square.and.arrow.down")
                    }
                    .disabled(busy)
                }
                Card("Restore", subtitle: "Uploading a backup file is only supported in the web UI for now; the controller's own 'restore previously saved' and factory reset are available here.", systemImage: "arrow.counterclockwise") {
                    HStack {
                        Button("Restore previously saved configuration…") { confirmRestoreSaved = true }
                        Button("Open web UI for file upload") {
                            if let url = URL(string: "https://\(store.settings.host)/admin/dashboard.jsp") { NSWorkspace.shared.open(url) }
                        }
                    }
                    .disabled(busy)
                }
                Card("Danger zone", systemImage: "exclamationmark.octagon") {
                    HStack {
                        Button("Reboot controller…") { confirmReboot = true }
                        Button(role: .destructive) { showFactoryReset = true } label: { Text("Reset to factory defaults…") }
                    }
                    .disabled(busy)
                }
                if busy { ProgressView().controlSize(.small) }
                if let errorText { Label(errorText, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).textSelection(.enabled) }
                if let resultText {
                    Card("Controller response", systemImage: nil) {
                        Text(resultText).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }
                }
            }
            .padding(20)
        }
        .confirmationDialog("Restore the previously saved configuration?", isPresented: $confirmRestoreSaved, titleVisibility: .visible) {
            Button("Restore and reboot", role: .destructive) { Task { await run("restore-saved") } }
        } message: {
            Text("The controller reverts to its last saved configuration and reboots.")
        }
        .confirmationDialog("Reboot the controller?", isPresented: $confirmReboot, titleVisibility: .visible) {
            Button("Reboot", role: .destructive) { Task { await run("restart") } }
        } message: {
            Text("All clients lose connectivity until the master AP is back, usually one to two minutes.")
        }
        .sheet(isPresented: $showFactoryReset) {
            VStack(alignment: .leading, spacing: 14) {
                Label("Reset to factory defaults", systemImage: "exclamationmark.octagon.fill").font(.title3.weight(.semibold)).foregroundStyle(.red)
                Text("This erases every setting, WLAN and user on the controller. Type RESET to confirm.")
                TextField("RESET", text: $factoryConfirmation).textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Cancel") { showFactoryReset = false; factoryConfirmation = "" }
                    Button("Erase everything", role: .destructive) {
                        showFactoryReset = false
                        factoryConfirmation = ""
                        Task { await run("restore-default") }
                    }
                    .disabled(factoryConfirmation != "RESET")
                }
            }
            .padding(22)
            .frame(width: 440)
        }
    }

    private func saveBackup() async {
        busy = true
        errorText = nil
        defer { busy = false }
        do {
            let millis = Int(Date().timeIntervalSince1970 * 1000)
            let data = try await store.downloadFile(path: "/admin/webPage/system/admin/_savebackup.jsp?time=\(millis)")
            let stamp = Date().formatted(.iso8601.year().month().day())
            saveDataWithPanel(data, suggestedName: "unleashed-backup-\(stamp).bak")
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func run(_ command: String) async {
        busy = true
        errorText = nil
        resultText = nil
        defer { busy = false }
        do {
            let text = try await store.adminAction(command: command)
            resultText = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if resultText?.isEmpty ?? true { resultText = "Command sent." }
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - Upgrade

struct UpgradeView: View {
    @Environment(ControllerStore.self) private var store
    @State private var rows: [[String: String]] = []
    @State private var busy = false
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Upgrade").font(.title2.weight(.semibold))
                Card("Current firmware", systemImage: "arrow.up.circle") {
                    FactGrid(facts: [
                        ("Controller", store.system.version),
                        ("Master AP", store.system.model),
                        ("Access points", store.accessPoints.map { "\($0.displayName): \($0.firmware)" }.joined(separator: "\n")),
                    ])
                }
                Card("Access point images", subtitle: "Active and backup firmware on each AP, as reported by the controller.", systemImage: "memorychip") {
                    HStack {
                        Button {
                            Task { await query() }
                        } label: {
                            Label("Query upgrade state", systemImage: "arrow.clockwise")
                        }
                        if busy { ProgressView().controlSize(.small) }
                    }
                    if !rows.isEmpty {
                        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                            GridRow {
                                ForEach(["AP", "Model", "Active", "Backup", "State", "Online"], id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                            }
                            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                                GridRow {
                                    Text(row["dev-name"] ?? row["mac"] ?? "")
                                    Text(row["display-model"] ?? row["model"] ?? "")
                                    Text(row["version"] ?? "")
                                    Text(row["bak-version"] ?? "")
                                    Text(row["upgrade-state"]?.isEmpty == false ? row["upgrade-state"]! : "idle")
                                    Text(row["online-state"] ?? "")
                                }
                                .font(.callout)
                            }
                        }
                    }
                }
                Card("Upgrade firmware", subtitle: "Online and local image upgrades reboot every AP; run them from the web UI where progress is shown.", systemImage: "safari") {
                    Button("Open Upgrade in web UI") {
                        if let url = URL(string: "https://\(store.settings.host)/admin/dashboard.jsp") { NSWorkspace.shared.open(url) }
                    }
                }
                if let errorText { Label(errorText, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
            }
            .padding(20)
        }
        .task { await query() }
    }

    private func query() async {
        busy = true
        errorText = nil
        defer { busy = false }
        do {
            let response = try await store.runCommand(component: "system", xcmd: "unleashed_query_upgrade_state", body: "<xcmd cmd='unleashed_query_upgrade_state'/>")
            rows = response.elements("ap").map(\.attributes)
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - Diagnostics

struct DiagnosticsView: View {
    @Environment(ControllerStore.self) private var store
    @State private var logText = ""
    @State private var loadingLogs = false
    @State private var target = "8.8.8.8"
    @State private var apMAC = ""
    @State private var toolOutput = ""
    @State private var runningTool = false
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Diagnostics").font(.title2.weight(.semibold))
                Card("System logs", subtitle: "The controller's syslog buffer.", systemImage: "doc.text.magnifyingglass") {
                    HStack {
                        Button { Task { await loadLogs() } } label: { Label("Load logs", systemImage: "arrow.clockwise") }
                        Button { Task { await saveLogs() } } label: { Label("Save log file…", systemImage: "square.and.arrow.down") }
                        if loadingLogs { ProgressView().controlSize(.small) }
                    }
                    if !logText.isEmpty {
                        ScrollView {
                            Text(logText)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .frame(height: 260)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                Card("Network connectivity", subtitle: "Runs ping or traceroute from an access point's shell.", systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
                    HStack {
                        Picker("Access point", selection: $apMAC) {
                            ForEach(store.accessPoints) { ap in Text(ap.displayName).tag(ap.mac) }
                        }
                        .frame(maxWidth: 240)
                        TextField("Host or IP", text: $target).textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                        Button("Ping") { Task { await runTool("ping -c 4 \(target)") } }
                        Button("Traceroute") { Task { await runTool("traceroute -m 15 \(target)") } }
                        if runningTool { ProgressView().controlSize(.small) }
                    }
                    .disabled(runningTool || apMAC.isEmpty)
                    if !toolOutput.isEmpty {
                        ScrollView {
                            Text(toolOutput)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .frame(height: 200)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                if let errorText { Label(errorText, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).textSelection(.enabled) }
            }
            .padding(20)
        }
        .onAppear { if apMAC.isEmpty { apMAC = store.accessPoints.first?.mac ?? "" } }
    }

    private func loadLogs() async {
        loadingLogs = true
        errorText = nil
        defer { loadingLogs = false }
        do {
            let response = try await store.runCommand(component: "system", xcmd: "get-syslog", body: "<xcmd cmd='get-syslog' type='sys'/>")
            let xmsg = response.element("xmsg")
            let text = xmsg?["res"] ?? xmsg?.text ?? ""
            logText = text.isEmpty ? response.root.prettyPrinted() : text
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func saveLogs() async {
        errorText = nil
        do {
            let millis = Int(Date().timeIntervalSince1970 * 1000)
            let data = try await store.downloadFile(path: "/admin/_savedsystemlog.jsp?time=\(millis)")
            saveDataWithPanel(data, suggestedName: "unleashed-systemlog-\(millis).txt", contentType: .plainText)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func runTool(_ command: String) async {
        runningTool = true
        errorText = nil
        toolOutput = "Running \(command) on \(store.accessPoint(mac: apMAC)?.displayName ?? apMAC)…"
        defer { runningTool = false }
        do {
            _ = try await store.runCommand(component: "system", xcmd: "apcli-cmd",
                                           body: "<xcmd cmd='apcli-cmd' ap='\(XMLNode.escape(apMAC))' apcmd='\(XMLNode.escape(command))'/>")
            for _ in 0..<20 {
                try await Task.sleep(for: .seconds(1))
                let poll = try await store.runCommand(component: "system", xcmd: "is-apcli-done",
                                                      body: "<xcmd cmd='is-apcli-done' ap='\(XMLNode.escape(apMAC))'/>",
                                                      rootAttributes: ["timeout": "-1"])
                let xmsg = poll.element("xmsg")
                let result = xmsg?.attr("res", "result", "output") ?? xmsg?.text ?? ""
                if !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    toolOutput = result
                    return
                }
                if (xmsg?["done"] ?? xmsg?["type"]) == "1" {
                    toolOutput = poll.root.prettyPrinted()
                    return
                }
            }
            toolOutput = "No output received within 20 seconds."
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - Certificate

struct CertificateView: View {
    @Environment(ControllerStore.self) private var store
    @State private var confirmRestore = false
    @State private var resultText: String?
    @State private var errorText: String?

    private var fingerprint: String? {
        CertificateTrustStore.shared.trustedFingerprint(for: store.settings.host.components(separatedBy: ":").first ?? store.settings.host)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Certificate").font(.title2.weight(.semibold))
                Card("Current certificate", subtitle: "Unleashed serves a certificate from its internal CA; this app pins its fingerprint on first use.", systemImage: "lock.shield") {
                    FactGrid(facts: [
                        ("Controller", store.settings.host),
                        ("SHA-256 fingerprint", fingerprint ?? "not pinned yet"),
                    ])
                    Button("Forget pinned fingerprint") {
                        CertificateTrustStore.shared.forget(host: store.settings.host.components(separatedBy: ":").first ?? store.settings.host)
                    }
                    .disabled(fingerprint == nil)
                }
                Card("Replace certificate", subtitle: "Importing your own certificate and private key is done from the web UI (Administration ▸ Certificate).", systemImage: "square.and.arrow.up") {
                    HStack {
                        Button("Open web UI") {
                            if let url = URL(string: "https://\(store.settings.host)/admin/dashboard.jsp") { NSWorkspace.shared.open(url) }
                        }
                        Button("Restore default certificate…") { confirmRestore = true }
                    }
                }
                if let errorText { Label(errorText, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
                if let resultText { Text(resultText).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
            }
            .padding(20)
        }
        .confirmationDialog("Restore the default certificate?", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("Restore and restart web server", role: .destructive) {
                Task {
                    do {
                        resultText = try await store.adminAction(command: "restore-cert")
                            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    } catch { errorText = error.localizedDescription }
                }
            }
        } message: {
            Text("The controller regenerates its self-signed certificate and restarts its web server. This app will need to trust the new fingerprint.")
        }
    }
}

// MARK: - Technical support

struct TechnicalSupportView: View {
    @Environment(ControllerStore.self) private var store
    @State private var errorText: String?
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Technical Support").font(.title2.weight(.semibold))
                Card("System summary", subtitle: "Handy when opening a case with Ruckus support.", systemImage: "info.circle") {
                    FactGrid(facts: [
                        ("System name", store.system.name),
                        ("Firmware", store.system.version),
                        ("Master AP", "\(store.system.model) · S/N \(store.system.serial)"),
                        ("Unleashed ID", store.system.unleashedID),
                        ("Uptime", Format.uptime(store.system.uptime)),
                        ("Access points", "\(store.onlineAccessPointCount) of \(store.accessPoints.count) online"),
                    ])
                }
                Card("Support files", systemImage: "doc.zipper") {
                    HStack {
                        Button { Task { await save(path: "/admin/_savedsystemlog.jsp?time=\(Int(Date().timeIntervalSince1970 * 1000))", name: "unleashed-systemlog.txt", type: .plainText) } } label: {
                            Label("Save system logs…", systemImage: "square.and.arrow.down")
                        }
                        Button { Task { await save(path: "/admin/webPage/system/admin/_savebackup.jsp?time=\(Int(Date().timeIntervalSince1970 * 1000))", name: "unleashed-backup.bak", type: .data) } } label: {
                            Label("Save configuration backup…", systemImage: "square.and.arrow.down")
                        }
                        if busy { ProgressView().controlSize(.small) }
                    }
                    .disabled(busy)
                }
                Card("Links", systemImage: "link") {
                    HStack {
                        Button("Ruckus support portal") {
                            if let url = URL(string: "https://support.ruckuswireless.com/") { NSWorkspace.shared.open(url) }
                        }
                        Button("Unleashed web UI") {
                            if let url = URL(string: "https://\(store.settings.host)/admin/dashboard.jsp") { NSWorkspace.shared.open(url) }
                        }
                    }
                }
                if let errorText { Label(errorText, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
            }
            .padding(20)
        }
    }

    private func save(path: String, name: String, type: UTType) async {
        busy = true
        errorText = nil
        defer { busy = false }
        do {
            let data = try await store.downloadFile(path: path)
            saveDataWithPanel(data, suggestedName: name, contentType: type)
        } catch {
            errorText = error.localizedDescription
        }
    }
}
