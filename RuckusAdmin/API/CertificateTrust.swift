import CryptoKit
import Foundation
import Security

/// Trust-on-first-use handling for the controller's self-signed certificate.
///
/// Unleashed ships with a certificate issued by its own internal CA, so system trust
/// evaluation always fails. The first time we connect we remember the SHA-256 fingerprint
/// of the leaf certificate; later connections must present the same certificate or the
/// connection is refused until the user explicitly trusts the new one.
final class CertificateTrustStore: @unchecked Sendable {
    static let shared = CertificateTrustStore()

    private let lock = NSLock()
    private let defaults: UserDefaults
    private let key = "trustedCertificateFingerprints"

    /// Fingerprint seen on the most recent connection that was refused because it did
    /// not match the stored one, keyed by host. The UI reads this to offer a "trust" button.
    private var pendingMismatches: [String: String] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func trustedFingerprint(for host: String) -> String? {
        lock.withLock {
            (defaults.dictionary(forKey: key) as? [String: String])?[host]
        }
    }

    func trust(fingerprint: String, for host: String) {
        lock.withLock {
            var all = (defaults.dictionary(forKey: key) as? [String: String]) ?? [:]
            all[host] = fingerprint
            defaults.set(all, forKey: key)
            pendingMismatches[host] = nil
        }
    }

    func forget(host: String) {
        lock.withLock {
            var all = (defaults.dictionary(forKey: key) as? [String: String]) ?? [:]
            all[host] = nil
            defaults.set(all, forKey: key)
            pendingMismatches[host] = nil
        }
    }

    func pendingMismatch(for host: String) -> String? {
        lock.withLock { pendingMismatches[host] }
    }

    enum Decision {
        case accept
        case reject(expected: String, actual: String)
    }

    /// Evaluates a server trust for `host`. Accepts on first use, or when the fingerprint
    /// matches the remembered one.
    func evaluate(trust: SecTrust, host: String) -> Decision {
        let actual = CertificateTrustStore.fingerprint(of: trust) ?? "unknown"
        return lock.withLock {
            var all = (defaults.dictionary(forKey: key) as? [String: String]) ?? [:]
            if let expected = all[host] {
                if expected == actual {
                    pendingMismatches[host] = nil
                    return .accept
                }
                pendingMismatches[host] = actual
                return .reject(expected: expected, actual: actual)
            }
            all[host] = actual
            defaults.set(all, forKey: key)
            return .accept
        }
    }

    static func fingerprint(of trust: SecTrust) -> String? {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first else { return nil }
        let der = SecCertificateCopyData(leaf) as Data
        let digest = SHA256.hash(data: der)
        return digest.map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    static func subjectSummary(of trust: SecTrust) -> String? {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first else { return nil }
        return SecCertificateCopySubjectSummary(leaf) as String?
    }
}
