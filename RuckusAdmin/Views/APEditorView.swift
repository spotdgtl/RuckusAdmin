import SwiftUI

/// Edit an access point's name, placement and per-radio overrides.
struct APEditorView: View {
    @Environment(ControllerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var ap: AccessPoint

    @State private var name = ""
    @State private var description = ""
    @State private var location = ""
    @State private var configNode: XMLNode?
    @State private var radioChannel: [String: String] = [:]
    @State private var radioWidth: [String: String] = [:]
    @State private var radioPower: [String: String] = [:]
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorText: String?

    private var configRadios: [XMLNode] { configNode?.all("radio") ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit \(ap.displayName)").font(.title3.weight(.semibold))
            Text("\(ap.model) · \(Format.mac(ap.mac))").foregroundStyle(.secondary)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 10) {
                GridRow {
                    Text("Device name").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                    TextField("", text: $name).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Description").foregroundStyle(.secondary)
                    TextField("", text: $description).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Location").foregroundStyle(.secondary)
                    TextField("", text: $location).textFieldStyle(.roundedBorder)
                }
            }
            if isLoading {
                ProgressView().controlSize(.small)
            } else if !configRadios.isEmpty {
                Text("Radio overrides").font(.headline)
                Text("* means “use the AP group setting”. Channel widths are in MHz; transmit power is a dB reduction from full (0 = full).")
                    .font(.caption).foregroundStyle(.secondary)
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 8) {
                    GridRow {
                        Text("Radio").font(.caption).foregroundStyle(.secondary)
                        Text("Channel").font(.caption).foregroundStyle(.secondary)
                        Text("Width").font(.caption).foregroundStyle(.secondary)
                        Text("Tx power").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(configRadios, id: \.self) { radio in
                        let type = radio["radio-type"] ?? ""
                        GridRow {
                            BandBadge(band: RadioBand.from(band: nil, radioType: type))
                            Picker("", selection: binding(radioChannel, type, "*")) {
                                ForEach(channelOptions(for: type), id: \.self) { Text($0 == "*" ? "Group default" : $0).tag($0) }
                            }.labelsHidden().frame(width: 150)
                            Picker("", selection: binding(radioWidth, type, "*")) {
                                ForEach(["*", "20", "40", "80", "160"], id: \.self) { Text($0 == "*" ? "Group default" : "\($0) MHz").tag($0) }
                            }.labelsHidden().frame(width: 150)
                            TextField("*", text: binding(radioPower, type, "*")).textFieldStyle(.roundedBorder).frame(width: 70)
                        }
                    }
                }
            }
            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).textSelection(.enabled)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button {
                    Task { await save() }
                } label: {
                    HStack { if isSaving { ProgressView().controlSize(.small) }; Text("Save") }.frame(minWidth: 70)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving || isLoading || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 600)
        .task { await load() }
    }

    private func binding(_ dict: [String: String], _ key: String, _ fallback: String) -> Binding<String> {
        Binding(
            get: {
                if dict == radioChannel { return radioChannel[key] ?? fallback }
                if dict == radioWidth { return radioWidth[key] ?? fallback }
                return radioPower[key] ?? fallback
            },
            set: { value in
                if dict == radioChannel { radioChannel[key] = value }
                else if dict == radioWidth { radioWidth[key] = value }
                else { radioPower[key] = value }
            }
        )
    }

    private func channelOptions(for radioType: String) -> [String] {
        let band = RadioBand.from(band: nil, radioType: radioType)
        return ["*"] + WiFiChannels.channels(for: band).map(String.init)
    }

    private func load() async {
        name = ap.name
        description = ap.description
        location = ap.location
        do {
            configNode = try await store.accessPointConfigNode(mac: ap.mac)
            for radio in configRadios {
                let type = radio["radio-type"] ?? ""
                radioChannel[type] = radio["channel"] ?? "*"
                radioWidth[type] = radio["channelization"] ?? "*"
                radioPower[type] = radio["tx-power"] ?? "*"
            }
        } catch {
            errorText = error.localizedDescription
        }
        isLoading = false
    }

    private func save() async {
        isSaving = true
        errorText = nil
        defer { isSaving = false }
        let id = configNode?["id"] ?? ap.raw["id"] ?? ""
        var radios: [XMLNode] = []
        for radio in configRadios {
            let type = radio["radio-type"] ?? ""
            var node = XMLNode(name: "radio", attributes: ["radio-type": type])
            if let radioID = radio["radio-id"] { node.attributes["radio-id"] = radioID }
            node.attributes["channel"] = radioChannel[type] ?? "*"
            node.attributes["channelization"] = radioWidth[type] ?? "*"
            node.attributes["tx-power"] = radioPower[type] ?? "*"
            radios.append(node)
        }
        do {
            try await store.updateAccessPoint(id: id, mac: ap.mac, attributes: [
                "devname": name,
                "description": description,
                "location": location,
            ], radios: radios)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
