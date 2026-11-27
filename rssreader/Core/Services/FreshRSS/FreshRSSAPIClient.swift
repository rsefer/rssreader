import Foundation
import Network
import os

// MARK: - Transport

/// The minimal HTTP surface the client needs, so tests can substitute a fake.
nonisolated protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, URLResponse)
    /// Releases the transport once in-flight requests complete. No-op unless it owns a session.
    func finish()
}

nonisolated extension HTTPTransport {
    func finish() {}
}

nonisolated extension URLSession: HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request)
    }

    func finish() {
        finishTasksAndInvalidate()
    }
}

/// Session configuration shared by every FreshRSS request, so timeouts are consistent.
nonisolated enum FreshRSSNetwork {
    static let requestTimeout: TimeInterval = 20
    static let resourceTimeout: TimeInterval = 90

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    /// A session with no cached DNS state or connections, for flaky VPN/split-DNS hosts.
    static func makeFreshSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 20
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: configuration)
    }
}

// MARK: - Retry

/// Exponential backoff for idempotent requests that fail transiently.
nonisolated struct RetryPolicy: Sendable {
    var maxAttempts = 3
    var baseDelay: Duration = .milliseconds(400)

    static let none = RetryPolicy(maxAttempts: 1)

    func delay(afterAttempt attempt: Int) -> Duration {
        baseDelay * (1 << max(0, attempt - 1))
    }

    func isRetryable(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return true
        default:
            return false
        }
    }

    func isRetryable(statusCode: Int) -> Bool {
        [429, 502, 503, 504].contains(statusCode)
    }
}

// MARK: - Server URL

nonisolated enum FreshRSSServerURL {
    /// Turns whatever the user typed into a canonical base URL (scheme and host, no API path).
    static func normalize(_ raw: String) -> String {
        var normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

        guard !normalized.isEmpty else { return "" }

        if normalized.hasPrefix("https://https://") {
            normalized = String(normalized.dropFirst("https://".count))
        } else if normalized.hasPrefix("http://http://") {
            normalized = String(normalized.dropFirst("http://".count))
        }

        if normalized.hasPrefix("https:/") && !normalized.hasPrefix("https://") {
            normalized = "https://" + normalized.dropFirst("https:/".count)
        } else if normalized.hasPrefix("http:/") && !normalized.hasPrefix("http://") {
            normalized = "http://" + normalized.dropFirst("http:/".count)
        } else if normalized.hasPrefix("https:") && !normalized.hasPrefix("https://") {
            normalized = "https://" + normalized.dropFirst("https:".count)
        } else if normalized.hasPrefix("http:") && !normalized.hasPrefix("http://") {
            normalized = "http://" + normalized.dropFirst("http:".count)
        }

        let withScheme = normalized.contains("://") ? normalized : "https://\(normalized)"
        guard var components = URLComponents(string: withScheme) else {
            return withScheme
        }

        if components.scheme == nil {
            components.scheme = "https"
        }

        if let range = components.path.range(of: "/api/greader.php") {
            components.path = String(components.path[..<range.lowerBound])
        }

        while components.path.hasSuffix("/") {
            components.path.removeLast()
        }

        return components.url?.absoluteString ?? withScheme
    }

    /// App Transport Security blocks cleartext HTTP except to IP addresses, unqualified names, and
    /// `.local` hosts. Mirror that rule so the user gets a clear message instead of error -1022.
    static func allowsCleartext(host: String) -> Bool {
        let host = host.lowercased()
        if !host.contains(".") || host.hasSuffix(".local") {
            return true
        }
        return IPv4Address(host) != nil || IPv6Address(host) != nil
    }

    static func validateTransportSecurity(of url: URL) throws {
        guard url.scheme?.lowercased() == "http", let host = url.host, !allowsCleartext(host: host) else {
            return
        }
        throw FreshRSSError.insecureServerURL(host: host)
    }

    static func isVPNStyleHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host.contains(".vpn.") || host.hasSuffix(".ts.net")
    }
}

// MARK: - Client

nonisolated enum ReadActionOutcome: Sendable, Equatable {
    case succeeded
    /// The server rejected the action token (HTTP 401); fetch a new one before retrying.
    case actionTokenRejected
    case failed
}

nonisolated struct PreflightResult: Sendable, Equatable {
    let success: Bool
    let message: String
    let urlErrorCode: Int?
}

/// Stateless client for the FreshRSS Google Reader-compatible API. Tokens are passed in by the
/// caller; nothing here touches UI or persistence state, so it is safe to use from any context.
nonisolated struct FreshRSSAPIClient: Sendable {
    typealias Sleeper = @Sendable (Duration) async -> Void

    let serverURL: String
    let transport: any HTTPTransport
    let makeFreshTransport: @Sendable () -> any HTTPTransport
    let sleep: Sleeper

    init(
        serverURL: String,
        transport: any HTTPTransport,
        makeFreshTransport: @escaping @Sendable () -> any HTTPTransport = { FreshRSSNetwork.makeFreshSession() },
        sleep: @escaping Sleeper = { try? await Task.sleep(for: $0) }
    ) {
        self.serverURL = serverURL
        self.transport = transport
        self.makeFreshTransport = makeFreshTransport
        self.sleep = sleep
    }

    var normalizedServerURL: String {
        FreshRSSServerURL.normalize(serverURL)
    }

    func gReaderURL(_ pathComponents: [String]) -> URL? {
        guard let baseURL = URL(string: normalizedServerURL), let host = baseURL.host, !host.isEmpty else {
            return nil
        }

        var url = baseURL
        url.appendPathComponent("api")
        url.appendPathComponent("greader.php")
        for component in pathComponents {
            url.appendPathComponent(component)
        }
        return url
    }

    private func authorizedRequest(_ url: URL, authToken: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("GoogleLogin auth=\(authToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func formBody(_ items: [URLQueryItem]) -> Data? {
        var components = URLComponents()
        components.queryItems = items
        return components.query?.data(using: .utf8)
    }

    /// Sends a request, retrying transient failures with exponential backoff.
    private func perform(_ request: URLRequest, retry: RetryPolicy = RetryPolicy()) async throws -> (Data, HTTPURLResponse) {
        var attempt = 1
        while true {
            do {
                let (data, response) = try await transport.send(request)
                guard let http = response as? HTTPURLResponse else {
                    throw FreshRSSError.networkError("The server sent an invalid response.")
                }
                if attempt < retry.maxAttempts, retry.isRetryable(statusCode: http.statusCode) {
                    await sleep(retry.delay(afterAttempt: attempt))
                    attempt += 1
                    continue
                }
                return (data, http)
            } catch let error as URLError where attempt < retry.maxAttempts && retry.isRetryable(error) {
                await sleep(retry.delay(afterAttempt: attempt))
                attempt += 1
            }
        }
    }

    // MARK: Authentication

    /// Returns the `Auth` token. Throws `FreshRSSError.authenticationFailed` for rejected
    /// credentials and `URLError` when the server cannot be reached.
    func login(username: String, password: String) async throws -> String {
        guard let loginURL = gReaderURL(["accounts", "ClientLogin"]) else {
            throw FreshRSSError.invalidServerURL
        }
        try FreshRSSServerURL.validateTransportSecurity(of: loginURL)

        var request = URLRequest(url: loginURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            URLQueryItem(name: "Email", value: username),
            URLQueryItem(name: "Passwd", value: password),
        ])

        let usesVPNStyleHost = FreshRSSServerURL.isVPNStyleHost(loginURL.host)
        let maxAttempts = usesVPNStyleHost ? 5 : 4

        for attempt in 1...maxAttempts {
            // VPN/split-DNS hostnames are more sensitive to stale resolver cache.
            let useFreshSession = usesVPNStyleHost || attempt == maxAttempts
            let session = useFreshSession ? makeFreshTransport() : transport
            defer { if useFreshSession { session.finish() } }

            do {
                let (data, response) = try await session.send(request)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    throw FreshRSSError.authenticationFailed
                }
                let text = String(data: data, encoding: .utf8) ?? ""
                guard let line = text.components(separatedBy: "\n").first(where: { $0.hasPrefix("Auth=") }) else {
                    throw FreshRSSError.authenticationFailed
                }
                return String(line.dropFirst("Auth=".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            } catch let error as URLError {
                let isDNSFailure = error.code == .cannotFindHost || error.code == .dnsLookupFailed
                guard isDNSFailure, attempt < maxAttempts else { throw error }
                // DNS for VPN hosts can come up a moment after the network path reports "satisfied".
                await sleep(.milliseconds((usesVPNStyleHost ? 500 : 350) * attempt))
            }
        }
        throw FreshRSSError.networkError("Could not reach the server.")
    }

    /// Checks whether the host resolves, retrying DNS failures once on a fresh session.
    func probeHost() async -> PreflightResult {
        guard let loginURL = gReaderURL(["accounts", "ClientLogin"]) else {
            return PreflightResult(success: false, message: "Invalid server URL", urlErrorCode: nil)
        }
        guard let host = loginURL.host, !host.isEmpty else {
            return PreflightResult(success: false, message: "Missing host in server URL", urlErrorCode: nil)
        }

        var request = URLRequest(url: loginURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 8

        func isDNSFailure(_ error: URLError) -> Bool {
            error.code == .cannotFindHost || error.code == .dnsLookupFailed
        }

        do {
            _ = try await transport.send(request)
            return PreflightResult(success: true, message: "DNS resolved for \(host)", urlErrorCode: nil)
        } catch let error as URLError {
            guard isDNSFailure(error) else {
                // Any non-DNS URL error means hostname resolution succeeded.
                return PreflightResult(success: true, message: "Host resolved; request failed with URL error \(error.errorCode)", urlErrorCode: error.errorCode)
            }
            let freshSession = makeFreshTransport()
            defer { freshSession.finish() }
            do {
                _ = try await freshSession.send(request)
                return PreflightResult(success: true, message: "DNS resolved for \(host) after refresh", urlErrorCode: nil)
            } catch let refreshedError as URLError {
                if isDNSFailure(refreshedError) {
                    return PreflightResult(success: false, message: "DNS lookup failed for \(host)", urlErrorCode: refreshedError.errorCode)
                }
                return PreflightResult(success: true, message: "Host resolved; request failed with URL error \(refreshedError.errorCode)", urlErrorCode: refreshedError.errorCode)
            } catch {
                return PreflightResult(success: false, message: "DNS preflight failed: \(error.localizedDescription)", urlErrorCode: error.urlErrorCode)
            }
        } catch {
            return PreflightResult(success: false, message: "DNS preflight failed: \(error.localizedDescription)", urlErrorCode: nil)
        }
    }

    // MARK: Reading

    func fetchSubscriptions(authToken: String) async throws -> [FeedSubscription] {
        guard let url = gReaderURL(["reader", "api", "0", "subscription", "list"]) else {
            throw FreshRSSError.invalidServerURL
        }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "output", value: "json")]
        guard let requestURL = components?.url else {
            throw FreshRSSError.invalidServerURL
        }

        let (data, response) = try await perform(authorizedRequest(requestURL, authToken: authToken))
        guard response.statusCode == 200 else {
            throw FreshRSSError.serverError(response.statusCode)
        }
        return try JSONDecoder().decode(GReaderSubscriptionListResponse.self, from: data).subscriptions
            .map { FeedSubscription(id: $0.id, title: $0.title ?? $0.id) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func fetchStreamPage(authToken: String, mode: SidebarMode, continuation: String?, todayCutoff: Date) async throws -> GReaderStreamResponse {
        guard let baseURL = gReaderURL(["reader", "api", "0", "stream", "contents", "reading-list"]) else {
            throw FreshRSSError.invalidServerURL
        }
        var queryItems = [
            URLQueryItem(name: "n", value: mode == .new ? "100" : "250"),
            URLQueryItem(name: "output", value: "json"),
        ]
        if mode == .new {
            queryItems.append(URLQueryItem(name: "xt", value: "user/-/state/com.google/read"))
        }
        if mode == .today {
            queryItems.append(URLQueryItem(name: "ot", value: String(Int(todayCutoff.timeIntervalSince1970))))
        }
        if let continuation {
            queryItems.append(URLQueryItem(name: "c", value: continuation))
        }

        var urlComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        urlComponents?.queryItems = queryItems
        guard let url = urlComponents?.url else {
            throw FreshRSSError.networkError("Invalid feed URL")
        }

        let (data, response) = try await perform(authorizedRequest(url, authToken: authToken))
        guard response.statusCode == 200 else {
            throw FreshRSSError.serverError(response.statusCode)
        }
        return try JSONDecoder().decode(GReaderStreamResponse.self, from: data)
    }

    // MARK: Writing

    func fetchActionToken(authToken: String) async throws -> String {
        guard let url = gReaderURL(["reader", "api", "0", "token"]) else {
            throw FreshRSSError.invalidServerURL
        }
        let (data, response) = try await perform(authorizedRequest(url, authToken: authToken))
        guard response.statusCode == 200 else {
            throw FreshRSSError.serverError(response.statusCode)
        }
        guard let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else {
            throw FreshRSSError.networkError("The server returned an empty action token.")
        }
        return token
    }

    /// Marks items read or unread with a bounded number of concurrent requests.
    func setReadState(
        itemIDs: [String],
        isRead: Bool,
        authToken: String,
        actionToken: String,
        maxConcurrentRequests: Int = 4
    ) async -> [String: ReadActionOutcome] {
        var iterator = itemIDs.makeIterator()

        return await withTaskGroup(of: (String, ReadActionOutcome).self) { group in
            func addNext() {
                guard let itemID = iterator.next() else { return }
                group.addTask {
                    (itemID, await setReadState(itemID: itemID, isRead: isRead, authToken: authToken, actionToken: actionToken))
                }
            }

            for _ in 0..<min(maxConcurrentRequests, itemIDs.count) {
                addNext()
            }

            var outcomes: [String: ReadActionOutcome] = [:]
            while let (itemID, outcome) = await group.next() {
                outcomes[itemID] = outcome
                addNext()
            }
            return outcomes
        }
    }

    func setReadState(itemID: String, isRead: Bool, authToken: String, actionToken: String) async -> ReadActionOutcome {
        guard let editURL = gReaderURL(["reader", "api", "0", "edit-tag"]) else { return .failed }

        var request = authorizedRequest(editURL, authToken: authToken)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            URLQueryItem(name: "i", value: itemID),
            URLQueryItem(name: isRead ? "a" : "r", value: "user/-/state/com.google/read"),
            URLQueryItem(name: "T", value: actionToken),
        ])

        do {
            let (_, response) = try await perform(request, retry: .none)
            switch response.statusCode {
            case 200: return .succeeded
            case 401: return .actionTokenRejected
            default:
                Log.network.error("Read-state update failed with HTTP \(response.statusCode, privacy: .public)")
                return .failed
            }
        } catch {
            Log.network.error("Read-state update failed: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }
}

nonisolated private extension Error {
    var urlErrorCode: Int? {
        (self as? URLError)?.errorCode
    }
}
