import Charts
import SwiftUI

struct DashboardView: View {
    @Environment(ControllerStore.self) private var store
    @Binding var selection: SidebarItem?

    private let statColumns = [GridItem(.adaptive(minimum: 170, maximum: 260), spacing: 14)]

    var body: some View {
        ScrollView {
            if store.hasSnapshot {
                VStack(alignment: .leading, spacing: 16) {
                    SystemHeaderView()
                    LazyVGrid(columns: statColumns, spacing: 14) {
                        statCards
                    }
                    HStack(alignment: .top, spacing: 14) {
                        ThroughputCard()
                            .frame(maxWidth: .infinity)
                        ClientsByBandCard()
                            .frame(width: 300)
                    }
                    RFEnvironmentCard { selection = .rfEnvironment }
                    HStack(alignment: .top, spacing: 14) {
                        AccessPointsSummaryCard { ap in
                            store.focusAccessPointMAC = ap.mac
                            selection = .accessPoints
                        }
                        .frame(maxWidth: .infinity)
                        TopClientsCard { client in
                            store.focusClientMAC = client.mac
                            selection = .clients
                        }
                        .frame(maxWidth: .infinity)
                    }
                    RecentEventsCard { selection = .events }
                }
                .padding(20)
            } else {
                loadingState
            }
        }
        .navigationSubtitle(store.lastUpdated.map { "Updated \(Format.relative($0))" } ?? "")
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading data from the controller…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 400)
    }

    @ViewBuilder
    private var statCards: some View {
        let online = store.onlineAccessPointCount
        let total = store.accessPoints.count
        let enabledWLANs = store.wlans.filter(\.isEnabled).count
        let blocked = store.clients.filter(\.isBlocked).count
        let todayBytes = store.totals.rxBytesToday + store.totals.txBytesToday

        StatCard(title: "Access Points", value: "\(online)/\(total)", caption: online == total ? "all online" : "\(total - online) offline",
                 systemImage: "antenna.radiowaves.left.and.right", tint: online == total ? .green : .orange) { selection = .accessPoints }
        StatCard(title: "Clients", value: "\(store.clients.count)",
                 caption: blocked > 0 ? "\(blocked) blocked" : "connected across \(store.clientsByBand.count) band\(store.clientsByBand.count == 1 ? "" : "s")",
                 systemImage: "laptopcomputer.and.iphone", tint: .blue) { selection = .clients }
        StatCard(title: "Wi-Fi Networks", value: "\(enabledWLANs)/\(store.wlans.count)", caption: "enabled", systemImage: "wifi", tint: .teal) { selection = .wlans }
        StatCard(title: "Alarms", value: "\(store.alarms.count)", caption: store.alarms.isEmpty ? "nothing outstanding" : "needs attention",
                 systemImage: "bell.badge", tint: store.alarms.isEmpty ? .green : .red) {
            store.focusAlarmsOnly = true
            selection = .events
        }
        StatCard(title: "Traffic today", value: Format.bytes(todayBytes),
                 caption: "↓ \(Format.bytes(store.totals.txBytesToday)) · ↑ \(Format.bytes(store.totals.rxBytesToday))",
                 systemImage: "arrow.up.arrow.down", tint: .indigo) { selection = .clients }
        StatCard(title: "Rogue APs", value: "\(store.totals.rogueCount)", caption: "detected nearby",
                 systemImage: "eye.trianglebadge.exclamationmark", tint: store.totals.rogueCount > 0 ? .orange : .secondary) { selection = .rfEnvironment }
    }
}

struct SystemHeaderView: View {
    @Environment(ControllerStore.self) private var store

    var body: some View {
        let system = store.system
        HStack(alignment: .center, spacing: 18) {
            Image(systemName: "wifi.router.fill")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(
                    LinearGradient(colors: [Color(white: 0.30), Color(white: 0.06)], startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(system.name.isEmpty ? "Unleashed network" : system.name)
                    .font(.title2.weight(.semibold))
                HStack(spacing: 10) {
                    if !system.model.isEmpty { Text("Master \(system.model)") }
                    if !system.version.isEmpty { Text("Firmware \(system.version)") }
                    if !system.serial.isEmpty { Text("S/N \(system.serial)") }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Chip(text: "Up \(Format.uptime(system.uptime))", systemImage: "clock")
                    if !system.managementIP.isEmpty {
                        Chip(text: system.managementIP, systemImage: "network")
                    }
                    if !system.gateway.isEmpty {
                        Chip(text: "GW \(system.gateway)", systemImage: "arrow.turn.up.right")
                    }
                    if store.summary.maxAccessPoints != nil || store.summary.maxClients != nil {
                        Chip(text: "Limits \(store.summary.maxAccessPoints ?? 0) APs · \(store.summary.maxClients ?? 0) clients", systemImage: "gauge.with.dots.needle.33percent")
                    }
                }
            }
            Spacer()
            if let connected = system.internetConnected {
                VStack(alignment: .trailing, spacing: 6) {
                    StatusPill(text: connected ? "Internet connected" : "Internet down", color: connected ? .green : .red)
                    if !system.wanIP.isEmpty {
                        Text("WAN \(system.wanIP)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.quaternary))
    }
}

struct ThroughputPoint: Identifiable {
    var id: String { "\(time.timeIntervalSince1970)-\(direction)" }
    var time: Date
    var direction: String
    var mbps: Double
}

enum ThroughputMath {
    /// The controller counts from the access point's side: `tx` is what the AP sends to
    /// clients (their downloads) and `rx` is what it receives from them (their uploads).
    static func points(from history: TrafficHistory, bucketSeconds: Double = 60) -> [ThroughputPoint] {
        history.samples.flatMap { sample -> [ThroughputPoint] in
            let download = Double(sample.txBytes) * 8 / bucketSeconds / 1_000_000
            let upload = Double(sample.rxBytes) * 8 / bucketSeconds / 1_000_000
            return [
                ThroughputPoint(time: sample.time, direction: "Download", mbps: download),
                ThroughputPoint(time: sample.time, direction: "Upload", mbps: upload),
            ]
        }
    }
}

struct ThroughputChart: View {
    var points: [ThroughputPoint]
    var showSeconds = false

    var body: some View {
        Chart(points) { point in
            AreaMark(x: .value("Time", point.time), y: .value("Mbps", point.mbps), stacking: .unstacked)
                .foregroundStyle(by: .value("Direction", point.direction))
                .interpolationMethod(.monotone)
                .opacity(0.18)
            LineMark(x: .value("Time", point.time), y: .value("Mbps", point.mbps))
                .foregroundStyle(by: .value("Direction", point.direction))
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2))
        }
        .chartForegroundStyleScale(["Download": Color.blue, "Upload": Color.orange])
        .chartYAxisLabel("Mbps")
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine()
                if showSeconds {
                    AxisValueLabel(format: .dateTime.hour().minute().second())
                } else {
                    AxisValueLabel(format: .dateTime.hour().minute())
                }
            }
        }
        .chartLegend(position: .top, alignment: .trailing)
    }
}

struct ThroughputCard: View {
    @Environment(ControllerStore.self) private var store

    var body: some View {
        if store.isLive && store.liveSamples.count >= 2 {
            liveBody
        } else {
            historyBody
        }
    }

    private var liveBody: some View {
        let samples = store.liveSamples
        let points = samples.flatMap { sample in
            [ThroughputPoint(time: sample.time, direction: "Download", mbps: sample.downloadBitsPerSecond / 1_000_000),
             ThroughputPoint(time: sample.time, direction: "Upload", mbps: sample.uploadBitsPerSecond / 1_000_000)]
        }
        let latest = samples.last
        let source = store.liveSource.isEmpty ? "Ethernet port" : (store.system.gatewayModeEnabled ? "internet (WAN \(store.liveSource))" : "Ethernet \(store.liveSource)")
        return Card("Throughput", subtitle: "Traffic through the master AP's \(source), sampled every \(Int(store.settings.liveInterval)) s", systemImage: "waveform.path.ecg") {
            ThroughputChart(points: points, showSeconds: true)
                .frame(height: 190)
            if let latest {
                HStack(spacing: 16) {
                    Label("↓ \(Format.bitrate(bitsPerSecond: latest.downloadBitsPerSecond))", systemImage: "arrow.down")
                        .foregroundStyle(.blue)
                    Label("↑ \(Format.bitrate(bitsPerSecond: latest.uploadBitsPerSecond))", systemImage: "arrow.up")
                        .foregroundStyle(.orange)
                    Spacer()
                    Text("Now · \(Format.time(latest.time))")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }
        }
    }

    private var historyBody: some View {
        let history = store.summary.history
        let points = ThroughputMath.points(from: history)
        let latest = history.samples.last
        return Card("Throughput", subtitle: "Wireless traffic across all access points, one-minute buckets", systemImage: "waveform.path.ecg") {
            if points.isEmpty {
                Text("No traffic history yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                ThroughputChart(points: points)
                    .frame(height: 190)
                if let latest {
                    HStack(spacing: 16) {
                        Label("↓ \(Format.bitrate(bitsPerSecond: Double(latest.txBytes) * 8 / 60))", systemImage: "arrow.down")
                            .foregroundStyle(.blue)
                        Label("↑ \(Format.bitrate(bitsPerSecond: Double(latest.rxBytes) * 8 / 60))", systemImage: "arrow.up")
                            .foregroundStyle(.orange)
                        Spacer()
                        Text("Last minute · \(Format.time(latest.time))")
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
        }
    }
}

struct ClientsByBandCard: View {
    @Environment(ControllerStore.self) private var store

    private func bandColor(_ band: RadioBand) -> Color {
        switch band {
        case .ghz2_4: return .orange
        case .ghz5: return .blue
        case .ghz6: return .purple
        case .unknown: return .gray
        }
    }

    var body: some View {
        let data = store.clientsByBand
        Card("Clients by band", systemImage: "chart.pie") {
            if data.isEmpty {
                Text("No clients connected.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                Chart(data) { item in
                    SectorMark(angle: .value("Clients", item.count), innerRadius: .ratio(0.62), angularInset: 1.5)
                        .cornerRadius(4)
                        .foregroundStyle(by: .value("Band", item.band.label))
                }
                .chartForegroundStyleScale(domain: data.map { $0.band.label }, range: data.map { bandColor($0.band) })
                .chartLegend(position: .bottom, alignment: .center)
                .chartBackground { _ in
                    VStack(spacing: 0) {
                        Text("\(store.clients.count)")
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                        Text("clients")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .offset(y: -12)
                }
                .frame(height: 210)
            }
        }
    }
}

struct AccessPointsSummaryCard: View {
    @Environment(ControllerStore.self) private var store
    var open: (AccessPoint) -> Void

    var body: some View {
        Card("Access points", subtitle: "\(store.onlineAccessPointCount) of \(store.accessPoints.count) online", systemImage: "antenna.radiowaves.left.and.right") {
            if store.accessPoints.isEmpty {
                Text("No access points reported.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(store.accessPoints) { ap in
                        ClickableRow(action: { open(ap) }) {
                        HStack(spacing: 12) {
                            StatusDot(color: ap.isOnline ? .green : .red)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(ap.displayName).fontWeight(.medium)
                                    if ap.isMaster { StatusPill(text: "Master", color: .accentColor) }
                                }
                                Text("\(ap.model) · \(ap.ip)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(ap.clientCount) client\(ap.clientCount == 1 ? "" : "s")")
                                Text(ap.radios.map { "\($0.band.shortLabel) ch \($0.channel)" }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(ap.isOnline ? Format.uptime(ap.uptime) : "offline")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 70, alignment: .trailing)
                        }
                        .padding(.vertical, 8)
                        }
                        if ap.id != store.accessPoints.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

struct TopClientsCard: View {
    @Environment(ControllerStore.self) private var store
    var open: (WirelessClient) -> Void

    var body: some View {
        let top = store.clients.sorted { $0.totalBytes > $1.totalBytes }.prefix(6)
        let maxBytes = max(1, top.first?.totalBytes ?? 1)
        Card("Top clients by traffic", subtitle: "Total bytes since association", systemImage: "chart.bar.xaxis") {
            if top.isEmpty {
                Text("No clients connected.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(top)) { client in
                        ClickableRow(action: { open(client) }) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(client.displayName).fontWeight(.medium).lineLimit(1)
                                    BandBadge(band: client.band)
                                    Spacer()
                                    Text(Format.bytes(client.totalBytes))
                                        .foregroundStyle(.secondary)
                                }
                                .font(.callout)
                                ProgressView(value: Double(client.totalBytes), total: Double(maxBytes))
                                    .tint(.accentColor)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct RecentEventsCard: View {
    @Environment(ControllerStore.self) private var store
    var open: () -> Void

    var body: some View {
        let recent = store.events.prefix(6)
        Card("Recent activity", subtitle: "Latest events and alarms", systemImage: "bell") {
            if recent.isEmpty {
                Text("No events reported.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recent)) { event in
                        ClickableRow(action: open) {
                        HStack(alignment: .top, spacing: 12) {
                            SeverityBadge(severity: event.severity)
                                .frame(width: 70, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.message)
                                    .lineLimit(2)
                                HStack(spacing: 8) {
                                    if event.kind == .alarm {
                                        Text("Alarm · \(event.alarmName)")
                                    }
                                    if !event.apName.isEmpty {
                                        Text(event.apName)
                                    }
                                    Text(Format.dateTime(event.time))
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 7)
                        }
                        if event.id != recent.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

struct RFEnvironmentCard: View {
    @Environment(ControllerStore.self) private var store
    var openPage: () -> Void

    private var bands: [RadioBand] {
        let present = Set(store.neighbors.map(\.band)).union(store.ownRadioMarkers.map(\.band))
        let shown = [RadioBand.ghz2_4, .ghz5, .ghz6].filter { present.contains($0) }
        return shown.isEmpty ? [.ghz2_4, .ghz5] : shown
    }

    var body: some View {
        Card("RF environment", subtitle: "Neighbouring networks heard by your access points' background scans; dashed lines are your own channels.", systemImage: "waveform.badge.magnifyingglass") {
            if store.neighbors.isEmpty {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Waiting for the first background scan…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(bands, id: \.self) { band in
                        bandColumn(band)
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .background(bandPanelColor(band), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(bandAccent(band).opacity(0.35)))
                    }
                }
            }
            HStack {
                Spacer()
                Button(action: openPage) {
                    Label("Open RF Environment", systemImage: "arrow.right.circle")
                }
                .buttonStyle(.link)
            }
        }
        .task {
            if store.neighbors.isEmpty { await store.refreshNeighbors() }
        }
    }

    private func bandAccent(_ band: RadioBand) -> Color {
        switch band {
        case .ghz2_4: return .orange
        case .ghz5: return .blue
        case .ghz6: return .purple
        case .unknown: return .gray
        }
    }

    private func bandPanelColor(_ band: RadioBand) -> Color {
        bandAccent(band).opacity(0.06)
    }

    private func bandColumn(_ band: RadioBand) -> some View {
        let neighbors = store.neighbors.filter { $0.band == band }
        let radios = store.ownRadioMarkers.filter { $0.band == band }
        let loads = ChannelLoad.compute(band: band, neighbors: store.neighbors, ownRadios: radios.map { ($0.apName, $0.band, $0.channel) })
        let quietest = loads.min { ($0.score, $0.channel) < ($1.score, $1.channel) }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: band == .ghz2_4 ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.circle")
                    .foregroundStyle(bandAccent(band))
                Text(band.label)
                    .font(.headline)
                    .foregroundStyle(bandAccent(band))
                Text("· \(neighbors.count) neighbour\(neighbors.count == 1 ? "" : "s")")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                if let quietest {
                    Text("Quietest: ch \(quietest.channel)")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            Divider()
            SpectrumChart(band: band, neighbors: neighbors, ownRadios: radios, compact: true)
                .frame(height: 150)
            if !neighbors.isEmpty {
                Text(neighbors.sorted { $0.bestSignal > $1.bestSignal }.prefix(3)
                        .map { "\($0.displaySSID) ch \($0.channel) (\($0.bestSignal) dB)" }
                        .joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            ForEach(radios) { radio in
                let load = loads.first { $0.channel == radio.channel }
                HStack(spacing: 6) {
                    StatusDot(color: (load?.networkCount ?? 0) > 3 ? .orange : .green, size: 7)
                    Text("\(radio.apName) · ch \(radio.channel) / \(radio.width) MHz")
                    Spacer()
                    if let load {
                        Text(load.networkCount == 0 ? "clear" : "\(load.networkCount) overlapping, strongest \(load.strongestSignal) dB")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
            }
        }
    }
}
