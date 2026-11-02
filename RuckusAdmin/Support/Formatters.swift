import Foundation

enum Format {
    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .decimal
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        formatter.zeroPadsFractionDigits = false
        return formatter
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    static func bytes(_ value: Int64?) -> String {
        guard let value else { return "–" }
        return byteFormatter.string(fromByteCount: value)
    }

    static func bitrate(bitsPerSecond: Double) -> String {
        let units = ["bps", "kbps", "Mbps", "Gbps"]
        var value = bitsPerSecond
        var unitIndex = 0
        while value >= 1000, unitIndex < units.count - 1 {
            value /= 1000
            unitIndex += 1
        }
        let digits = value >= 100 || unitIndex == 0 ? 0 : 1
        return String(format: "%.\(digits)f %@", value, units[unitIndex])
    }

    static func uptime(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds >= 0 else { return "–" }
        let total = Int(seconds)
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(total)s"
    }

    static func relative(_ date: Date?) -> String {
        guard let date else { return "–" }
        if abs(date.timeIntervalSinceNow) < 5 { return "just now" }
        return relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    static func dateTime(_ date: Date?) -> String {
        guard let date else { return "–" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    static func time(_ date: Date?) -> String {
        guard let date else { return "–" }
        return date.formatted(date: .omitted, time: .standard)
    }

    static func mac(_ value: String) -> String {
        value.uppercased()
    }

    static func percent(_ fraction: Double?) -> String {
        guard let fraction else { return "–" }
        return String(format: "%.0f%%", fraction * 100)
    }

    static func orDash(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "–" }
        return value
    }
}
