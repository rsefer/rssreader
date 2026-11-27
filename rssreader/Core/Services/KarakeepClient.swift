import Foundation

enum KarakeepClient {
    enum SaveResult {
        case saved(bookmarkID: String)
        case alreadyExists(bookmarkID: String)

        var bookmarkID: String {
            switch self {
            case .saved(let bookmarkID), .alreadyExists(let bookmarkID):
                return bookmarkID
            }
        }
    }

    struct BookmarkLinks {
        let appURL: URL
        let webURL: URL
    }

    enum APIError: LocalizedError {
        case invalidServerURL
        case invalidArticleURL
        case missingAPIKey
        case unauthorized
        case serverError(Int)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .invalidServerURL:
                return "Enter a valid http:// or https:// Karakeep server URL without credentials, a query, or a fragment."
            case .invalidArticleURL:
                return "This article does not have a valid http:// or https:// URL."
            case .missingAPIKey:
                return "Add your Karakeep API key in Settings."
            case .unauthorized:
                return "Karakeep rejected the API key. Check it in Settings."
            case .serverError(let status):
                return "Karakeep returned HTTP \(status). Try again later."
            case .invalidResponse:
                return "Karakeep did not return a valid bookmark."
            }
        }
    }

    static func serverURL(from value: String) throws -> URL {
        guard let components = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              let url = components.url else {
            throw APIError.invalidServerURL
        }
        return url
    }

    static func makeSaveRequest(server: String, apiKey: String, articleURL: URL, title: String) throws -> URLRequest {
        let baseURL = try serverURL(from: server)
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw APIError.missingAPIKey }
        guard let scheme = articleURL.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = articleURL.host, !host.isEmpty else {
            throw APIError.invalidArticleURL
        }

        struct Bookmark: Encodable {
            let type = "link"
            let url: String
            let title: String
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("api/v1/bookmarks"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(Bookmark(url: articleURL.absoluteString, title: title))
        return request
    }

    static func save(request: URLRequest, session: URLSession = .shared) async throws -> SaveResult {
        let (data, response) = try await session.data(for: request)
        return try saveResult(data: data, response: response)
    }

    static func bookmarkLinks(server: String, bookmarkID: String) throws -> BookmarkLinks {
        let baseURL = try serverURL(from: server)
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard !bookmarkID.isEmpty,
              let encodedID = bookmarkID.addingPercentEncoding(withAllowedCharacters: allowedCharacters),
              var webComponents = URLComponents(
                url: baseURL.appendingPathComponent("dashboard/preview"), resolvingAgainstBaseURL: false
              ) else {
            throw APIError.invalidResponse
        }
        webComponents.percentEncodedPath += "/" + encodedID
        var appComponents = URLComponents()
        appComponents.scheme = "karakeep"
        appComponents.host = ""
        appComponents.path = "/"
        guard let appURL = appComponents.url, let webURL = webComponents.url else {
            throw APIError.invalidResponse
        }
        return BookmarkLinks(appURL: appURL, webURL: webURL)
    }

    static func saveResult(data: Data, response: URLResponse) throws -> SaveResult {
        guard let response = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        switch response.statusCode {
        case 200, 201:
            struct Bookmark: Decodable {
                let id: String
            }
            guard let bookmark = try? JSONDecoder().decode(Bookmark.self, from: data),
                  !bookmark.id.isEmpty else {
                throw APIError.invalidResponse
            }
            return response.statusCode == 201
                ? .saved(bookmarkID: bookmark.id)
                : .alreadyExists(bookmarkID: bookmark.id)
        case 401, 403:
            throw APIError.unauthorized
        default:
            throw APIError.serverError(response.statusCode)
        }
    }
}
