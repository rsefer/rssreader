import Foundation
import Testing
@testable import SDC_RSS

struct SkippedItemsTests {
    private let account = SkippedItems.accountKey(serverURL: "https://example.com", username: "reader")
    private let otherAccount = SkippedItems.accountKey(serverURL: "https://example.com", username: "other")

    @Test func tracksItemsPerAccount() {
        var skipped = SkippedItems()
        skipped.insert("first", account: account)
        skipped.insert("first", account: account)
        skipped.insert("second", account: account)
        skipped.insert("first", account: otherAccount)

        skipped.remove(["first"], account: account)
        #expect(!skipped.contains("first", account: account))
        #expect(skipped.contains("second", account: account))
        #expect(skipped.contains("first", account: otherAccount))

        skipped.remove(["second"], account: account)
        #expect(skipped.accounts[account] == nil, "Empty accounts are pruned")
    }

    @Test func replacingSwapsTheWholeSet() {
        var skipped = SkippedItems()
        skipped.insert("old", account: account)
        skipped.insert("keep", account: otherAccount)

        skipped.replace(["replacement"], account: account)
        #expect(skipped.accounts[account] == ["replacement"])

        skipped.replace([], account: account)
        #expect(skipped.accounts[account] == nil)
        #expect(skipped.contains("keep", account: otherAccount))
    }

    @Test func survivesAPropertyListRoundTrip() throws {
        var skipped = SkippedItems()
        skipped.insert("first", account: account)
        skipped.insert("second", account: otherAccount)

        let suiteName = "rssreader-skipped-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(skipped.accounts, forKey: "skipped")

        let saved = try #require(defaults.dictionary(forKey: "skipped") as? [String: [String]])
        let restored = SkippedItems(accounts: saved)
        #expect(restored.contains("first", account: account))
        #expect(restored.contains("second", account: otherAccount))
    }

    @Test func initialSyncMergesLocalAndRemoteThenAppliesPendingChanges() {
        let ids = SkippedItems.synchronizedIDs(
            remoteIDs: ["remote", "removed"],
            localIDs: ["local", "removed"],
            pendingChanges: ["removed": false, "new": true],
            isInitialSync: true
        )
        #expect(ids == ["remote", "local", "new"])
    }

    @Test func laterSyncsTrustTheRemoteSet() {
        let ids = SkippedItems.synchronizedIDs(
            remoteIDs: ["remote", "stale"],
            localIDs: ["stale-local"],
            pendingChanges: ["stale": false],
            isInitialSync: false
        )
        #expect(ids == ["remote"])
    }
}
