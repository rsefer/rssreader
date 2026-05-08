import SwiftUI

struct DetailHeaderView: View {
    let item: FeedItem
    let primaryThumbnailURL: URL?
    let fallbackThumbnailURL: URL?
    let loadImages: Bool
    let thumbnailDisplayMode: ThumbnailDisplayMode

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                RemoteThumbnailView(
                    primaryURL: primaryThumbnailURL,
                    fallbackURL: fallbackThumbnailURL,
                    loadImages: loadImages,
                    width: thumbnailDisplayMode == .favicon ? 44 : 96,
                    height: thumbnailDisplayMode == .favicon ? 44 : 60,
                    cornerRadius: 8,
                    placeholderSystemName: "newspaper"
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(3)

                    HStack(spacing: 8) {
                        Label(item.publication, systemImage: "newspaper")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let author = item.author, !author.isEmpty {
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Label(author, systemImage: "person")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text("·")
                            .foregroundStyle(.tertiary)

                        Text(item.timeAgo)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("·")
                            .foregroundStyle(.tertiary)

                        Text(item.format)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let url = item.url {
                        Link(url.absoluteString, destination: url)
                            .font(.caption2)
                            .foregroundStyle(.blue)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}
