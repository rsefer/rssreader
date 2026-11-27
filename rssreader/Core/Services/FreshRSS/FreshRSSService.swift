import Foundation
import SwiftUI
import Combine
import os

// MARK: - Service

/// Observable state and orchestration for a FreshRSS account. Networking lives in
/// `FreshRSSAPIClient`, persistence in `FreshRSSStore`, and feed parsing in `FeedItemMapper`.
@MainActor
final class FreshRSSService: ObservableObject {
    let karakeep = KarakeepService()

    private typealias StorageKeys = FreshRSSStore.Key

    // MARK: Published state

    @Published var items: [FeedItem] = []
    @Published var subscriptions: [FeedSubscription] = []
    @Published var isLoading = false
    @Published private(set) var isUpdatingReadStatus = false
    @Published var isAuthenticated = false
    @Published var errorMessage: String?
    @Published private(set) var syncErrorMessage: String?
    @Published private(set) var locallyReadItemIDs: Set<String> = []
    @Published private(set) var pendingReadChanges: [String: Bool] = [:] {
        didSet { store.savePendingReadChanges(pendingReadChanges, account: accountStorageIdentifier) }
    }
    @Published private var skippedItems = SkippedItems() {
        didSet { store.skippedAccounts = skippedItems.accounts }
    }
    private var pendingSkippedItemChanges: [String: [String: Bool]] = [:] {
        didSet { store.pendingSkippedChanges = pendingSkippedItemChanges }
    }
    private var cloudSyncedSkippedAccounts: Set<String> = [] {
        didSet { store.cloudSyncedSkippedAccounts = cloudSyncedSkippedAccounts }
    }
    private var skippedItemsSyncTask: Task<Void, Never>?
    @Published var sidebarMode: SidebarMode = .new
    @Published var selectedSubscriptionID: String? = nil
    @Published private(set) var lastResolvedHost: String = ""
    @Published private(set) var lastURLErrorCode: Int?
    @Published private(set) var lastSyncDate: Date? {
        didSet { store.saveLastSyncDate(lastSyncDate, account: accountStorageIdentifier) }
    }

    // MARK: Persisted settings

    @Published var serverURL: String {
        didSet {
            if oldValue != serverURL {
                resetAccountState()
            }
            persistSetting(serverURL, forKey: StorageKeys.serverURL)
        }
    }
    @Published var username: String {
        didSet {
            if oldValue != username {
                resetAccountState()
            }
            persistSetting(username, forKey: StorageKeys.username)
        }
    }
    @Published var password: String {
        didSet {
            if !isLoadingStoredPassword {
                savePasswordToStore()
            }
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
    // MARK: Private state

    private let store: FreshRSSStore
    private let transport: any HTTPTransport
    private let makeFreshTransport: @Sendable () -> any HTTPTransport
    private let passwordStore: any PasswordStoring
    private let cloudKitSync: any ReadStateSyncing
    private let mapper = FeedItemMapper()

    private var authToken: String?
    private var actionToken: String?
    private var hasStoredPassword = false
    private var isLoadingStoredPassword = false
    private var ubiquitousStoreObserver: NSObjectProtocol?
    private var isApplyingCloudSync = false
    private var techmemeMetadataCache: [String: TechmemeMetadata] = [:]
    private var techmemeEnrichmentTask: Task<Void, Never>?
    private var accountStorageIdentifier: String {
        SkippedItems.accountKey(serverURL: serverURL, username: username)
    }

    private var client: FreshRSSAPIClient {
        FreshRSSAPIClient(serverURL: serverURL, transport: transport, makeFreshTransport: makeFreshTransport)
    }

    // MARK: Init

    init(
        store: FreshRSSStore? = nil,
        transport: any HTTPTransport = FreshRSSNetwork.makeSession(),
        makeFreshTransport: @escaping @Sendable () -> any HTTPTransport = { FreshRSSNetwork.makeFreshSession() },
        passwordStore: (any PasswordStoring)? = nil,
        readStateSync: (any ReadStateSyncing)? = nil
    ) {
        let store = store ?? .standard
        self.store = store
        self.transport = transport
        self.makeFreshTransport = makeFreshTransport
        self.passwordStore = passwordStore ?? KeychainPasswordStore()
        self.cloudKitSync = readStateSync ?? CloudKitSyncService()

        let defaults = store.defaults
        skippedItems = SkippedItems(accounts: store.skippedAccounts)
        pendingSkippedItemChanges = store.pendingSkippedChanges
        cloudSyncedSkippedAccounts = store.cloudSyncedSkippedAccounts
        serverURL = store.syncedString(forKey: StorageKeys.serverURL)
        username = store.syncedString(forKey: StorageKeys.username)
        password = ""
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

        let accountIdentifier = SkippedItems.accountKey(serverURL: serverURL, username: username)
        lastSyncDate = store.loadLastSyncDate(account: accountIdentifier)
        pendingReadChanges = store.loadPendingReadChanges(account: accountIdentifier)

        // On macOS, non-interactive keychain reads can fail depending on the item's access
        // control; allow normal retrieval so saved passwords load reliably after relaunch.
        loadStoredPassword(allowUserInteraction: true, reportErrors: true)

        // Merge any pending read IDs that were synced from another device via CloudKit.
        Task {
            let syncedReadIDs = await cloudKitSync.fetchSyncedReadIDs()
            if !syncedReadIDs.isEmpty {
                locallyReadItemIDs.formUnion(syncedReadIDs)
            }
            await synchronizeSkippedItems(for: skippedAccount)
        }

        if let cloud = store.cloud {
            ubiquitousStoreObserver = NotificationCenter.default.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: cloud,
                queue: .main
            ) { [weak self] notification in
                let changedKeys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []

                Task { @MainActor [weak self, changedKeys] in
                    self?.applyCloudSyncedConnectionInfo(changedKeys: changedKeys)
                }
            }
            cloud.synchronize()
        }
    }

    deinit {
        if let ubiquitousStoreObserver {
            NotificationCenter.default.removeObserver(ubiquitousStoreObserver)
        }
    }

    private func resetAccountState() {
        lastSyncDate = nil
        pendingReadChanges = [:]
        locallyReadItemIDs.removeAll()
        errorMessage = nil
        syncErrorMessage = nil
    }

    // MARK: Password storage

    private func savePasswordToStore() {
        do {
            try passwordStore.savePassword(password)
        } catch {
            Log.storage.error("Could not save the password: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Your password could not be saved to the Keychain, so you may need to enter it again after relaunching. \(FreshRSSError.keychain(error.localizedDescription).localizedDescription)"
        }
    }

    private func loadStoredPassword(allowUserInteraction: Bool, reportErrors: Bool) {
        do {
            let stored = try passwordStore.loadPassword(allowUserInteraction: allowUserInteraction) ?? ""
            isLoadingStoredPassword = true
            password = stored
            isLoadingStoredPassword = false
        } catch {
            Log.storage.error("Could not read the saved password: \(error.localizedDescription, privacy: .public)")
            if reportErrors {
                errorMessage = "Your saved password could not be read from the Keychain. \(FreshRSSError.keychain(error.localizedDescription).localizedDescription)"
            }
        }
        hasStoredPassword = !password.isEmpty
    }

    var isConfigured: Bool {
        !serverURL.isEmpty && !username.isEmpty && (!password.isEmpty || hasStoredPassword)
    }

    var unreadCount: Int {
        items.filter { !isMarkedRead($0) }.count
    }

    var normalizedServerURL: String {
        FreshRSSServerURL.normalize(serverURL)
    }

    func isMarkedRead(_ item: FeedItem) -> Bool {
        if let pendingReadStatus = pendingReadChanges[item.id] {
            return pendingReadStatus
        }
        return item.isRead || locallyReadItemIDs.contains(item.id)
    }

    private var skippedAccount: String {
        SkippedItems.accountKey(serverURL: normalizedServerURL, username: username)
    }

    func isSkipped(_ item: FeedItem) -> Bool {
        !isMarkedRead(item) && skippedItems.contains(item.id, account: skippedAccount)
    }

    func markSkipped(_ item: FeedItem) {
        guard !isMarkedRead(item), !isSkipped(item) else { return }
        let account = skippedAccount
        skippedItems.insert(item.id, account: account)
        queueSkippedItemChanges([item.id], isSkipped: true, account: account)
    }

    private func clearSkipped(_ ids: [String], account: String) {
        let skippedIDs = ids.filter { skippedItems.contains($0, account: account) }
        guard !skippedIDs.isEmpty else { return }
        skippedItems.remove(skippedIDs, account: account)
        queueSkippedItemChanges(skippedIDs, isSkipped: false, account: account)
    }

    private func queueSkippedItemChanges(_ ids: [String], isSkipped: Bool, account: String) {
        var changes = pendingSkippedItemChanges[account] ?? [:]
        for id in ids {
            changes[id] = isSkipped
        }
        pendingSkippedItemChanges[account] = changes
        scheduleSkippedItemsSync(for: account)
    }

    private func scheduleSkippedItemsSync(for account: String) {
        guard skippedItemsSyncTask == nil else { return }
        skippedItemsSyncTask = Task { @MainActor [weak self] in
            await self?.synchronizeSkippedItems(for: account)
        }
    }

    private func synchronizeSkippedItems(for account: String) async {
        defer { skippedItemsSyncTask = nil }

        while true {
            let changes = pendingSkippedItemChanges[account] ?? [:]
            let isInitialSync = !cloudSyncedSkippedAccounts.contains(account)
            guard let syncedIDs = await cloudKitSync.synchronizeSkippedItems(
                account: account,
                localIDs: Set(skippedItems.accounts[account] ?? []),
                changes: changes,
                isInitialSync: isInitialSync
            ) else {
                return
            }

            cloudSyncedSkippedAccounts.insert(account)
            skippedItems.replace(syncedIDs, account: account)

            var remainingChanges = pendingSkippedItemChanges[account] ?? [:]
            for (id, value) in changes where remainingChanges[id] == value {
                remainingChanges.removeValue(forKey: id)
            }
            if remainingChanges.isEmpty {
                pendingSkippedItemChanges.removeValue(forKey: account)
                return
            }
            pendingSkippedItemChanges[account] = remainingChanges
        }
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
        store.saveString(value, forKey: key, syncToCloud: !isApplyingCloudSync)
    }

    private func persistSetting(_ value: Bool, forKey key: String) {
        store.defaults.set(value, forKey: key)
    }

    private func persistSetting(_ value: Int, forKey key: String) {
        store.defaults.set(value, forKey: key)
    }

    private func applyCloudSyncedConnectionInfo(changedKeys: [String]) {
        guard changedKeys.contains(StorageKeys.serverURL) || changedKeys.contains(StorageKeys.username) else {
            return
        }

        var shouldRefreshPasswordState = false

        if let cloudServerURL = store.cloudString(forKey: StorageKeys.serverURL), cloudServerURL != serverURL {
            shouldRefreshPasswordState = true
            isApplyingCloudSync = true
            serverURL = cloudServerURL
            isApplyingCloudSync = false
        }

        if let cloudUsername = store.cloudString(forKey: StorageKeys.username), cloudUsername != username {
            shouldRefreshPasswordState = true
            isApplyingCloudSync = true
            username = cloudUsername
            isApplyingCloudSync = false
        }

        if shouldRefreshPasswordState {
            hasStoredPassword = !password.isEmpty
        }
    }

    // MARK: - Authentication

    func authenticateSilently() async {
        await authenticate(syncAfterLogin: true, allowUserInteraction: false, reportErrors: false)
    }

    func authenticate() async {
        await authenticate(syncAfterLogin: true, allowUserInteraction: true, reportErrors: true)
    }

    func runDNSPreflight() async -> (success: Bool, message: String) {
        guard let loginURL = client.gReaderURL(["accounts", "ClientLogin"]) else {
            return (false, "Invalid server URL")
        }

        lastResolvedHost = loginURL.host ?? ""
        lastURLErrorCode = nil

        let result = await client.probeHost()
        lastURLErrorCode = result.urlErrorCode
        return (result.success, result.message)
    }

    private func authenticate(syncAfterLogin: Bool, allowUserInteraction: Bool, reportErrors: Bool) async {
        if password.isEmpty {
            loadStoredPassword(allowUserInteraction: allowUserInteraction, reportErrors: reportErrors)
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

        guard let loginURL = client.gReaderURL(["accounts", "ClientLogin"]) else {
            if reportErrors {
                errorMessage = FreshRSSError.invalidServerURL.errorDescription
            }
            return
        }
        lastResolvedHost = loginURL.host ?? lastResolvedHost

        do {
            authToken = try await client.login(username: username, password: password)
            isAuthenticated = true
            lastURLErrorCode = nil
            await fetchSubscriptions()
            if syncAfterLogin {
                await syncCurrentMode()
            }
        } catch {
            authToken = nil
            isAuthenticated = false
            lastURLErrorCode = (error as? URLError)?.errorCode
            Log.network.error("Login failed: \(error.localizedDescription, privacy: .public)")
            if reportErrors {
                errorMessage = Self.loginErrorMessage(for: error, host: loginURL.host)
            }
        }
    }

    static func loginErrorMessage(for error: Error, host: String?) -> String {
        let host = host ?? "(unknown host)"
        switch (error as? URLError)?.code {
        case .cannotFindHost:
            if host.contains(".vpn.") {
                return "Network error: Could not resolve host '\(host)'. VPN DNS is likely unavailable. Confirm your VPN is connected and DNS is routed through it, then retry."
            }
            return "Network error: Could not resolve host '\(host)'. Verify the server URL host and DNS reachability."
        case .dnsLookupFailed:
            return "Network error: DNS lookup failed for '\(host)'. Check VPN/DNS settings and retry."
        default:
            if let freshRSSError = error as? FreshRSSError {
                return freshRSSError.errorDescription ?? freshRSSError.localizedDescription
            }
            return FreshRSSError.networkError(error.localizedDescription).errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Fetch items

    func syncCurrentMode() async {
        scheduleSkippedItemsSync(for: skippedAccount)
        await fetchItems(for: sidebarMode)
    }

    func fetchSubscriptions() async {
        guard let token = authToken else { return }
        do {
            subscriptions = try await client.fetchSubscriptions(authToken: token)
        } catch {
            // The filter menu keeps the previous list; reading is unaffected.
            Log.network.error("Could not load subscriptions: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func fetchItems(for mode: SidebarMode) async {
        let archiveLimit = 1_000
        let account = skippedAccount
        techmemeEnrichmentTask?.cancel()

        guard let token = await ensureAuthenticationToken() else {
            syncErrorMessage = errorMessage ?? "Could not connect to FreshRSS."
            return
        }

        isLoading = true
        errorMessage = nil
        syncErrorMessage = nil

        do {
            var fetchedItems: [FeedItem] = []
            var continuation: String?

            repeat {
                let response = try await client.fetchStreamPage(
                    authToken: token,
                    mode: mode,
                    continuation: continuation,
                    todayCutoff: mapper.todayModeCutoffDate()
                )
                fetchedItems.append(contentsOf: response.items.compactMap(mapper.makeFeedItem(from:)))
                continuation = response.continuation

                if mode == .archive, fetchedItems.count >= archiveLimit {
                    continuation = nil
                }
            } while continuation != nil

            if mode == .today {
                let cutoff = mapper.todayModeCutoffDate()
                fetchedItems = fetchedItems.filter { $0.publishedDate >= cutoff }
            }

            let deduplicatedItems = mapper.deduplicated(items: fetchedItems)
            clearSkipped(deduplicatedItems.filter(\.isRead).map(\.id), account: account)
            if mode == .archive {
                items = Array(deduplicatedItems.prefix(archiveLimit))
            } else {
                items = deduplicatedItems
            }

            scheduleTechmemeEnrichment(for: items)
            lastSyncDate = Date()
            locallyReadItemIDs.removeAll()
            Task { await cloudKitSync.clearSyncedReadIDs() }

        } catch {
            Log.sync.error("Feed sync failed: \(error.localizedDescription, privacy: .public)")
            let message = "Failed to load items: \(error.localizedDescription)"
            errorMessage = message
            syncErrorMessage = message
        }

        isLoading = false
    }

    // MARK: - Mark as read

    func markAsRead(_ item: FeedItem) async {
        await markAsRead([item])
    }

    func markAsRead(_ selectedItems: [FeedItem]) async {
        guard !isUpdatingReadStatus else { return }
        let unreadItems = selectedItems.filter { !isMarkedRead($0) }
        guard !unreadItems.isEmpty else { return }
        isUpdatingReadStatus = true
        defer { isUpdatingReadStatus = false }

        let itemIDs = unreadItems.map(\.id)
        let account = skippedAccount
        pendingReadChanges = pendingReadChanges.merging(
            Dictionary(uniqueKeysWithValues: itemIDs.map { ($0, true) }),
            uniquingKeysWith: { _, new in new }
        )
        locallyReadItemIDs.formUnion(itemIDs)

        guard await ensureAuthenticationToken() != nil else {
            errorMessage = "Read updates are waiting for a FreshRSS connection."
            return
        }

        let succeededIDs = await performReadActions(itemIDs, isRead: true)
        for itemID in succeededIDs {
            pendingReadChanges.removeValue(forKey: itemID)
            clearSkipped([itemID], account: account)
        }

        let failedIDs = Set(itemIDs).subtracting(succeededIDs)
        locallyReadItemIDs.subtract(failedIDs)

        if !failedIDs.isEmpty {
            errorMessage = "\(failedIDs.count) read update(s) are waiting to sync. Retry from the sync status."
        }

        // Push successfully read IDs to CloudKit so other devices see them immediately.
        let syncedIDs = locallyReadItemIDs.intersection(succeededIDs)
        if !syncedIDs.isEmpty {
            Task { await cloudKitSync.pushReadIDs(syncedIDs) }
        }
    }

    func markAsUnread(_ item: FeedItem) async {
        await markAsUnread([item])
    }

    func markAsUnread(_ selectedItems: [FeedItem]) async {
        guard !isUpdatingReadStatus else { return }
        let readItems = selectedItems.filter { isMarkedRead($0) }
        guard !readItems.isEmpty else { return }
        isUpdatingReadStatus = true
        defer { isUpdatingReadStatus = false }

        let itemIDs = readItems.map(\.id)
        pendingReadChanges = pendingReadChanges.merging(
            Dictionary(uniqueKeysWithValues: itemIDs.map { ($0, false) }),
            uniquingKeysWith: { _, new in new }
        )
        locallyReadItemIDs.subtract(itemIDs)

        guard await ensureAuthenticationToken() != nil else {
            errorMessage = "Unread updates are waiting for a FreshRSS connection."
            return
        }

        let succeededIDs = await performReadActions(itemIDs, isRead: false)
        for itemID in succeededIDs {
            pendingReadChanges.removeValue(forKey: itemID)
        }

        if !succeededIDs.isEmpty && readItems.contains(where: { $0.isRead }) {
            await syncCurrentMode()
        }

        let failedCount = itemIDs.count - succeededIDs.count
        if failedCount > 0 {
            errorMessage = "\(failedCount) unread update(s) are waiting to sync. Retry from the sync status."
        }
    }

    func markAllAsRead() async {
        guard !isUpdatingReadStatus else { return }
        let unreadItems = items.filter { !isMarkedRead($0) }
        guard !unreadItems.isEmpty else {
            await syncCurrentMode()
            return
        }
        isUpdatingReadStatus = true
        defer { isUpdatingReadStatus = false }

        let itemIDs = unreadItems.map(\.id)
        let account = skippedAccount
        pendingReadChanges = pendingReadChanges.merging(
            Dictionary(uniqueKeysWithValues: itemIDs.map { ($0, true) }),
            uniquingKeysWith: { _, new in new }
        )
        locallyReadItemIDs.formUnion(itemIDs)

        guard await ensureAuthenticationToken() != nil else {
                errorMessage = "Read updates are waiting for a FreshRSS connection."
                return
        }

        let succeededIDs = await performReadActions(itemIDs, isRead: true)
        for itemID in succeededIDs {
            pendingReadChanges.removeValue(forKey: itemID)
            clearSkipped([itemID], account: account)
        }

        locallyReadItemIDs.subtract(Set(itemIDs).subtracting(succeededIDs))

        let syncedIDs = locallyReadItemIDs.intersection(succeededIDs)
        if !syncedIDs.isEmpty {
            await cloudKitSync.pushReadIDs(syncedIDs)
        }

        await syncCurrentMode()

        if succeededIDs.count < itemIDs.count {
            errorMessage = "\(itemIDs.count - succeededIDs.count) read update(s) are waiting to sync. Retry from the sync status."
        }
    }

    func markAllAsUnread() async {
        guard !isUpdatingReadStatus else { return }
        let readItems = items.filter { isMarkedRead($0) }
        guard !readItems.isEmpty else {
            await syncCurrentMode()
            return
        }
        isUpdatingReadStatus = true
        defer { isUpdatingReadStatus = false }

        let itemIDs = readItems.map(\.id)
        pendingReadChanges = pendingReadChanges.merging(
            Dictionary(uniqueKeysWithValues: itemIDs.map { ($0, false) }),
            uniquingKeysWith: { _, new in new }
        )
        locallyReadItemIDs.subtract(itemIDs)

        guard await ensureAuthenticationToken() != nil else {
            errorMessage = "Unread updates are waiting for a FreshRSS connection."
            return
        }

        let succeededIDs = await performReadActions(itemIDs, isRead: false)
        for itemID in succeededIDs {
            pendingReadChanges.removeValue(forKey: itemID)
        }

        await syncCurrentMode()

        if succeededIDs.count < itemIDs.count {
            errorMessage = "\(itemIDs.count - succeededIDs.count) unread update(s) are waiting to sync. Retry from the sync status."
        }
    }

    func retryPendingReadChanges() async {
        guard !isUpdatingReadStatus else { return }
        guard !pendingReadChanges.isEmpty else { return }
        isUpdatingReadStatus = true
        defer { isUpdatingReadStatus = false }
        guard await ensureAuthenticationToken() != nil else {
            errorMessage = "Read updates are waiting for a FreshRSS connection."
            return
        }

        var didSucceed = false
        for isRead in [true, false] {
            let itemIDs = pendingReadChanges.filter { $0.value == isRead }.map(\.key)
            guard !itemIDs.isEmpty else { continue }

            let succeededIDs = await performReadActions(itemIDs, isRead: isRead)
            didSucceed = didSucceed || !succeededIDs.isEmpty
            for itemID in succeededIDs {
                pendingReadChanges.removeValue(forKey: itemID)
                if isRead {
                    locallyReadItemIDs.insert(itemID)
                    clearSkipped([itemID], account: skippedAccount)
                } else {
                    locallyReadItemIDs.remove(itemID)
                }
            }

            if isRead && !succeededIDs.isEmpty {
                await cloudKitSync.pushReadIDs(succeededIDs)
            }
        }

        if didSucceed {
            await syncCurrentMode()
        }
        if !pendingReadChanges.isEmpty {
            errorMessage = "\(pendingReadChanges.count) read update(s) are still waiting to sync."
        }
    }

    private func performReadActions(_ itemIDs: [String], isRead: Bool) async -> Set<String> {
        guard !itemIDs.isEmpty else { return [] }
        if actionToken == nil {
            actionToken = await fetchActionToken()
        }

        let initiallySucceeded = await sendReadActions(itemIDs, isRead: isRead)
        let failedIDs = itemIDs.filter { !initiallySucceeded.contains($0) }
        guard !failedIDs.isEmpty else { return initiallySucceeded }

        try? await Task.sleep(for: .milliseconds(500))
        actionToken = await fetchActionToken()
        let retriedSucceeded = await sendReadActions(failedIDs, isRead: isRead)
        return initiallySucceeded.union(retriedSucceeded)
    }

    private func sendReadActions(_ itemIDs: [String], isRead: Bool) async -> Set<String> {
        guard let authToken, let actionToken else { return [] }

        let outcomes = await client.setReadState(
            itemIDs: itemIDs,
            isRead: isRead,
            authToken: authToken,
            actionToken: actionToken
        )
        if outcomes.values.contains(.actionTokenRejected) {
            self.actionToken = nil
        }
        return Set(outcomes.filter { $0.value == .succeeded }.keys)
    }

    private func fetchActionToken() async -> String? {
        guard let authToken else { return nil }
        do {
            return try await client.fetchActionToken(authToken: authToken)
        } catch {
            Log.network.error("Could not fetch an action token: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func ensureAuthenticationToken() async -> String? {
        if let authToken {
            return authToken
        }

        await authenticate(syncAfterLogin: false, allowUserInteraction: true, reportErrors: true)
        return authToken
    }

    // MARK: - Techmeme enrichment

    private func scheduleTechmemeEnrichment(for sourceItems: [FeedItem]) {
        techmemeEnrichmentTask?.cancel()

        let targetIDs: [String] = sourceItems.compactMap { item in
            guard item.techmemeURL != nil else {
                return nil
            }

            return mapper.needsTechmemeEnrichment(item) ? item.id : nil
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
        let targets = items.filter { targetIDs.contains($0.id) && $0.techmemeURL != nil && mapper.needsTechmemeEnrichment($0) }
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
            let updated = mapper.applyingTechmemeMetadata(metadata, to: item)
            if mapper.hasDisplayChanges(original: item, updated: updated) {
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

    private func resolveTechmemeMetadata(for url: URL?) async -> TechmemeMetadata {
        guard let url, mapper.isTechmemeURL(url) else {
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
            let (data, response) = try await transport.send(request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return .empty
            }

            guard let html = String(data: data, encoding: .utf8), !html.isEmpty else {
                return .empty
            }

            let parsed = mapper.parseTechmemeMetadata(from: html, pageURL: url)
            techmemeMetadataCache[cacheKey] = parsed
            return parsed
        } catch {
            Log.network.debug("Techmeme metadata unavailable: \(error.localizedDescription, privacy: .public)")
            return .empty
        }
    }
}
