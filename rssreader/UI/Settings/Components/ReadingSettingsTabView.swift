import SwiftUI

struct ReadingSettingsTabView: View {
    @EnvironmentObject private var service: FreshRSSService

    var body: some View {
#if os(macOS)
        VStack(alignment: .leading, spacing: 14) {
            thumbnailsSection
            articleOpeningSection
        }
#else
        Form {
            thumbnailsSection
            articleOpeningSection
        }
        .formStyle(.grouped)
#if os(macOS)
        .padding()
#endif
#endif
    }

	@ViewBuilder
	private var thumbnailsSection: some View {
#if os(macOS)
		SettingsCard(
			title: "Thumbnails",
			subtitle: "Control artwork behavior in the feed list"
		) {
			thumbnailsContent
		}
#else
		Section("Thumbnails") {
			thumbnailsContent
		}
#endif
	}

	@ViewBuilder
	private var articleOpeningSection: some View {
#if os(macOS)
		SettingsCard(title: "Article Opening", subtitle: nil) {
			articleOpeningContent
		}
#else
		Section("Article Opening") {
			articleOpeningContent
		}
#endif
	}

	@ViewBuilder
	private var thumbnailsContent: some View {
		readingRow("Load article thumbnails") {
			platformToggle("Load article thumbnails", isOn: $service.loadArticleImages)
		}
		
		if (service.loadArticleImages) {
			
			readingDivider
			
			readingRow("Size") {
				HStack {
					#if !os(macOS)
					Text("Size")
					#endif
					Spacer()
					Text("\(service.articleThumbnailSize) pt")
					Stepper(value: $service.articleThumbnailSize, in: 24...72, step: 2) {
					}
				}
				.disabled(!service.loadArticleImages)
			}
			
			readingDivider
			
			readingRow("Style") {
				Picker("Style", selection: $service.thumbnailDisplayMode) {
					ForEach(ThumbnailDisplayMode.allCases) { mode in
						Text(mode.label).tag(mode)
					}
				}
#if os(macOS)
				.labelsHidden()
#endif
				.disabled(!service.loadArticleImages)
			}
			
			if (service.thumbnailDisplayMode == .articleThumbnail) {
				
				readingDivider
				
				readingRow("Aspect ratio") {
					Picker("Aspect ratio", selection: $service.articleThumbnailAspectRatio) {
						ForEach(ThumbnailAspectRatio.allCases) { ratio in
							Text(ratio.label).tag(ratio)
						}
					}
#if os(macOS)
					.labelsHidden()
#endif
					.disabled(!service.loadArticleImages || service.thumbnailDisplayMode == .favicon)
				}
				
			}
			
			
		}
	}

	@ViewBuilder
	private var articleOpeningContent: some View {
		readingRow("Always open articles in a browser") {
			platformToggle("Always open articles in a browser", isOn: $service.preferExternalBrowser)
		}

#if !os(macOS)
		Text("When enabled, the Web tab opens the current article in your default browser instead of the embedded web view.")
			.font(.caption)
			.foregroundStyle(.secondary)
#endif
	}

	@ViewBuilder
	private func readingRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
#if os(macOS)
		SettingsRow(title: title, detail: nil, content: content)
#else
		content()
#endif
	}

	@ViewBuilder
	private var readingDivider: some View {
#if os(macOS)
		Divider()
#endif
	}

	    @ViewBuilder
	    private func platformToggle(_ title: String, isOn: Binding<Bool>) -> some View {
		Toggle(title, isOn: isOn)
					.toggleStyle(.switch)
#if os(macOS)
		    .labelsHidden()
#endif
	}
}
