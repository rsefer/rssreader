import SwiftUI

struct ArticleSummaryView: View {
	@ObservedObject var controller: ArticleSummaryController
	let usesExternalBrowser: Bool
	let openInApp: () -> Void
	let retry: () -> Void

	var body: some View {
		if usesExternalBrowser {
			ContentUnavailableView {
				Label("Open the Article in the App", systemImage: "safari")
			} description: {
				Text("AI Summary needs access to the in-app webpage. It cannot read pages in your browser.")
			} actions: {
				Button("Open in App", action: openInApp)
			}
		} else {
			switch controller.state {
			case .waiting:
				ProgressView("Waiting for the webpage to load...")
			case .generating:
				ProgressView("Summarizing the article...")
			case .failed(let message):
				ContentUnavailableView {
					Label("Unable to Summarize", systemImage: "exclamationmark.triangle")
				} description: {
					Text(message)
				} actions: {
					Button("Try Again", action: retry)
				}
			case .ready(let paragraphs):
				ScrollView {
					VStack(alignment: .leading, spacing: 16) {
						Label("AI Summary", systemImage: "sparkles")
							.font(.title2.bold())
							.accessibilityAddTraits(.isHeader)
						ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
							Text(verbatim: paragraph)
								.textSelection(.enabled)
						}
						Text("Generated with Apple Intelligence. Summaries may contain mistakes.")
							.font(.footnote)
							.foregroundStyle(.secondary)
					}
					.frame(maxWidth: 740, alignment: .leading)
					.frame(maxWidth: .infinity, alignment: .center)
					.padding(24)
				}
			}
		}
	}
}
