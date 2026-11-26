# RSS Reader

rssreader is a SwiftUI app for iPhone, iPad, and macOS that connects to FreshRSS and presents your feed items with a two-pane reading workflow, inline content viewing, and read/unread management actions.

Unread articles scrolled past the top of the feed are marked with a grey ring
instead of the unread dot. They remain
unread until opened or explicitly marked read, including with Mark All as Read.
Skipped labels are stored locally per FreshRSS account and are not synced between devices.

To run the native macOS feed-scrolling regression checks:

```sh
swiftc -parse-as-library rssreader/UI/Feed/FeedSkipTracking.swift tests/FeedScrollChecks.swift -o /tmp/feed-scroll-checks
/tmp/feed-scroll-checks
```

The checks briefly open a test window and exercise scrolling in a real SwiftUI
list, including partial visibility, reverse scrolling, filtering, and fast jumps.

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

## Install on an iPhone

From the repository root:

```sh
cp .env.iphone.example .env.iphone
xcrun devicectl list devices
```

Set `DEVICE_ID=<identifier>` in `.env.iphone` using the phone's Identifier from
the device list, without quotes. The file is ignored by Git and is read as data,
not executed as shell code.

```sh
./scripts/install_iphone.sh
```

The script builds, installs, and launches the Debug app. The phone must be paired
and trusted, unlocked, and have Developer Mode enabled. Xcode must have valid
signing credentials and provisioning for the device. USB and Xcode-paired
wireless devices are supported. Build products go into `build/iphone`.
