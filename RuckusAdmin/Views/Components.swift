import SwiftUI

/// A rounded panel used throughout the dashboard.
struct Card<Content: View>: View {
    var title: String?
    var subtitle: String?
    var systemImage: String?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, subtitle: String? = nil, systemImage: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if title != nil || subtitle != nil {
                VStack(alignment: .leading, spacing: 2) {
                    if let title {
                        HStack(spacing: 6) {
                            if let systemImage {
                                Image(systemName: systemImage)
                                    .foregroundStyle(Color.accentColor)
                            }
                            Text(title)
                                .font(.headline)
                        }
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.quaternary))
    }
}

struct StatCard: View {
    var title: String
    var value: String
    var caption: String
    var systemImage: String
    var tint: Color = .accentColor
    var action: (() -> Void)? = nil

    @State private var isHovering = false

    var body: some View {
        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
                .onHover { isHovering = $0 }
                .help("Open \(title)")
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(tint)
            }
            Text(value)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            HStack {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if action != nil {
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isHovering ? tint : Color.secondary.opacity(0.4))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(isHovering ? tint.opacity(0.6) : Color.clear.opacity(0), lineWidth: 1))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.quaternary).opacity(isHovering ? 0 : 1))
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

struct StatusDot: View {
    var color: Color
    var size: CGFloat = 9

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay(Circle().stroke(color.opacity(0.3), lineWidth: 3))
    }
}

struct StatusPill: View {
    var text: String
    var color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }
}

struct Chip: View {
    var text: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
        }
        .font(.caption)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(.quaternary, in: Capsule())
    }
}

struct SignalBars: View {
    /// 0…1
    var quality: Double
    var color: Color?

    private var filledBars: Int {
        Int((quality * 4).rounded(.up))
    }

    private var barColor: Color {
        if let color { return color }
        if quality >= 0.6 { return .green }
        if quality >= 0.35 { return .orange }
        return .red
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(index < filledBars ? barColor : Color.secondary.opacity(0.25))
                    .frame(width: 4, height: CGFloat(5 + index * 3))
            }
        }
        .accessibilityLabel("Signal \(Int(quality * 100)) percent")
    }
}

struct SeverityBadge: View {
    var severity: EventSeverity

    var color: Color {
        switch severity {
        case .high: return .red
        case .medium: return .orange
        case .low: return .blue
        case .unknown: return .gray
        }
    }

    var body: some View {
        StatusPill(text: severity.label, color: color)
    }
}

struct BandBadge: View {
    var band: RadioBand

    var color: Color {
        switch band {
        case .ghz2_4: return .orange
        case .ghz5: return .blue
        case .ghz6: return .purple
        case .unknown: return .gray
        }
    }

    var body: some View {
        StatusPill(text: band.shortLabel, color: color)
    }
}

/// A two-column key/value grid for detail panes.
struct FactGrid: View {
    var facts: [(String, String)]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 7) {
            ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                GridRow {
                    Text(fact.0)
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    Text(fact.1.isEmpty ? "–" : fact.1)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.callout)
            }
        }
    }
}

struct MeterRow: View {
    var label: String
    var fraction: Double?
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(detail)
            }
            .font(.callout)
            ProgressView(value: min(1, max(0, fraction ?? 0)))
                .tint((fraction ?? 0) > 0.85 ? .red : ((fraction ?? 0) > 0.65 ? .orange : .accentColor))
        }
    }
}

struct RawAttributesView: View {
    var attributes: [String: String]

    var body: some View {
        DisclosureGroup("Raw attributes (\(attributes.count))") {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(attributes.keys.sorted(), id: \.self) { key in
                    HStack(alignment: .top, spacing: 8) {
                        Text(key)
                            .foregroundStyle(.secondary)
                            .frame(width: 170, alignment: .trailing)
                        Text(attributes[key] ?? "")
                            .textSelection(.enabled)
                    }
                    .font(.system(.caption2, design: .monospaced))
                }
            }
            .padding(.top, 6)
        }
        .font(.callout)
    }
}

struct SectionHeader: View {
    var title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.top, 6)
    }
}

struct ErrorBanner: View {
    var message: String
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .lineLimit(2)
            Spacer()
            Button("Dismiss", action: onDismiss)
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
    }
}

/// Wraps a dashboard row so it highlights on hover and acts as a button.
struct ClickableRow<Content: View>: View {
    var action: () -> Void
    @ViewBuilder var content: Content
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            content
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .background(isHovering ? Color.accentColor.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, -6)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}
