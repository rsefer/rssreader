import SwiftUI

struct DetailHeaderView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let item: FeedItem
    let thumbnailDisplayMode: ThumbnailDisplayMode
    let onURLTap: (URL) -> Void

    var body: some View {
				HStack(alignment: .top, spacing: 12) {
						VStack(alignment: .leading, spacing: 3) {
								Text(item.title)
										.font(.headline)
										.lineLimit(3)
								HStack(spacing: 8) {
									MetadataPrimaryView(item: item, thumbnailDisplayMode: thumbnailDisplayMode, loadImages: false)
								}
							VStack(alignment: .leading, spacing: 2) {
									if let url = item.url {
											Button(url.absoluteString) { onURLTap(url) }
													.font(.caption2)
													.foregroundStyle(.blue)
													.lineLimit(1)
													.multilineTextAlignment(.leading)
													.frame(maxWidth: .infinity, alignment: .leading)
													.buttonStyle(.plain)
									}

									if let techmemeURL = item.techmemeURL {
											Button(techmemeURL.absoluteString) { onURLTap(techmemeURL) }
													.font(.caption2)
													.foregroundStyle(.blue.opacity(0.7))
													.lineLimit(1)
													.multilineTextAlignment(.leading)
													.frame(maxWidth: .infinity, alignment: .leading)
													.buttonStyle(.plain)
									}
							}
						}
						.frame(maxWidth: .infinity, alignment: .leading)
				}
    }
}
