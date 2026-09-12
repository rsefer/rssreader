import SwiftUI

struct MetadataPrimaryView: View {
	enum Context {
		case detail
		case feed
	}

	let item: FeedItem
	let context: Context
	let thumbnailDisplayMode: ThumbnailDisplayMode
	let loadImages: Bool

	init(item: FeedItem, context: Context = .detail, thumbnailDisplayMode: ThumbnailDisplayMode, loadImages: Bool) {
		self.item = item
		self.context = context
		self.thumbnailDisplayMode = thumbnailDisplayMode
		self.loadImages = loadImages
	}

	private var shouldShowSystemImages: Bool {
		context == .detail
	}
	
	@ViewBuilder
	private func metadataValue(_ text: String, faviconURL: URL? = nil, systemImage: String? = nil) -> some View {
		HStack(spacing: 5) {
			if shouldShowSystemImages && systemImage != nil {
				Label(text, systemImage: systemImage ?? "newspaper")
			} else {
				if faviconURL != nil {
					RemoteThumbnailView(
						primaryURL: faviconURL,
						fallbackURL: nil as URL?,
						loadImages: true,
						width: 14,
						height: 14,
						cornerRadius: 3,
						placeholderSystemName: "newspaper"
					)
				}
				Text(text)
			}
		}
	}

	var body: some View {
		if context != .detail && (thumbnailDisplayMode != .favicon || !loadImages) {
			RemoteThumbnailView(
				primaryURL: item.googleFaviconURL,
				fallbackURL: nil as URL?,
				loadImages: thumbnailDisplayMode != .favicon || !loadImages,
				width: 14,
				height: 14,
				cornerRadius: 3,
				placeholderSystemName: "newspaper"
			)
		}
		metadataValue(item.publication, faviconURL: context == .detail ? item.googleFaviconURL : nil, systemImage: context == .detail ? nil : "newspaper")
			.font(.caption)
			.foregroundStyle(.secondary)


		if let author = item.author, !author.isEmpty && context == .detail {
			metadataValue(author, systemImage: "person")
				.font(.caption)
				.foregroundStyle(.secondary)
		} else if context == .feed {
			Spacer()
		}

		metadataValue(item.timeAgo, systemImage: "clock")
			.font(.caption)
			.foregroundStyle(.secondary)

	}
}
