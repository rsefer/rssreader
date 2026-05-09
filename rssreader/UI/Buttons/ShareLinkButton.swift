import SwiftUI

struct ShareLinkButton: View {
	
	let item: FeedItem

	var body: some View {
		if let url = item.url {
			ShareLink(item: url, subject: Text(item.title), message: Text(item.title)) {
				Label("Share this article", systemImage: "square.and.arrow.up")
			}
			.help("Share this article")
		} else {
			EmptyView()
		}
		
	}
}
