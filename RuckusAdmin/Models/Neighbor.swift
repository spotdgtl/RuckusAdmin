import Foundation

/// One sighting of a neighbouring network by one of our access points.
struct NeighborDetection: Sendable, Hashable, Identifiable {
    var id: String { apMAC }
    var apMAC: String
    var apName: String
    /// Signal above the noise floor in dB, as reported by the scanning AP.
    var rssi: Int
    var lastSeen: Date?
}

/// A BSSID seen by the controller's background scanning ("rogue" in Ruckus terms).
struct NeighborNetwork: Sendable, Hashable, Identifiable {
    var id: String { mac }
    var mac: String
    var ssid: String = ""
    var band: RadioBand = .unknown
    var channel: Int = 0
    var radioType: String = ""
    var isEncrypted: Bool = true
    var rogueType: String = ""
    var lastSeen: Date?
    var detections: [NeighborDetection] = []
    var isOwnNetwork = false
    var raw: [String: String] = [:]

    var displaySSID: String { ssid.isEmpty ? "(hidden network)" : ssid }
    var bestSignal: Int { detections.map(\.rssi).max() ?? 0 }
    var seenBy: String { detections.map(\.apName).filter { !$0.isEmpty }.joined(separator: ", ") }

    /// The scan does not report channel width, so assume the common width per radio type.
    var channelWidth: Int {
        let type = radioType.lowercased()
        switch band {
        case .ghz2_4: return 20
        case .ghz5: return (type.contains("ac") || type.contains("ax")) ? 80 : 40
        case .ghz6: return 80
        case .unknown: return 20
        }
    }

    var centerFrequency: Double { WiFiChannels.centerFrequency(channel: channel, band: band) }
    var lowFrequency: Double { centerFrequency - Double(channelWidth) / 2 }
    var highFrequency: Double { centerFrequency + Double(channelWidth) / 2 }
}

enum WiFiChannels {
    static func centerFrequency(channel: Int, band: RadioBand) -> Double {
        switch band {
        case .ghz2_4: return channel == 14 ? 2484 : 2407 + 5 * Double(channel)
        case .ghz5: return 5000 + 5 * Double(channel)
        case .ghz6: return 5950 + 5 * Double(channel)
        case .unknown: return 0
        }
    }

    static func channels(for band: RadioBand) -> [Int] {
        switch band {
        case .ghz2_4: return Array(1...13)
        case .ghz5: return [36, 40, 44, 48, 52, 56, 60, 64, 100, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140, 144, 149, 153, 157, 161, 165]
        case .ghz6: return Array(stride(from: 1, through: 233, by: 4))
        case .unknown: return []
        }
    }

    static func frequencyRange(for band: RadioBand) -> ClosedRange<Double> {
        switch band {
        case .ghz2_4: return 2400...2485
        case .ghz5: return 5160...5845
        case .ghz6: return 5940...7130
        case .unknown: return 0...1
        }
    }
}

/// Congestion estimate for one channel: overlapping neighbours weighted by their signal.
struct ChannelLoad: Identifiable, Sendable, Hashable {
    var id: Int { channel }
    var channel: Int
    var band: RadioBand
    var networkCount: Int
    var strongestSignal: Int
    var score: Double
    var ownAccessPoints: [String]

    var isUsedByOwnAP: Bool { !ownAccessPoints.isEmpty }

    static func compute(band: RadioBand, neighbors: [NeighborNetwork], ownRadios: [(apName: String, band: RadioBand, channel: Int)]) -> [ChannelLoad] {
        let others = neighbors.filter { $0.band == band && !$0.isOwnNetwork }
        return channels(for: band).map { channel in
            let center = WiFiChannels.centerFrequency(channel: channel, band: band)
            var count = 0
            var strongest = 0
            var score = 0.0
            for neighbor in others {
                let separation = abs(neighbor.centerFrequency - center)
                let overlapLimit = (20.0 + Double(neighbor.channelWidth)) / 2
                guard separation < overlapLimit else { continue }
                count += 1
                strongest = max(strongest, neighbor.bestSignal)
                // Full weight when co-channel, tapering off for partial overlap.
                let proximity = 1 - separation / overlapLimit
                score += Double(max(neighbor.bestSignal, 5)) * (0.5 + 0.5 * proximity)
            }
            let own = ownRadios.filter { $0.band == band && $0.channel == channel }.map(\.apName)
            return ChannelLoad(channel: channel, band: band, networkCount: count, strongestSignal: strongest, score: score, ownAccessPoints: own)
        }
    }

    private static func channels(for band: RadioBand) -> [Int] {
        WiFiChannels.channels(for: band)
    }
}
