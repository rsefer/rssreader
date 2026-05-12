import SwiftUI

struct FeedItemRow: View {
    let item: FeedItem
    let isRead: Bool
    let loadImages: Bool
    let thumbnailSize: CGFloat
    let thumbnailAspectRatio: ThumbnailAspectRatio
    let thumbnailDisplayMode: ThumbnailDisplayMode

    private var primaryThumbnailURL: URL? {
        switch thumbnailDisplayMode {
        case .articleThumbnail: return item.articleThumbnailURL
        case .favicon:          return item.googleFaviconURL
        }
    }

    private var fallbackThumbnailURL: URL? {
        // Always use publicationIconURL (direct /favicon.ico) as the fallback so
        // something is shown even when Google's service is unavailable.
        item.publicationIconURL
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            FeedRowThumbnail(
                primaryURL: primaryThumbnailURL,
                fallbackURL: fallbackThumbnailURL,
                loadImages: loadImages,
                size: thumbnailSize,
                aspectRatio: thumbnailAspectRatio,
                displayMode: thumbnailDisplayMode
            )

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top, spacing: 8) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isRead ? .secondary : .primary)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
										UnreadStatusIndicator(status: isRead)
											.padding(.top, 4)
                }

                HStack(alignment: .center, spacing: 6) {
                    Text(item.publication)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 2)

									Text(item.timeAgo)
											.font(.caption2)
											.foregroundStyle(.quaternary)

    //                FormatBadge(format: item.format)
                }
            }
        }
        .padding(.vertical, 3)
        .opacity(isRead ? 0.72 : 1)
    }
}

private struct FeedRowThumbnail: View {
    let primaryURL: URL?
    let fallbackURL: URL?
    let loadImages: Bool
    let size: CGFloat
    let aspectRatio: ThumbnailAspectRatio
    let displayMode: ThumbnailDisplayMode

    // Favicons look better letterboxed inside a square frame rather than
    // cropped to a landscape/portrait aspect ratio.
    private var effectiveAspectRatio: ThumbnailAspectRatio {
        displayMode == .favicon ? .square : aspectRatio
    }

    var body: some View {
        RemoteThumbnailView(
            primaryURL: primaryURL,
            fallbackURL: fallbackURL,
            loadImages: loadImages,
            width: size * effectiveAspectRatio.widthMultiplier,
            height: size,
            cornerRadius: displayMode == .favicon ? 4 : 7,
            placeholderSystemName: "newspaper"
        )
    }
}

private struct UnreadStatusIndicator: View {
		let status: Bool
    var body: some View {
        Circle()
				.fill(status ? Color.clear : Color.accentColor)
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }
}

// MARK: - Format badge

private struct FormatBadge: View {
    let format: String

    var body: some View {
        Text(format)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var color: Color {
        switch format {
        case "Video":   return .red
        case "Podcast": return .orange
        default:        return .blue
        }
    }
}
