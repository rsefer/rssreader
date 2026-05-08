import Foundation
import SwiftUI
import Combine

// MARK: - GReader API Codable types

private struct GReaderStreamResponse: Codable {
    let items: [GReaderItem]
    let continuation: String?
}

private struct GReaderItem: Codable {
    let id: String
    let title: String?
    let published: Int?
    let categories: [String]?
    let canonical: [GReaderLink]?
    let alternate: [GReaderLink]?
    let summary: GReaderContent?
    let content: GReaderContent?
    let origin: GReaderOrigin?
    let enclosure: [GReaderEnclosure]?
    let author: String?
}

private struct GReaderLink: Codable {
    let href: String
    let type: String?
}

private struct GReaderContent: Codable {
    let content: String?
}

private struct GReaderOrigin: Codable {
    let title: String?
    let htmlUrl: String?
    let streamId: String?
}

private struct GReaderEnclosure: Codable {
    let href: String?
    let type: String?
    let length: String?
}

private struct GReaderSubscriptionListResponse: Codable {
    let subscriptions: [GReaderSubscriptionItem]
}

private struct GReaderSubscriptionItem: Codable {
    let id: String
    let title: String?
}

// MARK: - Public subscription model

struct FeedSubscription: Identifiable, Hashable {
    let id: String    // GReader stream ID, e.g. "feed/https://..."
    let title: String
}

// MARK: - Errors

enum FreshRSSError: LocalizedError {
    case notConfigured
    case authenticationFailed
    case notAuthenticated
    case networkError(String)
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "FreshRSS is not configured. Open Settings (⌘,) to add your server details."
        case .authenticationFailed:
            return "Authentication failed. Check your username and password in Settings."
        case .notAuthenticated:
            return "Not authenticated. Please check Settings."
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .serverError(let code):
            return "Server returned error \(code)."
        }
    }
}

enum SidebarMode: String, CaseIterable, Identifiable {
    case new = "New"
    case today = "Today"
    case archive = "Archive"

    var id: String { rawValue }

    var syncLabel: String {
        switch self {
        case .new:
            return "Sync unread items"
        case .today:
            return "Sync today's items"
        case .archive:
            return "Sync archive"
        }
    }
}

enum ThumbnailDisplayMode: String, CaseIterable, Identifiable {
    case articleThumbnail
    case favicon

    var id: String { rawValue }

    var label: String {
        switch self {
        case .articleThumbnail: return "Article Thumbnails"
        case .favicon:          return "Site Favicons"
        }
    }
}

enum ThumbnailAspectRatio: String, CaseIterable, Identifiable {
    case landscape
    case square
    case portrait

    var id: String { rawValue }

    var label: String {
        switch self {
        case .landscape:
            return "Landscape"
        case .square:
            return "Square"
        case .portrait:
            return "Portrait"
        }
    }

    var widthMultiplier: CGFloat {
        switch self {
        case .landscape:
            return 16.0 / 9.0
        case .square:
            return 1.0
        case .portrait:
            return 3.0 / 4.0
        }
    }
}

// MARK: - Service

@MainActor
final class FreshRSSService: ObservableObject {

    private struct TechmemeMetadata {
        let articleURL: URL?
        let author: String?
        let thumbnailURL: URL?
        let publication: String?
        let summary: String?

        static let empty = TechmemeMetadata(articleURL: nil, author: nil, thumbnailURL: nil, publication: nil, summary: nil)
    }

    private enum StorageKeys {
        static let serverURL = "rssreader_url"
        static let username = "rssreader_username"
        static let password = "rssreader_password"
        static let preferExternalBrowser = "rssreader_prefer_external_browser"
        static let loadArticleImages = "rssreader_load_article_images"
        static let articleThumbnailSize = "rssreader_article_thumbnail_size"
        static let articleThumbnailAspectRatio = "rssreader_article_thumbnail_aspect_ratio"
        static let thumbnailDisplayMode = "rssreader_thumbnail_display_mode"
        static let autoRefreshEnabled = "rssreader_auto_refresh_enabled"
        static let autoRefreshIntervalMinutes = "rssreader_auto_refresh_interval_minutes"
    }

    // MARK: Published state

    @Published var items: [FeedItem] = []
    @Published var subscriptions: [FeedSubscription] = []
    @Published var isLoading = false
    @Published var isAuthenticated = false
    @Published var errorMessage: String?
    @Published private(set) var locallyReadItemIDs: Set<String> = []
    @Published var sidebarMode: SidebarMode = .new
    @Published var selectedSubscriptionID: String? = nil
    @Published private(set) var lastResolvedHost: String = ""
    @Published private(set) var lastURLErrorCode: Int?
    @Published private(set) var lastSyncDate: Date?

    // MARK: Persisted settings

    @Published var serverURL: String {
        didSet {
            persistSetting(serverURL, forKey: StorageKeys.serverURL)
        }
    }
    @Published var username: String {
        didSet {
            persistSetting(username, forKey: StorageKeys.username)
        }
    }
    @Published var password: String {
        didSet {
            try? KeychainHelper.save(key: StorageKeys.password, value: password)
            hasStoredPassword = !password.isEmpty
        }
    }
    @Published var preferExternalBrowser: Bool {
        didSet { persistSetting(preferExternalBrowser, forKey: StorageKeys.preferExternalBrowser) }
    }
    @Published var loadArticleImages: Bool {
        didSet { persistSetting(loadArticleImages, forKey: StorageKeys.loadArticleImages) }
    }
    @Published var articleThumbnailSize: Int {
        didSet {
            let clampedSize = Self.clampArticleThumbnailSize(articleThumbnailSize)
            if clampedSize != articleThumbnailSize {
                articleThumbnailSize = clampedSize
                return
            }
            persistSetting(articleThumbnailSize, forKey: StorageKeys.articleThumbnailSize)
        }
    }
    @Published var articleThumbnailAspectRatio: ThumbnailAspectRatio {
        didSet {
            persistSetting(articleThumbnailAspectRatio.rawValue, forKey: StorageKeys.articleThumbnailAspectRatio)
        }
    }
    @Published var thumbnailDisplayMode: ThumbnailDisplayMode {
        didSet {
            persistSetting(thumbnailDisplayMode.rawValue, forKey: StorageKeys.thumbnailDisplayMode)
        }
    }
    @Published var autoRefreshEnabled: Bool {
        didSet { persistSetting(autoRefreshEnabled, forKey: StorageKeys.autoRefreshEnabled) }
    }
    @Published var autoRefreshIntervalMinutes: Int {
        didSet {
            let clampedMinutes = Self.clampAutoRefreshInterval(autoRefreshIntervalMinutes)
            if clampedMinutes != autoRefreshIntervalMinutes {
                autoRefreshIntervalMinutes = clampedMinutes
                return
            }
            persistSetting(autoRefreshIntervalMinutes, forKey: StorageKeys.autoRefreshIntervalMinutes)
        }
    }

    // MARK: Private auth state

    private var authToken: String?
    private var actionToken: String?
    private var hasStoredPassword = false
    private var techmemeMetadataCache: [String: TechmemeMetadata] = [:]
    private var techmemeEnrichmentTask: Task<Void, Never>?

    // MARK: Init

    init() {
        let defaults = UserDefaults.standard
        serverURL = defaults.string(forKey: StorageKeys.serverURL) ?? ""
        username = defaults.string(forKey: StorageKeys.username) ?? ""
        password = (try? KeychainHelper.retrieve(key: StorageKeys.password, allowUserInteraction: false)) ?? ""
        preferExternalBrowser = defaults.bool(forKey: StorageKeys.preferExternalBrowser)
        loadArticleImages = defaults.object(forKey: StorageKeys.loadArticleImages) as? Bool ?? true
        let storedThumbnailSize = defaults.integer(forKey: StorageKeys.articleThumbnailSize)
        articleThumbnailSize = Self.clampArticleThumbnailSize(storedThumbnailSize == 0 ? 38 : storedThumbnailSize)
        let storedAspectRatio = defaults.string(forKey: StorageKeys.articleThumbnailAspectRatio) ?? ThumbnailAspectRatio.landscape.rawValue
        articleThumbnailAspectRatio = ThumbnailAspectRatio(rawValue: storedAspectRatio) ?? .landscape
        let storedDisplayMode = defaults.string(forKey: StorageKeys.thumbnailDisplayMode) ?? ThumbnailDisplayMode.articleThumbnail.rawValue
        thumbnailDisplayMode = ThumbnailDisplayMode(rawValue: storedDisplayMode) ?? .articleThumbnail
        autoRefreshEnabled = defaults.object(forKey: StorageKeys.autoRefreshEnabled) as? Bool ?? true
        let storedInterval = defaults.integer(forKey: StorageKeys.autoRefreshIntervalMinutes)
        autoRefreshIntervalMinutes = Self.clampAutoRefreshInterval(storedInterval == 0 ? 15 : storedInterval)
        hasStoredPassword = !password.isEmpty
    }

    var isConfigured: Bool {
        !serverURL.isEmpty && !username.isEmpty && (!password.isEmpty || hasStoredPassword)
    }

    var unreadCount: Int {
        items.filter { !isMarkedRead($0) }.count
    }

    var normalizedServerURL: String {
        cleanBase()
    }

    func isMarkedRead(_ item: FeedItem) -> Bool {
        item.isRead || locallyReadItemIDs.contains(item.id)
    }

    var autoRefreshInterval: TimeInterval {
        TimeInterval(Self.clampAutoRefreshInterval(autoRefreshIntervalMinutes)) * 60
    }

    func shouldAutoSync(now: Date = .now) -> Bool {
        guard autoRefreshEnabled, isConfigured, !isLoading else { return false }
        guard let lastSyncDate else { return true }
        return now.timeIntervalSince(lastSyncDate) >= autoRefreshInterval
    }

    private static func clampAutoRefreshInterval(_ minutes: Int) -> Int {
        min(max(minutes, 1), 240)
    }

    private static func clampArticleThumbnailSize(_ size: Int) -> Int {
        min(max(size, 24), 72)
    }

    private func persistSetting(_ value: String, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private func persistSetting(_ value: Bool, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private func persistSetting(_ value: Int, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    // MARK: - Authentication

    func authenticateSilently() async {
        await authenticate(syncAfterLogin: true, allowUserInteraction: false, reportErrors: false)
    }

    func authenticate() async {
        await authenticate(syncAfterLogin: true, allowUserInteraction: true, reportErrors: true)
    }

    func runDNSPreflight() async -> (success: Bool, message: String) {
        guard let loginURL = gReaderURL(pathComponents: ["accounts", "ClientLogin"]) else {
            return (false, "Invalid server URL")
        }

        let host = loginURL.host ?? ""
        lastResolvedHost = host
        lastURLErrorCode = nil

        guard !host.isEmpty else {
            return (false, "Missing host in server URL")
        }

        var request = URLRequest(url: loginURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 8

        do {
            _ = try await URLSession.shared.data(for: request)
            return (true, "DNS resolved for \(host)")
        } catch {
            if let urlError = error as? URLError {
                lastURLErrorCode = urlError.errorCode
                if urlError.code == .cannotFindHost || urlError.code == .dnsLookupFailed {
                    let freshSession = makeFreshSession()
                    defer { freshSession.invalidateAndCancel() }
                    do {
                        _ = try await freshSession.data(for: request)
                        lastURLErrorCode = nil
                        return (true, "DNS resolved for \(host) after refresh")
                    } catch {
                        if let refreshedError = error as? URLError {
                            lastURLErrorCode = refreshedError.errorCode
                            if refreshedError.code == .cannotFindHost || refreshedError.code == .dnsLookupFailed {
                                return (false, "DNS lookup failed for \(host)")
                            }
                            return (true, "Host resolved; request failed with URL error \(refreshedError.errorCode)")
                        }
                        return (false, "DNS preflight failed: \(error.localizedDescription)")
                    }
                }
                // Any non-DNS URL error means hostname resolution succeeded.
                return (true, "Host resolved; request failed with URL error \(urlError.errorCode)")
            }
            return (false, "DNS preflight failed: \(error.localizedDescription)")
        }
    }

    private func authenticate(syncAfterLogin: Bool, allowUserInteraction: Bool, reportErrors: Bool) async {
        if password.isEmpty {
            password = (try? KeychainHelper.retrieve(key: StorageKeys.password, allowUserInteraction: allowUserInteraction)) ?? ""
            hasStoredPassword = !password.isEmpty
        }

        guard isConfigured else {
            if reportErrors {
                errorMessage = FreshRSSError.notConfigured.errorDescription
            }
            return
        }

        if reportErrors {
            errorMessage = nil
        }

        lastResolvedHost = URL(string: normalizedServerURL)?.host ?? ""
        lastURLErrorCode = nil

        guard let loginURL = gReaderURL(pathComponents: ["accounts", "ClientLogin"]) else {
            if reportErrors {
                errorMessage = "Invalid server URL. Use a host like example.com or a full URL like https://example.com."
            }
            return
        }
        lastResolvedHost = loginURL.host ?? lastResolvedHost
        let usesVPNStyleHost = isVPNStyleHost(loginURL.host)

        var request = URLRequest(url: loginURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "Email",  value: username),
            URLQueryItem(name: "Passwd", value: password)
        ]
        request.httpBody = components.query?.data(using: .utf8)

        let maxAttempts = usesVPNStyleHost ? 5 : 4
        var lastError: Error?

        for attempt in 1...maxAttempts {
            // VPN/split-DNS hostnames are more sensitive to stale resolver cache.
            let useFreshSession = usesVPNStyleHost || attempt == maxAttempts
            let session = useFreshSession ? makeFreshSession() : URLSession.shared

            do {
                let (data, response) = try await session.data(for: request)
                if useFreshSession {
                    session.finishTasksAndInvalidate()
                }
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    if reportErrors {
                        errorMessage = FreshRSSError.authenticationFailed.errorDescription
                    }
                    isAuthenticated = false
                    return
                }

                let text = String(data: data, encoding: .utf8) ?? ""
                authToken = nil
                for line in text.components(separatedBy: "\n") {
                    if line.hasPrefix("Auth=") {
                        authToken = String(line.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
                        break
                    }
                }

                if authToken != nil {
                    isAuthenticated = true
                    lastURLErrorCode = nil
                    await fetchSubscriptions()
                    if syncAfterLogin {
                        await syncCurrentMode()
                    }
                } else {
                    if reportErrors {
                        errorMessage = FreshRSSError.authenticationFailed.errorDescription
                    }
                    isAuthenticated = false
                }
                return
            } catch {
                if useFreshSession {
                    session.invalidateAndCancel()
                }
                lastError = error
                guard let urlError = error as? URLError else { break }

                lastURLErrorCode = urlError.errorCode
                let retryableDNSFailure = urlError.code == .cannotFindHost || urlError.code == .dnsLookupFailed
                if retryableDNSFailure && attempt < maxAttempts {
                    // DNS for VPN hosts can come up a moment after network path reports "satisfied".
                    let delayMultiplier = usesVPNStyleHost ? 500_000_000 : 350_000_000
                    try? await Task.sleep(nanoseconds: UInt64(delayMultiplier * attempt))
                    continue
                }
                break
            }
        }

        if reportErrors {
            if let urlError = lastError as? URLError, urlError.code == .cannotFindHost {
                let host = loginURL.host ?? "(unknown host)"
                if host.contains(".vpn.") {
                    errorMessage = "Network error: Could not resolve host '\(host)'. VPN DNS is likely unavailable. Confirm your VPN is connected and DNS is routed through it, then retry."
                } else {
                    errorMessage = "Network error: Could not resolve host '\(host)'. Verify the server URL host and DNS reachability."
                }
            } else if let urlError = lastError as? URLError, urlError.code == .dnsLookupFailed {
                let host = loginURL.host ?? "(unknown host)"
                errorMessage = "Network error: DNS lookup failed for '\(host)'. Check VPN/DNS settings and retry."
            } else if let lastError {
                errorMessage = FreshRSSError.networkError(lastError.localizedDescription).errorDescription
            }
        }

        isAuthenticated = false
    }

    // MARK: - Fetch items

    func syncCurrentMode() async {
        await fetchItems(for: sidebarMode)
    }

    func fetchSubscriptions() async {
        guard let token = authToken,
              let url = gReaderURL(pathComponents: ["reader", "api", "0", "subscription", "list"]) else { return }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "output", value: "json")]
        guard let requestURL = components?.url else { return }
        var request = URLRequest(url: requestURL)
        request.setValue("GoogleLogin auth=\(token)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let list = try? JSONDecoder().decode(GReaderSubscriptionListResponse.self, from: data) else { return }
        subscriptions = list.subscriptions
            .map { FeedSubscription(id: $0.id, title: $0.title ?? $0.id) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func fetchItems(for mode: SidebarMode) async {
        let archiveLimit = 1_000
        techmemeEnrichmentTask?.cancel()

        guard let token = await ensureAuthenticationToken() else {
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            var fetchedItems: [FeedItem] = []
            var continuation: String?

            repeat {
                let response = try await fetchStreamPage(token: token, mode: mode, continuation: continuation)
                fetchedItems.append(contentsOf: response.items.compactMap(makeFeedItem(from:)))
                continuation = response.continuation

                if mode == .archive, fetchedItems.count >= archiveLimit {
                    continuation = nil
                }
            } while continuation != nil

            if mode == .today {
                let cutoff = todayModeCutoffDate()
                fetchedItems = fetchedItems.filter { $0.publishedDate >= cutoff }
            }

            let deduplicatedItems = deduplicated(items: fetchedItems)
            if mode == .archive {
                items = Array(deduplicatedItems.prefix(archiveLimit))
            } else {
                items = deduplicatedItems
            }

            scheduleTechmemeEnrichment(for: items)
            lastSyncDate = Date()
            locallyReadItemIDs.removeAll()

        } catch {
            errorMessage = "Failed to load items: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - Mark as read

    func markAsRead(_ item: FeedItem) async {
        await markAsRead([item])
    }

    func markAsRead(_ selectedItems: [FeedItem]) async {
        let unreadItems = selectedItems.filter { !isMarkedRead($0) }
        guard !unreadItems.isEmpty else { return }

        locallyReadItemIDs.formUnion(unreadItems.map(\.id))

        guard await ensureAuthenticationToken() != nil else {
            locallyReadItemIDs.subtract(unreadItems.map(\.id))
            return
        }

        if actionToken == nil {
            actionToken = await fetchActionToken()
        }

        var failedCount = 0
        for item in unreadItems {
            let succeeded = await sendMarkAsRead(item)
            if succeeded { continue }

            actionToken = await fetchActionToken()
            if await sendMarkAsRead(item) { continue }

            failedCount += 1
            locallyReadItemIDs.remove(item.id)
        }

        if failedCount > 0 {
            errorMessage = unreadItems.count == 1
                ? "Failed to mark \(unreadItems[0].title) as read."
                : "Some selected items could not be marked as read."
        }
    }

    func markAsUnread(_ item: FeedItem) async {
        await markAsUnread([item])
    }

    func markAsUnread(_ selectedItems: [FeedItem]) async {
        let readItems = selectedItems.filter { isMarkedRead($0) }
        guard !readItems.isEmpty else { return }

        let initiallyLocallyRead = Set(readItems.filter { locallyReadItemIDs.contains($0.id) }.map(\.id))
        locallyReadItemIDs.subtract(readItems.map(\.id))

        guard await ensureAuthenticationToken() != nil else {
            locallyReadItemIDs.formUnion(initiallyLocallyRead)
            return
        }

        if actionToken == nil {
            actionToken = await fetchActionToken()
        }

        var failedCount = 0
        for item in readItems {
            let succeeded = await sendMarkAsUnread(item)
            if succeeded { continue }

            actionToken = await fetchActionToken()
            if await sendMarkAsUnread(item) { continue }

            failedCount += 1
            if initiallyLocallyRead.contains(item.id) {
                locallyReadItemIDs.insert(item.id)
            }
        }

        if readItems.contains(where: { $0.isRead }) {
            await syncCurrentMode()
        }

        if failedCount > 0 {
            errorMessage = readItems.count == 1
                ? "Failed to mark \(readItems[0].title) as unread."
                : "Some selected items could not be marked as unread."
        }
    }

    func markAllAsRead() async {
        let unreadItems = items.filter { !isMarkedRead($0) }
        guard !unreadItems.isEmpty else {
            await syncCurrentMode()
            return
        }

        locallyReadItemIDs.formUnion(unreadItems.map(\.id))

        guard await ensureAuthenticationToken() != nil else {
                locallyReadItemIDs.subtract(unreadItems.map(\.id))
                return
        }

        if actionToken == nil {
            actionToken = await fetchActionToken()
        }

        var allSucceeded = true
        for item in unreadItems {
            let succeeded = await sendMarkAsRead(item)
            if succeeded { continue }

            actionToken = await fetchActionToken()
            if await sendMarkAsRead(item) { continue }

            allSucceeded = false
            locallyReadItemIDs.remove(item.id)
        }

        await syncCurrentMode()

        if !allSucceeded {
            errorMessage = "Some items could not be marked as read."
        }
    }

    func markAllAsUnread() async {
        let readItems = items.filter { isMarkedRead($0) }
        guard !readItems.isEmpty else {
            await syncCurrentMode()
            return
        }

        locallyReadItemIDs.subtract(readItems.map(\.id))

        guard await ensureAuthenticationToken() != nil else {
            return
        }

        if actionToken == nil {
            actionToken = await fetchActionToken()
        }

        var allSucceeded = true
        for item in readItems {
            let succeeded = await sendMarkAsUnread(item)
            if succeeded { continue }

            actionToken = await fetchActionToken()
            if await sendMarkAsUnread(item) { continue }

            allSucceeded = false
            locallyReadItemIDs.insert(item.id)
        }

        await syncCurrentMode()

        if !allSucceeded {
            errorMessage = "Some items could not be marked as unread."
        }
    }

    @discardableResult
    private func sendMarkAsRead(_ item: FeedItem) async -> Bool {
        guard let authToken = authToken, let actionToken = actionToken else { return false }

        guard let editURL = gReaderURL(pathComponents: ["reader", "api", "0", "edit-tag"]) else { return false }

        var request = URLRequest(url: editURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("GoogleLogin auth=\(authToken)", forHTTPHeaderField: "Authorization")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "i", value: item.id),
            URLQueryItem(name: "a", value: "user/-/state/com.google/read"),
            URLQueryItem(name: "T", value: actionToken)
        ]
        request.httpBody = components.query?.data(using: .utf8)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 401 {
                    self.actionToken = nil
                    return false
                }
                return http.statusCode == 200
            }
        } catch {}
        return false
    }

    @discardableResult
    private func sendMarkAsUnread(_ item: FeedItem) async -> Bool {
        guard let authToken = authToken, let actionToken = actionToken else { return false }

        guard let editURL = gReaderURL(pathComponents: ["reader", "api", "0", "edit-tag"]) else { return false }

        var request = URLRequest(url: editURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("GoogleLogin auth=\(authToken)", forHTTPHeaderField: "Authorization")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "i", value: item.id),
            URLQueryItem(name: "r", value: "user/-/state/com.google/read"),
            URLQueryItem(name: "T", value: actionToken)
        ]
        request.httpBody = components.query?.data(using: .utf8)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 401 {
                    self.actionToken = nil
                    return false
                }
                return http.statusCode == 200
            }
        } catch {}
        return false
    }

    // MARK: - Action token

    private func fetchActionToken() async -> String? {
        guard let authToken = authToken else { return nil }

        guard let tokenURL = gReaderURL(pathComponents: ["reader", "api", "0", "token"]) else { return nil }

        var request = URLRequest(url: tokenURL)
        request.setValue("GoogleLogin auth=\(authToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    // MARK: - Helpers

    private func ensureAuthenticationToken() async -> String? {
        if let authToken {
            return authToken
        }

        await authenticate(syncAfterLogin: false, allowUserInteraction: true, reportErrors: true)
        return authToken
    }

    private func fetchStreamPage(token: String, mode: SidebarMode, continuation: String?) async throws -> GReaderStreamResponse {
        guard let baseURL = gReaderURL(pathComponents: ["reader", "api", "0", "stream", "contents", "reading-list"]) else {
            throw FreshRSSError.networkError("Invalid server URL")
        }
        var urlComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        var queryItems = [
            URLQueryItem(name: "n", value: mode == .new ? "100" : "250"),
            URLQueryItem(name: "output", value: "json")
        ]

        if mode == .new {
            queryItems.append(URLQueryItem(name: "xt", value: "user/-/state/com.google/read"))
        }

        if mode == .today {
            queryItems.append(URLQueryItem(name: "ot", value: String(Int(todayModeCutoffDate().timeIntervalSince1970))))
        }

        if let continuation {
            queryItems.append(URLQueryItem(name: "c", value: continuation))
        }

        urlComponents?.queryItems = queryItems

        guard let url = urlComponents?.url else {
            throw FreshRSSError.networkError("Invalid feed URL")
        }

        var request = URLRequest(url: url)
        request.setValue("GoogleLogin auth=\(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw FreshRSSError.serverError(http.statusCode)
        }

        return try JSONDecoder().decode(GReaderStreamResponse.self, from: data)
    }

    private func makeFeedItem(from gItem: GReaderItem) -> FeedItem? {
        let href = gItem.canonical?.first?.href ?? gItem.alternate?.first?.href
        let url = href.flatMap { URL(string: $0).map(enforcingHTTPSForTechmemeURL) }
        let html = gItem.content?.content ?? gItem.summary?.content ?? ""
        let techmemeURL = techmemeURL(for: gItem, html: html) ?? url.flatMap { isTechmemeURL($0) ? $0 : nil }
        let inlineTechmemeMetadata = techmemeURL.flatMap { parseInlineTechmemeMetadata(from: html, techmemeURL: $0) } ?? .empty
        let categories = gItem.categories ?? []
        let resolvedURL = inlineTechmemeMetadata.articleURL ?? url
        let author = cleanedAuthorString(inlineTechmemeMetadata.author) ?? cleanedAuthorString(gItem.author)
        let publication = resolvedPublicationLabel(existing: gItem.origin?.title ?? "Unknown", endPublication: inlineTechmemeMetadata.publication, author: author)
        let summary = cleanedNonEmptyString(inlineTechmemeMetadata.summary)
        let normalizedTitle = cleanedTechmemeHeadlineTitle(
            gItem.title ?? "Untitled",
            isTechmemeItem: techmemeURL != nil,
            author: author,
            publication: publication
        )
        let articleThumbnailURL = inlineTechmemeMetadata.thumbnailURL
            ?? bestThumbnailURL(for: gItem, articleURL: resolvedURL, html: html)
            ?? techmemeFallbackThumbnailURL(for: techmemeURL)
        let publicationIconURL = publicationIconURL(for: publication, articleURL: resolvedURL, fallback: publicationIconURL(for: gItem, articleURL: resolvedURL))

        return FeedItem(
            id: gItem.id,
            title: normalizedTitle,
            publication: publication,
            author: author,
            url: resolvedURL,
            techmemeURL: techmemeURL,
            techmemeSummary: summary,
            articleThumbnailURL: articleThumbnailURL,
            publicationIconURL: publicationIconURL,
            content: html,
            publishedDate: Date(timeIntervalSince1970: TimeInterval(gItem.published ?? 0)),
            enclosureType: gItem.enclosure?.first?.type,
            isRead: categories.contains("user/-/state/com.google/read"),
            subscriptionID: gItem.origin?.streamId
        )
    }

    private func techmemeURL(for gItem: GReaderItem, html: String) -> URL? {
        let links = (gItem.canonical ?? []) + (gItem.alternate ?? [])

        for link in links {
            guard let candidate = URL(string: link.href).map(enforcingHTTPSForTechmemeURL), isTechmemeURL(candidate) else {
                continue
            }
            return candidate
        }

        if let permalink = techmemePermalinkURL(in: html) {
            return permalink
        }

        return nil
    }

    private func techmemePermalinkURL(in html: String) -> URL? {
        guard let href = firstMatchGroup(
            in: html,
            pattern: "(?is)<a[^>]+href\\s*=\\s*['\"]([^'\"]+)['\"][^>]*title\\s*=\\s*['\"]Techmeme permalink['\"]"
        ) ?? firstMatchGroup(
            in: html,
            pattern: "(?is)<a[^>]*title\\s*=\\s*['\"]Techmeme permalink['\"][^>]*href\\s*=\\s*['\"]([^'\"]+)['\"]"
        ) else {
            return nil
        }

        guard let permalinkURL = URL(string: decodeHTMLEntities(href)).map(enforcingHTTPSForTechmemeURL), isTechmemeURL(permalinkURL) else {
            return nil
        }

        return permalinkURL
    }

    private func enforcingHTTPSForTechmemeURL(_ url: URL) -> URL {
        guard isTechmemeURL(url),
              url.scheme?.lowercased() == "http",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        components.scheme = "https"
        return components.url ?? url
    }

    private func scheduleTechmemeEnrichment(for sourceItems: [FeedItem]) {
        techmemeEnrichmentTask?.cancel()

        let targetIDs: [String] = sourceItems.compactMap { item in
            guard item.techmemeURL != nil else {
                return nil
            }

            return needsTechmemeEnrichment(item) ? item.id : nil
        }
        guard !targetIDs.isEmpty else {
            return
        }

        let idSet = Set(targetIDs)
        techmemeEnrichmentTask = Task {
            await enrichTechmemeItems(targetIDs: idSet)
        }
    }

    private func enrichTechmemeItems(targetIDs: Set<String>) async {
        let targets = items.filter { targetIDs.contains($0.id) && $0.techmemeURL != nil && needsTechmemeEnrichment($0) }
        guard !targets.isEmpty else {
            return
        }

        var updates: [String: FeedItem] = [:]

        for item in targets {
            if Task.isCancelled {
                return
            }

            guard let techmemeURL = item.techmemeURL else {
                continue
            }

            let metadata = await resolveTechmemeMetadata(for: techmemeURL)
            let updated = applyingTechmemeMetadata(metadata, to: item)
            if hasDisplayChanges(original: item, updated: updated) {
                updates[item.id] = updated
            }
        }

        if Task.isCancelled || updates.isEmpty {
            return
        }

        items = items.map { item in
            updates[item.id] ?? item
        }
    }

    private func applyingTechmemeMetadata(_ metadata: TechmemeMetadata, to item: FeedItem) -> FeedItem {
        let resolvedURL = metadata.articleURL ?? item.url
        let resolvedAuthor = cleanedAuthorString(metadata.author) ?? item.author
        let resolvedThumbnail = metadata.thumbnailURL ?? item.articleThumbnailURL ?? techmemeFallbackThumbnailURL(for: item.techmemeURL)
        let publication = resolvedPublicationLabel(existing: item.publication, endPublication: metadata.publication, author: resolvedAuthor)
        let summary = cleanedNonEmptyString(metadata.summary) ?? item.techmemeSummary
        let resolvedPublicationIconURL = publicationIconURL(for: publication, articleURL: resolvedURL, fallback: item.publicationIconURL)

        return FeedItem(
            id: item.id,
            title: item.title,
            publication: publication,
            author: resolvedAuthor,
            url: resolvedURL,
            techmemeURL: item.techmemeURL,
            techmemeSummary: summary,
            articleThumbnailURL: resolvedThumbnail,
            publicationIconURL: resolvedPublicationIconURL,
            content: item.content,
            publishedDate: item.publishedDate,
            enclosureType: item.enclosureType,
            isRead: item.isRead,
            subscriptionID: item.subscriptionID
        )
    }


            private func techmemeFallbackThumbnailURL(for techmemeURL: URL?) -> URL? {
                guard let techmemeURL,
                      let host = techmemeURL.host,
                      !host.isEmpty else {
                    return nil
                }

                var components = URLComponents()
                components.scheme = techmemeURL.scheme ?? "https"
                components.host = host
                components.path = "/favicon.ico"
                return components.url
            }
    private func resolvedPublicationLabel(existing: String, endPublication: String?, author: String?) -> String {
        guard let cleanedEndPublication = normalizedTechmemePublication(endPublication, author: author) else {
            return existing
        }

        return "Techmeme > \(cleanedEndPublication)"
    }

    private func hasDisplayChanges(original: FeedItem, updated: FeedItem) -> Bool {
        original.url != updated.url ||
        original.author != updated.author ||
        original.articleThumbnailURL != updated.articleThumbnailURL ||
        original.publicationIconURL != updated.publicationIconURL ||
        original.publication != updated.publication ||
        original.techmemeSummary != updated.techmemeSummary
    }

    private func needsTechmemeEnrichment(_ item: FeedItem) -> Bool {
        item.url == item.techmemeURL ||
        item.articleThumbnailURL == nil ||
        cleanedNonEmptyString(item.techmemeSummary) == nil ||
        item.publication == "Techmeme"
    }

    private func publicationIconURL(for publication: String, articleURL: URL?, fallback: URL?) -> URL? {
        if publication.lowercased().contains("techmeme") == false,
           let host = articleURL?.host,
           !host.isEmpty {
            return URL(string: "https://\(host)/favicon.ico")
        }

        return fallback
    }

    private func resolveTechmemeMetadata(for url: URL?) async -> TechmemeMetadata {
        guard let url, isTechmemeURL(url) else {
            return .empty
        }

        let cacheKey = url.absoluteString
        if let cached = techmemeMetadataCache[cacheKey] {
            return cached
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("text/html", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return .empty
            }

            guard let html = String(data: data, encoding: .utf8), !html.isEmpty else {
                return .empty
            }

            let parsed = parseTechmemeMetadata(from: html, pageURL: url)
            techmemeMetadataCache[cacheKey] = parsed
            return parsed
        } catch {
            return .empty
        }
    }

    private func parseTechmemeMetadata(from html: String, pageURL: URL) -> TechmemeMetadata {
        let section = techmemeSectionHTML(in: html, anchor: pageURL.fragment) ?? html
        let itemBlock = techmemePrimaryItemHTML(in: section) ?? section
        let articleURL = techmemePrimaryArticleURL(in: itemBlock, relativeTo: pageURL)
            ?? firstExternalLink(in: itemBlock, relativeTo: pageURL)
        let author = techmemeAuthor(in: section)
        let publication = techmemePublication(in: section)
        let summary = techmemeSummary(in: itemBlock)
        let thumbnailURL = techmemeThumbnailURL(in: itemBlock, relativeTo: pageURL)
            ?? firstImageSource(in: itemBlock).flatMap { resolvePossibleRelativeURL($0, relativeTo: pageURL) }

        return TechmemeMetadata(articleURL: articleURL, author: author, thumbnailURL: thumbnailURL, publication: publication, summary: summary)
    }

    private func parseInlineTechmemeMetadata(from html: String, techmemeURL: URL) -> TechmemeMetadata {
        let itemBlock = techmemePrimaryItemHTML(in: html) ?? html
        let articleURL = techmemePrimaryArticleURL(in: itemBlock, relativeTo: techmemeURL)
            ?? firstExternalLink(in: itemBlock, relativeTo: techmemeURL)
        let publication = techmemePublication(in: html)
        let summary = techmemeSummary(in: itemBlock)
        let thumbnailURL = techmemeThumbnailURL(in: itemBlock, relativeTo: techmemeURL)
            ?? firstImageSource(in: itemBlock).flatMap { resolvePossibleRelativeURL($0, relativeTo: techmemeURL) }

        return TechmemeMetadata(articleURL: articleURL, author: nil, thumbnailURL: thumbnailURL, publication: publication, summary: summary)
    }

    private func techmemePrimaryItemHTML(in html: String) -> String? {
        firstMatchGroup(in: html, pattern: "(?is)<div[^>]*class\\s*=\\s*['\\\"][^'\\\"]*ii[^'\\\"]*['\\\"][^>]*>(.*?)</div>")
    }

    private func techmemePrimaryArticleURL(in html: String, relativeTo pageURL: URL) -> URL? {
        if let href = firstMatchGroup(in: html, pattern: "(?is)<a[^>]*class\\s*=\\s*['\\\"][^'\\\"]*ourh[^'\\\"]*['\\\"][^>]*href\\s*=\\s*['\\\"]([^'\\\"]+)['\\\"]") {
            return resolvePossibleRelativeURL(decodeHTMLEntities(href), relativeTo: pageURL)
        }

        if let href = firstMatchGroup(in: html, pattern: "(?is)<div[^>]*class\\s*=\\s*['\\\"][^'\\\"]*ii[^'\\\"]*['\\\"][^>]*>.*?<a[^>]+href\\s*=\\s*['\\\"]([^'\\\"]+)['\\\"]") {
            return resolvePossibleRelativeURL(decodeHTMLEntities(href), relativeTo: pageURL)
        }

        return nil
    }

    private func techmemeThumbnailURL(in html: String, relativeTo pageURL: URL) -> URL? {
        guard let source = firstMatchGroup(in: html, pattern: "(?is)<img[^>]*class\\s*=\\s*['\\\"][^'\\\"]*ill[^'\\\"]*['\\\"][^>]*src\\s*=\\s*['\\\"]([^'\\\"]+)['\\\"]")
            ?? firstMatchGroup(in: html, pattern: "(?is)<div[^>]*class\\s*=\\s*['\\\"][^'\\\"]*ii[^'\\\"]*['\\\"][^>]*>.*?<img[^>]+src\\s*=\\s*['\\\"]([^'\\\"]+)['\\\"]") else {
            return nil
        }

        return resolvePossibleRelativeURL(decodeHTMLEntities(source), relativeTo: pageURL)
    }

    private func techmemeSectionHTML(in html: String, anchor: String?) -> String? {
        guard let anchor, !anchor.isEmpty else {
            return nil
        }

        let nsHTML = html as NSString
        let escapedAnchor = NSRegularExpression.escapedPattern(for: anchor)
        let anchorPattern = "(?is)(id|name)\\s*=\\s*[\\\"']\(escapedAnchor)[\\\"']"
        guard let anchorRegex = try? NSRegularExpression(pattern: anchorPattern),
              let anchorMatch = anchorRegex.firstMatch(in: html, range: NSRange(location: 0, length: nsHTML.length)) else {
            return nil
        }

        let startLocation = anchorMatch.range.location
        let remainingRange = NSRange(location: min(startLocation + 1, nsHTML.length), length: max(0, nsHTML.length - (startLocation + 1)))
        let nextAnchorPattern = "(?is)(id|name)\\s*=\\s*[\\\"']a\\d{6}p\\d+[\\\"']"
        let nextAnchorRegex = try? NSRegularExpression(pattern: nextAnchorPattern)
        let nextAnchor = nextAnchorRegex?.firstMatch(in: html, range: remainingRange)

        let hardLimit = min(nsHTML.length, startLocation + 8_000)
        let endLocation = min(nextAnchor?.range.location ?? hardLimit, hardLimit)
        guard endLocation > startLocation else {
            return nil
        }

        return nsHTML.substring(with: NSRange(location: startLocation, length: endLocation - startLocation))
    }

    private func firstExternalLink(in html: String, relativeTo pageURL: URL) -> URL? {
        guard let regex = try? NSRegularExpression(pattern: "(?is)<a[^>]+href\\s*=\\s*['\\\"]([^'\\\"]+)['\\\"]") else {
            return nil
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex.matches(in: html, options: [], range: range)

        for match in matches where match.numberOfRanges > 1 {
            guard let hrefRange = Range(match.range(at: 1), in: html) else { continue }
            let href = decodeHTMLEntities(String(html[hrefRange]))
            guard let candidateURL = resolvePossibleRelativeURL(href, relativeTo: pageURL),
                  let host = candidateURL.host?.lowercased() else {
                continue
            }

            if host == "techmeme.com" || host.hasSuffix(".techmeme.com") {
                continue
            }

            return candidateURL
        }

        return nil
    }

    private func techmemeAuthor(in html: String) -> String? {
        if let citeInner = firstMatchGroup(in: html, pattern: "(?is)<cite[^>]*>(.*?)</cite>") {
            var cleanedCite = decodeHTMLEntities(strippingHTMLTags(from: citeInner))
            cleanedCite = cleanedCite.replacingOccurrences(of: ":", with: "")
            cleanedCite = cleanedCite.trimmingCharacters(in: CharacterSet(charactersIn: " \n\r\t"))

            if let slashIndex = cleanedCite.firstIndex(of: "/") {
                let beforeSlash = cleanedCite[..<slashIndex]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !beforeSlash.isEmpty {
                    return beforeSlash
                }
            }
        }

        if let sourceText = firstMatchGroup(in: html, pattern: "(?is)<a[^>]*class\\s*=\\s*['\\\"][^'\\\"]*ourh[^'\\\"]*['\\\"][^>]*>(.*?)</a>") {
            let cleaned = decodeHTMLEntities(strippingHTMLTags(from: sourceText))
                .trimmingCharacters(in: CharacterSet(charactersIn: " :\n\r\t"))
            if !cleaned.isEmpty {
                return cleaned
            }
        }

        return nil
    }

    private func techmemePublication(in html: String) -> String? {
        if let publication = firstMatchGroup(in: html, pattern: "(?is)<cite[^>]*>\\s*<a[^>]*>(.*?)</a>") {
            return cleanedNonEmptyString(decodeHTMLEntities(strippingHTMLTags(from: publication)))
        }

        if let citeInner = firstMatchGroup(in: html, pattern: "(?is)<cite[^>]*>(.*?)</cite>") {
            return cleanedNonEmptyString(decodeHTMLEntities(strippingHTMLTags(from: citeInner)).replacingOccurrences(of: ":", with: ""))
        }

        return nil
    }

    private func normalizedTechmemePublication(_ publication: String?, author: String?) -> String? {
        guard var cleanedPublication = cleanedNonEmptyString(publication) else {
            return nil
        }

        if let slashIndex = cleanedPublication.firstIndex(of: "/") {
            let afterSlash = cleanedPublication[cleanedPublication.index(after: slashIndex)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !afterSlash.isEmpty {
                cleanedPublication = afterSlash
            }
        }

        if let author = cleanedNonEmptyString(author) {
            let lowerPublication = cleanedPublication.lowercased()
            let lowerAuthor = author.lowercased()

            if lowerPublication.hasPrefix(lowerAuthor) {
                cleanedPublication = cleanedPublication.dropFirst(author.count)
                    .trimmingCharacters(in: CharacterSet(charactersIn: " /:-\n\r\t"))
            }
        }

        return cleanedNonEmptyString(cleanedPublication)
    }

    private func techmemeSummary(in itemHTML: String) -> String? {
        if let rawSummary = firstMatchGroup(in: itemHTML, pattern: "(?is)</strong>\\s*&nbsp;\\s*[—-]\\s*&nbsp;\\s*(.*?)\\s*$") {
            return cleanedNonEmptyString(decodeHTMLEntities(strippingHTMLTags(from: rawSummary)))
        }

        let plainText = decodeHTMLEntities(strippingHTMLTags(from: itemHTML))
        let separators = [" — ", " - "]
        for separator in separators {
            if let range = plainText.range(of: separator) {
                let summary = String(plainText[range.upperBound...])
                if let cleaned = cleanedNonEmptyString(summary) {
                    return cleaned
                }
            }
        }

        return nil
    }

    private func firstMatchGroup(in text: String, pattern: String, group: Int = 1) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > group,
              let outputRange = Range(match.range(at: group), in: text) else {
            return nil
        }

        return String(text[outputRange])
    }

    private func strippingHTMLTags(from value: String) -> String {
        guard !value.isEmpty,
              let regex = try? NSRegularExpression(pattern: "(?is)<[^>]+>") else {
            return value
        }

        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        let noTags = regex.stringByReplacingMatches(in: value, options: [], range: range, withTemplate: " ")
        return noTags
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func decodeHTMLEntities(_ value: String) -> String {
        var decoded = value
        let replacements = [
            "&amp;": "&",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'",
            "&lt;": "<",
            "&gt;": ">",
            "&nbsp;": " "
        ]

        for (entity, replacement) in replacements {
            decoded = decoded.replacingOccurrences(of: entity, with: replacement)
        }

        return decoded
    }

    private func isTechmemeURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return false
        }

        return host == "techmeme.com" || host.hasSuffix(".techmeme.com")
    }

    private func cleanedNonEmptyString(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func cleanedAuthorString(_ value: String?) -> String? {
        guard let cleaned = cleanedNonEmptyString(value) else {
            return nil
        }

        let wordCount = cleaned
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .count

        guard wordCount <= 5 else {
            return nil
        }

        return cleaned
    }

    private func cleanedTechmemeHeadlineTitle(_ title: String, isTechmemeItem: Bool, author: String?, publication: String?) -> String {
        let baseTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isTechmemeItem,
              !baseTitle.isEmpty,
              let attribution = firstMatchGroup(in: baseTitle, pattern: "\\(([^()]*)\\)\\s*$"),
              let titleWithoutAttribution = firstMatchGroup(in: baseTitle, pattern: "^(.*?)\\s*\\([^()]*\\)\\s*$") else {
            return baseTitle.isEmpty ? "Untitled" : baseTitle
        }

        let cleanAttribution = attribution.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTitle = titleWithoutAttribution.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanAttribution.isEmpty, !cleanTitle.isEmpty else {
            return baseTitle
        }

        let normalizedAuthor = normalizedAttributionToken(author)
        let normalizedPublication = normalizedAttributionToken(publication)
        let parts = cleanAttribution
            .split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let containsKnownSource = parts.contains { part in
            let normalizedPart = normalizedAttributionToken(part)
            guard !normalizedPart.isEmpty else { return false }

            if !normalizedAuthor.isEmpty,
               (normalizedAuthor.contains(normalizedPart) || normalizedPart.contains(normalizedAuthor)) {
                return true
            }

            if !normalizedPublication.isEmpty,
               (normalizedPublication.contains(normalizedPart) || normalizedPart.contains(normalizedPublication)) {
                return true
            }

            return false
        }

        let looksLikeByline = parts.count >= 2
            && parts.allSatisfy { part in
                let words = part.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
                return words > 0 && words <= 8
            }

        guard containsKnownSource || looksLikeByline else {
            return baseTitle
        }

        return cleanTitle
    }

    private func normalizedAttributionToken(_ value: String?) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return ""
        }

        let lowered = value.lowercased()
        let filteredScalars = lowered.unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar) || CharacterSet.whitespacesAndNewlines.contains(scalar)
        }
        let normalized = String(String.UnicodeScalarView(filteredScalars))
        return normalized
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func bestThumbnailURL(for gItem: GReaderItem, articleURL: URL?, html: String) -> URL? {
        if let imageEnclosure = gItem.enclosure?.first(where: { ($0.type ?? "").lowercased().hasPrefix("image/") }),
           let href = imageEnclosure.href,
           let url = resolvePossibleRelativeURL(href, relativeTo: articleURL) {
            return url
        }

        if let firstImageSource = firstImageSource(in: html) {
            return resolvePossibleRelativeURL(firstImageSource, relativeTo: articleURL)
        }

        return nil
    }

    private func publicationIconURL(for gItem: GReaderItem, articleURL: URL?) -> URL? {
        if let originURLString = gItem.origin?.htmlUrl,
           let originURL = URL(string: originURLString),
           let host = originURL.host,
           !host.isEmpty {
            return URL(string: "https://\(host)/favicon.ico")
        }

        if let host = articleURL?.host, !host.isEmpty {
            return URL(string: "https://\(host)/favicon.ico")
        }

        return nil
    }

    private func firstImageSource(in html: String) -> String? {
        guard !html.isEmpty,
              let regex = try? NSRegularExpression(pattern: "(?i)<img[^>]+src\\s*=\\s*['\"]([^'\"]+)['\"]") else {
            return nil
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: range),
              match.numberOfRanges > 1,
              let sourceRange = Range(match.range(at: 1), in: html) else {
            return nil
        }

        return String(html[sourceRange])
    }

    private func resolvePossibleRelativeURL(_ value: String, relativeTo articleURL: URL?) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let absolute = URL(string: trimmed), absolute.scheme != nil {
            return enforcingHTTPSForTechmemeURL(absolute)
        }

        if let articleURL {
            if let relativeURL = URL(string: trimmed, relativeTo: articleURL)?.absoluteURL {
                return enforcingHTTPSForTechmemeURL(relativeURL)
            }
        }

        if let fallbackURL = URL(string: trimmed) {
            return enforcingHTTPSForTechmemeURL(fallbackURL)
        }

        return nil
    }

    private func deduplicated(items: [FeedItem]) -> [FeedItem] {
        var seenIDs = Set<String>()
        var uniqueItems: [FeedItem] = []

        for item in items.sorted(by: { $0.publishedDate > $1.publishedDate }) {
            if seenIDs.insert(item.id).inserted {
                uniqueItems.append(item)
            }
        }

        return uniqueItems
    }

    private func todayModeCutoffDate(now: Date = .now) -> Date {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now)
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now) ?? startOfDay.addingTimeInterval(12 * 60 * 60)

        if now < noon {
            return now.addingTimeInterval(-12 * 60 * 60)
        }

        return startOfDay
    }

    private func cleanBase() -> String {
        var normalized = serverURL
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

    private func gReaderURL(pathComponents: [String]) -> URL? {
        let base = cleanBase()
        guard let baseURL = URL(string: base), let host = baseURL.host, !host.isEmpty else {
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

    private func makeFreshSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: config)
    }

    private func isVPNStyleHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host.contains(".vpn.") || host.hasSuffix(".ts.net")
    }

}
