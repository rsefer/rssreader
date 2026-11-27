import Foundation

private enum CheckError: Error {
    case failed(String)
}

private func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw CheckError.failed(message) }
}

private func expectError(_ expected: KarakeepClient.APIError, _ operation: () throws -> Void) throws {
    do {
        try operation()
        throw CheckError.failed("Expected \(expected)")
    } catch let error as KarakeepClient.APIError {
        try check(error.localizedDescription == expected.localizedDescription, "Unexpected API error: \(error)")
    }
}

private final class BookmarkURLProtocol: URLProtocol {
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

@main
struct KarakeepChecks {
    static func main() async throws {
        let articleURL = URL(string: "https://news.example/article?q=one%20two&source=rss")!
        let request = try KarakeepClient.makeSaveRequest(
            server: " https://bookmarks.example/library/ ",
            apiKey: " test-key ",
            articleURL: articleURL,
            title: "A \"quoted\" article & more"
        )
        try check(request.url?.absoluteString == "https://bookmarks.example/library/api/v1/bookmarks", "Base path was lost")
        try check(request.httpMethod == "POST", "Incorrect request method")
        try check(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key", "Incorrect authentication header")
        try check(request.value(forHTTPHeaderField: "Content-Type") == "application/json", "Incorrect content type")
        let payload = try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: String]
        try check(payload?["type"] == "link", "Incorrect bookmark type")
        try check(payload?["url"] == articleURL.absoluteString, "Article URL changed")
        try check(payload?["title"] == "A \"quoted\" article & more", "Article title changed")
        try check(payload?.count == 3, "Unexpected bookmark fields")

        for server in ["example.com", "ftp://example.com", "https://user:password@example.com", "https://example.com?key=x", "https://example.com#fragment"] {
            try expectError(.invalidServerURL) { _ = try KarakeepClient.serverURL(from: server) }
        }
        try expectError(.missingAPIKey) {
            _ = try KarakeepClient.makeSaveRequest(server: "https://example.com", apiKey: " ", articleURL: articleURL, title: "")
        }
        try expectError(.invalidArticleURL) {
            _ = try KarakeepClient.makeSaveRequest(
                server: "https://example.com", apiKey: "key",
                articleURL: URL(string: "file:///tmp/article")!, title: ""
            )
        }

        let bookmark = Data(#"{"id":"bookmark-id"}"#.utf8)
        func response(_ status: Int) -> HTTPURLResponse {
            HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        }
        if case .saved(let bookmarkID) = try KarakeepClient.saveResult(data: bookmark, response: response(201)) {
            try check(bookmarkID == "bookmark-id", "New bookmark ID was lost")
        } else {
            throw CheckError.failed("New bookmark was not recognized")
        }
        if case .alreadyExists(let bookmarkID) = try KarakeepClient.saveResult(data: bookmark, response: response(200)) {
            try check(bookmarkID == "bookmark-id", "Existing bookmark ID was lost")
        } else {
            throw CheckError.failed("Existing bookmark was not recognized")
        }
        for status in [401, 403] {
            try expectError(.unauthorized) { _ = try KarakeepClient.saveResult(data: Data(), response: response(status)) }
        }
        try expectError(.serverError(503)) { _ = try KarakeepClient.saveResult(data: Data(), response: response(503)) }
        for invalid in ["{}", "not JSON", #"{"id":""}"#] {
            try expectError(.invalidResponse) {
                _ = try KarakeepClient.saveResult(data: Data(invalid.utf8), response: response(201))
            }
        }
        let links = try KarakeepClient.bookmarkLinks(server: "https://bookmarks.example/library/", bookmarkID: "bookmark-id")
        try check(links.webURL.absoluteString == "https://bookmarks.example/library/dashboard/preview/bookmark-id", "Incorrect web bookmark link")
        try check(links.appURL.absoluteString == "karakeep:///", "Native app did not open at its main screen")
        let escapedLinks = try KarakeepClient.bookmarkLinks(server: "https://bookmarks.example", bookmarkID: "one/two?x#y")
        try check(escapedLinks.webURL.absoluteString == "https://bookmarks.example/dashboard/preview/one%2Ftwo%3Fx%23y", "Bookmark ID changed the web route")
        try check(escapedLinks.appURL == links.appURL, "Bookmark ID changed the app's main-screen link")
        try expectError(.invalidResponse) { _ = try KarakeepClient.bookmarkLinks(server: "https://example.com", bookmarkID: "") }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BookmarkURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        if case .saved = try await KarakeepClient.save(request: request, session: session) {
        } else {
            throw CheckError.failed("Mocked save request failed")
        }
        print("Karakeep checks passed.")
    }
}
