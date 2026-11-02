import Foundation

enum RuckusError: LocalizedError, Sendable {
    case invalidHost(String)
    case invalidCredentials
    case notLoggedIn
    case sessionExpired
    case certificateMismatch(host: String, expected: String, actual: String)
    case httpStatus(Int, body: String)
    case transport(String)
    case apiFailure(message: String, raw: String)
    case unexpectedResponse(String)
    case notSupported(String)

    var rawBody: String? {
        switch self {
        case .httpStatus(_, let body): return body
        case .apiFailure(_, let raw): return raw
        default: return nil
        }
    }

    var statusCode: Int {
        if case .httpStatus(let status, _) = self { return status }
        return 0
    }

    var errorDescription: String? {
        switch self {
        case .invalidHost(let host):
            return "\"\(host)\" is not a valid controller address."
        case .invalidCredentials:
            return "The controller rejected the username or password."
        case .notLoggedIn:
            return "Not signed in to the controller."
        case .sessionExpired:
            return "The controller session expired. Sign in again."
        case .certificateMismatch(let host, _, let actual):
            return "The certificate presented by \(host) changed (now \(actual.prefix(23))…). Review it in Settings before continuing."
        case .httpStatus(let status, _):
            return "The controller answered with HTTP \(status)."
        case .transport(let detail):
            return detail
        case .apiFailure(let message, _):
            return message
        case .unexpectedResponse(let detail):
            return "Unexpected response from the controller: \(detail)"
        case .notSupported(let detail):
            return detail
        }
    }
}
