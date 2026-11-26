import Foundation

@main
struct SkippedItemsChecks {
    static func main() {
        let account = SkippedItems.accountKey(serverURL: "https://example.com", username: "reader")
        let otherAccount = SkippedItems.accountKey(serverURL: "https://example.com", username: "other")
        var skipped = SkippedItems()

        skipped.insert("first", account: account)
        skipped.insert("first", account: account)
        skipped.insert("second", account: account)
        skipped.insert("first", account: otherAccount)

        let suiteName = "rssreader-skipped-checks-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Could not create test defaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(skipped.accounts, forKey: "skipped")
        guard let saved = defaults.dictionary(forKey: "skipped") as? [String: [String]] else {
            fatalError("Skipped items did not persist")
        }
        skipped = SkippedItems(accounts: saved)
        precondition(skipped.contains("first", account: account))
        precondition(skipped.contains("second", account: account))
        precondition(skipped.contains("first", account: otherAccount))

        skipped.remove(["first"], account: account)
        precondition(!skipped.contains("first", account: account))
        precondition(skipped.contains("second", account: account))
        precondition(skipped.contains("first", account: otherAccount))

        skipped.remove(["second"], account: account)
        precondition(skipped.accounts[account] == nil)
        precondition(skipped.contains("first", account: otherAccount))
        print("Skipped item checks passed")
    }
}
