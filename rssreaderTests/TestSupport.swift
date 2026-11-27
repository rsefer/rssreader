import Foundation
@testable import SDC_RSS

/// Records requests and answers them from a closure, so no test touches the network.
nonisolated final class FakeTransport: HTTPTransport, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (status: Int, body: Data)

    private let lock = NSLock()
    private let handler: Handler
    private var recorded: [URLRequest] = []

    init(_ handler: @escaping Handler) {
        self.handler = handler
    }

    var requests: [URLRequest] {
        lock.withLock { recorded }
    }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        lock.withLock { recorded.append(request) }
        let result = try handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: result.status, httpVersion: nil, headerFields: nil)!
        return (result.body, response)
    }
}

/// Thread-safe call counter for handlers that fail a set number of times.
nonisolated final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    /// Increments and returns the new count.
    func next() -> Int {
        lock.withLock {
            value += 1
            return value
        }
    }
}

extension Data {
    nonisolated init(_ string: String) {
        self = Data(string.utf8)
    }
}

extension FreshRSSAPIClient {
    /// A client whose retries and DNS backoff return immediately.
    nonisolated static func test(_ transport: FakeTransport, serverURL: String = "https://rss.example.com") -> FreshRSSAPIClient {
        FreshRSSAPIClient(
            serverURL: serverURL,
            transport: transport,
            makeFreshTransport: { transport },
            sleep: { _ in }
        )
    }
}

extension FeedItem {
    static func test(id: String, published: TimeInterval = 1_700_000_000, isRead: Bool = false) -> FeedItem {
        FeedItem(
            id: id,
            title: "Title \(id)",
            publication: "Example",
            author: nil,
            url: URL(string: "https://news.example/\(id)"),
            techmemeURL: nil,
            techmemeSummary: nil,
            articleThumbnailURL: nil,
            publicationIconURL: nil,
            content: "",
            publishedDate: Date(timeIntervalSince1970: published),
            enclosureType: nil,
            isRead: isRead,
            subscriptionID: nil
        )
    }
}
