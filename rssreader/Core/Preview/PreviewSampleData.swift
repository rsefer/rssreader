import Foundation
import CoreGraphics

enum PreviewSampleData {
    /// Standard canvas size for macOS previews.
    static let previewFrame = CGSize(width: 900, height: 600)

    static let subscriptions: [FeedSubscription] = [
				FeedSubscription(id: "feed/https://www.techmeme.com/feed.xml", title: "Techmeme"),
        FeedSubscription(id: "feed/https://daringfireball.net/feeds/main", title: "Daring Fireball"),
        FeedSubscription(id: "feed/https://developer.apple.com/news/rss/news.rss", title: "Apple Developer News"),
        FeedSubscription(id: "feed/https://www.theverge.com/rss/index.xml", title: "The Verge")
    ]

    static func items(count: Int = 10, subscriptions: [FeedSubscription] = subscriptions) -> [FeedItem] {
        let normalizedCount = max(count, 1)
        let now = Date()

        return (0..<normalizedCount).map { index in
            let subscription = subscriptions[index % subscriptions.count]
            let feedURLString = subscription.id.replacingOccurrences(of: "feed/", with: "")
            let feedHost = URL(string: feedURLString)?.host ?? "example.com"

            // Keep the first item on a guaranteed-live page so detail previews can load real web content.
            let articleURL = index == 0
                ? URL(string: "https://example.com")
                : URL(string: "https://\(feedHost)/articles/sample-\(index + 1)")
            let techmemeURL = index.isMultiple(of: 4)
                ? URL(string: "https://www.techmeme.com/\(2026 - (index % 2))/\(String(format: "%02d", (index % 12) + 1))/a\(String(format: "%04d", index + 10)).htm")
                : nil
            let thumbnailURL = URL(string: "https://picsum.photos/seed/rssreader-\(index + 1)/640/360")
            let publicationIconURL = URL(string: "https://\(feedHost)/favicon.ico")
            let author = ["Alex Rivera", "Sam Lee", "Jordan Kim", "Taylor Brooks"][index % 4]
            let isRead = index >= 7

            return FeedItem(
                id: "tag:google.com,2005:reader/item/preview-\(index + 1)",
                title: "Preview Item \(index + 1): SwiftUI Canvas Sample",
                publication: subscription.title,
                author: author,
                url: articleURL,
                techmemeURL: techmemeURL,
                techmemeSummary: techmemeURL == nil ? nil : "This is sample metadata used for Techmeme-style preview rendering.",
                articleThumbnailURL: thumbnailURL,
                publicationIconURL: publicationIconURL,
                content: """
                <p>This is preview content for item \(index + 1).</p>
                <p>Use this data to validate list rendering, metadata, and detail layouts in SwiftUI previews.</p>
                """,
                publishedDate: now.addingTimeInterval(TimeInterval(-(index * 45 * 60))),
                enclosureType: index.isMultiple(of: 5) ? "audio/mpeg" : nil,
                isRead: isRead,
                subscriptionID: subscription.id
            )
        }
    }

    static func firstItemID(itemCount: Int = 10) -> String? {
        items(count: itemCount).first?.id
    }
}
