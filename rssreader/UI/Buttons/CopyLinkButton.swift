
import SwiftUI

struct CopyLinkButton: View {
	let item: FeedItem
	
	private func copyLink(_ url: URL) {
			PlatformCapabilities.copyToPasteboard(url.absoluteString)
	}

	var body: some View {
		if let url = item.url {
			Button("Copy Link", systemImage: "link") {
				copyLink(url)
			}
			.help("Copy Link")
		} else {
			EmptyView()
		}
		
	}
}
