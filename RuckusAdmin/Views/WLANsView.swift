import Charts
import SwiftUI

struct WLANsView: View {
    @Environment(ControllerStore.self) private var store
    @State private var showNewNetwork = false

    private let columns = [GridItem(.adaptive(minimum: 360, maximum: 560), spacing: 14)]

    var body: some View {
        ScrollView {
            if store.wlans.isEmpty {
                ContentUnavailableView("No Wi-Fi networks", systemImage: "wifi.slash",
                                       description: Text("The controller has not reported any WLANs yet."))
                    .frame(minHeight: 400)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    ForEach(store.wlans) { wlan in
                        WLANCard(wlan: wlan)
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("Wi-Fi Networks")
        .navigationSubtitle("\(store.wlans.filter(\.isEnabled).count) of \(store.wlans.count) enabled")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button { showNewNetwork = true } label: { Label("New network", systemImage: "plus") }
                    .help("Create a Wi-Fi network from the controller's standard template")
            }
        }
        .sheet(isPresented: $showNewNetwork) {
            WLANEditorView(wlan: nil).environment(store)
        }
    }
}

struct WLANCard: View {
    @Environment(ControllerStore.self) private var store
    var wlan: WLAN

    @State private var confirmDisable = false
    @State private var actionError: String?
    @State private var isWorking = false
    @State private var showClients = false
    @State private var showEditor = false
    @State private var confirmDelete = false

    var body: some View {
        let clients = store.clients(forWLAN: wlan)
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Image(systemName: wlan.isGuest ? "person.badge.key" : "wifi")
                                .foregroundStyle(wlan.isEnabled ? Color.accentColor : Color.secondary)
                            Text(wlan.ssid.isEmpty ? wlan.name : wlan.ssid)
                                .font(.title3.weight(.semibold))
                        }
                        if !wlan.description.isEmpty, wlan.description != wlan.ssid {
                            Text(wlan.description)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        StatusPill(text: wlan.isEnabled ? (wlan.isScheduled ? "Scheduled" : "Enabled") : "Disabled",
                                   color: wlan.isEnabled ? .green : .gray)
                        Toggle("Enabled", isOn: Binding(
                            get: { wlan.isEnabled },
                            set: { newValue in
                                if newValue {
                                    run { try await store.setWLAN(wlan, enabled: true) }
                                } else {
                                    confirmDisable = true
                                }
                            }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .disabled(isWorking)
                    }
                }

                HStack(spacing: 6) {
                    Chip(text: wlan.securitySummary, systemImage: "lock")
                    Chip(text: "VLAN \(wlan.vlanID.isEmpty ? "1" : wlan.vlanID)", systemImage: "number")
                    if wlan.isGuest { Chip(text: "Guest", systemImage: "person.2") }
                    if wlan.isHidden { Chip(text: "Hidden SSID", systemImage: "eye.slash") }
                    if wlan.clientIsolation { Chip(text: "Client isolation", systemImage: "shield") }
                    if wlan.wifi6 { Chip(text: "Wi-Fi 6", systemImage: "6.circle") }
                }

                HStack(spacing: 18) {
                    metric("Clients", "\(clients.isEmpty ? wlan.clientCount : clients.count)")
                    metric("Max per radio", wlan.maxClientsPerRadio.map(String.init) ?? "–")
                    metric("Traffic (history)", Format.bytes(wlan.history.totalRx + wlan.history.totalTx))
                    metric("Created", wlan.createdAt.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "–")
                }

                if !wlan.history.isEmpty {
                    ThroughputChart(points: ThroughputMath.points(from: wlan.history, bucketSeconds: 300))
                        .frame(height: 120)
                }

                DisclosureGroup(isExpanded: $showClients) {
                    if clients.isEmpty {
                        Text("No clients on this network.")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                            .padding(.top, 4)
                    } else {
                        VStack(spacing: 5) {
                            ForEach(clients) { client in
                                HStack {
                                    SignalBars(quality: client.signalQuality)
                                    Text(client.displayName).lineLimit(1)
                                    BandBadge(band: client.band)
                                    Spacer()
                                    Text(client.apName)
                                        .foregroundStyle(.secondary)
                                }
                                .font(.callout)
                            }
                        }
                        .padding(.top, 4)
                    }
                } label: {
                    Text("Connected clients (\(clients.count))")
                        .font(.callout.weight(.medium))
                }

                HStack {
                    Button { showEditor = true } label: { Label("Edit", systemImage: "pencil") }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
                    if isWorking {
                        ProgressView().controlSize(.small)
                    }
                }
                .controlSize(.small)
                .disabled(isWorking)
            }
        }
        .sheet(isPresented: $showEditor) {
            WLANEditorView(wlan: wlan).environment(store)
        }
        .confirmationDialog("Delete \(wlan.ssid)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete network", role: .destructive) {
                run { try await store.deleteWLAN(id: wlan.id) }
            }
        } message: {
            Text("The network is removed from every access point and its clients are disconnected.")
        }
        .alert("Action failed", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
        .confirmationDialog("Disable \(wlan.ssid)?", isPresented: $confirmDisable, titleVisibility: .visible) {
            Button("Disable network", role: .destructive) {
                run { try await store.setWLAN(wlan, enabled: false) }
            }
        } message: {
            Text("Every client on this network will be disconnected until it is enabled again.")
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.medium))
        }
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
