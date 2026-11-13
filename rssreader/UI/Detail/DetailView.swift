import SwiftUI

struct DetailView: View {
		@Environment(\.openURL) private var openURL
		@Environment(\.horizontalSizeClass) private var horizontalSizeClass
		@Environment(\.scenePhase) private var scenePhase
		@EnvironmentObject private var service: FreshRSSService

		let item: FeedItem
		let openSettings: () -> Void
		let isSidebarVisible: Bool
		@State private var activeTab: DetailTab = .web
		@State private var lastAutoOpenedItemID: String?
		@State private var currentWebURL: URL?
		@State private var isURLBarVisible = false
		@State private var isHeaderVisible = false
		@State private var editableURLText: String
		@State private var urlFieldError: String?
		@State private var webReloadToken = 0
		@State private var openArticleInApp = false
		@State private var isAISummaryAvailable = ArticleSummaryController.isAvailable
		@StateObject private var summaryController = ArticleSummaryController()
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

		private var usesExternalBrowser: Bool {
				service.preferExternalBrowser && !openArticleInApp
		}

		private var webPageID: String {
				item.id + "-web-" + (currentWebURL?.absoluteString ?? "") + "-" + String(webReloadToken)
		}

	private var previousNextItemButtonsLocation: ToolbarItemPlacement {
		#if os(iOS)
		if horizontalSizeClass == .compact {
			return .bottomBar
		}
		#endif
		return .primaryAction
	}

	private var itemActionsButtonsLocation: ToolbarItemPlacement {
		#if os(iOS)
		if horizontalSizeClass == .compact {
			return .bottomBar
		}
		#endif
		return .primaryAction
	}

		private struct URLBarAnimationState: Equatable {
			let isVisible: Bool
			let errorMessage: String?
		}

		private var urlBarAnimationState: URLBarAnimationState {
				URLBarAnimationState(isVisible: isURLBarVisible, errorMessage: urlFieldError)
		}

		private struct HeaderAnimationState: Equatable {
			let isVisible: Bool
		}

		private var headerAnimationState: HeaderAnimationState {
				HeaderAnimationState(isVisible: isHeaderVisible)
		}

		var body: some View {
				VStack(spacing: 0) {
						// ── Header ──────────────────────────────────────────────────────────
						if isHeaderVisible {
							header
									.frame(maxWidth: .infinity, alignment: .leading)
									.padding(.horizontal, 16)
									.padding(.vertical, 12)
									.background(.bar)
									.transition(.move(edge: .top).combined(with: .opacity))

							Divider()
									.transition(.opacity)
						}
						// ── Content area ─────────────────────────────────────────────────
						ZStack {
								webPane
										.opacity(activeTab == .web ? 1 : 0)
										.allowsHitTesting(activeTab == .web)
										.accessibilityHidden(activeTab != .web)

								switch activeTab {
								case .web:
										EmptyView()
								case .reader:
										readerPane
												.transition(.opacity)
												.id(DetailTab.reader)
								case .aiSummary:
										ArticleSummaryView(
												controller: summaryController,
												usesExternalBrowser: usesExternalBrowser,
												openInApp: { openArticleInApp = true },
												retry: { summaryController.requestSummary(for: webPageID) }
										)
										.transition(.opacity)
								}
						}
						.frame(maxWidth: .infinity, maxHeight: .infinity)
						.animation(.viewTransition, value: activeTab)
				}
				.animation(.viewTransition, value: headerAnimationState)
				.frame(maxWidth: .infinity, maxHeight: .infinity)
				// Reset to the web tab when a different item is selected.
				.onChange(of: item.id, initial: false) { _, _ in
						lastAutoOpenedItemID = nil
						activeTab = .web
						openArticleInApp = false
						currentWebURL = item.url
						webReloadToken = 0
						editableURLText = item.url?.absoluteString ?? ""
						urlFieldError = nil
						isURLBarVisible = false
				}
				.onChange(of: activeTab, initial: false) { _, tab in
						if tab == .aiSummary && !usesExternalBrowser {
								summaryController.requestSummary(for: webPageID)
						}
				}
				.onChange(of: summaryController.pageRevision, initial: false) { _, _ in
						if activeTab == .aiSummary && !usesExternalBrowser {
								summaryController.requestSummary(for: webPageID)
						}
				}
				.onChange(of: scenePhase, initial: true) { _, phase in
						if phase == .active {
								isAISummaryAvailable = ArticleSummaryController.isAvailable
								if !isAISummaryAvailable && activeTab == .aiSummary {
										activeTab = .web
								}
						}
				}
				.onChange(of: isURLBarVisible, initial: false) { _, isVisible in
						if isVisible {
							isHeaderVisible = false
						}
				}
				.onChange(of: isHeaderVisible, initial: false) { _, isVisible in
						if isVisible {
							isURLBarVisible = false
							isURLFieldFocused = false
						}
				}
				.onAppear {
						activeTab = .web
						currentWebURL = item.url
						webReloadToken = 0
						editableURLText = item.url?.absoluteString ?? ""
						urlFieldError = nil
				}
				.navigationTitle("")
				.toolbar {

					if (horizontalSizeClass != .compact && !isSidebarVisible) {
						ToolbarItemGroup(placement: .platformLeading) {
							GlobalActionsButtons(openSettings: openSettings)
								.environmentObject(service)
						}
					}

					ToolbarItemGroup(placement: .navigation) {
						ControlGroup {
							ToggleDetailHeader(isHeaderVisible: $isHeaderVisible)
						}
					}


					if currentWebURL != nil {
						ToolbarItem(placement: .primaryAction) {
							DetailTabSwitcher(activeTab: $activeTab, isAISummaryAvailable: isAISummaryAvailable)
						}
					}

						ToolbarItemGroup(placement: itemActionsButtonsLocation) {
								ControlGroup("Item Actions") {

									ItemActionsButtons(item: item, isHeaderVisible: $isHeaderVisible)
										.environmentObject(service)
								}
								.controlGroupStyle(.automatic)
						}

					ToolbarItemGroup(placement: previousNextItemButtonsLocation) {
						PreviousNextItemButtons()
					}

					ToolbarItemGroup(placement: .primaryAction) {
						Menu("Web Options", systemImage: "ellipsis") {
							Button(isURLBarVisible ? "Hide URL Bar" : "Show URL Bar", systemImage: isURLBarVisible ? "xmark.circle" : "menubar.rectangle") {
								toggleURLBar()
							}
								.help(isURLBarVisible ? "Hide URL Bar" : "Show URL Bar")
							Button("Remove Paywalls", systemImage: "lock.open") {
								removePaywalls()
							}
							.disabled(currentWebURL == nil)
							.help("Open the current page through Remove Paywalls")
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
						thumbnailDisplayMode: service.thumbnailDisplayMode,
						onURLTap: { url in
								currentWebURL = url
								editableURLText = url.absoluteString
								webReloadToken = 0
								activeTab = .web
						}
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

						topAndBottomToolbarUnderlapWebContent
				}
		}

		@ViewBuilder
		private var topAndBottomToolbarUnderlapWebContent: some View {
				webContent
						.ignoresSafeArea(.container, edges: [.top, .bottom])
		}

		@ViewBuilder
		private var webContent: some View {
						if let url = currentWebURL {
								if usesExternalBrowser {
									externalBrowserPane(url: url)
								} else {
										WebView(source: .url(url), itemID: webPageID, summaryController: summaryController)
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
				guard usesExternalBrowser, activeTab == .web, lastAutoOpenedItemID != item.id else {
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

				if usesExternalBrowser {
						lastAutoOpenedItemID = nil
						openInBrowser()
						return
				}

				webReloadToken += 1
		}

		private func removePaywalls() {
				guard let currentWebURL,
							let removePaywallsURL = makeArchiveButtonsURL(for: currentWebURL) else { return }

				self.currentWebURL = removePaywallsURL
				editableURLText = removePaywallsURL.absoluteString
				urlFieldError = nil
				lastAutoOpenedItemID = nil
				webReloadToken = 0
				activeTab = .web

				if usesExternalBrowser {
						openInBrowser()
				}
		}

		private func makeArchiveButtonsURL(for url: URL) -> URL? {
				var components = URLComponents()
				components.scheme = "https"
				components.host = "www.archivebuttons.com"
				components.path = "/articles"
				components.queryItems = [URLQueryItem(name: "article", value: url.absoluteString)]
				return components.url
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

		// MARK: - Reader pane

		@ViewBuilder
		private var readerPane: some View {
				if let url = currentWebURL {
						ReaderWebView(
								url: url,
								itemID: item.id + "-reader",
								fallbackHTML: item.content.isEmpty ? nil : item.content
						)
						.frame(maxWidth: .infinity, maxHeight: .infinity)
				} else {
						VStack(spacing: 12) {
								Image(systemName: "text.alignleft")
										.font(.largeTitle)
										.foregroundStyle(.secondary)
								Text("No URL available for Reader view.")
										.foregroundStyle(.secondary)
						}
						.frame(maxWidth: .infinity, maxHeight: .infinity)
				}
		}
}
