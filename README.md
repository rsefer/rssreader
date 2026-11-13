# RSS Reader

rssreader is a SwiftUI app for iPhone, iPad, and macOS that connects to FreshRSS and presents your feed items with a two-pane reading workflow, inline content viewing, and read/unread management actions.

On devices with Apple Intelligence available, AI Summary summarizes the article
shown in the in-app Web view using Apple's on-device model. Summaries are cached
in memory while the detail view is open and regenerated if the page content
changes. When articles are set to open in an external browser, select Open in
App in AI Summary to load the page in the app first. Summaries may contain
mistakes.

To run the standalone macOS article-summary checks, compile and run:

```sh
swiftc -parse-as-library rssreader/UI/Detail/ArticleSummaryText.swift rssreader/UI/Detail/ArticleSummaryController.swift rssreader/UI/Web/WebView.swift rssreader/Core/EmbeddedWebNavigationPolicy.swift tests/ArticleSummaryChecks.swift -o /tmp/article-summary-checks
/tmp/article-summary-checks --real-model
```

The on-device model check is optional; omit `--real-model` to run the other
checks. Model-dependent checks are skipped when Apple Intelligence is unavailable.
