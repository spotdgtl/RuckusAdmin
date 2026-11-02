import AppKit
import Charts
import SwiftUI

struct AccessPointsView: View {
    @Environment(ControllerStore.self) private var store
    @State private var selection: AccessPoint.ID?
    @State private var sortOrder = [KeyPathComparator(\AccessPoint.name)]
    @State private var showInspector = true

    private var rows: [AccessPoint] {
        store.accessPoints.sorted(using: sortOrder)
    }

    private var selected: AccessPoint? {
        rows.first { $0.id == selection }
    }

    var body: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Status") { ap in
                HStack(spacing: 6) {
                    StatusDot(color: ap.isOnline ? .green : .red, size: 8)
                    Text(ap.state.label)
                }
            }
            .width(min: 90, ideal: 110)

            TableColumn("Name", value: \.name) { ap in
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(ap.displayName).fontWeight(.medium)
                        if ap.isMaster {
                            StatusPill(text: "Master", color: .accentColor)
                        }
                    }
                    if !ap.location.isEmpty {
                        Text(ap.location)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .width(min: 140, ideal: 200)

            TableColumn("Model", value: \.model)
                .width(min: 60, ideal: 80)

            TableColumn("IP address", value: \.ip)
                .width(min: 100, ideal: 120)

            TableColumn("MAC") { ap in
                Text(Format.mac(ap.mac))
                    .font(.system(.body, design: .monospaced))
            }
            .width(min: 130, ideal: 150)

            TableColumn("Clients", value: \.clientCount) { ap in
                Text("\(ap.clientCount)")
            }
            .width(min: 50, ideal: 60)

            TableColumn("2.4 GHz") { ap in
                Text(channelText(ap.radio(for: .ghz2_4)))
            }
            .width(min: 70, ideal: 90)

            TableColumn("5 GHz") { ap in
                Text(channelText(ap.radio(for: .ghz5)))
            }
            .width(min: 70, ideal: 90)

            TableColumn("Uptime") { ap in
                Text(ap.isOnline ? Format.uptime(ap.uptime) : "–")
            }
            .width(min: 70, ideal: 90)

            TableColumn("Firmware", value: \.firmware)
                .width(min: 110, ideal: 140)
        }
        .inspector(isPresented: $showInspector) {
            Group {
                if let selected {
                    AccessPointDetailView(ap: selected)
                } else {
                    ContentUnavailableView("Select an access point", systemImage: "antenna.radiowaves.left.and.right",
                                           description: Text("Details and actions appear here."))
                }
            }
            .inspectorColumnWidth(min: 320, ideal: 380, max: 520)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showInspector.toggle()
                } label: {
                    Label("Details", systemImage: "sidebar.trailing")
                }
                .help("Show or hide the details panel")
            }
        }
        .navigationTitle("Access Points")
        .navigationSubtitle("\(store.onlineAccessPointCount) of \(store.accessPoints.count) online")
        .onAppear {
            consumeFocus()
            if selection == nil { selection = rows.first?.id }
        }
        .onChange(of: store.focusAccessPointMAC) { _, _ in consumeFocus() }
    }

    private func consumeFocus() {
        guard let mac = store.focusAccessPointMAC else { return }
        selection = mac
        showInspector = true
        store.focusAccessPointMAC = nil
    }

    private func channelText(_ radio: Radio?) -> String {
        guard let radio, !radio.channel.isEmpty, radio.channel != "*" else { return "–" }
        return radio.channelization.isEmpty ? "ch \(radio.channel)" : "ch \(radio.channel) / \(radio.channelization)"
    }
}

struct AccessPointDetailView: View {
    @Environment(ControllerStore.self) private var store
    var ap: AccessPoint

    @State private var confirmRestart = false
    @State private var showEditor = false
    @State private var actionError: String?
    @State private var isWorking = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                actions
                Card("Device", systemImage: "cpu") {
                    FactGrid(facts: deviceFacts)
                }
                Card("Network", systemImage: "network") {
                    FactGrid(facts: networkFacts)
                }
                healthCard
                radiosCard
                if !ap.history.isEmpty {
                    Card("Traffic", subtitle: "Per-band history from the controller", systemImage: "waveform.path.ecg") {
                        ThroughputChart(points: ThroughputMath.points(from: ap.history, bucketSeconds: 300))
                            .frame(height: 150)
                    }
                }
                if !ap.interfaces.isEmpty {
                    interfacesCard
                }
                clientsCard
                RawAttributesView(attributes: ap.raw)
            }
            .padding(16)
        }
        .alert("Action failed", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
        .sheet(isPresented: $showEditor) {
            APEditorView(ap: ap).environment(store)
        }
        .confirmationDialog("Restart \(ap.displayName)?", isPresented: $confirmRestart, titleVisibility: .visible) {
            Button("Restart access point", role: .destructive) {
                run { try await store.restartAccessPoint(ap) }
            }
        } message: {
            Text(ap.isMaster
                 ? "This is the master AP. Restarting it restarts the Unleashed controller and will briefly disconnect every client, including this app."
                 : "Clients on this access point will be disconnected while it reboots.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(ap.displayName)
                    .font(.title2.weight(.semibold))
                Text("\(ap.model) · \(Format.mac(ap.mac))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                HStack(spacing: 6) {
                    StatusPill(text: ap.state.label, color: ap.isOnline ? .green : .red)
                    if ap.isMaster { StatusPill(text: "Master", color: .accentColor) }
                    if !ap.meshState.isEmpty { StatusPill(text: "Mesh \(ap.meshState)", color: .purple) }
                    if !ap.meshUplinkType.isEmpty { Chip(text: ap.meshUplinkType.capitalized + " uplink") }
                }
            }
            Spacer()
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button {
                showEditor = true
            } label: {
                Label("Edit…", systemImage: "pencil")
            }
            Button {
                confirmRestart = true
            } label: {
                Label("Restart", systemImage: "arrow.counterclockwise")
            }
            .disabled(!ap.isOnline || isWorking)
            Button {
                copy(ap.ip)
            } label: {
                Label("Copy IP", systemImage: "doc.on.doc")
            }
            .disabled(ap.ip.isEmpty)
            Button {
                copy(Format.mac(ap.mac))
            } label: {
                Label("Copy MAC", systemImage: "doc.on.doc")
            }
            if !ap.ip.isEmpty, !ap.isMaster {
                Button {
                    if let url = URL(string: "https://\(ap.ip)/") { NSWorkspace.shared.open(url) }
                } label: {
                    Label("Open AP", systemImage: "safari")
                }
            }
            if isWorking {
                ProgressView().controlSize(.small)
            }
        }
        .controlSize(.small)
    }

    private var deviceFacts: [(String, String)] {
        [
            ("Model", ap.model),
            ("Serial", ap.serial),
            ("Firmware", ap.firmware),
            ("Role", ap.role.capitalized),
            ("Uptime", ap.isOnline ? Format.uptime(ap.uptime) : "–"),
            ("Last seen", Format.relative(ap.lastSeen)),
            ("Joined", Format.dateTime(ap.firstJoined)),
            ("Last reboot", ap.lastRebootReason),
            ("Reboots", ap.rebootCount.map(String.init) ?? "–"),
            ("Power", ap.poeMode),
            ("Temperature", ap.temperature.isEmpty ? "–" : "\(ap.temperature) °C"),
            ("Wi-Fi 6", ap.supports11ax ? "Yes" : "No"),
            ("Location", ap.location),
            ("Description", ap.description),
        ]
    }

    private var networkFacts: [(String, String)] {
        [
            ("IP address", ap.ip + (ap.ipType.isEmpty ? "" : " (\(ap.ipType))")),
            ("Netmask", ap.netmask),
            ("Gateway", ap.gateway),
            ("External IP", ap.externalIP),
            ("MAC", Format.mac(ap.mac)),
            ("AP group", ap.groupID),
            ("Mesh depth", ap.meshState.isEmpty ? "–" : "\(ap.meshDepth)"),
            ("LAN port", "in \(Format.bytes(ap.lanRxBytes)) · out \(Format.bytes(ap.lanTxBytes))"),
            ("Wireless", "↓ \(Format.bytes(ap.wlanTxBytes)) to clients · ↑ \(Format.bytes(ap.wlanRxBytes)) from clients"),
        ]
    }

    @ViewBuilder
    private var healthCard: some View {
        if ap.cpuUtilization != nil || ap.memoryUsedFraction != nil {
            Card("Health", systemImage: "heart.text.square") {
                VStack(spacing: 10) {
                    MeterRow(label: "CPU", fraction: (ap.cpuUtilization ?? 0) / 100, detail: ap.cpuUtilization.map { "\(Int($0))%" } ?? "–")
                    MeterRow(label: "Memory", fraction: ap.memoryUsedFraction,
                             detail: ap.memoryTotalKB.map { total in
                                 let used = total - (ap.memoryAvailableKB ?? 0)
                                 return "\(Format.bytes(Int64(used) * 1024)) of \(Format.bytes(Int64(total) * 1024))"
                             } ?? "–")
                }
            }
        }
    }

    @ViewBuilder
    private var radiosCard: some View {
        if !ap.radios.isEmpty {
            Card("Radios", systemImage: "dot.radiowaves.left.and.right") {
                HStack(spacing: 10) {
                    ForEach(ap.radios) { radio in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                BandBadge(band: radio.band)
                                Text(radio.radioType)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(radio.channel == "*" || radio.channel.isEmpty ? "Auto" : "Channel \(radio.channel)")
                                .font(.headline)
                            Text([
                                radio.channelization.isEmpty || radio.channelization == "*" ? nil : "\(radio.channelization) MHz",
                                radio.txPower.isEmpty ? nil : "Tx \(radio.txPower)",
                                radio.clientCount.map { "\($0) client\($0 == 1 ? "" : "s")" },
                            ].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }

    private var interfacesCard: some View {
        Card("Interfaces", systemImage: "cable.connector") {
            VStack(spacing: 6) {
                ForEach(ap.interfaces) { iface in
                    HStack {
                        StatusDot(color: iface.isUp ? .green : .gray, size: 7)
                        Text(iface.name).fontWeight(.medium)
                        Text(iface.speed == "0" || iface.speed.isEmpty ? "" : (Int(iface.speed) != nil ? "\(iface.speed) Mbps" : iface.speed))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("in \(Format.bytes(iface.inOctets)) · out \(Format.bytes(iface.outOctets))")
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
        }
    }

    private var clientsCard: some View {
        let clients = store.clients(forAccessPoint: ap.mac)
        return Card("Clients", subtitle: "\(clients.count) connected", systemImage: "laptopcomputer.and.iphone") {
            if clients.isEmpty {
                Text("No clients on this access point.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(clients) { client in
                        HStack {
                            SignalBars(quality: client.signalQuality)
                            Text(client.displayName).lineLimit(1)
                            BandBadge(band: client.band)
                            Spacer()
                            Text(client.ip)
                                .foregroundStyle(.secondary)
                                .font(.system(.callout, design: .monospaced))
                        }
                        .font(.callout)
                    }
                }
            }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func run(_ operation: @escaping () async throws -> Void) {
        isWorking = true
        Task {
            do {
                try await operation()
            } catch {
                actionError = error.localizedDescription
            }
            isWorking = false
        }
    }
}
