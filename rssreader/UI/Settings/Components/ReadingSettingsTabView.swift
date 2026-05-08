import SwiftUI

struct ReadingSettingsTabView: View {
    @EnvironmentObject private var service: FreshRSSService

    var body: some View {
        Form {
            Section("Reading") {

                Toggle("Load article thumbnails", isOn: $service.loadArticleImages)

                Stepper(value: $service.articleThumbnailSize, in: 24...72, step: 2) {
                    Text("Thumbnail size: \(service.articleThumbnailSize) pt")
                }
                .disabled(!service.loadArticleImages)

                Picker("Thumbnail aspect ratio", selection: $service.articleThumbnailAspectRatio) {
                    ForEach(ThumbnailAspectRatio.allCases) { ratio in
                        Text(ratio.label).tag(ratio)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!service.loadArticleImages || service.thumbnailDisplayMode == .favicon)

                Picker("Thumbnail style", selection: $service.thumbnailDisplayMode) {
                    ForEach(ThumbnailDisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!service.loadArticleImages)

                Text("Site Favicons uses Google's favicon service to fetch the best available icon for each publication. Article Thumbnails shows the article's lead image.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

							Toggle("Open articles in the default browser", isOn: $service.preferExternalBrowser)

							Text("When enabled, the Web tab opens the current article in your default browser instead of the embedded web view.")
									.font(.caption)
									.foregroundStyle(.secondary)

            }
        }
        .formStyle(.grouped)
#if os(macOS)
        .padding()
#endif
    }
}
