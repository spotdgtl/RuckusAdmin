import AppKit
import SwiftUI

extension WirelessClient {
    var rssiValue: Int { rssi ?? 0 }
    var deviceSummary: String {
        [osDescription, deviceType].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct ClientsView: View {
    @Environment(ControllerStore.self) private var store
    @State private var selection: WirelessClient.ID?
    @State private var sortOrder = [KeyPathComparator(\WirelessClient.displayName)]
    @State private var searchText = ""
    @State private var showInspector = true

    private var rows: [WirelessClient] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = query.isEmpty ? store.clients : store.clients.filter { client in
            [client.hostname, client.ip, client.mac, client.model, client.osDescription, client.apName, client.ssid, client.username]
                .contains { $0.lowercased().contains(query) }
        }
        return filtered.sorted(using: sortOrder)
    }

    private var selected: WirelessClient? {
        rows.first { $0.id == selection }
    }

    var body: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            Group {
                TableColumn("Name", value: \.displayName) { ClientNameCell(client: $0) }
                    .width(min: 160, ideal: 220)
                TableColumn("IP address", value: \.ip)
                    .width(min: 100, ideal: 120)
                TableColumn("MAC") { MonoText(text: Format.mac($0.mac)) }
                    .width(min: 130, ideal: 150)
                TableColumn("Device", value: \.deviceSummary)
                    .width(min: 100, ideal: 140)
                TableColumn("Access point", value: \.apName)
                    .width(min: 100, ideal: 130)
                TableColumn("Network", value: \.ssid)
                    .width(min: 100, ideal: 130)
            }
            Group {
                TableColumn("Band", value: \.band) { ClientBandCell(client: $0) }
                    .width(min: 90, ideal: 110)
                TableColumn("Signal", value: \.rssiValue) { ClientSignalCell(client: $0) }
                    .width(min: 90, ideal: 110)
                TableColumn("Rate") { ClientRateCell(rate: store.clientRates[$0.mac], isLive: store.isLive) }
                    .width(min: 120, ideal: 150)
                TableColumn("Traffic", value: \.totalBytes) { ClientTrafficCell(client: $0) }
                    .width(min: 140, ideal: 170)
                TableColumn("First seen") { ClientFirstSeenCell(client: $0) }
                    .width(min: 80, ideal: 100)
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search clients")
        .inspector(isPresented: $showInspector) {
            Group {
                if let selected {
                    ClientDetailView(client: selected)
                } else {
                    ContentUnavailableView("Select a client", systemImage: "laptopcomputer.and.iphone",
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
            }
        }
        .navigationTitle("Clients")
        .navigationSubtitle("\(store.clients.count) connected")
        .onAppear(perform: consumeFocus)
        .onChange(of: store.focusClientMAC) { _, _ in consumeFocus() }
    }

    private func consumeFocus() {
        guard let mac = store.focusClientMAC else { return }
        searchText = ""
        selection = mac
        showInspector = true
        store.focusClientMAC = nil
    }
}

struct ClientDetailView: View {
    @Environment(ControllerStore.self) private var store
    var client: WirelessClient

    @State private var confirmBlock = false
    @State private var confirmDisconnect = false
    @State private var showRename = false
    @State private var newName = ""
    @State private var actionError: String?
    @State private var isWorking = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                actions
                Card("Connection", systemImage: "wifi") {
                    FactGrid(facts: connectionFacts)
                }
                Card("Device", systemImage: "desktopcomputer") {
                    FactGrid(facts: deviceFacts)
                }
                Card("Traffic", systemImage: "arrow.up.arrow.down") {
                    FactGrid(facts: trafficFacts)
                }
                RawAttributesView(attributes: client.raw)
            }
            .padding(16)
        }
        .alert("Action failed", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
        .confirmationDialog("Block \(client.displayName)?", isPresented: $confirmBlock, titleVisibility: .visible) {
            Button("Block client", role: .destructive) {
                run { try await store.blockClient(client) }
            }
        } message: {
            Text("The device is added to the controller's System deny list and cannot rejoin any Wi-Fi network until it is unblocked.")
        }
        .confirmationDialog("Disconnect \(client.displayName)?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) {
                run { try await store.disconnectClient(client) }
            }
        } message: {
            Text("The client is removed from the access point. It may reconnect immediately.")
        }
        .alert("Rename client", isPresented: $showRename) {
            TextField("Name", text: $newName)
            Button("Rename") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                run { try await store.renameClient(client, to: name) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Sets the display name the controller shows for this device.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(client.displayName)
                    .font(.title2.weight(.semibold))
                if client.isFavourite {
                    Image(systemName: "star.fill").foregroundStyle(.yellow)
                }
            }
            Text(Format.mac(client.mac))
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            HStack(spacing: 6) {
                StatusPill(text: client.isBlocked ? "Blocked" : (client.isAuthorized ? "Authorized" : "Unauthorized"),
                           color: client.isBlocked ? .red : (client.isAuthorized ? .green : .orange))
                BandBadge(band: client.band)
                if !client.healthLevel.isEmpty { Chip(text: client.healthLevel, systemImage: "heart") }
                if client.isIoT { Chip(text: "IoT", systemImage: "sensor") }
            }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    newName = client.hostname
                    showRename = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Button {
                    run { try await store.setFavourite(client, !client.isFavourite) }
                } label: {
                    Label(client.isFavourite ? "Unfavourite" : "Favourite", systemImage: client.isFavourite ? "star.slash" : "star")
                }
                Button {
                    copy(client.ip)
                } label: {
                    Label("Copy IP", systemImage: "doc.on.doc")
                }
                .disabled(client.ip.isEmpty)
            }
            HStack(spacing: 8) {
                if client.isBlocked {
                    Button {
                        run { try await store.unblockClient(client) }
                    } label: {
                        Label("Unblock", systemImage: "lock.open")
                    }
                } else {
                    Button(role: .destructive) {
                        confirmBlock = true
                    } label: {
                        Label("Block", systemImage: "hand.raised")
                    }
                }
                Button(role: .destructive) {
                    confirmDisconnect = true
                } label: {
                    Label("Disconnect", systemImage: "xmark.circle")
                }
                if isWorking {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .controlSize(.small)
        .disabled(isWorking)
    }

    private var connectionFacts: [(String, String)] {
        [
            ("Network", client.ssid),
            ("Access point", client.apName.isEmpty ? Format.mac(client.apMAC) : client.apName),
            ("Band", client.band.label + (client.radioType.isEmpty ? "" : " (\(client.radioType))")),
            ("Channel", client.channel),
            ("Signal at AP", client.signalDBm.map { "\($0) dBm (uplink, as received by the AP)" } ?? "–"),
            ("SNR at AP", client.rssi.map { "\($0) dB above noise" } ?? "–"),
            ("Noise floor", client.noiseFloor.map { "\($0) dBm" } ?? "–"),
            ("Security", [client.encryption, client.authMethod].filter { !$0.isEmpty }.joined(separator: " · ")),
            ("VLAN", client.vlan),
            ("First associated", Format.dateTime(client.firstAssociated)),
        ]
    }

    private var deviceFacts: [(String, String)] {
        [
            ("Hostname", client.hostname),
            ("User", client.username),
            ("IP address", client.ip),
            ("IPv6", client.ipv6),
            ("MAC", Format.mac(client.mac)),
            ("Operating system", client.osDescription),
            ("Type", client.deviceType),
            ("Model", client.model),
        ]
    }

    private var trafficFacts: [(String, String)] {
        [
            ("Downloaded", Format.bytes(client.txBytes)),
            ("Uploaded", Format.bytes(client.rxBytes)),
            ("Packets", "↓ \(client.txPackets.map(String.init) ?? "–") · ↑ \(client.rxPackets.map(String.init) ?? "–")"),
        ]
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

struct ClientRateCell: View {
    var rate: ClientRate?
    var isLive: Bool

    var body: some View {
        if let rate {
            let total = rate.downloadBitsPerSecond + rate.uploadBitsPerSecond
            Text("↓ \(Format.bitrate(bitsPerSecond: rate.downloadBitsPerSecond)) · ↑ \(Format.bitrate(bitsPerSecond: rate.uploadBitsPerSecond))")
                .foregroundStyle(total > 1_000 ? Color.primary : Color.secondary)
                .help("Average since the controller's previous client-stats update (about a minute)")
        } else {
            Text(isLive ? "…" : "–")
                .foregroundStyle(.secondary)
                .help(isLive ? "Appears after the controller's next client-stats update (about a minute)" : "Turn on Live in the Auto-refresh menu to see current rates")
        }
    }
}

struct MonoText: View {
    var text: String
    var body: some View {
        Text(text).font(.system(.body, design: .monospaced))
    }
}

struct ClientNameCell: View {
    var client: WirelessClient
    var body: some View {
        HStack(spacing: 8) {
            StatusDot(color: client.isBlocked ? .red : (client.isAuthorized ? .green : .orange), size: 8)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(client.displayName).fontWeight(.medium)
                    if client.isFavourite {
                        Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption)
                    }
                    if client.isBlocked {
                        StatusPill(text: "Blocked", color: .red)
                    }
                }
                if !client.model.isEmpty {
                    Text(client.model).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct ClientBandCell: View {
    var client: WirelessClient
    var body: some View {
        HStack(spacing: 4) {
            BandBadge(band: client.band)
            if !client.channel.isEmpty {
                Text("ch \(client.channel)").foregroundStyle(.secondary)
            }
        }
    }
}

struct ClientSignalCell: View {
    var client: WirelessClient
    var body: some View {
        HStack(spacing: 6) {
            SignalBars(quality: client.signalQuality)
            Text(client.signalDBm.map { "\($0) dBm" } ?? (client.rssi.map { "\($0) dB" } ?? "–"))
                .foregroundStyle(.secondary)
        }
    }
}

struct ClientTrafficCell: View {
    var client: WirelessClient
    var body: some View {
        Text("↓ \(Format.bytes(client.txBytes)) · ↑ \(Format.bytes(client.rxBytes))")
            .foregroundStyle(.secondary)
    }
}

struct ClientFirstSeenCell: View {
    var client: WirelessClient
    var body: some View {
        Text(Format.relative(client.firstAssociated))
            .foregroundStyle(.secondary)
            .help("When the controller first saw this device associate (the controller keeps client records across sessions; it is not the length of the current connection)")
    }
}
