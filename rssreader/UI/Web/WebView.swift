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

static func readerHTML(body: String, sourceURL: URL) -> String {
"""
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
\(body)
</body>
</html>
"""
}
}

private class LinkNavigationCoordinator: NSObject, WKNavigationDelegate {
var lastItemID = ""

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

    func makeCoordinator() -> LinkNavigationCoordinator {
        LinkNavigationCoordinator()
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

    private func loadSourceIfNeeded(on webView: WKWebView, coordinator: LinkNavigationCoordinator) {
        guard coordinator.lastItemID != itemID else { return }
        coordinator.lastItemID = itemID

        switch source {
        case .url(let url):
            webView.load(URLRequest(url: url))
        case .html(let html):
            webView.loadHTMLString(html, baseURL: nil)
        }
    }
}

extension LinkNavigationCoordinator {
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

/// Loads a webpage, extracts the main content block, and renders a clean reader view.
struct ReaderWebView: PlatformViewRepresentable {
    let url: URL
    let itemID: String
    let fallbackHTML: String?

    func makeCoordinator() -> ReaderCoordinator {
        ReaderCoordinator(url: url, fallbackHTML: fallbackHTML)
    }

    #if os(macOS)
    func makeNSView(context: Context) -> WKWebView {
        makeWebView(delegate: context.coordinator)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        update(webView: webView, coordinator: context.coordinator)
    }
    #else
    func makeUIView(context: Context) -> WKWebView {
        makeWebView(delegate: context.coordinator)
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        update(webView: webView, coordinator: context.coordinator)
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

    private func update(webView: WKWebView, coordinator: ReaderCoordinator) {
        coordinator.updateContext(url: url, fallbackHTML: fallbackHTML)
        guard coordinator.lastItemID != itemID else { return }

        coordinator.lastItemID = itemID
        coordinator.didLoadReaderHTML = false
        webView.load(URLRequest(url: url))
    }

    final class ReaderCoordinator: LinkNavigationCoordinator {
        private(set) var currentURL: URL
        private(set) var fallbackHTML: String?
        var didLoadReaderHTML = false

        init(url: URL, fallbackHTML: String?) {
            self.currentURL = url
            self.fallbackHTML = fallbackHTML
        }

        func updateContext(url: URL, fallbackHTML: String?) {
            guard currentURL != url || self.fallbackHTML != fallbackHTML else { return }
            currentURL = url
            self.fallbackHTML = fallbackHTML
            didLoadReaderHTML = false
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !didLoadReaderHTML else { return }

            webView.evaluateJavaScript(ReaderContentExtractor.extractionScript) { [weak self, weak webView] result, _ in
                guard let self, let webView else { return }

                let extractedBody = (result as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let extractedTextLength = ReaderContentExtractor.plainTextLength(fromHTML: extractedBody)
                let shouldUseExtracted = extractedTextLength >= ReaderContentExtractor.minimumExtractedTextLength

                self.didLoadReaderHTML = true

                if shouldUseExtracted {
                    let readerHTML = ReaderContentExtractor.readerHTML(body: extractedBody, sourceURL: self.currentURL)
                    webView.loadHTMLString(readerHTML, baseURL: self.currentURL.deletingLastPathComponent())
                    return
                }

                let fallbackBody = (self.fallbackHTML ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !fallbackBody.isEmpty {
                    let readerHTML = ReaderContentExtractor.readerHTML(body: fallbackBody, sourceURL: self.currentURL)
                    webView.loadHTMLString(readerHTML, baseURL: self.currentURL.deletingLastPathComponent())
                    return
                }
            }
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
