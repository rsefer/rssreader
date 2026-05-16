import SwiftUI

struct ItemActionsButtons: View {
	let item: FeedItem
	@Binding var isHeaderVisible: Bool
	@EnvironmentObject private var service: FreshRSSService

	var body: some View {
		OpenInBrowserButton(item: item)
			.keyboardShortcut("o", modifiers: [.command, .shift])
			.help("Open the article in your default browser (⌘↩ or ⌘⇧O)")
		ShareLinkButton(item: item)
		CopyLinkButton(item: item)
		ToggleItemReadStatusButton(item: item)
	}
}
