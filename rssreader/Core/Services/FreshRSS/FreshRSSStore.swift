import Foundation

// MARK: - Dependencies

/// Where the FreshRSS password lives. The default is the Keychain; tests use an in-memory fake.
protocol PasswordStoring {
    func loadPassword(allowUserInteraction: Bool) throws -> String?
    func savePassword(_ password: String) throws
}

struct KeychainPasswordStore: PasswordStoring {
    func loadPassword(allowUserInteraction: Bool) throws -> String? {
        try KeychainHelper.retrieve(key: FreshRSSStore.Key.password, allowUserInteraction: allowUserInteraction)
    }

    func savePassword(_ password: String) throws {
        try KeychainHelper.save(key: FreshRSSStore.Key.password, value: password)
    }
}

/// Cross-device sync of read and skipped state.
@MainActor
protocol ReadStateSyncing: AnyObject {
    func fetchSyncedReadIDs() async -> Set<String>
    func pushReadIDs(_ ids: Set<String>) async
    func clearSyncedReadIDs() async
    func synchronizeSkippedItems(
        account: String,
        localIDs: Set<String>,
        changes: [String: Bool],
        isInitialSync: Bool
    ) async -> Set<String>?
}

extension CloudKitSyncService: ReadStateSyncing {}

/// A password store that keeps the value in memory, for previews and tests. Set `loadError` or
/// `saveError` to simulate Keychain failures.
final class InMemoryPasswordStore: PasswordStoring {
    var password: String?
    var loadError: Error?
    var saveError: Error?

    init(password: String? = nil) {
        self.password = password
    }

    func loadPassword(allowUserInteraction: Bool) throws -> String? {
        if let loadError { throw loadError }
        return password
    }

    func savePassword(_ password: String) throws {
        if let saveError { throw saveError }
        self.password = password
    }
}

/// Behaves like an unavailable iCloud account: nothing syncs and local state stays queued.
@MainActor
final class NoOpReadStateSync: ReadStateSyncing {
    func fetchSyncedReadIDs() async -> Set<String> { [] }
    func pushReadIDs(_ ids: Set<String>) async {}
    func clearSyncedReadIDs() async {}
    func synchronizeSkippedItems(account: String, localIDs: Set<String>, changes: [String: Bool], isInitialSync: Bool) async -> Set<String>? { nil }
}

// MARK: - Store

/// Typed access to the UserDefaults and iCloud key-value storage backing FreshRSS state.
struct FreshRSSStore {
    enum Key {
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
        static let skippedItems = "rssreader_skipped_items"
        static let pendingSkippedItemChanges = "rssreader_pending_skipped_item_changes"
        static let cloudSyncedSkippedAccounts = "rssreader_cloud_synced_skipped_accounts"
        static let lastSyncDate = "rssreader_last_sync_date"
        static let lastSyncAccount = "rssreader_last_sync_account"
        static let pendingReadChanges = "rssreader_pending_read_changes"
        static let pendingReadChangesAccount = "rssreader_pending_read_changes_account"
    }

    let defaults: UserDefaults
    /// iCloud key-value storage used for connection details. `nil` disables cross-device sync.
    let cloud: NSUbiquitousKeyValueStore?

    static var standard: FreshRSSStore {
        FreshRSSStore(defaults: .standard, cloud: .default)
    }

    /// Throwaway storage that never touches the user's defaults or iCloud.
    static func ephemeral() -> FreshRSSStore {
        FreshRSSStore(defaults: UserDefaults(suiteName: "rssreader-ephemeral-\(UUID().uuidString)") ?? .standard, cloud: nil)
    }

    // MARK: Connection settings (synced through iCloud)

    /// Prefers the iCloud value, mirroring it into local defaults.
    func syncedString(forKey key: String) -> String {
        if let cloudValue = cloud?.string(forKey: key), !Self.isBlank(cloudValue) {
            defaults.set(cloudValue, forKey: key)
            return cloudValue
        }
        return defaults.string(forKey: key) ?? ""
    }

    func cloudString(forKey key: String) -> String? {
        guard let value = cloud?.string(forKey: key), !Self.isBlank(value) else { return nil }
        return value
    }

    func saveString(_ value: String, forKey key: String, syncToCloud: Bool = true) {
        defaults.set(value, forKey: key)
        guard syncToCloud, let cloud else { return }
        if Self.isBlank(value) {
            cloud.removeObject(forKey: key)
        } else {
            cloud.set(value, forKey: key)
        }
        cloud.synchronize()
    }

    private static func isBlank(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Skipped items

    var skippedAccounts: [String: [String]] {
        get { defaults.dictionary(forKey: Key.skippedItems) as? [String: [String]] ?? [:] }
        nonmutating set { defaults.set(newValue, forKey: Key.skippedItems) }
    }

    var pendingSkippedChanges: [String: [String: Bool]] {
        get { defaults.dictionary(forKey: Key.pendingSkippedItemChanges) as? [String: [String: Bool]] ?? [:] }
        nonmutating set { defaults.set(newValue, forKey: Key.pendingSkippedItemChanges) }
    }

    var cloudSyncedSkippedAccounts: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.cloudSyncedSkippedAccounts) ?? []) }
        nonmutating set { defaults.set(Array(newValue), forKey: Key.cloudSyncedSkippedAccounts) }
    }

    // MARK: Per-account sync state

    func loadPendingReadChanges(account: String) -> [String: Bool] {
        guard defaults.string(forKey: Key.pendingReadChangesAccount) == account else { return [:] }
        return defaults.dictionary(forKey: Key.pendingReadChanges) as? [String: Bool] ?? [:]
    }

    func savePendingReadChanges(_ changes: [String: Bool], account: String) {
        defaults.set(changes, forKey: Key.pendingReadChanges)
        defaults.set(account, forKey: Key.pendingReadChangesAccount)
    }

    func loadLastSyncDate(account: String) -> Date? {
        guard defaults.string(forKey: Key.lastSyncAccount) == account else { return nil }
        return defaults.object(forKey: Key.lastSyncDate) as? Date
    }

    func saveLastSyncDate(_ date: Date?, account: String) {
        if let date {
            defaults.set(date, forKey: Key.lastSyncDate)
            defaults.set(account, forKey: Key.lastSyncAccount)
        } else {
            defaults.removeObject(forKey: Key.lastSyncDate)
            defaults.removeObject(forKey: Key.lastSyncAccount)
        }
    }
}
