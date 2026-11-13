import Foundation
import SwiftUI
import WebKit

#if os(macOS)
import AppKit
private typealias PlatformViewRepresentable = NSViewRepresentable
#elseif os(iOS)
import UIKit
private typealias PlatformViewRepresentable = UIViewRepresentable
#endif

private enum ReaderContentExtractor {
static let minimumExtractedTextLength = 450

static func plainTextLength(fromHTML html: String) -> Int {
guard !html.isEmpty else { return 0 }

let withoutTags = html.replacingOccurrences(
of: "<[^>]+>",
with: " ",
options: .regularExpression
)
let normalized = withoutTags.replacingOccurrences(
of: "\\s+",
with: " ",
options: .regularExpression
)
return normalized.trimmingCharacters(in: .whitespacesAndNewlines).count
}

static let extractionScript = #"""
(() => {
const root = document.cloneNode(true);
root.querySelectorAll('script,style,noscript,iframe,header,footer,nav,aside,form').forEach(el => el.remove());

const preferred = [
root.querySelector('article'),
root.querySelector('main'),
root.querySelector('[role="main"]'),
root.querySelector('.post-content, .article-content, .entry-content, .story-body, .main-content')
].filter(Boolean);

const score = (el) => {
const text = (el.innerText || '').replace(/\s+/g, ' ').trim();
const pCount = el.querySelectorAll('p').length;
return text.length + pCount * 120;
};

let best = null;
let bestScore = -1;

for (const candidate of preferred) {
const s = score(candidate);
if (s > bestScore) {
best = candidate;
bestScore = s;
}
}

if (!best) {
const candidates = root.querySelectorAll('article, main, section, div');
for (const candidate of candidates) {
if (candidate.querySelectorAll('p').length < 2) continue;
const s = score(candidate);
if (s > bestScore) {
best = candidate;
bestScore = s;
}
}
}

if (!best) return '';

best.querySelectorAll('script,style,noscript,iframe,form,button,input,svg').forEach(el => el.remove());
return best.innerHTML || '';
})();
"""#

/// The Mozilla Readability.js source, bundled as an app resource.
static let readabilitySource: String = {
guard let url = Bundle.main.url(forResource: "Readability", withExtension: "js"),
let source = try? String(contentsOf: url, encoding: .utf8) else {
NSLog("Readability.js resource is missing from the app bundle.")
return ""
}
return source
}()

/// Runs Readability against a clone of the live page DOM and posts the parsed
/// article back to native code through the `readerContent` message handler.
static func readabilityRunnerScript() -> String {
#"""
(() => {
const post = (payload) => {
window.webkit?.messageHandlers?.readerContent?.postMessage(payload);
};
try {
\#(readabilitySource)
const article = new Readability(document.cloneNode(true)).parse();
if (article && article.content) {
post({
content: article.content,
title: article.title || "",
byline: article.byline || ""
});
} else {
post({ error: "Readability returned no content." });
}
} catch (error) {
post({ error: String(error) });
}
})();
"""#
}

static func readerHTML(body: String, sourceURL: URL, title: String = "", byline: String = "") -> String {
let escapedTitle = escapeHTML(title)
let escapedByline = escapeHTML(byline)
let heading = escapedTitle.isEmpty ? "" : "<h1 class=\"reader-title\">\(escapedTitle)</h1>"
let bylineBlock = escapedByline.isEmpty ? "" : "<p class=\"reader-byline\">\(escapedByline)</p>"
return """
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
:root { color-scheme: light dark; }
*, *::before, *::after { box-sizing: border-box; }
body {
font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Georgia, serif;
font-size: 18px;
line-height: 1.8;
width: 100%;
max-width: 760px;
margin: 0 auto;
padding: 28px 24px 64px;
color: #1b1b1b;
background: #ffffff;
}
@media (max-width: 820px) {
body {
max-width: none;
margin: 0;
padding: 22px 16px 48px;
}
}
.source {
display: inline-block;
margin-bottom: 18px;
font-size: 12px;
color: #6b7280;
text-decoration: none;
border: 1px solid #e5e7eb;
border-radius: 999px;
padding: 5px 10px;
}
h1, h2, h3, h4 { line-height: 1.28; margin-top: 1.45em; }
.reader-title { margin-top: 0.2em; margin-bottom: 0.3em; }
.reader-byline { margin-top: 0; color: #6b7280; font-size: 14px; }
@media (prefers-color-scheme: dark) {
.reader-byline { color: #b3b3b8; }
}
img, video, iframe { max-width: 100%; height: auto; border-radius: 8px; }
pre {
background: #f5f5f6;
border-radius: 8px;
padding: 14px 16px;
overflow-x: auto;
}
blockquote {
border-left: 3px solid #d5d5d5;
margin: 1.1em 0;
padding: 2px 0 2px 14px;
color: #666;
}
@media (prefers-color-scheme: dark) {
body { color: #e6e6e6; background: #1c1c1e; }
a { color: #7cb7ff; }
pre { background: #2d2d31; }
blockquote { border-color: #4a4a4f; color: #b3b3b8; }
.source { color: #c0c4ca; border-color: #414247; }
}
</style>
</head>
<body>
<a class="source" href="\(sourceURL.absoluteString)">Source</a>
\(heading)
\(bylineBlock)
\(body)
</body>
</html>
"""
}

static func escapeHTML(_ value: String) -> String {
value
.replacingOccurrences(of: "&", with: "&amp;")
.replacingOccurrences(of: "<", with: "&lt;")
.replacingOccurrences(of: ">", with: "&gt;")
.replacingOccurrences(of: "\"", with: "&quot;")
}
}

class ExternalLinkNavigationCoordinator: NSObject, WKNavigationDelegate {
    private(set) var lastItemID = ""

    func updateLastItemID(_ itemID: String) {
        lastItemID = itemID
    }

    func shouldHandleExternalLink(for navigationAction: WKNavigationAction) -> Bool {
        guard navigationAction.navigationType == .linkActivated,
              let url = navigationAction.request.url,
              !EmbeddedWebNavigationPolicy.shouldStayEmbedded(url) else {
            return false
        }

        openExternalURL(url)
        return true
    }
}

/// Wraps WKWebView for use in SwiftUI.
/// Supports loading either a remote URL or a local HTML string.
struct WebView: PlatformViewRepresentable {
    enum Source: Equatable {
        case url(URL)
        case html(String)
    }

    let source: Source
    /// A unique identifier so updates only reload when the source actually changes.
    let itemID: String
    var summaryController: ArticleSummaryController?

    static var articleTextScript: String {
        """
        (() => {
            const html = \(ReaderContentExtractor.extractionScript);
            if (!html) return "";
            const parsedDocument = new DOMParser().parseFromString(html, "text/html");
            parsedDocument.body.querySelectorAll("br").forEach(element => element.replaceWith("\\n"));
            parsedDocument.body.querySelectorAll("h1, h2, h3, h4, p, li, div, section, blockquote, pre")
                .forEach(element => element.append("\\n\\n"));
            return (parsedDocument.body.textContent || "")
                .replace(/[ \\t\\f\\r]+/g, " ")
                .replace(/\\n(?:\\s*\\n)+/g, "\\n\\n")
                .trim();
        })()
        """
    }

    func makeCoordinator() -> WebCoordinator {
        WebCoordinator(summaryController: summaryController)
    }

    #if os(macOS)
    func makeNSView(context: Context) -> WKWebView {
        makeWebView(delegate: context.coordinator)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        loadSourceIfNeeded(on: webView, coordinator: context.coordinator)
    }
    #else
    func makeUIView(context: Context) -> WKWebView {
        makeWebView(delegate: context.coordinator)
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        loadSourceIfNeeded(on: webView, coordinator: context.coordinator)
    }
    #endif

    private func makeWebView(delegate: WKNavigationDelegate) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = delegate
        #if os(macOS)
        webView.allowsMagnification = true
        #endif
        return webView
    }

    private func loadSourceIfNeeded(on webView: WKWebView, coordinator: WebCoordinator) {
        coordinator.summaryController = summaryController
        guard coordinator.lastItemID != itemID else { return }
        coordinator.updateLastItemID(itemID)

        switch source {
        case .url(let url):
            coordinator.currentNavigation = webView.load(URLRequest(url: url))
        case .html(let html):
            coordinator.currentNavigation = webView.loadHTMLString(html, baseURL: nil)
        }
    }

    final class WebCoordinator: ExternalLinkNavigationCoordinator {
        weak var summaryController: ArticleSummaryController?
        var currentNavigation: WKNavigation?

        init(summaryController: ArticleSummaryController?) {
            self.summaryController = summaryController
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            currentNavigation = navigation
            summaryController?.pageWillLoad(webView, pageID: lastItemID)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard navigation === currentNavigation else { return }
            summaryController?.pageDidLoad(webView, pageID: lastItemID)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            guard navigation === currentNavigation else { return }
            summaryController?.pageDidFail(webView, pageID: lastItemID, error: error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            guard navigation === currentNavigation else { return }
            summaryController?.pageDidFail(webView, pageID: lastItemID, error: error)
        }
    }
}

extension ExternalLinkNavigationCoordinator {
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if shouldHandleExternalLink(for: navigationAction) {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}

/// Forwards script messages to a weakly-held delegate so the
/// WKUserContentController doesn't retain the coordinator.
final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

/// Loads a webpage in an authenticated web session, runs Mozilla Readability.js
/// against the live DOM, and renders the parsed article as a clean reader view.
struct ReaderWebView: PlatformViewRepresentable {
    static let messageHandlerName = "readerContent"

    let url: URL
    let itemID: String
    let fallbackHTML: String?

    func makeCoordinator() -> ReaderCoordinator {
        let coordinator = ReaderCoordinator()
        coordinator.updateContext(url: url, fallbackHTML: fallbackHTML)
        return coordinator
    }

    #if os(macOS)
    func makeNSView(context: Context) -> WKWebView {
        makeWebView(coordinator: context.coordinator)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        update(webView: webView, coordinator: context.coordinator)
    }
    #else
    func makeUIView(context: Context) -> WKWebView {
        makeWebView(coordinator: context.coordinator)
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        update(webView: webView, coordinator: context.coordinator)
    }
    #endif

    private func makeWebView(coordinator: ReaderCoordinator) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Shares the default website data store so authenticated sessions carry over.
        config.websiteDataStore = .default()
        config.userContentController.add(
            WeakScriptMessageHandler(delegate: coordinator),
            name: Self.messageHandlerName
        )
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = coordinator
        #if os(macOS)
        webView.allowsMagnification = true
        #endif
        return webView
    }

    private func update(webView: WKWebView, coordinator: ReaderCoordinator) {
        coordinator.updateContext(url: url, fallbackHTML: fallbackHTML)
        guard coordinator.lastItemID != itemID else { return }

        coordinator.updateLastItemID(itemID)
        coordinator.didLoadReaderHTML = false
        webView.load(URLRequest(url: url))
    }

    final class ReaderCoordinator: ExternalLinkNavigationCoordinator, WKScriptMessageHandler {
        private(set) var currentURL = URL(fileURLWithPath: "/")
        private(set) var fallbackHTML: String?
        var didLoadReaderHTML = false

        func updateContext(url: URL, fallbackHTML: String?) {
            guard currentURL != url || self.fallbackHTML != fallbackHTML else { return }
            currentURL = url
            self.fallbackHTML = fallbackHTML
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !didLoadReaderHTML else { return }

            guard !ReaderContentExtractor.readabilitySource.isEmpty else {
                loadLegacyExtraction(in: webView)
                return
            }

            webView.evaluateJavaScript(ReaderContentExtractor.readabilityRunnerScript()) { _, error in
                if let error {
                    NSLog("Readability runner failed to evaluate: %@", String(describing: error))
                }
                // The parsed article (or an error) arrives via the message handler.
            }
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == ReaderWebView.messageHandlerName,
                  !didLoadReaderHTML,
                  let webView = message.webView else { return }

            let body = message.body as? [String: Any]
            if let errorDescription = body?["error"] as? String {
                NSLog("Readability parse failed: %@", errorDescription)
            }

            let content = (body?["content"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let extractedTextLength = ReaderContentExtractor.plainTextLength(fromHTML: content)

            guard extractedTextLength >= ReaderContentExtractor.minimumExtractedTextLength else {
                loadFallbackHTML(in: webView)
                return
            }

            didLoadReaderHTML = true
            let readerHTML = ReaderContentExtractor.readerHTML(
                body: content,
                sourceURL: currentURL,
                title: body?["title"] as? String ?? "",
                byline: body?["byline"] as? String ?? ""
            )
            webView.loadHTMLString(readerHTML, baseURL: currentURL.deletingLastPathComponent())
        }

        /// Heuristic DOM extraction used only when Readability.js is unavailable.
        private func loadLegacyExtraction(in webView: WKWebView) {
            webView.evaluateJavaScript(ReaderContentExtractor.extractionScript) { [weak self, weak webView] result, error in
                guard let self, let webView, !self.didLoadReaderHTML else { return }
                if let error {
                    NSLog("Reader extraction script failed: %@", String(describing: error))
                }

                let extractedBody = (result as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let extractedTextLength = ReaderContentExtractor.plainTextLength(fromHTML: extractedBody)

                guard extractedTextLength >= ReaderContentExtractor.minimumExtractedTextLength else {
                    self.loadFallbackHTML(in: webView)
                    return
                }

                self.didLoadReaderHTML = true
                let readerHTML = ReaderContentExtractor.readerHTML(body: extractedBody, sourceURL: self.currentURL)
                webView.loadHTMLString(readerHTML, baseURL: self.currentURL.deletingLastPathComponent())
            }
        }

        private func loadFallbackHTML(in webView: WKWebView) {
            let fallbackBody = (fallbackHTML ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !fallbackBody.isEmpty else { return }

            didLoadReaderHTML = true
            let readerHTML = ReaderContentExtractor.readerHTML(body: fallbackBody, sourceURL: currentURL)
            webView.loadHTMLString(readerHTML, baseURL: currentURL.deletingLastPathComponent())
        }
    }
}

private func openExternalURL(_ url: URL) {
    #if os(macOS)
    NSWorkspace.shared.open(url)
    #else
    UIApplication.shared.open(url)
    #endif
}
