import Foundation
import Testing
@testable import SDC_RSS

/// Builds a service wired to a fake server, an isolated defaults suite, and in-memory secrets.
@MainActor
private struct Fixture {
    static let items = """
    {"items":[
      {"id":"item-1","title":"First","published":1700000300,"canonical":[{"href":"https://news.example/1"}],"origin":{"title":"Example"}},
      {"id":"item-2","title":"Second","published":1700000200,"canonical":[{"href":"https://news.example/2"}],"origin":{"title":"Example"}}
    ]}
    """

    let service: FreshRSSService
    let transport: FakeTransport
    let store: FreshRSSStore
    let passwords: InMemoryPasswordStore
    private let suiteName: String

    init(
        serverURL: String = "https://rss.example.com",
        username: String = "reader",
        password: String? = "secret",
        suiteName: String = "rssreader-tests-\(UUID().uuidString)",
        editTagStatus: @escaping @Sendable () -> Int = { 200 },
        loginStatus: Int = 200
    ) {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(serverURL, forKey: FreshRSSStore.Key.serverURL)
        defaults.set(username, forKey: FreshRSSStore.Key.username)
        self.suiteName = suiteName
        store = FreshRSSStore(defaults: defaults, cloud: nil)
        passwords = InMemoryPasswordStore(password: password)
        transport = FakeTransport { request in
            let path = request.url?.path ?? ""
            switch path {
            case let path where path.hasSuffix("/accounts/ClientLogin"):
                return (loginStatus, Data("Auth=tok\n"))
            case let path where path.hasSuffix("/subscription/list"):
                return (200, Data(#"{"subscriptions":[{"id":"feed/1","title":"b feed"},{"id":"feed/2","title":"A feed"}]}"#))
            case let path where path.contains("/stream/contents/"):
                return (200, Data(Self.items))
            case let path where path.hasSuffix("/api/0/token"):
                return (200, Data("action-token"))
            case let path where path.hasSuffix("/edit-tag"):
                return (editTagStatus(), Data("OK"))
            default:
                return (404, Data())
            }
        }
        service = FreshRSSService(
            store: store,
            transport: transport,
            makeFreshTransport: { [transport] in transport },
            passwordStore: passwords,
            readStateSync: NoOpReadStateSync()
        )
    }

    /// A second service over the same storage, as after relaunching the app.
    func relaunch() -> FreshRSSService {
        FreshRSSService(
            store: store,
            transport: transport,
            passwordStore: passwords,
            readStateSync: NoOpReadStateSync()
        )
    }

    func tearDown() {
        store.defaults.removePersistentDomain(forName: suiteName)
    }
}

@MainActor
struct FreshRSSServiceTests {
    @Test func loadsSavedConnectionDetailsAtLaunch() {
        let fixture = Fixture()
        defer { fixture.tearDown() }

        #expect(fixture.service.serverURL == "https://rss.example.com")
        #expect(fixture.service.username == "reader")
        #expect(fixture.service.password == "secret")
        #expect(fixture.service.isConfigured)
    }

    @Test func authenticatingLoadsSubscriptionsAndUnreadItems() async {
        let fixture = Fixture()
        defer { fixture.tearDown() }

        await fixture.service.authenticate()

        #expect(fixture.service.isAuthenticated)
        #expect(fixture.service.errorMessage == nil)
        #expect(fixture.service.subscriptions.map(\.title) == ["A feed", "b feed"])
        #expect(fixture.service.items.map(\.id) == ["item-1", "item-2"])
        #expect(fixture.service.unreadCount == 2)
        #expect(fixture.service.lastSyncDate != nil)
    }

    @Test func rejectedCredentialsShowAnAuthenticationError() async {
        let fixture = Fixture(loginStatus: 403)
        defer { fixture.tearDown() }

        await fixture.service.authenticate()

        #expect(!fixture.service.isAuthenticated)
        #expect(fixture.service.errorMessage == FreshRSSError.authenticationFailed.errorDescription)
        #expect(fixture.service.items.isEmpty)
    }

    @Test func cleartextInternetServersExplainWhyTheyFail() async {
        let fixture = Fixture(serverURL: "http://rss.example.com")
        defer { fixture.tearDown() }

        await fixture.service.authenticate()

        #expect(!fixture.service.isAuthenticated)
        #expect(fixture.service.errorMessage?.contains("https://") == true)
        #expect(fixture.transport.requests.isEmpty)
    }

    @Test func unconfiguredServiceAsksForSettings() async {
        let fixture = Fixture(serverURL: "", password: nil)
        defer { fixture.tearDown() }

        await fixture.service.authenticate()

        #expect(fixture.service.errorMessage == FreshRSSError.notConfigured.errorDescription)
    }

    // MARK: Read state

    @Test func markingReadSyncsToTheServer() async throws {
        let fixture = Fixture()
        defer { fixture.tearDown() }
        await fixture.service.authenticate()
        let item = try #require(fixture.service.items.first)

        await fixture.service.markAsRead(item)

        #expect(fixture.service.isMarkedRead(item))
        #expect(fixture.service.pendingReadChanges.isEmpty)
        let editBody = fixture.transport.requests
            .first { $0.url?.path.hasSuffix("/edit-tag") == true }
            .flatMap { $0.httpBody.flatMap { String(data: $0, encoding: .utf8) } }
        #expect(editBody == "i=item-1&a=user%2F-%2Fstate%2Fcom.google%2Fread&T=action-token")
    }

    @Test func failedReadUpdatesStayQueuedAcrossRelaunch() async throws {
        let fixture = Fixture(editTagStatus: { 500 })
        defer { fixture.tearDown() }
        await fixture.service.authenticate()
        let item = try #require(fixture.service.items.first)

        await fixture.service.markAsRead(item)

        #expect(fixture.service.pendingReadChanges == [item.id: true])
        #expect(fixture.service.isMarkedRead(item), "Optimistic state should survive a failed upload")
        #expect(fixture.service.errorMessage?.contains("waiting to sync") == true)

        let relaunched = fixture.relaunch()
        #expect(relaunched.pendingReadChanges == [item.id: true])
    }

    @Test func switchingAccountsClearsQueuedChanges() async throws {
        let fixture = Fixture(editTagStatus: { 500 })
        defer { fixture.tearDown() }
        await fixture.service.authenticate()
        await fixture.service.markAsRead(try #require(fixture.service.items.first))
        #expect(!fixture.service.pendingReadChanges.isEmpty)

        fixture.service.username = "someone-else"

        #expect(fixture.service.pendingReadChanges.isEmpty)
        #expect(fixture.service.lastSyncDate == nil)
    }

    // MARK: Skipped items

    @Test func skippedItemsPersistAndQueueForCloudSync() async throws {
        let fixture = Fixture()
        defer { fixture.tearDown() }
        await fixture.service.authenticate()
        let item = try #require(fixture.service.items.first)

        fixture.service.markSkipped(item)

        #expect(fixture.service.isSkipped(item))
        #expect(!fixture.store.pendingSkippedChanges.isEmpty, "Changes stay queued while CloudKit is unavailable")
        #expect(fixture.relaunch().isSkipped(item))
    }

    // MARK: Auto refresh

    @Test func autoRefreshWaitsForTheConfiguredInterval() async {
        let fixture = Fixture()
        defer { fixture.tearDown() }
        #expect(fixture.service.shouldAutoSync(), "Never synced yet")

        await fixture.service.authenticate()
        let syncedAt = try? #require(fixture.service.lastSyncDate)

        #expect(fixture.service.shouldAutoSync(now: Date()) == false)
        #expect(fixture.service.shouldAutoSync(now: (syncedAt ?? .now).addingTimeInterval(16 * 60)))
    }

    // MARK: Keychain

    @Test func keychainWriteFailuresAreShownToTheUser() {
        let fixture = Fixture()
        defer { fixture.tearDown() }
        fixture.passwords.saveError = KeychainHelper.KeychainError.saveFailed(-34018)

        fixture.service.password = "new-secret"

        #expect(fixture.service.errorMessage?.contains("Keychain") == true)
    }

    @Test func keychainReadFailuresAreShownToTheUser() {
        let passwords = InMemoryPasswordStore(password: "secret")
        passwords.loadError = KeychainHelper.KeychainError.retrieveFailed(-25308)
        let service = FreshRSSService(
            store: FreshRSSStore(defaults: UserDefaults(suiteName: "rssreader-tests-\(UUID().uuidString)")!, cloud: nil),
            passwordStore: passwords,
            readStateSync: NoOpReadStateSync()
        )

        #expect(service.errorMessage?.contains("Keychain") == true)
        #expect(service.password.isEmpty)
    }

    @Test func successfulPasswordChangesAreStored() {
        let fixture = Fixture()
        defer { fixture.tearDown() }

        fixture.service.password = "rotated"

        #expect(fixture.passwords.password == "rotated")
        #expect(fixture.service.errorMessage == nil)
    }
}
