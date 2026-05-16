import SwiftUI

struct MetadataPrimaryView: View {
	enum Context {
		case detail
		case feed
	}

	let item: FeedItem
	let context: Context

	init(item: FeedItem, context: Context = .detail) {
		self.item = item
		self.context = context
	}

	private var shouldShowSystemImages: Bool {
		context == .detail
	}

	@ViewBuilder
	private func metadataValue(_ text: String, systemImage: String) -> some View {
		if shouldShowSystemImages {
			Label(text, systemImage: systemImage)
		} else {
			Text(text)
		}
	}

	var body: some View {
		metadataValue(item.publication, systemImage: "newspaper")
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
