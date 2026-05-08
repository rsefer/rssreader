import Foundation

struct FeedItem: Identifiable, Hashable {
    let id: String           // Full GReader tag ID: "tag:google.com,2005:reader/item/..."
    let title: String
    let publication: String  // Feed/origin title
    let author: String?
    let url: URL?
    let techmemeURL: URL?
    let techmemeSummary: String?
    let articleThumbnailURL: URL?
    let publicationIconURL: URL?
    let content: String      // HTML content from RSS summary/content
    let publishedDate: Date
    let enclosureType: String?  // e.g., "audio/mpeg" for podcasts
    let isRead: Bool
    let subscriptionID: String?  // GReader stream ID from origin (e.g. "feed/https://...")

    /// Inferred format based on URL pattern or enclosure type
    var format: String {
        if let enc = enclosureType, enc.hasPrefix("audio") {
            return "Podcast"
        }
        if let host = url?.host {
            if host.contains("youtube.com") || host.contains("youtu.be") {
                return "Video"
            }
            if host.contains("vimeo.com") {
                return "Video"
            }
        }
        return "Article"
    }

    /// Best-quality favicon URL for the article's publication, using Google's favicon service
    /// with a direct /favicon.ico URL as the fallback stored on the item.
    var googleFaviconURL: URL? {
        // Prefer the publication icon's host (the feed's origin domain) over the article URL's
        // host so we always show the correct brand icon rather than a CDN or third-party host.
        let domain = publicationIconURL?.host ?? url?.host
        guard let domain, !domain.isEmpty else { return nil }
        return URL(string: "https://www.google.com/s2/favicons?domain=\(domain)&sz=256")
    }

    /// Human-readable relative time (e.g. "3h ago")
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: publishedDate, relativeTo: Date())
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: FeedItem, rhs: FeedItem) -> Bool {
        lhs.id == rhs.id
    }
}
