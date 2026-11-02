import SwiftUI

@main
struct RuckusAdminApp: App {
    @State private var store = ControllerStore()
    @StateObject private var updates = UpdateManager.shared

    init() {
        // Headless runs exit by themselves; Sparkle must not schedule anything for them.
        let headless = CommandLine.arguments.contains("--set") || CommandLine.arguments.contains("--probe-live")
        if !headless {
            UpdateManager.shared.start()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .frame(minWidth: 1040, minHeight: 680)
                .task {
                    // `--demo` (useful from Xcode's scheme arguments) opens the sample network.
                    if CommandLine.arguments.contains("--demo") {
                        store.startDemo()
                    } else {
                        await store.connectIfPossible()
                    }
                    if CommandLine.arguments.contains("--probe-live") {
                        await LiveProbe.run(store: store)
                    }
                    // `--live` turns Live mode on at launch.
                    if CommandLine.arguments.contains("--live") {
                        store.setLiveMode(true)
                    }
                    // `--set <page> path.key=value …` applies settings headlessly and exits (see Automation.swift).
                    if let command = AutomationCommand.parse(CommandLine.arguments) {
                        await AutomationRunner.run(command, store: store)
                    }
                }
        }
        .defaultSize(width: 1320, height: 860)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updates: updates)
            }
            CommandGroup(after: .toolbar) {
                Button("Refresh") {
                    Task { await store.refresh(includeEvents: true) }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!store.isConnected)
            }
            SidebarCommands()
        }

        Settings {
            SettingsView()
                .environment(store)
        }
    }
}

/// "Check for Updates…" in the application menu; disabled while Sparkle is busy or not started.
struct CheckForUpdatesView: View {
    @ObservedObject var updates: UpdateManager

    var body: some View {
        Button("Check for Updates…") { updates.checkForUpdates() }
            .disabled(!updates.canCheckForUpdates)
    }
}
