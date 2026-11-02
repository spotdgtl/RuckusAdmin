import SwiftUI

/// Create or edit a WLAN. New networks start from the controller's own standard template so
/// every attribute the firmware expects is present; edits send only the changed attributes.
struct WLANEditorView: View {
    @Environment(ControllerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var wlan: WLAN?

    @State private var name = ""
    @State private var ssid = ""
    @State private var description = ""
    @State private var usage = "user"
    @State private var authentication = "open"
    @State private var encryption = "wpa2"
    @State private var passphrase = ""
    @State private var vlanID = "1"
    @State private var hidden = false
    @State private var clientIsolation = false
    @State private var maxClients = "100"
    @State private var enabled = true
    @State private var wifi6 = true
    @State private var isSaving = false
    @State private var errorText: String?

    private var isNew: Bool { wlan == nil }

    private var needsPassphrase: Bool {
        authentication == "open" && ["wpa2", "wpa3", "wpa23-mixed"].contains(encryption)
    }

    private var canSave: Bool {
        !ssid.trimmingCharacters(in: .whitespaces).isEmpty
            && (!needsPassphrase || !isNew || passphrase.count >= 8)
            && (passphrase.isEmpty || passphrase.count >= 8)
            && !isSaving
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? "New Wi-Fi network" : "Edit \(wlan?.ssid ?? "network")")
                .font(.title3.weight(.semibold))
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 10) {
                row("Network name (SSID)") { TextField("", text: $ssid).textFieldStyle(.roundedBorder).onChange(of: ssid) { _, new in if name.isEmpty || name == wlan?.ssid { name = new } } }
                row("Internal name") { TextField("", text: $name).textFieldStyle(.roundedBorder) }
                row("Description") { TextField("", text: $description).textFieldStyle(.roundedBorder) }
                row("Usage") {
                    Picker("", selection: $usage) {
                        Text("Standard").tag("user")
                        Text("Guest access").tag("guest")
                    }.labelsHidden()
                }
                row("Authentication") {
                    Picker("", selection: $authentication) {
                        Text("Open (pre-shared key)").tag("open")
                        Text("802.1X EAP").tag("eap")
                        Text("MAC address").tag("mac")
                    }.labelsHidden()
                }
                row("Encryption") {
                    Picker("", selection: $encryption) {
                        Text("WPA2").tag("wpa2")
                        Text("WPA3").tag("wpa3")
                        Text("WPA2/WPA3 mixed").tag("wpa23-mixed")
                        Text("None (open)").tag("none")
                    }.labelsHidden()
                }
                if needsPassphrase {
                    row(isNew ? "Passphrase" : "New passphrase") {
                        VStack(alignment: .leading, spacing: 3) {
                            SecureField("", text: $passphrase).textFieldStyle(.roundedBorder)
                            Text(isNew ? "8 to 63 characters." : "Leave blank to keep the current passphrase.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                row("VLAN ID") { TextField("", text: $vlanID).textFieldStyle(.roundedBorder).frame(width: 90) }
                row("Max clients per radio") { TextField("", text: $maxClients).textFieldStyle(.roundedBorder).frame(width: 90) }
                row("Options") {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Enabled", isOn: $enabled)
                        Toggle("Hide SSID", isOn: $hidden)
                        Toggle("Client isolation", isOn: $clientIsolation)
                        Toggle("Wi-Fi 6 (802.11ax)", isOn: $wifi6)
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
                    HStack { if isSaving { ProgressView().controlSize(.small) }; Text(isNew ? "Create" : "Save") }.frame(minWidth: 70)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(22)
        .frame(width: 560)
        .onAppear(perform: loadExisting)
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func loadExisting() {
        guard let wlan else { return }
        name = wlan.name
        ssid = wlan.ssid
        description = wlan.description
        usage = wlan.usage.isEmpty ? "user" : wlan.usage
        authentication = wlan.authentication.isEmpty ? "open" : wlan.authentication
        encryption = wlan.encryption.isEmpty ? "none" : wlan.encryption
        vlanID = wlan.vlanID.isEmpty ? "1" : wlan.vlanID
        hidden = wlan.isHidden
        clientIsolation = wlan.clientIsolation
        maxClients = wlan.maxClientsPerRadio.map(String.init) ?? "100"
        enabled = wlan.isEnabled
        wifi6 = wlan.wifi6
    }

    private var attributeOverrides: [String: String] {
        [
            "name": name.isEmpty ? ssid : name,
            "ssid": ssid,
            "description": description,
            "usage": usage,
            "is-guest": usage == "guest" ? "true" : "false",
            "authentication": authentication,
            "encryption": encryption,
            "vlan-id": vlanID,
            "close-system": hidden ? "true" : "false",
            "client-isolation": clientIsolation ? "enabled" : "disabled",
            "max-clients-per-radio": maxClients,
            "enable-type": enabled ? "0" : "1",
            "wifi6": wifi6 ? "true" : "false",
        ]
    }

    private func save() async {
        isSaving = true
        errorText = nil
        defer { isSaving = false }
        do {
            if let wlan {
                try await store.updateWLAN(id: wlan.id, attributes: attributeOverrides, passphrase: passphrase.isEmpty ? nil : passphrase, encryption: encryption)
            } else {
                try await store.createWLAN(attributes: attributeOverrides, passphrase: passphrase, encryption: encryption)
            }
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

extension ControllerStore {
    func createWLAN(attributes: [String: String], passphrase: String, encryption: String) async throws {
        let service = try serviceForTools()
        let root = try await service.fetchSystemConfig(elements: ["wlansvc-standard-template"], action: .getstat)
        guard var template = root.firstDescendant(named: "wlansvc") else {
            throw RuckusError.unexpectedResponse("The controller did not return its WLAN template.")
        }
        template.attributes.removeValue(forKey: "id")
        for (key, value) in attributes { template.attributes[key] = value }
        if let index = template.children.firstIndex(where: { $0.name == "wpa" }) {
            template.children[index].attributes["cipher"] = "aes"
            template.children[index].attributes["x-passphrase"] = passphrase
            if encryption == "wpa3" || encryption == "wpa23-mixed" {
                template.children[index].attributes["x-sae-passphrase"] = passphrase
            }
            template.children[index].attributes.removeValue(forKey: "passphrase")
            template.children[index].attributes.removeValue(forKey: "sae-passphrase")
        }
        try await service.addObject(component: "wlansvc-list", body: template.serialized())
        await refresh()
    }

    func updateWLAN(id: String, attributes: [String: String], passphrase: String?, encryption: String) async throws {
        let service = try serviceForTools()
        var node = XMLNode(name: "wlansvc", attributes: attributes)
        node.attributes["id"] = id
        node.attributes["IS_PARTIAL"] = "true"
        if let passphrase {
            var wpa = XMLNode(name: "wpa", attributes: ["cipher": "aes", "x-passphrase": passphrase])
            if encryption == "wpa3" || encryption == "wpa23-mixed" {
                wpa.attributes["x-sae-passphrase"] = passphrase
            }
            node.children = [wpa]
        }
        try await service.updateObject(component: "wlansvc-list", body: node.serialized())
        await refresh()
    }

    func deleteWLAN(id: String) async throws {
        try await serviceForTools().deleteObject(component: "wlansvc-list", body: "<wlansvc id='\(XMLNode.escape(id))'/>")
        await refresh()
    }

    func updateAccessPoint(id: String, mac: String, attributes: [String: String], radios: [XMLNode]) async throws {
        var node = XMLNode(name: "ap", attributes: attributes)
        node.attributes["id"] = id
        node.attributes["mac"] = mac
        node.attributes["IS_PARTIAL"] = "true"
        node.children = radios
        try await serviceForTools().updateObject(component: "ap-list", body: node.serialized())
        await refresh()
    }

    func accessPointConfigNode(mac: String) async throws -> XMLNode? {
        let rows = try await serviceForTools().fetchListRows(component: "ap-list", element: "ap", action: .getconf, decrypt: false, statBody: nil, idAttribute: "mac")
        guard let row = rows.first(where: { $0.id.lowercased() == mac.lowercased() || $0["mac"].lowercased() == mac.lowercased() }) else { return nil }
        return XMLNode(name: "ap", attributes: row.attributes, children: row.children)
    }
}

extension XMLNode {
    /// Compact single-line XML for request bodies.
    func serialized() -> String {
        let attrs = attributes.sorted { $0.key < $1.key }.map { " \($0.key)='\(XMLNode.escape($0.value))'" }.joined()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if children.isEmpty && trimmed.isEmpty { return "<\(name)\(attrs)/>" }
        return "<\(name)\(attrs)>" + XMLNode.escape(trimmed) + children.map { $0.serialized() }.joined() + "</\(name)>"
    }
}
