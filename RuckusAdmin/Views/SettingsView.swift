import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(ControllerStore.self) private var store
    @ObservedObject private var updates = UpdateManager.shared
    @State private var certificateFingerprint: String?

    var body: some View {
        @Bindable var store = store
        Form {
            Section("Controller") {
                TextField("Address", text: $store.settings.host)
                TextField("Username", text: $store.settings.username)
                Toggle("Remember password in Keychain", isOn: $store.settings.rememberPassword)
                Toggle("Connect automatically at launch", isOn: $store.settings.autoConnect)
                LabeledContent("Stored password") {
                    HStack {
                        Text(store.hasStoredPassword ? "Saved in Keychain" : "Not saved")
                            .foregroundStyle(.secondary)
                        if store.hasStoredPassword {
                            Button("Forget") { store.forgetStoredPassword() }
                        }
                    }
                }
            }

            Section("Refresh") {
                Picker("Poll the controller", selection: $store.settings.pollInterval) {
                    Text("Every 10 seconds").tag(10.0)
                    Text("Every 20 seconds").tag(20.0)
                    Text("Every 30 seconds").tag(30.0)
                    Text("Every minute").tag(60.0)
                    Text("Every 2 minutes").tag(120.0)
                }
                .onChange(of: store.settings.pollInterval) { _, _ in
                    store.restartPolling()
                }
                Text("Each poll makes the same handful of requests the stock web dashboard makes once a minute.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Live mode samples", selection: $store.settings.liveInterval) {
                    Text("Every 2 seconds").tag(2.0)
                    Text("Every 3 seconds").tag(3.0)
                    Text("Every 5 seconds").tag(5.0)
                    Text("Every 10 seconds").tag(10.0)
                }
                Text("Live mode only fetches client and AP statistics (two small requests per sample). Traffic history buckets and background scans are produced by the controller every 60 s and 5 min and cannot be faster.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Updates") {
                Toggle("Check for updates automatically (hourly)", isOn: Binding(
                    get: { updates.automaticallyChecksForUpdates },
                    set: { updates.automaticallyChecksForUpdates = $0 }))
                Toggle("Download and install updates automatically", isOn: Binding(
                    get: { updates.automaticallyDownloadsUpdates },
                    set: { updates.automaticallyDownloadsUpdates = $0 }))
                LabeledContent("Last checked") {
                    HStack {
                        Text(updates.lastUpdateCheckDate == nil ? "Never" : Format.dateTime(updates.lastUpdateCheckDate))
                            .foregroundStyle(.secondary)
                        Button("Check Now") { updates.checkForUpdates() }
                            .disabled(!updates.canCheckForUpdates)
                    }
                }
                Text("Releases are published on GitHub and verified against the app's signing keys before they are installed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Certificate") {
                if let certificateFingerprint {
                    LabeledContent("Trusted fingerprint") {
                        Text(certificateFingerprint)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .multilineTextAlignment(.trailing)
                    }
                    Button("Forget certificate") {
                        CertificateTrustStore.shared.forget(host: hostOnly)
                        refreshFingerprint()
                    }
                    Text("Unleashed uses a self-signed certificate. The first certificate seen for this address is trusted; a different one is refused until you approve it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No certificate has been pinned for \(hostOnly) yet. It is trusted on first use.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("About") {
                LabeledContent("Ruckus Admin", value: "Version \(AppVersion.display)")
                Link("Source code and releases on GitHub", destination: URL(string: "https://github.com/spotdgtl/RuckusAdmin")!)
                Button("Open the stock web UI") {
                    if let url = URL(string: "https://\(store.settings.host)/admin/dashboard.jsp") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .onAppear(perform: refreshFingerprint)
        .onChange(of: store.settings.host) { _, _ in refreshFingerprint() }
    }

    private var hostOnly: String {
        store.settings.host.components(separatedBy: ":").first ?? store.settings.host
    }

    private func refreshFingerprint() {
        certificateFingerprint = CertificateTrustStore.shared.trustedFingerprint(for: hostOnly)
    }
}
