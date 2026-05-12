import SwiftUI

/// A button that opens a URL in the user's default browser.
/// Uses `@Environment(\.openURL)` so callers don't need to thread the action through.
/// Pass `onOpen` for any side effects that must run before the URL is opened
/// (e.g. tracking which item was last auto-opened).
struct OpenInBrowserButton: View {
    @Environment(\.openURL) private var openURL

		let item: FeedItem
    var onOpen: (() -> Void)? = nil

    var body: some View {
			if let url = item.url {
				Button("Open in Browser", systemImage: "safari") {
					onOpen?()
					openURL(url)
				}
				.help("Open in Browser")
			} else {
				EmptyView()
			}
    }
}
