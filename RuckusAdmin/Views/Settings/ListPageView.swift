import SwiftUI

/// Generic table + editor for a list component (roles, users, AAA servers, …).
struct ListPageView: View {
    @Environment(ControllerStore.self) private var store
    var spec: ListPageSpec
    var embedded = false

    @State private var rows: [ListRow] = []
    @State private var selection: ListRow.ID?
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var editor: EditorTarget?
    @State private var confirmDelete = false
    @State private var showDetails = false

    private struct EditorTarget: Identifiable {
        var id: String { row?.id ?? "new" }
        var row: ListRow?
    }

    private var selectedRow: ListRow? { rows.first { $0.id == selection } }

    var body: some View {
        Group {
            if embedded {
                VStack(alignment: .leading, spacing: 12) { content }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) { content }
                        .padding(20)
                }
            }
        }
        .task(id: spec.id) { await load() }
        .sheet(item: $editor) { target in
            ListEditorView(spec: spec, row: target.row) { values in
                if let row = target.row {
                    try await store.updateRow(spec, row: row, values: values)
                } else {
                    try await store.addRow(spec, values: values)
                }
                await load()
            }
            .environment(store)
        }
        .confirmationDialog("Delete \(selectedRow?["name"] ?? "entry")?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                guard let row = selectedRow else { return }
                Task {
                    do { try await store.deleteRow(spec, row: row); await load() } catch { errorText = error.localizedDescription }
                }
            }
        } message: {
            Text("This removes the entry from the controller.")
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
            Button { Task { await load() } } label: { Label("Reload", systemImage: "arrow.clockwise") }
            if spec.canAdd {
                Button { editor = EditorTarget(row: nil) } label: { Label("Add", systemImage: "plus") }
            }
            if spec.canEdit {
                Button { if let row = selectedRow { editor = EditorTarget(row: row) } } label: { Label("Edit", systemImage: "pencil") }
                    .disabled(selectedRow == nil || !(selectedRow?.isEditable ?? false))
            }
            if spec.canDelete {
                Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
                    .disabled(selectedRow == nil || !(selectedRow?.isEditable ?? false))
            }
        }
        if let errorText {
            Label(errorText, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).textSelection(.enabled)
        }
        if let note = spec.note {
            Text(note).font(.callout).foregroundStyle(.secondary)
        }
        if rows.isEmpty && !isLoading {
            Text("No entries.").foregroundStyle(.secondary).padding(.vertical, 8)
        } else {
            Table(rows, selection: $selection) {
                TableColumnForEach(spec.columns) { column in
                    TableColumn(column.title) { row in
                        Text(row[column.key])
                            .foregroundStyle(row.isEditable ? .primary : .secondary)
                    }
                    .width(min: column.width.map { $0 * 0.6 }, ideal: column.width)
                }
            }
            .frame(minHeight: CGFloat(min(max(rows.count, 2), 14)) * 28 + 36)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
        }
        if let row = selectedRow {
            DisclosureGroup("Details for \(row["name"].isEmpty ? row.id : row["name"])", isExpanded: $showDetails) {
                VStack(alignment: .leading, spacing: 6) {
                    RawAttributesView(attributes: row.attributes)
                    if !row.children.isEmpty {
                        Text(XMLNode(name: spec.element, attributes: [:], children: row.children).prettyPrinted())
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                .padding(.top, 6)
            }
            .font(.callout)
        }
    }

    private func load() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            rows = try await store.loadList(spec)
        } catch {
            errorText = error.localizedDescription
        }
    }
}

struct ListEditorView: View {
    @Environment(ControllerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var spec: ListPageSpec
    var row: ListRow?
    var onSave: ([String: String]) async throws -> Void

    @State private var values = ConfigValues()
    @State private var options: [String: [ConfigOption]] = [:]
    @State private var errorText: String?
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(row == nil ? "New \(spec.element)" : "Edit \(row?["name"] ?? spec.element)")
                .font(.title3.weight(.semibold))
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 10) {
                ForEach(spec.fields.filter { $0.visibleWhen?(values) ?? true }) { field in
                    GridRow {
                        Text(field.label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                        VStack(alignment: .leading, spacing: 3) {
                            ConfigFieldControl(field: field, values: $values, options: options[field.id] ?? [])
                            if let help = field.help { Text(help).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button {
                    Task { await save() }
                } label: {
                    HStack { if isSaving { ProgressView().controlSize(.small) }; Text("Save") }.frame(minWidth: 60)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving)
            }
        }
        .padding(22)
        .frame(width: 560)
        .task {
            if let row {
                values.attributes[spec.elementPath] = row.attributes
            }
            for field in spec.fields {
                if case .dynamicPicker(let dynamic) = field.kind {
                    options[field.id] = (try? await store.loadOptions(dynamic)) ?? []
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        errorText = nil
        defer { isSaving = false }
        var payload: [String: String] = [:]
        for field in spec.fields where field.isEditable {
            payload[field.key] = values[spec.elementPath, field.key]
        }
        do {
            try await onSave(payload)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
