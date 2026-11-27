import Foundation
import SwiftUI

// MARK: - GReader API Codable types

nonisolated struct GReaderStreamResponse: Codable, Sendable {
    let items: [GReaderItem]
    let continuation: String?
}

nonisolated struct GReaderItem: Codable, Sendable {
    let id: String
    let title: String?
    let published: Int?
    let categories: [String]?
    let canonical: [GReaderLink]?
    let alternate: [GReaderLink]?
    let summary: GReaderContent?
    let content: GReaderContent?
    let origin: GReaderOrigin?
    let enclosure: [GReaderEnclosure]?
    let author: String?
}

nonisolated struct GReaderLink: Codable, Sendable {
    let href: String
    let type: String?
}

nonisolated struct GReaderContent: Codable, Sendable {
    let content: String?
}

nonisolated struct GReaderOrigin: Codable, Sendable {
    let title: String?
    let htmlUrl: String?
    let streamId: String?
}

nonisolated struct GReaderEnclosure: Codable, Sendable {
    let href: String?
    let type: String?
    let length: String?
}

nonisolated struct GReaderSubscriptionListResponse: Codable, Sendable {
    let subscriptions: [GReaderSubscriptionItem]
}

nonisolated struct GReaderSubscriptionItem: Codable, Sendable {
    let id: String
    let title: String?
}

// MARK: - Public subscription model

nonisolated struct FeedSubscription: Identifiable, Hashable, Sendable {
    let id: String    // GReader stream ID, e.g. "feed/https://..."
    let title: String
}

// MARK: - Errors

nonisolated enum FreshRSSError: LocalizedError {
    case notConfigured
    case authenticationFailed
    case notAuthenticated
    case networkError(String)
    case serverError(Int)
    case invalidServerURL
    case insecureServerURL(host: String)
    case keychain(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "FreshRSS is not configured. Open Settings (⌘,) to add your server details."
        case .authenticationFailed:
            return "Authentication failed. Check your username and password in Settings."
        case .notAuthenticated:
            return "Not authenticated. Please check Settings."
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .serverError(let code):
            return "Server returned error \(code)."
        case .invalidServerURL:
            return "Invalid server URL. Use a host like example.com or a full URL like https://example.com."
        case .insecureServerURL(let host):
            return "\(host) is using http://, which iOS and macOS block for internet hosts. Switch the server URL to https://, or use an IP address or a .local hostname for a server on your local network."
        case .keychain(let detail):
            return "Keychain error: \(detail)"
        }
    }
}

nonisolated enum SidebarMode: String, CaseIterable, Identifiable, Sendable {
    case new = "New"
    case today = "Today"
    case archive = "Archive"

    var id: String { rawValue }

    var syncLabel: String {
        switch self {
        case .new:
            return "Sync unread items"
        case .today:
            return "Sync today's items"
        case .archive:
            return "Sync archive"
        }
    }
}

enum ThumbnailDisplayMode: String, CaseIterable, Identifiable {
    case articleThumbnail
    case favicon

    var id: String { rawValue }

    var label: String {
        switch self {
        case .articleThumbnail: return "Article Thumbnails"
        case .favicon:          return "Site Favicons"
        }
    }
}

enum ThumbnailAspectRatio: String, CaseIterable, Identifiable {
    case landscape
    case square
    case portrait

    var id: String { rawValue }

    var label: String {
        switch self {
        case .landscape:
            return "Landscape"
        case .square:
            return "Square"
        case .portrait:
            return "Portrait"
        }
    }

    var widthMultiplier: CGFloat {
        switch self {
        case .landscape:
            return 16.0 / 9.0
        case .square:
            return 1.0
        case .portrait:
            return 3.0 / 4.0
        }
    }
}
