import SwiftUI

struct DetailHeaderView: View {
    let item: FeedItem
    let primaryThumbnailURL: URL?
    let fallbackThumbnailURL: URL?
    let loadImages: Bool
    let thumbnailDisplayMode: ThumbnailDisplayMode
    let useCompactHorizontalLayout: Bool
    let onURLTap: (URL) -> Void

    private var compactMetadataLeadingInset: CGFloat {
        let thumbnailWidth = thumbnailDisplayMode == .favicon ? 44.0 : 96.0
        return thumbnailWidth + 12.0
    }

    private var thumbnailView: some View {
        RemoteThumbnailView(
            primaryURL: primaryThumbnailURL,
            fallbackURL: fallbackThumbnailURL,
            loadImages: loadImages,
            width: thumbnailDisplayMode == .favicon ? 44 : 96,
            height: thumbnailDisplayMode == .favicon ? 44 : 60,
            cornerRadius: 8,
            placeholderSystemName: "newspaper"
        )
    }

    private var linkView: some View {
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

    var body: some View {
        if useCompactHorizontalLayout {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 12) {
                    thumbnailView

                    Text(item.title)
                        .font(.headline)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

								VStack(alignment: .leading, spacing: 3) {
										MetadataPrimaryView(item: item)
										linkView
								}
                    .padding(.leading, compactMetadataLeadingInset)
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                thumbnailView

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(3)

										HStack(spacing: 8) {
											MetadataPrimaryView(item: item)
										}
                    linkView
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
