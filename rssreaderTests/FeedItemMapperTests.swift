import Foundation
import Testing
@testable import SDC_RSS

struct FeedItemMapperTests {
    private let mapper = FeedItemMapper()

    private func decodeItem(_ json: String) throws -> GReaderItem {
        try JSONDecoder().decode(GReaderItem.self, from: Data(json))
    }

    @Test func mapsAGReaderItemToAFeedItem() throws {
        let gItem = try decodeItem("""
        {
          "id": "tag:google.com,2005:reader/item/1",
          "title": "Hello",
          "published": 1700000000,
          "categories": ["user/-/state/com.google/read"],
          "canonical": [{"href": "https://news.example/a"}],
          "summary": {"content": "<p><img src=\\"/img/a.png\\"></p>"},
          "origin": {"title": "Example News", "htmlUrl": "https://news.example", "streamId": "feed/https://news.example/rss"},
          "author": "Ada Lovelace"
        }
        """)

        let item = try #require(mapper.makeFeedItem(from: gItem))

        #expect(item.id == "tag:google.com,2005:reader/item/1")
        #expect(item.title == "Hello")
        #expect(item.publication == "Example News")
        #expect(item.author == "Ada Lovelace")
        #expect(item.url?.absoluteString == "https://news.example/a")
        #expect(item.isRead)
        #expect(item.publishedDate == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(item.articleThumbnailURL?.absoluteString == "https://news.example/img/a.png")
        #expect(item.publicationIconURL?.absoluteString == "https://news.example/favicon.ico")
        #expect(item.subscriptionID == "feed/https://news.example/rss")
    }

    @Test func fallsBackWhenFieldsAreMissing() throws {
        let item = try #require(mapper.makeFeedItem(from: decodeItem(#"{"id": "x"}"#)))

        #expect(item.title == "Untitled")
        #expect(item.publication == "Unknown")
        #expect(item.url == nil)
        #expect(!item.isRead)
    }

    @Test func prefersImageEnclosuresForThumbnails() throws {
        let item = try #require(mapper.makeFeedItem(from: decodeItem("""
        {
          "id": "x",
          "alternate": [{"href": "https://news.example/a"}],
          "enclosure": [{"href": "https://cdn.example/cover.jpg", "type": "image/jpeg"}],
          "summary": {"content": "<img src=\\"https://other.example/inline.png\\">"}
        }
        """)))

        #expect(item.articleThumbnailURL?.absoluteString == "https://cdn.example/cover.jpg")
    }

    // MARK: Techmeme

    @Test func upgradesTechmemeLinksToHTTPSOnly() throws {
        let techmeme = try #require(URL(string: "http://www.techmeme.com/261127/p1"))
        let other = try #require(URL(string: "http://news.example/a"))

        #expect(mapper.enforcingHTTPSForTechmemeURL(techmeme).scheme == "https")
        #expect(mapper.enforcingHTTPSForTechmemeURL(other).scheme == "http")
    }

    @Test func stripsTheByllineFromTechmemeHeadlines() {
        let cleaned = mapper.cleanedTechmemeHeadlineTitle(
            "Big news happens (Jane Doe / The Verge)",
            isTechmemeItem: true,
            author: "Jane Doe",
            publication: "The Verge"
        )
        #expect(cleaned == "Big news happens")
    }

    @Test func leavesOrdinaryTitlesAlone() {
        let title = "Big news happens (Jane Doe / The Verge)"
        #expect(mapper.cleanedTechmemeHeadlineTitle(title, isTechmemeItem: false, author: nil, publication: nil) == title)
        #expect(mapper.cleanedTechmemeHeadlineTitle("Plain headline", isTechmemeItem: true, author: nil, publication: nil) == "Plain headline")
    }

    @Test func normalizesTechmemePublications() {
        #expect(mapper.normalizedTechmemePublication("Jane Doe / The Verge", author: "Jane Doe") == "The Verge")
        #expect(mapper.normalizedTechmemePublication("   ", author: nil) == nil)
    }

    @Test func rejectsAuthorStringsThatLookLikeSentences() {
        #expect(mapper.cleanedAuthorString("Ada Lovelace") == "Ada Lovelace")
        #expect(mapper.cleanedAuthorString("one two three four five six") == nil)
        #expect(mapper.cleanedAuthorString("  ") == nil)
    }

    @Test func extractsTechmemeSummaryAndArticleLink() throws {
        let pageURL = try #require(URL(string: "https://techmeme.com/261127/p1"))
        let html = """
        <div class="ii"><a class="ourh" href="https://news.example/story">Headline</a>
        <cite>Jane Doe / <a href="https://news.example">The Verge</a>:</cite>
        <strong>Headline</strong>&nbsp; &mdash; &nbsp;Short summary here.</div>
        """

        let metadata = mapper.parseTechmemeMetadata(from: html, pageURL: pageURL)

        #expect(metadata.articleURL?.absoluteString == "https://news.example/story")
        #expect(metadata.author == "Jane Doe")
        #expect(mapper.normalizedTechmemePublication(metadata.publication, author: metadata.author) == "The Verge")
    }

    // MARK: HTML helpers

    @Test func stripsTagsAndDecodesEntities() {
        let stripped = mapper.strippingHTMLTags(from: "<b>Hi</b>  there &amp; <i>you</i>")
        #expect(stripped == "Hi there &amp; you")
        #expect(mapper.decodeHTMLEntities(stripped) == "Hi there & you")
        #expect(mapper.decodeHTMLEntities("&quot;q&quot; &lt;b&gt; it&#39;s") == "\"q\" <b> it's")
    }

    @Test func resolvesRelativeURLsAgainstTheArticle() throws {
        let article = try #require(URL(string: "https://news.example/section/story"))
        #expect(mapper.resolvePossibleRelativeURL("/img/a.png", relativeTo: article)?.absoluteString == "https://news.example/img/a.png")
        #expect(mapper.resolvePossibleRelativeURL("https://cdn.example/a.png", relativeTo: article)?.absoluteString == "https://cdn.example/a.png")
        #expect(mapper.resolvePossibleRelativeURL("   ", relativeTo: article) == nil)
    }

    // MARK: Ordering and dates

    @Test func deduplicatesByIDAndSortsNewestFirst() {
        let items = [
            FeedItem.test(id: "a", published: 100),
            FeedItem.test(id: "b", published: 300),
            FeedItem.test(id: "a", published: 100),
            FeedItem.test(id: "c", published: 200),
        ]
        #expect(mapper.deduplicated(items: items).map(\.id) == ["b", "c", "a"])
    }

    @Test func todayWindowStartsTwelveHoursBackBeforeNoon() throws {
        let calendar = Calendar.current
        let morning = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 27, hour: 9)))
        let afternoon = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 27, hour: 15)))

        #expect(mapper.todayModeCutoffDate(now: morning) == morning.addingTimeInterval(-12 * 3600))
        #expect(mapper.todayModeCutoffDate(now: afternoon) == calendar.startOfDay(for: afternoon))
    }
}
