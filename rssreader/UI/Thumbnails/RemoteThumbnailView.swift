import SwiftUI
import Kingfisher

private final class ThumbnailRequestModifier: ImageDownloadRequestModifier {
    private let timeout: TimeInterval

    init(timeout: TimeInterval = 8) {
        self.timeout = timeout
    }

    func modified(for request: URLRequest) -> URLRequest? {
        var modifiedRequest = request
        modifiedRequest.timeoutInterval = timeout
        return modifiedRequest
    }
}

private final class ThumbnailURLPolicy {
    static let shared = ThumbnailURLPolicy()

    private var failedURLStrings: Set<String> = []
    private let lock = NSLock()

    private let disallowedExtensions: Set<String> = [
        "html", "htm", "php", "asp", "aspx", "jsp", "cgi", "cfm"
    ]

    private init() {}

    func shouldAttempt(_ url: URL) -> Bool {
        guard isSupportedURL(url), !isKnownFailed(url) else {
            return false
        }

        let ext = url.pathExtension.lowercased()
        if ext.isEmpty {
            return true
        }

        return !disallowedExtensions.contains(ext)
    }

    func markFailed(_ url: URL) {
        lock.lock()
        failedURLStrings.insert(url.absoluteString)
        lock.unlock()
    }

    private func isKnownFailed(_ url: URL) -> Bool {
        lock.lock()
        let isKnown = failedURLStrings.contains(url.absoluteString)
        lock.unlock()
        return isKnown
    }

    private func isSupportedURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), (scheme == "http" || scheme == "https") else {
            return false
        }

        return !(url.host?.isEmpty ?? true)
    }
}

struct RemoteThumbnailView: View {
    let primaryURL: URL?
    let fallbackURL: URL?
    let loadImages: Bool
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat
    let placeholderSystemName: String

    @State private var activeURL: URL?

    private let requestModifier = ThumbnailRequestModifier()

    var body: some View {
        Group {
            if loadImages, let displayURL = displayURL {
                remoteImage(for: displayURL)
            } else {
                placeholder
            }
        }
        .frame(width: width, height: height)
        .background(.quaternary.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onAppear {
            activeURL = initialURL()
        }
        .onChange(of: primaryURL?.absoluteString, initial: false) { _, _ in
            activeURL = initialURL()
        }
        .onChange(of: fallbackURL?.absoluteString, initial: false) { _, _ in
            activeURL = initialURL()
        }
        .onChange(of: loadImages, initial: false) { _, _ in
            activeURL = initialURL()
        }
    }

    private var displayURL: URL? {
        if let activeURL, ThumbnailURLPolicy.shared.shouldAttempt(activeURL) {
            return activeURL
        }

        let fallbackCandidate = selectPreferredURL(primary: fallbackURL, fallback: nil)
        if let fallbackCandidate, ThumbnailURLPolicy.shared.shouldAttempt(fallbackCandidate) {
            return fallbackCandidate
        }

        return nil
    }

    private func initialURL() -> URL? {
        selectPreferredURL(primary: primaryURL, fallback: fallbackURL)
    }

    private func selectPreferredURL(primary: URL?, fallback: URL?) -> URL? {
        if let primary, ThumbnailURLPolicy.shared.shouldAttempt(primary) {
            return primary
        }

        if let fallback, ThumbnailURLPolicy.shared.shouldAttempt(fallback) {
            return fallback
        }

        return nil
    }

    private func handleFailure(for url: URL) {
        ThumbnailURLPolicy.shared.markFailed(url)

        if primaryURL == url {
            activeURL = selectPreferredURL(primary: fallbackURL, fallback: nil)
        } else {
            activeURL = nil
        }
    }

    @ViewBuilder
    private func remoteImage(for displayURL: URL) -> some View {
        if isGoogleFaviconURL(displayURL) {
            KFImage.url(displayURL)
                .requestModifier(requestModifier)
                .cacheOriginalImage()
                .memoryCacheExpiration(.days(7))
                .diskCacheExpiration(.days(30))
                .fade(duration: 0.2)
                .placeholder {
                    ProgressView()
                        .scaleEffect(0.6)
                }
                .onFailure { _ in
                    handleFailure(for: displayURL)
                }
                .cancelOnDisappear(true)
                .resizable()
                .scaledToFill()
        } else {
            KFImage.url(displayURL)
                .requestModifier(requestModifier)
                .cacheOriginalImage()
                .fade(duration: 0.2)
                .placeholder {
                    ProgressView()
                        .scaleEffect(0.6)
                }
                .onFailure { _ in
                    handleFailure(for: displayURL)
                }
                .cancelOnDisappear(true)
                .resizable()
                .scaledToFill()
        }
    }

    private func isGoogleFaviconURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "www.google.com" && url.path == "/s2/favicons"
    }

    private var placeholder: some View {
        Image(systemName: placeholderSystemName)
            .resizable()
            .scaledToFit()
            .frame(width: min(width, height) * 0.48, height: min(width, height) * 0.48)
            .foregroundStyle(.tertiary)
    }
}
