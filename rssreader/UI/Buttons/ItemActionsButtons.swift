import SwiftUI

struct ItemActionsButtons: View {
	let item: FeedItem

	@EnvironmentObject private var service: FreshRSSService

	var body: some View {
		if let url = item.url {
			OpenInBrowserButton(url: url)
				.keyboardShortcut("o", modifiers: [.command, .shift])
				.help("Open the current article in your default browser (⌘↩ or ⌘⇧O)")

			ShareLink(item: url, subject: Text(item.title), message: Text(item.title)) {
				Label("Share this article", systemImage: "square.and.arrow.up")
			}
			.help("Share this article")
		}

		Button {
			Task {
				if service.isMarkedRead(item) {
					await service.markAsUnread(item)
				} else {
					await service.markAsRead(item)
				}
			}
		} label: {
			Image(systemName: service.isMarkedRead(item) ? "circle.dotted" : "checkmark.circle.fill")
		}
		.help(service.isMarkedRead(item) ? "Mark selected article as unread" : "Mark selected article as read")
		.disabled(service.isLoading)
	}
}
