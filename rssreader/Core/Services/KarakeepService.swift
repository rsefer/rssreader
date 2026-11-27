import Combine
import Foundation

@MainActor
final class KarakeepService: ObservableObject {
    struct SaveFeedback {
        let message: String
        var bookmarkLinks: KarakeepClient.BookmarkLinks?
        var isError = false
    }

    private static let serverKey = "rssreader_karakeep_server"
    private static let apiKeyKey = "rssreader_karakeep_api_key"

    @Published private(set) var serverURL: String
    @Published private(set) var isSaving = false
    @Published var saveFeedback: SaveFeedback?

    var isConfigured: Bool { !serverURL.isEmpty }

    init() {
        serverURL = UserDefaults.standard.string(forKey: Self.serverKey) ?? ""
    }

    func loadAPIKey() throws -> String {
        try KeychainHelper.retrieve(key: Self.apiKeyKey) ?? ""
    }

    func configure(server: String, apiKey: String) throws {
        let normalizedURL = try KarakeepClient.serverURL(from: server).absoluteString
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw KarakeepClient.APIError.missingAPIKey }
        try KeychainHelper.save(key: Self.apiKeyKey, value: trimmedKey)
        UserDefaults.standard.set(normalizedURL, forKey: Self.serverKey)
        serverURL = normalizedURL
    }

    func disconnect() throws {
        try KeychainHelper.delete(key: Self.apiKeyKey)
        UserDefaults.standard.removeObject(forKey: Self.serverKey)
        serverURL = ""
    }

    func save(_ item: FeedItem) async throws -> KarakeepClient.SaveResult {
        guard let articleURL = item.url else { throw KarakeepClient.APIError.invalidArticleURL }
        isSaving = true
        defer { isSaving = false }
        let request = try KarakeepClient.makeSaveRequest(
            server: serverURL, apiKey: loadAPIKey(), articleURL: articleURL, title: item.title
        )
        return try await KarakeepClient.save(request: request)
    }
}
