import SwiftUI

struct DetailView: View {
		@Environment(\.openURL) private var openURL
		@EnvironmentObject private var service: FreshRSSService

		let item: FeedItem
		let openSettings: () -> Void
		let isSidebarVisible: Bool
		@State private var activeTab: ContentTab = .web
		@State private var lastAutoOpenedItemID: String?
		@State private var currentWebURL: URL?
		@State private var isURLBarVisible = false
		@State private var editableURLText: String
		@State private var urlFieldError: String?
		@State private var webReloadToken = 0
		@FocusState private var isURLFieldFocused: Bool

		init(item: FeedItem, openSettings: @escaping () -> Void = {}, isSidebarVisible: Bool = false) {
				self.item = item
				self.openSettings = openSettings
				self.isSidebarVisible = isSidebarVisible
				_currentWebURL = State(initialValue: item.url)
				_editableURLText = State(initialValue: item.url?.absoluteString ?? "")
		}

		private var detailPrimaryThumbnailURL: URL? {
				switch service.thumbnailDisplayMode {
				case .articleThumbnail: return item.articleThumbnailURL
				case .favicon:          return item.googleFaviconURL
				}
		}

		private var detailFallbackThumbnailURL: URL? {
				item.publicationIconURL
		}

		private var shouldShowGlobalButtonsToolbarItemGroup: Bool {
				#if os(iOS)
				switch UIDevice.current.userInterfaceIdiom {
				case .phone:
						false
				case .pad:
						!isSidebarVisible
				default:
						true
				}
				#else
				true
				#endif
		}

	private var previousNextItemButtonsLocation: ToolbarItemPlacement {
		#if os(iOS)
		if isIPhone {
			return .bottomBar
		}
		#endif
		return .primaryAction
	}

	private var itemActionsButtonsLocation: ToolbarItemPlacement {
		#if os(iOS)
		if isIPhone {
			return .bottomBar
		}
		#endif
		return .primaryAction
	}

		private var isIPhone: Bool {
				#if os(iOS)
				UIDevice.current.userInterfaceIdiom == .phone
				#else
				false
				#endif
		}

		private struct URLBarAnimationState: Equatable {
			let isVisible: Bool
			let errorMessage: String?
		}

		private var urlBarAnimationState: URLBarAnimationState {
				URLBarAnimationState(isVisible: isURLBarVisible, errorMessage: urlFieldError)
		}

		var body: some View {
				VStack(spacing: 0) {
						// ── Header ──────────────────────────────────────────────────────────
#if os(macOS)
						header
								.frame(maxWidth: .infinity, alignment: .leading)
								.padding(.horizontal, 16)
								.padding(.vertical, 12)
								.background(.bar)

						Divider()
					#endif
						// ── Content area ─────────────────────────────────────────────────
						ZStack {
								switch activeTab {
								case .web:
																webPane
												.transition(.opacity)
												.id(ContentTab.web)
								case .reader:
										readerPane
												.transition(.opacity)
												.id(ContentTab.reader)
								case .content:
										contentPane
												.transition(.opacity)
												.id(ContentTab.content)
								}
						}
						.frame(maxWidth: .infinity, maxHeight: .infinity)
						.animation(.viewTransition, value: activeTab)
				}
				.frame(maxWidth: .infinity, maxHeight: .infinity)
				// Reset to web tab when a different item is selected, but prefer content
				// if there's no URL
				.onChange(of: item.id, initial: false) { _, _ in
						lastAutoOpenedItemID = nil
						activeTab = item.url != nil ? .web : .content
						currentWebURL = item.url
						webReloadToken = 0
						editableURLText = item.url?.absoluteString ?? ""
						urlFieldError = nil
						isURLBarVisible = false
				}
				.onAppear {
						activeTab = item.url != nil ? .web : .content
						currentWebURL = item.url
						webReloadToken = 0
						editableURLText = item.url?.absoluteString ?? ""
						urlFieldError = nil
				}
				.navigationTitle("")
				.toolbar {

					if shouldShowGlobalButtonsToolbarItemGroup {
						ToolbarItemGroup(placement: .platformLeading) {
							GlobalActionsButtons(openSettings: openSettings)
								.environmentObject(service)
						}
					}

					ToolbarItem(placement: .primaryAction) {
						DetailTabSwitcher(activeTab: $activeTab, hasWebURL: currentWebURL != nil)
					}

						ToolbarItemGroup(placement: itemActionsButtonsLocation) {
								ControlGroup {
									ItemActionsButtons(item: item)
										.environmentObject(service)
								}
								.controlGroupStyle(.automatic)
						}

					ToolbarItemGroup(placement: previousNextItemButtonsLocation) {
						PreviousNextItemButtons()
					}

					ToolbarItemGroup(placement: .primaryAction) {
						Menu("Web Options", systemImage: "ellipsis") {
							Button("Toggle URL Bar", systemImage: isURLBarVisible ? "xmark.circle" : "menubar.rectangle") {
								toggleURLBar()
							}
							.help(isURLBarVisible ? "Hide URL Bar" : "Show URL Bar")
							Button("Refresh Page", systemImage: "arrow.clockwise") {
								reloadCurrentWebPage()
							}
							.help("Refresh Page")
						}

					}


				}
		}

		// MARK: - Header

		private var header: some View {
				DetailHeaderView(
						item: item,
						primaryThumbnailURL: detailPrimaryThumbnailURL,
						fallbackThumbnailURL: detailFallbackThumbnailURL,
						loadImages: service.loadArticleImages,
						thumbnailDisplayMode: service.thumbnailDisplayMode
				)
		}

		// MARK: - Web pane

		@ViewBuilder
		private var webPane: some View {
				VStack(spacing: 0) {
						if isURLBarVisible {
								urlBar
										.transition(.move(edge: .top).combined(with: .opacity))
								Divider()
						}

						iPhoneTopAndBottomToolbarUnderlapWebContent
				}
		}

		@ViewBuilder
		private var iPhoneTopAndBottomToolbarUnderlapWebContent: some View {
				#if os(iOS)
				if isIPhone {
						webContent
								.ignoresSafeArea(.container, edges: [.top, .bottom])
				} else {
						webContent
				}
				#else
				webContent
				#endif
		}

		@ViewBuilder
		private var webContent: some View {
						if let url = currentWebURL {
								if service.preferExternalBrowser {
									externalBrowserPane(url: url)
								} else {
										WebView(source: .url(url), itemID: item.id + "-web-" + url.absoluteString + "-" + String(webReloadToken))
												.frame(maxWidth: .infinity, maxHeight: .infinity)
								}
						} else {
								VStack(spacing: 12) {
										Image(systemName: "link.badge.plus")
												.font(.largeTitle)
												.foregroundStyle(.secondary)
										Text("No URL available for this item.")
												.foregroundStyle(.secondary)
										Text("Use the URL bar to open a webpage.")
												.font(.caption)
												.foregroundStyle(.tertiary)
								}
								.frame(maxWidth: .infinity, maxHeight: .infinity)
						}
		}

		private var urlBar: some View {
				VStack(alignment: .leading, spacing: 6) {
						HStack(spacing: 8) {
								TextField("https://example.com", text: $editableURLText)
										.textFieldStyle(.roundedBorder)
										.focused($isURLFieldFocused)
										.onSubmit {
												applyURLChange()
										}

								Button("Go") {
										applyURLChange()
								}
						}

						Group {
								if let urlFieldError {
										Text(urlFieldError)
												.font(.caption)
												.foregroundStyle(.red)
												.transition(.opacity)
								}
						}
				}
				.animation(.viewTransition, value: urlBarAnimationState)
				.padding(.horizontal, 12)
				.padding(.vertical, 10)
				.background(.bar)
		}

		private func externalBrowserPane(url: URL) -> some View {
				ExternalBrowserPaneView(url: url, openInBrowser: openInBrowser)
				.onAppear {
						openInBrowserIfNeeded()
				}
		}

		private func openInBrowserIfNeeded() {
				guard service.preferExternalBrowser, activeTab == .web, lastAutoOpenedItemID != item.id else {
						return
				}

				openInBrowser()
		}

		private func openInBrowser() {
				guard let url = currentWebURL else { return }
				lastAutoOpenedItemID = item.id
				openURL(url)
		}

		private func toggleURLBar() {
				withAnimation(.viewTransition) {
						isURLBarVisible.toggle()
				}

				if isURLBarVisible {
						editableURLText = currentWebURL?.absoluteString ?? editableURLText
						urlFieldError = nil
						isURLFieldFocused = true
				}
		}

		private func applyURLChange() {
				guard let parsedURL = normalizedWebURL(from: editableURLText) else {
						urlFieldError = "Enter a valid http:// or https:// URL."
						return
				}

				currentWebURL = parsedURL
				webReloadToken = 0
				editableURLText = parsedURL.absoluteString
				urlFieldError = nil
				lastAutoOpenedItemID = nil
		}

		private func reloadCurrentWebPage() {
				guard currentWebURL != nil else { return }

				if service.preferExternalBrowser {
						lastAutoOpenedItemID = nil
						openInBrowser()
						return
				}

				webReloadToken += 1
		}

		private func normalizedWebURL(from rawValue: String) -> URL? {
				let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
				guard !trimmed.isEmpty else { return nil }

				if let direct = URL(string: trimmed), isValidHTTPURL(direct) {
						return direct
				}

				if let httpsPrefixed = URL(string: "https://\(trimmed)"), isValidHTTPURL(httpsPrefixed) {
						return httpsPrefixed
				}

				return nil
		}

		private func isValidHTTPURL(_ url: URL) -> Bool {
				guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
						return false
				}

				return !(url.host?.isEmpty ?? true)
		}

		// MARK: - Content pane (RSS HTML rendered with reader styling)

		@ViewBuilder
		private var readerPane: some View {
				if let url = item.url {
						ReaderWebView(
								url: url,
								itemID: item.id + "-reader",
								fallbackHTML: item.content.isEmpty ? nil : item.content
						)
						.frame(maxWidth: .infinity, maxHeight: .infinity)
				} else {
						contentPane
				}
		}

		private var contentPane: some View {
				WebView(source: .html(styledHTML), itemID: item.id + "-content")
						.frame(maxWidth: .infinity, maxHeight: .infinity)
		}

		private var styledHTML: String {
				let techmemeMeta = techmemeMetadataHTML
				let body = item.content.isEmpty
						? "<p><em>No content available for this article.</em></p>"
						: item.content

				return """
				<!DOCTYPE html>
				<html>
				<head>
				<meta charset="UTF-8">
				<meta name="viewport" content="width=device-width, initial-scale=1">
				<style>
				:root { color-scheme: light dark; }
				*, *::before, *::after { box-sizing: border-box; }
				body {
						font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Georgia, serif;
						font-size: 17px;
						line-height: 1.75;
											width: 100%;
						max-width: 740px;
						margin: 0 auto;
						padding: 32px 24px 64px;
						color: #1a1a1a;
						background: #ffffff;
				}
										@media (max-width: 820px) {
											body {
												max-width: none;
												margin: 0;
												padding: 22px 16px 48px;
											}
										}
				@media (prefers-color-scheme: dark) {
						body { color: #e2e2e2; background: #1c1c1e; }
						a { color: #58a6ff; }
						pre, code { background: #2d2d30; }
						blockquote { border-color: #444; color: #aaa; }
				}
				h1, h2, h3, h4 { line-height: 1.3; margin-top: 1.6em; }
				h1 { font-size: 1.6em; }
				h2 { font-size: 1.3em; }
				img, video, iframe { max-width: 100%; height: auto; border-radius: 6px; display: block; margin: 1em 0; }
				a { color: #0070e0; text-decoration: none; }
				a:hover { text-decoration: underline; }
				pre {
						background: #f4f4f5;
						border-radius: 6px;
						padding: 14px 16px;
						overflow-x: auto;
						font-size: 0.88em;
				}
				code { font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: 0.9em; }
				p > code { background: #f0f0f1; padding: 1px 5px; border-radius: 3px; }
				@media (prefers-color-scheme: dark) { p > code { background: #3a3a3c; } }
				blockquote {
						border-left: 3px solid #d0d0d0;
						margin: 1em 0;
						padding: 4px 16px;
						color: #666;
				}
				.meta-card {
						display: block;
						width: 100%;
						max-width: 100%;
						clear: both;
						text-align: left;
						margin: 0 0 1.4em;
						padding: 12px 14px;
						border: 1px solid #e2e2e2;
						border-radius: 8px;
						background: #f8f8f9;
				}
				.meta-row {
						margin: 0 0 6px;
						font-size: 0.9em;
						color: #555;
						text-align: left;
						word-break: break-all;
						overflow-wrap: break-word;
				}
				.meta-row:last-child { margin-bottom: 0; }
				.meta-label {
						font-weight: 600;
						color: #444;
						margin-right: 6px;
				}
				.meta-summary {
						margin-top: 10px;
						padding-top: 10px;
						border-top: 1px solid #e2e2e2;
						color: #333;
						font-size: 0.95em;
						text-align: left;
				}
				figure { margin: 1.5em 0; }
				figcaption { font-size: 0.85em; color: #888; margin-top: 6px; text-align: center; }
				hr { border: none; border-top: 1px solid #e0e0e0; margin: 2em 0; }
				@media (prefers-color-scheme: dark) {
						hr { border-color: #3a3a3c; }
						.meta-card { border-color: #3a3a3c; background: #252528; }
						.meta-row { color: #c9c9ce; }
						.meta-label { color: #f0f0f3; }
						.meta-summary { border-color: #3a3a3c; color: #e8e8eb; }
				}
				</style>
				</head>
				<body>
				\(techmemeMeta)
				\(body)
				</body>
				</html>
				"""
		}

		private var techmemeMetadataHTML: String {
				let hasTechmemeURL = item.techmemeURL != nil
				let hasSummary = (item.techmemeSummary?.isEmpty == false)
				guard hasTechmemeURL || hasSummary else {
						return ""
				}

				var rows: [String] = []
				rows.append("<p class=\"meta-row\"><span class=\"meta-label\">Publication:</span>\(escapeHTML(item.publication))</p>")

				if let author = item.author, !author.isEmpty {
						rows.append("<p class=\"meta-row\"><span class=\"meta-label\">Author:</span>\(escapeHTML(author))</p>")
				}

				if let articleURL = item.url {
						rows.append("<p class=\"meta-row\"><span class=\"meta-label\">Article URL:</span><a href=\"\(escapeHTML(articleURL.absoluteString))\">\(escapeHTML(articleURL.absoluteString))</a></p>")
				}

				if let techmemeURL = item.techmemeURL {
						rows.append("<p class=\"meta-row\"><span class=\"meta-label\">Original Techmeme URL:</span><a href=\"\(escapeHTML(techmemeURL.absoluteString))\">\(escapeHTML(techmemeURL.absoluteString))</a></p>")
				}

				if let summary = item.techmemeSummary, !summary.isEmpty {
						rows.append("<p class=\"meta-summary\">\(escapeHTML(summary))</p>")
				}

				return "<section class=\"meta-card\">\(rows.joined())</section>"
		}

		private func escapeHTML(_ value: String) -> String {
				value
						.replacingOccurrences(of: "&", with: "&amp;")
						.replacingOccurrences(of: "<", with: "&lt;")
						.replacingOccurrences(of: ">", with: "&gt;")
						.replacingOccurrences(of: "\"", with: "&quot;")
						.replacingOccurrences(of: "'", with: "&#39;")
		}
}
