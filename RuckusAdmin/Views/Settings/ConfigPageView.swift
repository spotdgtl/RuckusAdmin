import SwiftUI

/// Generic editor for a `ConfigPageSpec`: reads the controller's elements, renders the fields
/// and writes them back with `IS_PARTIAL` exactly like the stock web forms.
struct ConfigPageView: View {
    @Environment(ControllerStore.self) private var store
    var spec: ConfigPageSpec
    var embedded = false

    @State private var values = ConfigValues()
    @State private var original = ConfigValues()
    @State private var options: [String: [ConfigOption]] = [:]
    @State private var isLoading = false
    @State private var isApplying = false
    @State private var errorText: String?
    @State private var statusText: String?
    @State private var confirmApply = false

    private var hasChanges: Bool { values != original }

    var body: some View {
        Group {
            if embedded {
                VStack(alignment: .leading, spacing: 12) {
                    content
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        content
                    }
                    .padding(20)
                }
            }
        }
        .task(id: spec.id) { await load() }
        .confirmationDialog("Apply changes?", isPresented: $confirmApply, titleVisibility: .visible) {
            Button("Apply", role: .destructive) { Task { await apply() } }
        } message: {
            Text(spec.applyWarning ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(spec.title).font(embedded ? .title3.weight(.semibold) : .title2.weight(.semibold))
                Text(spec.subtitle).foregroundStyle(.secondary)
            }
            Spacer()
            if isLoading { ProgressView().controlSize(.small) }
            Button {
                Task { await load() }
            } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }
            .accessibilityLabel("Reload")
            .disabled(isLoading || isApplying)
        }
        if let errorText {
            Label(errorText, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
        ForEach(spec.sections) { section in
            sectionCard(section)
        }
        HStack {
            if let statusText {
                Label(statusText, systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            }
            Spacer()
            Button("Revert") { values = original; statusText = nil }
                .disabled(!hasChanges || isApplying)
                .accessibilityLabel("Revert")
            Button {
                if spec.applyWarning != nil { confirmApply = true } else { Task { await apply() } }
            } label: {
                HStack {
                    if isApplying { ProgressView().controlSize(.small) }
                    Text("Apply")
                }
                .frame(minWidth: 70)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("s", modifiers: .command)
            .accessibilityLabel("Apply")
            .help("Apply changes (⌘S)")
            .disabled(!hasChanges || isApplying || isLoading || spec.writes.isEmpty)
        }
    }

    private func sectionCard(_ section: ConfigSection) -> some View {
        let visible = section.fields.filter { $0.visibleWhen?(values) ?? true }
        return Card(section.title, subtitle: section.footer, systemImage: nil) {
            if visible.isEmpty {
                Text("Nothing to show.").foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 10) {
                    ForEach(visible) { field in
                        GridRow {
                            Text(field.label)
                                .foregroundStyle(.secondary)
                                .gridColumnAlignment(.trailing)
                                .frame(maxWidth: 260, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 3) {
                                ConfigFieldControl(field: field, values: $values, options: options[field.id] ?? [])
                                if let help = field.help {
                                    Text(help).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        errorText = nil
        statusText = nil
        defer { isLoading = false }
        do {
            let loaded = try await store.loadConfig(spec)
            original = loaded
            values = loaded
            await loadOptions()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func loadOptions() async {
        for field in spec.fields {
            if case .dynamicPicker(let dynamic) = field.kind {
                do {
                    options[field.id] = try await store.loadOptions(dynamic)
                } catch {
                    options[field.id] = []
                }
            }
        }
    }

    private func apply() async {
        isApplying = true
        errorText = nil
        defer { isApplying = false }
        do {
            try await store.applyConfig(spec, values: values, original: original)
            statusText = "Applied \(Format.time(Date()))"
            await load()
            statusText = "Applied \(Format.time(Date()))"
        } catch {
            errorText = error.localizedDescription
        }
    }
}

/// Renders one field bound to `ConfigValues`.
struct ConfigFieldControl: View {
    var field: ConfigField
    @Binding var values: ConfigValues
    var options: [ConfigOption]

    private var binding: Binding<String> {
        Binding(get: { values[field.path, field.key] }, set: { values[field.path, field.key] = $0 })
    }

    var body: some View {
        switch field.kind {
        case .text:
            TextField("", text: binding).textFieldStyle(.roundedBorder).frame(maxWidth: 360)
        case .number(let range):
            HStack {
                TextField("", text: binding).textFieldStyle(.roundedBorder).frame(width: 110)
                Text("\(range.lowerBound)–\(range.upperBound)").font(.caption).foregroundStyle(.tertiary)
            }
        case .toggle(let on, let off):
            Toggle("", isOn: Binding(
                get: { values[field.path, field.key].lowercased() == on.lowercased() },
                set: { values[field.path, field.key] = $0 ? on : off }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        case .picker(let list):
            pickerView(list)
        case .dynamicPicker:
            if options.isEmpty {
                HStack { ProgressView().controlSize(.mini); Text("Loading options…").foregroundStyle(.secondary) }
            } else {
                pickerView(options)
            }
        case .password:
            SecureField("", text: binding).textFieldStyle(.roundedBorder).frame(maxWidth: 360)
        case .readOnly:
            Text(Format.orDash(values[field.path, field.key])).textSelection(.enabled)
        case .readOnlyDate:
            Text(Format.dateTime(RuckusParsers.date(values[field.path, field.key])))
        case .multiline:
            TextEditor(text: binding)
                .font(.body)
                .frame(minHeight: 70, maxHeight: 140)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
        }
    }

    private func pickerView(_ list: [ConfigOption]) -> some View {
        var items = list
        let current = values[field.path, field.key]
        if !current.isEmpty, !items.contains(where: { $0.value == current }) {
            items.insert(ConfigOption(current, current), at: 0)
        }
        if current.isEmpty, !items.isEmpty, !items.contains(where: { $0.value.isEmpty }) {
            items.insert(ConfigOption("", "–"), at: 0)
        }
        return Picker("", selection: binding) {
            ForEach(items) { option in
                Text(option.label).tag(option.value)
            }
        }
        .labelsHidden()
        .frame(maxWidth: 360, alignment: .leading)
    }
}
