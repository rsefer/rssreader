import SwiftUI

struct ShareLinkButton: View {
	
	let item: FeedItem

	var body: some View {
		if let url = item.url {
			ShareLink(item: url) {
				Label("Share this article", systemImage: "square.and.arrow.up")
			}
			.help("Share this article")
		} else {
			EmptyView()
		}
		
	}
}
