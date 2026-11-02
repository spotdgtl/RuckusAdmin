import AppKit
import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case dashboard, accessPoints, clients, wlans, rfEnvironment, events, explorer, systemSettings, adminSettings, servicesSettings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .accessPoints: return "Access Points"
        case .clients: return "Clients"
        case .wlans: return "Wi-Fi Networks"
        case .rfEnvironment: return "RF Environment"
        case .events: return "Events & Alarms"
        case .explorer: return "API Explorer"
        case .systemSettings: return "System"
        case .adminSettings: return "Administration"
        case .servicesSettings: return "Services"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .accessPoints: return "antenna.radiowaves.left.and.right"
        case .clients: return "laptopcomputer.and.iphone"
        case .wlans: return "wifi"
        case .rfEnvironment: return "waveform.badge.magnifyingglass"
        case .events: return "bell.badge"
        case .explorer: return "terminal"
        case .systemSettings: return "gearshape"
        case .adminSettings: return "person.badge.key"
        case .servicesSettings: return "square.stack.3d.up"
        }
    }
}

struct MainView: View {
    @Environment(ControllerStore.self) private var store
    @State private var selection: SidebarItem? = {
        // `--page <id>` (e.g. --page rfEnvironment) opens a section at launch; handy for screenshots.
        if let index = CommandLine.arguments.firstIndex(of: "--page"), index + 1 < CommandLine.arguments.count,
           let item = SidebarItem(rawValue: CommandLine.arguments[index + 1]) {
            return item
        }
        return .dashboard
    }()

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            VStack(spacing: 0) {
                if let error = store.lastError {
                    ErrorBanner(message: error) { store.lastError = nil }
                }
                detail
            }
            .toolbar { toolbarContent }
        }
        .navigationTitle(store.displayName)
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section("Overview") {
                sidebarRow(.dashboard)
            }
            Section("Network") {
                sidebarRow(.accessPoints, badge: "\(store.onlineAccessPointCount)/\(store.accessPoints.count)")
                sidebarRow(.clients, badge: "\(store.clients.count)")
                sidebarRow(.wlans, badge: "\(store.wlans.count)")
                sidebarRow(.rfEnvironment, badge: store.neighbors.isEmpty ? nil : "\(store.neighbors.count)")
            }
            Section("Monitoring") {
                sidebarRow(.events, badge: store.alarms.isEmpty ? nil : "\(store.alarms.count)")
                sidebarRow(.explorer)
            }
            Section("Settings") {
                sidebarRow(.systemSettings)
                sidebarRow(.adminSettings)
                sidebarRow(.servicesSettings)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            ConnectionFooter()
        }
    }

    private func sidebarRow(_ item: SidebarItem, badge: String? = nil) -> some View {
        HStack {
            Label(item.title, systemImage: item.systemImage)
            Spacer()
            if let badge {
                Text(badge)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .tag(item)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .dashboard {
        case .dashboard: DashboardView(selection: $selection)
        case .accessPoints: AccessPointsView()
        case .clients: ClientsView()
        case .wlans: WLANsView()
        case .rfEnvironment: RFEnvironmentView()
        case .events: EventsView()
        case .explorer: APIExplorerView()
        case .systemSettings: SettingsGroupView(group: .system)
        case .adminSettings: SettingsGroupView(group: .administration)
        case .servicesSettings: SettingsGroupView(group: .services)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Toggle(isOn: Binding(get: { store.settings.liveMode }, set: { store.setLiveMode($0) })) {
                    Label("Live (every \(Int(store.settings.liveInterval)) s)", systemImage: "bolt.fill")
                }
                Divider()
                Text("Full refresh")
                ForEach([10.0, 20.0, 30.0, 60.0, 120.0], id: \.self) { interval in
                    Button {
                        store.settings.pollInterval = interval
                        store.restartPolling()
                    } label: {
                        if store.settings.pollInterval == interval {
                            Label("Every \(Int(interval)) s", systemImage: "checkmark")
                        } else {
                            Text("Every \(Int(interval)) s")
                        }
                    }
                }
            } label: {
                Label("Auto-refresh", systemImage: store.isLive ? "bolt.fill" : "timer")
            }
            .help("Live mode samples clients and AP stats every few seconds; the full refresh reloads configuration, events and scans")

            Button {
                Task { await store.refresh(includeEvents: true) }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Refresh now (⌘R); polling also runs quietly in the background")

            if !store.isDemo {
                Button {
                    if let url = URL(string: "https://\(store.settings.host)/admin/dashboard.jsp") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Open web UI", systemImage: "safari")
                }
                .help("Open the stock Unleashed web interface")
            }

            Button {
                Task { await store.disconnect() }
            } label: {
                Label("Disconnect", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .help("Sign out of the controller")
        }
    }
}

struct ConnectionFooter: View {
    @Environment(ControllerStore.self) private var store

    private var statusColor: Color {
        store.lastError != nil ? .orange : .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                StatusDot(color: statusColor, size: 8)
                Text(store.isDemo ? "Demo mode" : store.settings.host)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
            }
            Text(store.isLive
                 ? "Live · every \(Int(store.settings.liveInterval)) s"
                 : (store.lastUpdated.map { "Updated \(Format.relative($0))" } ?? "Waiting for first update…"))
                .font(.caption)
                .foregroundStyle(store.isLive ? Color.green : Color.secondary)
            if !store.system.version.isEmpty {
                Text("\(store.system.model) · \(store.system.version)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Text("Ruckus Admin \(AppVersion.display)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }
}
