import Charts
import SwiftUI

struct OwnRadioMarker: Identifiable, Hashable {
    var id: String { "\(apMAC)-\(band.rawValue)" }
    var apMAC: String
    var apName: String
    var band: RadioBand
    var channel: Int
    var width: Int

    var centerFrequency: Double { WiFiChannels.centerFrequency(channel: channel, band: band) }
}

struct RFEnvironmentView: View {
    @Environment(ControllerStore.self) private var store
    @State private var band: RadioBand = .ghz2_4
    @State private var selection: NeighborNetwork.ID?
    @State private var sortOrder = [KeyPathComparator(\NeighborNetwork.bestSignal, order: .reverse)]

    private var availableBands: [RadioBand] {
        let present = Set(store.neighbors.map(\.band)).union(ownRadios.map(\.band))
        return RadioBand.allCases.filter { $0 != .unknown && (present.contains($0) || $0 == .ghz2_4 || $0 == .ghz5) }
    }

    private var ownRadios: [OwnRadioMarker] { store.ownRadioMarkers }

    private var neighborsInBand: [NeighborNetwork] {
        store.neighbors.filter { $0.band == band }
    }

    private var loads: [ChannelLoad] {
        ChannelLoad.compute(band: band, neighbors: store.neighbors, ownRadios: ownRadios.map { ($0.apName, $0.band, $0.channel) })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                SpectrumCard(band: band, neighbors: neighborsInBand, ownRadios: ownRadios.filter { $0.band == band })
                HStack(alignment: .top, spacing: 14) {
                    ChannelLoadCard(band: band, loads: loads)
                        .frame(maxWidth: .infinity)
                    OwnRadiosCard(radios: ownRadios.filter { $0.band == band }, loads: loads)
                        .frame(width: 300)
                }
                NeighborTableCard(neighbors: neighborsInBand, selection: $selection, sortOrder: $sortOrder)
            }
            .padding(20)
        }
        .navigationTitle("RF Environment")
        .navigationSubtitle("\(store.neighbors.count) neighbouring networks seen by background scanning")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Picker("Band", selection: $band) {
                    ForEach(availableBands, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
        .task {
            if store.neighbors.isEmpty { await store.refreshNeighbors() }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("What your access points hear")
                    .font(.title2.weight(.semibold))
                Text("Unleashed APs scan off-channel in the background and report every BSSID they detect. Signal is in dB above the noise floor as measured at the AP, so this is the interference picture from the AP's position, not from a client's.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button {
                Task { await store.refreshNeighbors() }
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
        }
    }
}

extension ControllerStore {
    /// Channel markers for every radio of every access point, used by the RF views.
    var ownRadioMarkers: [OwnRadioMarker] {
        accessPoints.flatMap { ap in
            ap.radios.compactMap { radio -> OwnRadioMarker? in
                guard let channel = Int(radio.channel), channel > 0 else { return nil }
                let width = Int(radio.channelization) ?? (radio.band == .ghz2_4 ? 20 : 80)
                return OwnRadioMarker(apMAC: ap.mac, apName: ap.displayName, band: radio.band, channel: channel, width: width == 0 ? 20 : width)
            }
        }
    }
}

/// The channel-usage chart: one block per neighbouring BSSID, with our own radios highlighted.
struct SpectrumChart: View {
    var band: RadioBand
    var neighbors: [NeighborNetwork]
    var ownRadios: [OwnRadioMarker]
    var compact = false

    /// One label per occupied channel: the strongest network there plus a count of the others.
    private var labels: [String: String] {
        guard !compact else { return [:] }
        var byChannel: [Int: [NeighborNetwork]] = [:]
        for neighbor in neighbors { byChannel[neighbor.channel, default: []].append(neighbor) }
        var result: [String: String] = [:]
        let groups = byChannel.values
            .compactMap { group -> (NeighborNetwork, Int)? in
                guard let strongest = group.max(by: { $0.bestSignal < $1.bestSignal }) else { return nil }
                return (strongest, group.count)
            }
            .sorted { $0.0.bestSignal > $1.0.bestSignal }
            .prefix(8)
        for (network, count) in groups {
            result[network.id] = count > 1 ? "\(network.displaySSID) +\(count - 1)" : network.displaySSID
        }
        return result
    }

    private var domain: ClosedRange<Double> { WiFiChannels.frequencyRange(for: band) }

    private var tickChannels: [Int] {
        switch band {
        case .ghz2_4: return compact ? [1, 3, 5, 7, 9, 11, 13] : Array(1...13)
        case .ghz5: return compact ? [36, 52, 100, 116, 132, 149, 165] : [36, 44, 52, 60, 100, 108, 116, 124, 132, 140, 149, 157, 165]
        case .ghz6: return Array(stride(from: 1, through: 233, by: compact ? 32 : 16))
        case .unknown: return []
        }
    }

    private var maxSignal: Int {
        max(40, (neighbors.map(\.bestSignal).max() ?? 0) + 8)
    }

    static func neighborTint(for band: RadioBand) -> Color {
        switch band {
        case .ghz2_4: return Color.orange.opacity(0.22)
        case .ghz5: return Color.blue.opacity(0.2)
        case .ghz6: return Color.purple.opacity(0.2)
        case .unknown: return Color.gray.opacity(0.2)
        }
    }

    var body: some View {
        Chart {
            ForEach(neighbors) { neighbor in
                RectangleMark(
                    xStart: .value("From", neighbor.lowFrequency),
                    xEnd: .value("To", neighbor.highFrequency),
                    yStart: .value("Floor", 0),
                    yEnd: .value("Signal", neighbor.bestSignal)
                )
                .foregroundStyle(neighbor.isOwnNetwork ? Color.accentColor.opacity(0.55) : SpectrumChart.neighborTint(for: band))
                .annotation(position: .top, alignment: .center, spacing: 2) {
                    if let label = labels[neighbor.id] {
                        Text(label)
                            .font(.caption2)
                            .lineLimit(1)
                            .padding(.horizontal, 3)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.85), in: RoundedRectangle(cornerRadius: 3))
                            .foregroundStyle(neighbor.isOwnNetwork ? Color.accentColor : .secondary)
                    }
                }
            }
            ForEach(ownRadios) { radio in
                RectangleMark(
                    xStart: .value("From", radio.centerFrequency - Double(radio.width) / 2),
                    xEnd: .value("To", radio.centerFrequency + Double(radio.width) / 2),
                    yStart: .value("Floor", 0),
                    yEnd: .value("Signal", maxSignal)
                )
                .foregroundStyle(Color.accentColor.opacity(0.08))
                RuleMark(x: .value("Channel", radio.centerFrequency))
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .annotation(position: .topTrailing, alignment: .leading) {
                        Text(compact ? "ch \(radio.channel)" : "\(radio.apName) · ch \(radio.channel)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: 0...Double(maxSignal))
        .chartXAxis {
            AxisMarks(values: tickChannels.map { WiFiChannels.centerFrequency(channel: $0, band: band) }) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let frequency = value.as(Double.self), let channel = tickChannels.first(where: { WiFiChannels.centerFrequency(channel: $0, band: band) == frequency }) {
                        Text("\(channel)")
                    }
                }
            }
        }
        .chartYAxis(compact ? .hidden : .automatic)
        .chartYAxisLabel(compact ? "" : "Signal (dB above noise)")
        .chartXAxisLabel(compact ? "" : "Channel")
    }
}

struct SpectrumCard: View {
    var band: RadioBand
    var neighbors: [NeighborNetwork]
    var ownRadios: [OwnRadioMarker]

    var body: some View {
        Card("Channel usage", subtitle: "Each block is one neighbouring BSSID: position is its channel, width its assumed channel width, height its signal. Your radios are highlighted.", systemImage: "waveform") {
            if neighbors.isEmpty && ownRadios.isEmpty {
                Text("No networks have been reported on this band yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                SpectrumChart(band: band, neighbors: neighbors, ownRadios: ownRadios)
                    .frame(height: 260)
            }
        }
    }
}

struct ChannelLoadCard: View {
    var band: RadioBand
    var loads: [ChannelLoad]

    private var quietest: ChannelLoad? {
        loads.min { ($0.score, $0.channel) < ($1.score, $1.channel) }
    }

    private var busiest: ChannelLoad? {
        loads.max { $0.score < $1.score }
    }

    var body: some View {
        Card("Channel congestion", subtitle: "Overlapping neighbours weighted by signal strength; lower is better", systemImage: "chart.bar") {
            if loads.isEmpty {
                Text("No channel plan for this band.")
                    .foregroundStyle(.secondary)
            } else {
                Chart(loads) { load in
                    BarMark(x: .value("Channel", "\(load.channel)"), y: .value("Load", load.score))
                        .foregroundStyle(load.isUsedByOwnAP ? Color.accentColor : barColor(for: load))
                        .annotation(position: .top) {
                            if load.networkCount > 0 {
                                Text("\(load.networkCount)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                }
                .chartYAxis(.hidden)
                .chartXAxisLabel("Channel · number above a bar is how many networks overlap it")
                .frame(height: 160)
                HStack(spacing: 16) {
                    if let quietest {
                        Label("Least congested: channel \(quietest.channel) (\(quietest.networkCount) overlapping)", systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                    }
                    if let busiest, busiest.score > 0 {
                        Label("Busiest: channel \(busiest.channel) (\(busiest.networkCount) overlapping, strongest \(busiest.strongestSignal) dB)", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.callout)
            }
        }
    }

    private func barColor(for load: ChannelLoad) -> Color {
        guard let maxScore = loads.map(\.score).max(), maxScore > 0 else { return .gray.opacity(0.5) }
        let ratio = load.score / maxScore
        if ratio > 0.66 { return .red.opacity(0.7) }
        if ratio > 0.33 { return .orange.opacity(0.7) }
        return .green.opacity(0.6)
    }
}

struct OwnRadiosCard: View {
    var radios: [OwnRadioMarker]
    var loads: [ChannelLoad]

    var body: some View {
        Card("Your radios", systemImage: "antenna.radiowaves.left.and.right") {
            if radios.isEmpty {
                Text("No radios on this band.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(radios) { radio in
                        let load = loads.first { $0.channel == radio.channel }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(radio.apName).fontWeight(.medium)
                            Text("Channel \(radio.channel) · \(radio.width) MHz")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            if let load {
                                Text(load.networkCount == 0
                                     ? "No neighbours overlap this channel"
                                     : "\(load.networkCount) neighbour\(load.networkCount == 1 ? "" : "s") overlap, strongest \(load.strongestSignal) dB")
                                    .font(.caption)
                                    .foregroundStyle(load.networkCount > 3 ? .orange : .secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct NeighborTableCard: View {
    var neighbors: [NeighborNetwork]
    @Binding var selection: NeighborNetwork.ID?
    @Binding var sortOrder: [KeyPathComparator<NeighborNetwork>]

    var body: some View {
        Card("Neighbouring networks", subtitle: "\(neighbors.count) on this band", systemImage: "list.bullet") {
            if neighbors.isEmpty {
                Text("Nothing detected on this band.")
                    .foregroundStyle(.secondary)
            } else {
                Table(neighbors.sorted(using: sortOrder), selection: $selection, sortOrder: $sortOrder) {
                    TableColumn("Network", value: \.displaySSID) { neighbor in
                        HStack(spacing: 6) {
                            Text(neighbor.displaySSID)
                                .foregroundStyle(neighbor.ssid.isEmpty ? .secondary : .primary)
                            if neighbor.isOwnNetwork {
                                StatusPill(text: "Yours", color: .accentColor)
                            }
                        }
                    }
                    .width(min: 160, ideal: 220)
                    TableColumn("BSSID") { neighbor in
                        Text(Format.mac(neighbor.mac)).font(.system(.body, design: .monospaced))
                    }
                    .width(min: 140, ideal: 150)
                    TableColumn("Channel", value: \.channel) { neighbor in
                        Text("\(neighbor.channel)")
                    }
                    .width(min: 60, ideal: 70)
                    TableColumn("Signal", value: \.bestSignal) { neighbor in
                        HStack(spacing: 6) {
                            SignalBars(quality: Double(neighbor.bestSignal) / 50)
                            Text("\(neighbor.bestSignal) dB")
                        }
                    }
                    .width(min: 90, ideal: 100)
                    TableColumn("Radio", value: \.radioType)
                        .width(min: 90, ideal: 110)
                    TableColumn("Security") { neighbor in
                        Text(neighbor.isEncrypted ? "Encrypted" : "Open")
                            .foregroundStyle(neighbor.isEncrypted ? .primary : Color.orange)
                    }
                    .width(min: 70, ideal: 90)
                    TableColumn("Seen by", value: \.seenBy)
                        .width(min: 100, ideal: 130)
                    TableColumn("Last seen") { neighbor in
                        Text(Format.relative(neighbor.lastSeen))
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 90, ideal: 110)
                }
                .frame(minHeight: CGFloat(min(neighbors.count, 12)) * 28 + 40)
            }
        }
    }
}
