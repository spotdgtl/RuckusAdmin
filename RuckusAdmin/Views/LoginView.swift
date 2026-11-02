import SwiftUI

struct LoginView: View {
    @Environment(ControllerStore.self) private var store
    @State private var host = ""
    @State private var username = ""
    @State private var password = ""
    @State private var rememberPassword = true
    @State private var loadedDefaults = false

    private var isConnecting: Bool { store.phase == .connecting }

    private var errorMessage: String? {
        if case .failed(let message) = store.phase { return message }
        return nil
    }

    private var canConnect: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty
            && !username.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty
            && !isConnecting
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.28), Color.accentColor.opacity(0.04), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 22) {
                header
                fields
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let pending = store.pendingCertificate {
                    certificatePanel(pending)
                }
                actions
            }
            .padding(32)
            .frame(width: 440)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.quaternary))
            .shadow(color: .black.opacity(0.12), radius: 24, y: 10)
        }
        .onAppear(perform: loadDefaults)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.router.fill")
                .font(.system(size: 46, weight: .medium))
                .foregroundStyle(.primary)
            Text("Ruckus Admin")
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
            Text("Sign in to your Unleashed controller")
                .foregroundStyle(.secondary)
            Text("Version \(AppVersion.display)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var fields: some View {
        VStack(spacing: 12) {
            TextField("Controller address (e.g. 192.168.1.1)", text: $host)
                .textContentType(.URL)
            TextField("Username", text: $username)
                .textContentType(.username)
            SecureField("Password", text: $password)
                .textContentType(.password)
                .onSubmit(connect)
            Toggle("Remember password in Keychain", isOn: $rememberPassword)
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .textFieldStyle(.roundedBorder)
        .controlSize(.large)
        .disabled(isConnecting)
    }

    private func certificatePanel(_ pending: PendingCertificate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("The controller's certificate changed", systemImage: "lock.trianglebadge.exclamationmark")
                .font(.headline)
            Text("Expected fingerprint")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(pending.expected)
                .font(.system(.caption2, design: .monospaced))
                .textSelection(.enabled)
            Text("Presented fingerprint")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(pending.actual)
                .font(.system(.caption2, design: .monospaced))
                .textSelection(.enabled)
            Button("Trust the new certificate and connect") {
                Task { await store.trustPendingCertificate(password: password) }
            }
            .disabled(password.isEmpty)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private var actions: some View {
        HStack {
            Button("Browse demo data") {
                store.startDemo()
            }
            .buttonStyle(.link)
            Spacer()
            Button(action: connect) {
                HStack(spacing: 8) {
                    if isConnecting {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(isConnecting ? "Connecting…" : "Connect")
                        .frame(minWidth: 90)
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canConnect)
        }
    }

    private func loadDefaults() {
        guard !loadedDefaults else { return }
        loadedDefaults = true
        host = store.settings.host
        username = store.settings.username
        rememberPassword = store.settings.rememberPassword
        let host = host
        let username = username
        Task {
            let stored = await Task.detached(priority: .userInitiated) {
                KeychainStore.password(host: host, username: username)
            }.value
            if password.isEmpty, let stored { password = stored }
        }
    }

    private func connect() {
        guard canConnect else { return }
        Task {
            await store.connect(host: host, username: username, password: password, rememberPassword: rememberPassword)
        }
    }
}
