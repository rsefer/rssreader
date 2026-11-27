import Foundation
import Testing
@testable import SDC_RSS

nonisolated final class BookmarkURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "bookmarks.example"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let isValid = request.httpMethod == "POST"
            && request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key"
            && request.url?.path == "/library/api/v1/bookmarks"
        let response = HTTPURLResponse(
            url: request.url!, statusCode: isValid ? 201 : 401, httpVersion: nil, headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"id":"bookmark-id"}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

struct KarakeepClientTests {
    private let articleURL = URL(string: "https://news.example/article?q=one%20two&source=rss")!

    private func expect(_ expected: KarakeepClient.APIError, from operation: () throws -> Void) {
        do {
            try operation()
            Issue.record("Expected \(expected)")
        } catch let error as KarakeepClient.APIError {
            #expect(error.localizedDescription == expected.localizedDescription)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func response(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: articleURL, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    @Test func buildsTheSaveRequest() throws {
        let request = try KarakeepClient.makeSaveRequest(
            server: " https://bookmarks.example/library/ ",
            apiKey: " test-key ",
            articleURL: articleURL,
            title: "A \"quoted\" article & more"
        )

        #expect(request.url?.absoluteString == "https://bookmarks.example/library/api/v1/bookmarks")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let payload = try JSONSerialization.jsonObject(with: #require(request.httpBody)) as? [String: String]
        #expect(payload == ["type": "link", "url": articleURL.absoluteString, "title": "A \"quoted\" article & more"])
    }

    @Test(arguments: ["example.com", "ftp://example.com", "https://user:password@example.com", "https://example.com?key=x", "https://example.com#fragment"])
    func rejectsInvalidServerURLs(server: String) {
        expect(.invalidServerURL) { _ = try KarakeepClient.serverURL(from: server) }
    }

    @Test func rejectsMissingKeysAndNonWebArticles() {
        expect(.missingAPIKey) {
            _ = try KarakeepClient.makeSaveRequest(server: "https://example.com", apiKey: " ", articleURL: articleURL, title: "")
        }
        expect(.invalidArticleURL) {
            _ = try KarakeepClient.makeSaveRequest(
                server: "https://example.com", apiKey: "key",
                articleURL: URL(string: "file:///tmp/article")!, title: ""
            )
        }
    }

    @Test func interpretsSaveResponses() throws {
        let bookmark = Data(#"{"id":"bookmark-id"}"#.utf8)

        guard case .saved(let newID) = try KarakeepClient.saveResult(data: bookmark, response: response(201)) else {
            Issue.record("201 should be a new bookmark")
            return
        }
        #expect(newID == "bookmark-id")

        guard case .alreadyExists(let existingID) = try KarakeepClient.saveResult(data: bookmark, response: response(200)) else {
            Issue.record("200 should be an existing bookmark")
            return
        }
        #expect(existingID == "bookmark-id")

        for status in [401, 403] {
            expect(.unauthorized) { _ = try KarakeepClient.saveResult(data: Data(), response: response(status)) }
        }
        expect(.serverError(503)) { _ = try KarakeepClient.saveResult(data: Data(), response: response(503)) }
        for invalid in ["{}", "not JSON", #"{"id":""}"#] {
            expect(.invalidResponse) {
                _ = try KarakeepClient.saveResult(data: Data(invalid.utf8), response: response(201))
            }
        }
    }

    @Test func buildsBookmarkLinks() throws {
        let links = try KarakeepClient.bookmarkLinks(server: "https://bookmarks.example/library/", bookmarkID: "bookmark-id")
        #expect(links.webURL.absoluteString == "https://bookmarks.example/library/dashboard/preview/bookmark-id")
        #expect(links.appURL.absoluteString == "karakeep:///")

        let escaped = try KarakeepClient.bookmarkLinks(server: "https://bookmarks.example", bookmarkID: "one/two?x#y")
        #expect(escaped.webURL.absoluteString == "https://bookmarks.example/dashboard/preview/one%2Ftwo%3Fx%23y")
        #expect(escaped.appURL == links.appURL)

        expect(.invalidResponse) { _ = try KarakeepClient.bookmarkLinks(server: "https://example.com", bookmarkID: "") }
    }

    @Test func savesThroughTheSession() async throws {
        let request = try KarakeepClient.makeSaveRequest(
            server: "https://bookmarks.example/library", apiKey: "test-key", articleURL: articleURL, title: "Title"
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BookmarkURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        guard case .saved = try await KarakeepClient.save(request: request, session: session) else {
            Issue.record("The mocked save should create a bookmark")
            return
        }
    }
}
