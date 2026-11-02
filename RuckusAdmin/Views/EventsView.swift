import SwiftUI

struct EventsView: View {
    @Environment(ControllerStore.self) private var store

    enum KindFilter: String, CaseIterable, Identifiable {
        case all = "All", events = "Events", alarms = "Alarms"
        var id: String { rawValue }
    }

    enum SeverityFilter: String, CaseIterable, Identifiable {
        case all = "Any severity", high = "High", medium = "Medium", low = "Low"
        var id: String { rawValue }

        var severity: EventSeverity? {
            switch self {
            case .all: return nil
            case .high: return .high
            case .medium: return .medium
            case .low: return .low
            }
        }
    }

    @State private var kind: KindFilter = .all
    @State private var severity: SeverityFilter = .all
    @State private var searchText = ""

    private var filtered: [ControllerEvent] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return store.events.filter { event in
            switch kind {
            case .all: break
            case .events: if event.kind != .event { return false }
            case .alarms: if event.kind != .alarm { return false }
            }
            if let wanted = severity.severity, event.severity != wanted { return false }
            if !query.isEmpty {
                return event.message.lowercased().contains(query)
                    || event.apName.lowercased().contains(query)
                    || event.alarmName.lowercased().contains(query)
            }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("Kind", selection: $kind) {
                    ForEach(KindFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 240)
                Picker("Severity", selection: $severity) {
                    ForEach(SeverityFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .frame(width: 150)
                Spacer()
                Text("\(filtered.count) of \(store.events.count)")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider()
            if filtered.isEmpty {
                ContentUnavailableView("No matching events", systemImage: "bell.slash",
                                       description: Text(store.events.isEmpty ? "The controller has not reported any events yet." : "Try a different filter."))
            } else {
                List(filtered) { event in
                    EventRow(event: event)
                        .listRowSeparator(.visible)
                }
                .listStyle(.inset)
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search events")
        .navigationTitle("Events & Alarms")
        .navigationSubtitle("\(store.alarms.count) alarm\(store.alarms.count == 1 ? "" : "s")")
        .task {
            if store.events.isEmpty { await store.refreshEvents() }
        }
        .onAppear(perform: consumeFocus)
        .onChange(of: store.focusAlarmsOnly) { _, _ in consumeFocus() }
    }

    private func consumeFocus() {
        guard store.focusAlarmsOnly else { return }
        kind = .alarms
        store.focusAlarmsOnly = false
    }
}

struct EventRow: View {
    var event: ControllerEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: event.kind == .alarm ? "bell.fill" : "circle.fill")
                .font(event.kind == .alarm ? .body : .system(size: 7))
                .foregroundStyle(SeverityBadge(severity: event.severity).color)
                .frame(width: 16, height: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.message)
                    .textSelection(.enabled)
                HStack(spacing: 8) {
                    SeverityBadge(severity: event.severity)
                    if event.kind == .alarm, !event.alarmName.isEmpty {
                        Chip(text: event.alarmName, systemImage: "bell")
                    }
                    if !event.apName.isEmpty {
                        Chip(text: event.apName, systemImage: "antenna.radiowaves.left.and.right")
                    }
                    if !event.category.isEmpty {
                        Text(event.category.capitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let occurrences = event.occurrences, occurrences > 1 {
                        Text("×\(occurrences)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.dateTime(event.time))
                Text(Format.relative(event.time))
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }
}
