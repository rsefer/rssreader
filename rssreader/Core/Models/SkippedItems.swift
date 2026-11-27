import Foundation

struct SkippedItems {
    private var idsByAccount: [String: Set<String>]

    var accounts: [String: [String]] {
        idsByAccount.mapValues(Array.init)
    }

    init(accounts: [String: [String]] = [:]) {
        idsByAccount = accounts.mapValues(Set.init)
    }

    static func accountKey(serverURL: String, username: String) -> String {
        let server = Data(serverURL.utf8).base64EncodedString()
        let user = Data(username.utf8).base64EncodedString()
        return "\(server):\(user)"
    }

    static func synchronizedIDs(
        remoteIDs: Set<String>,
        localIDs: Set<String>,
        pendingChanges: [String: Bool],
        isInitialSync: Bool
    ) -> Set<String> {
        var ids = remoteIDs
        if isInitialSync {
            ids.formUnion(localIDs)
        }
        for (id, isSkipped) in pendingChanges {
            if isSkipped {
                ids.insert(id)
            } else {
                ids.remove(id)
            }
        }
        return ids
    }

    func contains(_ id: String, account: String) -> Bool {
        idsByAccount[account]?.contains(id) == true
    }

    mutating func insert(_ id: String, account: String) {
        idsByAccount[account, default: []].insert(id)
    }

    mutating func replace(_ ids: Set<String>, account: String) {
        if ids.isEmpty {
            idsByAccount.removeValue(forKey: account)
        } else {
            idsByAccount[account] = ids
        }
    }

    mutating func remove(_ ids: some Sequence<String>, account: String) {
        var storedIDs = idsByAccount[account] ?? []
        storedIDs.subtract(ids)
        if storedIDs.isEmpty {
            idsByAccount.removeValue(forKey: account)
        } else {
            idsByAccount[account] = storedIDs
        }
    }
}
