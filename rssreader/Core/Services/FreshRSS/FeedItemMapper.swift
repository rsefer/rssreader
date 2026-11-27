import Foundation

/// Metadata scraped from a Techmeme page or inline feed HTML.
nonisolated struct TechmemeMetadata: Sendable {
    let articleURL: URL?
    let author: String?
    let thumbnailURL: URL?
    let publication: String?
    let summary: String?

    static let empty = TechmemeMetadata(articleURL: nil, author: nil, thumbnailURL: nil, publication: nil, summary: nil)
}

/// Pure transformations from GReader payloads to `FeedItem`s, including Techmeme-specific cleanup.
nonisolated struct FeedItemMapper {
    func makeFeedItem(from gItem: GReaderItem) -> FeedItem? {
        let href = gItem.canonical?.first?.href ?? gItem.alternate?.first?.href
        let url = href.flatMap { URL(string: $0).map(enforcingHTTPSForTechmemeURL) }
        let html = gItem.content?.content ?? gItem.summary?.content ?? ""
        let techmemeURL = techmemeURL(for: gItem, html: html) ?? url.flatMap { isTechmemeURL($0) ? $0 : nil }
        let inlineTechmemeMetadata = techmemeURL.flatMap { parseInlineTechmemeMetadata(from: html, techmemeURL: $0) } ?? .empty
        let categories = gItem.categories ?? []
        let resolvedURL = inlineTechmemeMetadata.articleURL ?? url
        let author = cleanedAuthorString(inlineTechmemeMetadata.author) ?? cleanedAuthorString(gItem.author)
        let publication = resolvedPublicationLabel(existing: gItem.origin?.title ?? "Unknown", endPublication: inlineTechmemeMetadata.publication, author: author)
        let summary = cleanedNonEmptyString(inlineTechmemeMetadata.summary)
        let normalizedTitle = cleanedTechmemeHeadlineTitle(
            gItem.title ?? "Untitled",
            isTechmemeItem: techmemeURL != nil,
            author: author,
            publication: publication
        )
        let articleThumbnailURL = inlineTechmemeMetadata.thumbnailURL
            ?? bestThumbnailURL(for: gItem, articleURL: resolvedURL, html: html)
            ?? techmemeFallbackThumbnailURL(for: techmemeURL)
        let publicationIconURL = publicationIconURL(for: publication, articleURL: resolvedURL, fallback: techmemeFallbackThumbnailURL(for: techmemeURL) ?? publicationIconURL(for: gItem, articleURL: resolvedURL))

        return FeedItem(
            id: gItem.id,
            title: normalizedTitle,
            publication: publication,
            author: author,
            url: resolvedURL,
            techmemeURL: techmemeURL,
            techmemeSummary: summary,
            articleThumbnailURL: articleThumbnailURL,
            publicationIconURL: publicationIconURL,
            content: html,
            publishedDate: Date(timeIntervalSince1970: TimeInterval(gItem.published ?? 0)),
            enclosureType: gItem.enclosure?.first?.type,
            isRead: categories.contains("user/-/state/com.google/read"),
            subscriptionID: gItem.origin?.streamId
        )
    }

    func techmemeURL(for gItem: GReaderItem, html: String) -> URL? {
        let links = (gItem.canonical ?? []) + (gItem.alternate ?? [])

        for link in links {
            guard let candidate = URL(string: link.href).map(enforcingHTTPSForTechmemeURL), isTechmemeURL(candidate) else {
                continue
            }
            return candidate
        }

        if let permalink = techmemePermalinkURL(in: html) {
            return permalink
        }

        return nil
    }

    func techmemePermalinkURL(in html: String) -> URL? {
        guard let href = firstMatchGroup(
            in: html,
            pattern: "(?is)<a[^>]+href\\s*=\\s*['\"]([^'\"]+)['\"][^>]*title\\s*=\\s*['\"]Techmeme permalink['\"]"
        ) ?? firstMatchGroup(
            in: html,
            pattern: "(?is)<a[^>]*title\\s*=\\s*['\"]Techmeme permalink['\"][^>]*href\\s*=\\s*['\"]([^'\"]+)['\"]"
        ) else {
            return nil
        }

        guard let permalinkURL = URL(string: decodeHTMLEntities(href)).map(enforcingHTTPSForTechmemeURL), isTechmemeURL(permalinkURL) else {
            return nil
        }

        return permalinkURL
    }

    func enforcingHTTPSForTechmemeURL(_ url: URL) -> URL {
        guard isTechmemeURL(url),
              url.scheme?.lowercased() == "http",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        components.scheme = "https"
        return components.url ?? url
    }

    func applyingTechmemeMetadata(_ metadata: TechmemeMetadata, to item: FeedItem) -> FeedItem {
        let resolvedURL = metadata.articleURL ?? item.url
        let resolvedAuthor = cleanedAuthorString(metadata.author) ?? item.author
        let resolvedThumbnail = metadata.thumbnailURL ?? item.articleThumbnailURL ?? techmemeFallbackThumbnailURL(for: item.techmemeURL)
        let publication = resolvedPublicationLabel(existing: item.publication, endPublication: metadata.publication, author: resolvedAuthor)
        let summary = cleanedNonEmptyString(metadata.summary) ?? item.techmemeSummary
        let resolvedPublicationIconURL = publicationIconURL(for: publication, articleURL: resolvedURL, fallback: item.publicationIconURL)

        return FeedItem(
            id: item.id,
            title: item.title,
            publication: publication,
            author: resolvedAuthor,
            url: resolvedURL,
            techmemeURL: item.techmemeURL,
            techmemeSummary: summary,
            articleThumbnailURL: resolvedThumbnail,
            publicationIconURL: resolvedPublicationIconURL,
            content: item.content,
            publishedDate: item.publishedDate,
            enclosureType: item.enclosureType,
            isRead: item.isRead,
            subscriptionID: item.subscriptionID
        )
    }


            func techmemeFallbackThumbnailURL(for techmemeURL: URL?) -> URL? {
                guard let techmemeURL,
                      let host = techmemeURL.host,
                      !host.isEmpty else {
                    return nil
                }

                var components = URLComponents()
                components.scheme = techmemeURL.scheme ?? "https"
                components.host = host
                components.path = "/favicon.ico"
                return components.url
            }
    func resolvedPublicationLabel(existing: String, endPublication: String?, author: String?) -> String {
        guard let cleanedEndPublication = normalizedTechmemePublication(endPublication, author: author) else {
            return existing
        }

        return "Techmeme > \(cleanedEndPublication)"
    }

    func hasDisplayChanges(original: FeedItem, updated: FeedItem) -> Bool {
        original.url != updated.url ||
        original.author != updated.author ||
        original.articleThumbnailURL != updated.articleThumbnailURL ||
        original.publicationIconURL != updated.publicationIconURL ||
        original.publication != updated.publication ||
        original.techmemeSummary != updated.techmemeSummary
    }

    func needsTechmemeEnrichment(_ item: FeedItem) -> Bool {
        item.url == item.techmemeURL ||
        item.articleThumbnailURL == nil ||
        cleanedNonEmptyString(item.techmemeSummary) == nil ||
        item.publication == "Techmeme"
    }

    func publicationIconURL(for publication: String, articleURL: URL?, fallback: URL?) -> URL? {
        if publication.lowercased().contains("techmeme") == false,
           let host = articleURL?.host,
           !host.isEmpty {
            return URL(string: "https://\(host)/favicon.ico")
        }

        return fallback
    }

    func parseTechmemeMetadata(from html: String, pageURL: URL) -> TechmemeMetadata {
        let section = techmemeSectionHTML(in: html, anchor: pageURL.fragment) ?? html
        let itemBlock = techmemePrimaryItemHTML(in: section) ?? section
        let articleURL = techmemePrimaryArticleURL(in: itemBlock, relativeTo: pageURL)
            ?? firstExternalLink(in: itemBlock, relativeTo: pageURL)
        let author = techmemeAuthor(in: section)
        let publication = techmemePublication(in: section)
        let summary = techmemeSummary(in: itemBlock)
        let thumbnailURL = techmemeThumbnailURL(in: itemBlock, relativeTo: pageURL)
            ?? firstImageSource(in: itemBlock).flatMap { resolvePossibleRelativeURL($0, relativeTo: pageURL) }

        return TechmemeMetadata(articleURL: articleURL, author: author, thumbnailURL: thumbnailURL, publication: publication, summary: summary)
    }

    func parseInlineTechmemeMetadata(from html: String, techmemeURL: URL) -> TechmemeMetadata {
        let itemBlock = techmemePrimaryItemHTML(in: html) ?? html
        let articleURL = techmemePrimaryArticleURL(in: itemBlock, relativeTo: techmemeURL)
            ?? firstExternalLink(in: itemBlock, relativeTo: techmemeURL)
        let publication = techmemePublication(in: html)
        let summary = techmemeSummary(in: itemBlock)
        let thumbnailURL = techmemeThumbnailURL(in: itemBlock, relativeTo: techmemeURL)
            ?? firstImageSource(in: itemBlock).flatMap { resolvePossibleRelativeURL($0, relativeTo: techmemeURL) }

        return TechmemeMetadata(articleURL: articleURL, author: nil, thumbnailURL: thumbnailURL, publication: publication, summary: summary)
    }

    func techmemePrimaryItemHTML(in html: String) -> String? {
        firstMatchGroup(in: html, pattern: "(?is)<div[^>]*class\\s*=\\s*['\\\"][^'\\\"]*ii[^'\\\"]*['\\\"][^>]*>(.*?)</div>")
    }

    func techmemePrimaryArticleURL(in html: String, relativeTo pageURL: URL) -> URL? {
        if let href = firstMatchGroup(in: html, pattern: "(?is)<a[^>]*class\\s*=\\s*['\\\"][^'\\\"]*ourh[^'\\\"]*['\\\"][^>]*href\\s*=\\s*['\\\"]([^'\\\"]+)['\\\"]") {
            return resolvePossibleRelativeURL(decodeHTMLEntities(href), relativeTo: pageURL)
        }

        if let href = firstMatchGroup(in: html, pattern: "(?is)<div[^>]*class\\s*=\\s*['\\\"][^'\\\"]*ii[^'\\\"]*['\\\"][^>]*>.*?<a[^>]+href\\s*=\\s*['\\\"]([^'\\\"]+)['\\\"]") {
            return resolvePossibleRelativeURL(decodeHTMLEntities(href), relativeTo: pageURL)
        }

        return nil
    }

    func techmemeThumbnailURL(in html: String, relativeTo pageURL: URL) -> URL? {
        guard let source = firstMatchGroup(in: html, pattern: "(?is)<img[^>]*class\\s*=\\s*['\\\"][^'\\\"]*ill[^'\\\"]*['\\\"][^>]*src\\s*=\\s*['\\\"]([^'\\\"]+)['\\\"]")
            ?? firstMatchGroup(in: html, pattern: "(?is)<div[^>]*class\\s*=\\s*['\\\"][^'\\\"]*ii[^'\\\"]*['\\\"][^>]*>.*?<img[^>]+src\\s*=\\s*['\\\"]([^'\\\"]+)['\\\"]") else {
            return nil
        }

        return resolvePossibleRelativeURL(decodeHTMLEntities(source), relativeTo: pageURL)
    }

    func techmemeSectionHTML(in html: String, anchor: String?) -> String? {
        guard let anchor, !anchor.isEmpty else {
            return nil
        }

        let nsHTML = html as NSString
        let escapedAnchor = NSRegularExpression.escapedPattern(for: anchor)
        let anchorPattern = "(?is)(id|name)\\s*=\\s*[\\\"']\(escapedAnchor)[\\\"']"
        guard let anchorRegex = try? NSRegularExpression(pattern: anchorPattern),
              let anchorMatch = anchorRegex.firstMatch(in: html, range: NSRange(location: 0, length: nsHTML.length)) else {
            return nil
        }

        let startLocation = anchorMatch.range.location
        let remainingRange = NSRange(location: min(startLocation + 1, nsHTML.length), length: max(0, nsHTML.length - (startLocation + 1)))
        let nextAnchorPattern = "(?is)(id|name)\\s*=\\s*[\\\"']a\\d{6}p\\d+[\\\"']"
        let nextAnchorRegex = try? NSRegularExpression(pattern: nextAnchorPattern)
        let nextAnchor = nextAnchorRegex?.firstMatch(in: html, range: remainingRange)

        let hardLimit = min(nsHTML.length, startLocation + 8_000)
        let endLocation = min(nextAnchor?.range.location ?? hardLimit, hardLimit)
        guard endLocation > startLocation else {
            return nil
        }

        return nsHTML.substring(with: NSRange(location: startLocation, length: endLocation - startLocation))
    }

    func firstExternalLink(in html: String, relativeTo pageURL: URL) -> URL? {
        guard let regex = try? NSRegularExpression(pattern: "(?is)<a[^>]+href\\s*=\\s*['\\\"]([^'\\\"]+)['\\\"]") else {
            return nil
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex.matches(in: html, options: [], range: range)

        for match in matches where match.numberOfRanges > 1 {
            guard let hrefRange = Range(match.range(at: 1), in: html) else { continue }
            let href = decodeHTMLEntities(String(html[hrefRange]))
            guard let candidateURL = resolvePossibleRelativeURL(href, relativeTo: pageURL),
                  let host = candidateURL.host?.lowercased() else {
                continue
            }

            if host == "techmeme.com" || host.hasSuffix(".techmeme.com") {
                continue
            }

            return candidateURL
        }

        return nil
    }

    func techmemeAuthor(in html: String) -> String? {
        if let citeInner = firstMatchGroup(in: html, pattern: "(?is)<cite[^>]*>(.*?)</cite>") {
            var cleanedCite = decodeHTMLEntities(strippingHTMLTags(from: citeInner))
            cleanedCite = cleanedCite.replacingOccurrences(of: ":", with: "")
            cleanedCite = cleanedCite.trimmingCharacters(in: CharacterSet(charactersIn: " \n\r\t"))

            if let slashIndex = cleanedCite.firstIndex(of: "/") {
                let beforeSlash = cleanedCite[..<slashIndex]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !beforeSlash.isEmpty {
                    return beforeSlash
                }
            }
        }

        if let sourceText = firstMatchGroup(in: html, pattern: "(?is)<a[^>]*class\\s*=\\s*['\\\"][^'\\\"]*ourh[^'\\\"]*['\\\"][^>]*>(.*?)</a>") {
            let cleaned = decodeHTMLEntities(strippingHTMLTags(from: sourceText))
                .trimmingCharacters(in: CharacterSet(charactersIn: " :\n\r\t"))
            if !cleaned.isEmpty {
                return cleaned
            }
        }

        return nil
    }

    func techmemePublication(in html: String) -> String? {
        if let publication = firstMatchGroup(in: html, pattern: "(?is)<cite[^>]*>\\s*<a[^>]*>(.*?)</a>") {
            return cleanedNonEmptyString(decodeHTMLEntities(strippingHTMLTags(from: publication)))
        }

        if let citeInner = firstMatchGroup(in: html, pattern: "(?is)<cite[^>]*>(.*?)</cite>") {
            return cleanedNonEmptyString(decodeHTMLEntities(strippingHTMLTags(from: citeInner)).replacingOccurrences(of: ":", with: ""))
        }

        return nil
    }

    func normalizedTechmemePublication(_ publication: String?, author: String?) -> String? {
        guard var cleanedPublication = cleanedNonEmptyString(publication) else {
            return nil
        }

        if let slashIndex = cleanedPublication.firstIndex(of: "/") {
            let afterSlash = cleanedPublication[cleanedPublication.index(after: slashIndex)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !afterSlash.isEmpty {
                cleanedPublication = afterSlash
            }
        }

        if let author = cleanedNonEmptyString(author) {
            let lowerPublication = cleanedPublication.lowercased()
            let lowerAuthor = author.lowercased()

            if lowerPublication.hasPrefix(lowerAuthor) {
                cleanedPublication = cleanedPublication.dropFirst(author.count)
                    .trimmingCharacters(in: CharacterSet(charactersIn: " /:-\n\r\t"))
            }
        }

        return cleanedNonEmptyString(cleanedPublication)
    }

    func techmemeSummary(in itemHTML: String) -> String? {
        if let rawSummary = firstMatchGroup(in: itemHTML, pattern: "(?is)</strong>\\s*&nbsp;\\s*[—-]\\s*&nbsp;\\s*(.*?)\\s*$") {
            return cleanedNonEmptyString(decodeHTMLEntities(strippingHTMLTags(from: rawSummary)))
        }

        let plainText = decodeHTMLEntities(strippingHTMLTags(from: itemHTML))
        let separators = [" — ", " - "]
        for separator in separators {
            if let range = plainText.range(of: separator) {
                let summary = String(plainText[range.upperBound...])
                if let cleaned = cleanedNonEmptyString(summary) {
                    return cleaned
                }
            }
        }

        return nil
    }

    func firstMatchGroup(in text: String, pattern: String, group: Int = 1) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > group,
              let outputRange = Range(match.range(at: group), in: text) else {
            return nil
        }

        return String(text[outputRange])
    }

    func strippingHTMLTags(from value: String) -> String {
        guard !value.isEmpty,
              let regex = try? NSRegularExpression(pattern: "(?is)<[^>]+>") else {
            return value
        }

        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        let noTags = regex.stringByReplacingMatches(in: value, options: [], range: range, withTemplate: " ")
        return noTags
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    func decodeHTMLEntities(_ value: String) -> String {
        var decoded = value
        let replacements = [
            "&amp;": "&",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'",
            "&lt;": "<",
            "&gt;": ">",
            "&nbsp;": " "
        ]

        for (entity, replacement) in replacements {
            decoded = decoded.replacingOccurrences(of: entity, with: replacement)
        }

        return decoded
    }

    func isTechmemeURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return false
        }

        return host == "techmeme.com" || host.hasSuffix(".techmeme.com")
    }

    func cleanedNonEmptyString(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    func cleanedAuthorString(_ value: String?) -> String? {
        guard let cleaned = cleanedNonEmptyString(value) else {
            return nil
        }

        let wordCount = cleaned
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .count

        guard wordCount <= 5 else {
            return nil
        }

        return cleaned
    }

    func cleanedTechmemeHeadlineTitle(_ title: String, isTechmemeItem: Bool, author: String?, publication: String?) -> String {
        let baseTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isTechmemeItem,
              !baseTitle.isEmpty,
              let attribution = firstMatchGroup(in: baseTitle, pattern: "\\(([^()]*)\\)\\s*$"),
              let titleWithoutAttribution = firstMatchGroup(in: baseTitle, pattern: "^(.*?)\\s*\\([^()]*\\)\\s*$") else {
            return baseTitle.isEmpty ? "Untitled" : baseTitle
        }

        let cleanAttribution = attribution.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTitle = titleWithoutAttribution.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanAttribution.isEmpty, !cleanTitle.isEmpty else {
            return baseTitle
        }

        let normalizedAuthor = normalizedAttributionToken(author)
        let normalizedPublication = normalizedAttributionToken(publication)
        let parts = cleanAttribution
            .split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let containsKnownSource = parts.contains { part in
            let normalizedPart = normalizedAttributionToken(part)
            guard !normalizedPart.isEmpty else { return false }

            if !normalizedAuthor.isEmpty,
               (normalizedAuthor.contains(normalizedPart) || normalizedPart.contains(normalizedAuthor)) {
                return true
            }

            if !normalizedPublication.isEmpty,
               (normalizedPublication.contains(normalizedPart) || normalizedPart.contains(normalizedPublication)) {
                return true
            }

            return false
        }

        let looksLikeByline = parts.count >= 2
            && parts.allSatisfy { part in
                let words = part.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
                return words > 0 && words <= 8
            }

        guard containsKnownSource || looksLikeByline else {
            return baseTitle
        }

        return cleanTitle
    }

    func normalizedAttributionToken(_ value: String?) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return ""
        }

        let lowered = value.lowercased()
        let filteredScalars = lowered.unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar) || CharacterSet.whitespacesAndNewlines.contains(scalar)
        }
        let normalized = String(String.UnicodeScalarView(filteredScalars))
        return normalized
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    func bestThumbnailURL(for gItem: GReaderItem, articleURL: URL?, html: String) -> URL? {
        if let imageEnclosure = gItem.enclosure?.first(where: { ($0.type ?? "").lowercased().hasPrefix("image/") }),
           let href = imageEnclosure.href,
           let url = resolvePossibleRelativeURL(href, relativeTo: articleURL) {
            return url
        }

        if let firstImageSource = firstImageSource(in: html) {
            return resolvePossibleRelativeURL(firstImageSource, relativeTo: articleURL)
        }

        return nil
    }

    func publicationIconURL(for gItem: GReaderItem, articleURL: URL?) -> URL? {
        if let originURLString = gItem.origin?.htmlUrl,
           let originURL = URL(string: originURLString),
           let host = originURL.host,
           !host.isEmpty {
            return URL(string: "https://\(host)/favicon.ico")
        }

        if let host = articleURL?.host, !host.isEmpty {
            return URL(string: "https://\(host)/favicon.ico")
        }

        return nil
    }

    func firstImageSource(in html: String) -> String? {
        guard !html.isEmpty,
              let regex = try? NSRegularExpression(pattern: "(?i)<img[^>]+src\\s*=\\s*['\"]([^'\"]+)['\"]") else {
            return nil
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: range),
              match.numberOfRanges > 1,
              let sourceRange = Range(match.range(at: 1), in: html) else {
            return nil
        }

        return String(html[sourceRange])
    }

    func resolvePossibleRelativeURL(_ value: String, relativeTo articleURL: URL?) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let absolute = URL(string: trimmed), absolute.scheme != nil {
            return enforcingHTTPSForTechmemeURL(absolute)
        }

        if let articleURL {
            if let relativeURL = URL(string: trimmed, relativeTo: articleURL)?.absoluteURL {
                return enforcingHTTPSForTechmemeURL(relativeURL)
            }
        }

        if let fallbackURL = URL(string: trimmed) {
            return enforcingHTTPSForTechmemeURL(fallbackURL)
        }

        return nil
    }

    func deduplicated(items: [FeedItem]) -> [FeedItem] {
        var seenIDs = Set<String>()
        var uniqueItems: [FeedItem] = []

        for item in items.sorted(by: { $0.publishedDate > $1.publishedDate }) {
            if seenIDs.insert(item.id).inserted {
                uniqueItems.append(item)
            }
        }

        return uniqueItems
    }

    func todayModeCutoffDate(now: Date = .now) -> Date {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now)
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now) ?? startOfDay.addingTimeInterval(12 * 60 * 60)

        if now < noon {
            return now.addingTimeInterval(-12 * 60 * 60)
        }

        return startOfDay
    }
}
