import Foundation

/// The app's own version, as stamped into Info.plist at build time
/// (`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`; `scripts/release.sh` sets both).
enum AppVersion {
    static let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    static let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"

    /// "1.0.0 (12)"
    static var display: String { "\(short) (\(build))" }
}
