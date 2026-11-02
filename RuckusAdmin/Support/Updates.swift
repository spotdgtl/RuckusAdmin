import Combine
import Foundation
import Sparkle

/// Thin wrapper around Sparkle so the menu bar and the Settings window can observe it.
///
/// The feed (`SUFeedURL`), public key and scheduling live in Info.plist; `scripts/release.sh`
/// publishes signed builds and the appcast. Updates are verified with the EdDSA key and the
/// Developer ID code signature before Sparkle installs them.
@MainActor
final class UpdateManager: ObservableObject {
    static let shared = UpdateManager()

    @Published private(set) var canCheckForUpdates = false

    private let controller: SPUStandardUpdaterController

    var updater: SPUUpdater { controller.updater }

    private init() {
        // Started explicitly from the app so headless runs (`--set`, `--probe-live`) never check.
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
    }

    func start() {
        controller.startUpdater()
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }

    var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set {
            objectWillChange.send()
            updater.automaticallyChecksForUpdates = newValue
        }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { updater.automaticallyDownloadsUpdates }
        set {
            objectWillChange.send()
            updater.automaticallyDownloadsUpdates = newValue
        }
    }

    var lastUpdateCheckDate: Date? { updater.lastUpdateCheckDate }
}
