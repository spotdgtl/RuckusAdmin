import Foundation
import Security

/// One request to the Unleashed AJAX API.
///
/// The web UI serialises a JavaScript object into `<ajax-request …>` XML and POSTs it to
/// `_cmdstat.jsp` (statistics and commands) or `_conf.jsp` (configuration). Everything in
/// `body` goes inside the root element.
struct AjaxRequest: Sendable, Hashable {
    enum Action: String, Sendable, CaseIterable, Hashable {
        case getstat, docmd, getconf, setconf, addobj, updobj, delobj, delallobj

        var path: String {
            switch self {
            case .getstat, .docmd: return "/admin/_cmdstat.jsp"
            case .getconf, .setconf, .addobj, .updobj, .delobj, .delallobj: return "/admin/_conf.jsp"
            }
        }

        /// Whether the request can change controller state.
        var isMutating: Bool {
            switch self {
            case .getstat, .getconf: return false
            default: return true
            }
        }
    }

    var action: Action
    var component: String
    var rootAttributes: [String: String] = [:]
    var body: String = ""
    /// Explicit updater id; generated when nil. Sharded requests (events) must reference it.
    var updater: String?

    init(action: Action, component: String, rootAttributes: [String: String] = [:], body: String = "", updater: String? = nil) {
        self.action = action
        self.component = component
        self.rootAttributes = rootAttributes
        self.body = body
        self.updater = updater
    }

    static func makeUpdater(component: String) -> String {
        let millis = Int(Date().timeIntervalSince1970 * 1000)
        let random = Int.random(in: 1000...9999)
        return "\(component).\(millis).\(random)"
    }

    func xml(updater: String) -> String {
        var attrs: [(String, String)] = [
            ("action", action.rawValue),
            ("comp", component),
            ("updater", updater),
        ]
        for key in rootAttributes.keys.sorted() {
            attrs.append((key, rootAttributes[key]!))
        }
        let attrString = attrs.map { " \($0.0)='\(XMLNode.escape($0.1))'" }.joined()
        if body.isEmpty {
            return "<ajax-request\(attrString)/>"
        }
        return "<ajax-request\(attrString)>\(body)</ajax-request>"
    }
}

/// The parsed `<ajax-response>` for one request, with the raw text kept for diagnostics.
struct AjaxResponse: Sendable {
    let requestXML: String
    let raw: String
    let root: XMLNode
    let duration: TimeInterval

    /// The `<response>` element; most payloads live directly underneath it.
    var response: XMLNode? {
        root.name == "response" ? root : root.first("response")
    }

    /// Convenience: the first element under `<response>` with the given name, searched at any depth.
    func element(_ name: String) -> XMLNode? {
        (response ?? root).firstDescendant(named: name)
    }

    func elements(_ name: String) -> [XMLNode] {
        (response ?? root).descendants(named: name)
    }
}

/// Low-level transport for one controller: cookie session, CSRF token, login and TLS trust.
actor RuckusSession {
    let host: String
    let username: String
    private let password: String
    private let urlSession: URLSession
    private let sessionDelegate: SessionDelegate
    private var csrfToken = ""
    private(set) var isLoggedIn = false
    private var loginInFlight: Task<Void, Error>?

    static let unauthorizedMarker = "content=\"Unauthorized\""

    init(host: String, username: String, password: String) throws {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty, URL(string: "https://\(trimmed)/") != nil else {
            throw RuckusError.invalidHost(host)
        }
        self.host = trimmed
        self.username = username
        self.password = password
        self.sessionDelegate = SessionDelegate(host: trimmed.components(separatedBy: ":").first ?? trimmed)

        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 90
        config.httpAdditionalHeaders = [
            "User-Agent": "RuckusAdmin/1.0 (macOS)",
            "Accept": "*/*",
            "Accept-Language": "en-US,en;q=0.9",
        ]
        self.urlSession = URLSession(configuration: config, delegate: sessionDelegate, delegateQueue: nil)
    }

    var baseURL: URL { URL(string: "https://\(host)")! }

    // MARK: Login

    func login() async throws {
        if let inFlight = loginInFlight {
            return try await inFlight.value
        }
        let task = Task { try await self.performLogin() }
        loginInFlight = task
        defer { loginInFlight = nil }
        try await task.value
    }

    private func performLogin() async throws {
        isLoggedIn = false
        csrfToken = ""

        // Prime the session cookie exactly like a browser visiting the login page.
        _ = try await perform(path: "/admin/login.jsp", method: "GET")

        let form = RuckusSession.formEncode([
            ("username", username),
            ("password", password),
            ("ok", "Log in"),
        ])
        let (data, http) = try await perform(
            path: "/admin/login.jsp",
            method: "POST",
            body: Data(form.utf8),
            contentType: "application/x-www-form-urlencoded; charset=UTF-8",
            csrf: true
        )
        let text = String(decoding: data, as: UTF8.self)
        switch http.statusCode {
        case 200 where text.contains(RuckusSession.unauthorizedMarker):
            throw RuckusError.invalidCredentials
        case 200, 301, 302, 303, 307:
            break
        default:
            throw RuckusError.httpStatus(http.statusCode, body: text)
        }

        if let header = http.value(forHTTPHeaderField: "HTTP_X_CSRF_TOKEN")
            ?? http.value(forHTTPHeaderField: "X-CSRF-Token"), !header.isEmpty {
            csrfToken = header
        } else if let scraped = RuckusSession.scrapeCSRFToken(from: text) {
            csrfToken = scraped
        } else {
            let (page, pageResponse) = try await perform(path: "/admin/dashboard.jsp", method: "GET")
            let pageText = String(decoding: page, as: UTF8.self)
            if pageResponse.statusCode == 200, pageText.contains(RuckusSession.unauthorizedMarker) {
                throw RuckusError.invalidCredentials
            }
            csrfToken = RuckusSession.scrapeCSRFToken(from: pageText) ?? ""
        }
        isLoggedIn = true
    }

    func logout() async {
        guard isLoggedIn else { return }
        _ = try? await perform(path: "/admin/logout.jsp", method: "GET")
        isLoggedIn = false
        csrfToken = ""
    }

    // MARK: Requests

    private var logger: (@Sendable (RequestLogEntry) -> Void)?

    func setLogger(_ logger: (@Sendable (RequestLogEntry) -> Void)?) {
        self.logger = logger
    }

    func send(_ request: AjaxRequest) async throws -> AjaxResponse {
        let updater = request.updater ?? AjaxRequest.makeUpdater(component: request.component)
        return try await sendRaw(xml: request.xml(updater: updater), path: request.action.path)
    }

    /// Sends a complete `<ajax-request>` document to the given endpoint path.
    func sendRaw(xml: String, path: String) async throws -> AjaxResponse {
        if !isLoggedIn {
            try await login()
        }
        let started = Date()
        do {
            let response = try await performAjax(xml: xml, path: path, started: started)
            logger?(RequestLogEntry(path: path, requestXML: xml, responseText: response.raw, status: 200,
                                    duration: response.duration, error: nil))
            return response
        } catch {
            logger?(RequestLogEntry(path: path, requestXML: xml, responseText: (error as? RuckusError)?.rawBody ?? "",
                                    status: (error as? RuckusError)?.statusCode ?? 0,
                                    duration: Date().timeIntervalSince(started), error: error.localizedDescription))
            throw error
        }
    }

    private func performAjax(xml: String, path: String, started: Date) async throws -> AjaxResponse {
        var (data, http) = try await post(xml: xml, path: path)
        var text = String(decoding: data, as: UTF8.self)
        if RuckusSession.looksUnauthorized(status: http.statusCode, body: text) {
            // The controller session timed out; sign in again and retry once.
            try await login()
            (data, http) = try await post(xml: xml, path: path)
            text = String(decoding: data, as: UTF8.self)
            if RuckusSession.looksUnauthorized(status: http.statusCode, body: text) {
                isLoggedIn = false
                throw RuckusError.sessionExpired
            }
        }
        guard (200..<300).contains(http.statusCode) else {
            throw RuckusError.httpStatus(http.statusCode, body: text)
        }

        let root: XMLNode
        do {
            root = try XMLTreeParser.parse(text)
        } catch {
            throw RuckusError.unexpectedResponse("\(error.localizedDescription) — \(text.prefix(200))")
        }
        let response = AjaxResponse(requestXML: xml, raw: text, root: root, duration: Date().timeIntervalSince(started))
        if let xmsg = response.response?.first("xmsg") ?? root.firstDescendant(named: "xmsg"),
           xmsg["type"] == "-1" {
            let message = xmsg.attr("lmsg", "msg") ?? "The controller reported that the action failed."
            throw RuckusError.apiFailure(message: message, raw: text)
        }
        return response
    }

    /// GET a page or file with the session cookie (backups, logs, admin actions).
    func get(path: String, query: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
        if !isLoggedIn { try await login() }
        var fullPath = path
        if !query.isEmpty {
            var allowed = CharacterSet.alphanumerics
            allowed.insert(charactersIn: "-._~")
            let encoded = query.sorted { $0.key < $1.key }.map { key, value in
                "\(key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
            }.joined(separator: "&")
            fullPath += (path.contains("?") ? "&" : "?") + encoded
        }
        var (data, http) = try await perform(path: fullPath, method: "GET", csrf: true)
        let text = String(decoding: data.prefix(4000), as: UTF8.self)
        if RuckusSession.looksUnauthorized(status: http.statusCode, body: text) {
            try await login()
            (data, http) = try await perform(path: fullPath, method: "GET", csrf: true)
        }
        return (data, http)
    }

    private func post(xml: String, path: String) async throws -> (Data, HTTPURLResponse) {
        try await perform(
            path: path,
            method: "POST",
            body: Data(xml.utf8),
            contentType: "application/x-www-form-urlencoded; charset=UTF-8",
            csrf: true
        )
    }

    private func perform(path: String, method: String, body: Data? = nil, contentType: String? = nil,
                         csrf: Bool = false) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw RuckusError.invalidHost(host)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        if csrf {
            request.setValue(csrfToken, forHTTPHeaderField: "X-CSRF-Token")
            request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        }
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw RuckusError.unexpectedResponse("non-HTTP response")
            }
            return (data, http)
        } catch let error as RuckusError {
            throw error
        } catch let error as URLError {
            if error.code == .cancelled,
               let actual = CertificateTrustStore.shared.pendingMismatch(for: sessionDelegate.host),
               let expected = CertificateTrustStore.shared.trustedFingerprint(for: sessionDelegate.host) {
                throw RuckusError.certificateMismatch(host: host, expected: expected, actual: actual)
            }
            if error.code == .serverCertificateUntrusted || error.code == .secureConnectionFailed {
                throw RuckusError.transport("Secure connection to \(host) failed: \(error.localizedDescription)")
            }
            throw RuckusError.transport(error.localizedDescription)
        } catch {
            throw RuckusError.transport(error.localizedDescription)
        }
    }

    // MARK: Helpers

    static func looksUnauthorized(status: Int, body: String) -> Bool {
        if (300..<400).contains(status) { return true }
        return status == 200 && body.contains(unauthorizedMarker)
    }

    static func scrapeCSRFToken(from html: String) -> String? {
        let pattern = #"csfrToken\s*=\s*['"]([^'"]+)['"]"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[range])
    }

    static func formEncode(_ fields: [(String, String)]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
    }
}

/// Accepts the controller's self-signed certificate (trust on first use) and stops
/// URLSession from following redirects so that a 302 to the login page is visible.
final class SessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    let host: String

    init(host: String) {
        self.host = host
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        guard challenge.protectionSpace.host == host else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        if SecTrustEvaluateWithError(trust, nil) {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }
        switch CertificateTrustStore.shared.evaluate(trust: trust, host: host) {
        case .accept:
            completionHandler(.useCredential, URLCredential(trust: trust))
        case .reject:
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
