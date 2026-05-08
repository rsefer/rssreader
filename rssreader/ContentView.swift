//
//  ContentView.swift
//  rssreader
//
//  Created by Robert Sefer on 5/8/26.
//

import SwiftUI

struct ContentView: View {

	@Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject var service: FreshRSSService
	@StateObject private var logic: ContentLogic
	@State private var splitColumnVisibility: NavigationSplitViewVisibility = .all

	init(initialSelectedItemIDs: Set<String> = []) {
		_logic = StateObject(wrappedValue: ContentLogic(initialSelectedItemIDs: initialSelectedItemIDs))
	}

	private var isDetailPresented: Binding<Bool> {
					Binding(
							get: { selectedItem != nil },
							set: { isPresented in
									if !isPresented { logic.clearSelection() }
							}
					)
			}

			private var selectedItem: FeedItem? {
					logic.selectedItem(in: service.items)
			}

			private var canGoPrevious: Bool {
					logic.canGoPrevious(in: service.items)
			}

			private var canGoNext: Bool {
					logic.canGoNext(in: service.items)
			}

			private func selectPrevious() {
					logic.selectPrevious(in: service.items)
			}

			private func selectNext() {
					logic.selectNext(in: service.items)
			}

	private var useSplitLayout: Bool {
			#if os(iOS)
			UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
			#else
			false
			#endif
	}

	private var phoneNavigation: some View {
			NavigationStack {
					FeedView(
							selectedItemIDs: $logic.selectedItemIDs,
							openSettings: { logic.openSettings() }
					)
					.navigationDestination(isPresented: isDetailPresented) {
							detailContent(isSidebarVisible: false)
					}
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
			.background(.background)
	}

	private var splitNavigation: some View {
			NavigationSplitView(columnVisibility: $splitColumnVisibility) {
					FeedView(
							selectedItemIDs: $logic.selectedItemIDs,
							openSettings: { logic.openSettings() }
					)
					.navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 420)
			} detail: {
					GeometryReader { proxy in
							let sidebarVisibleByWidth = isIPadSidebarVisible(detailWidth: proxy.size.width)
							let sidebarVisibleBySplitState = splitColumnVisibility != .detailOnly
							detailContent(isSidebarVisible: sidebarVisibleBySplitState || sidebarVisibleByWidth)
									.frame(maxWidth: .infinity, maxHeight: .infinity)
					}
			}
			.navigationSplitViewStyle(.balanced)
	}

	private func isIPadSidebarVisible(detailWidth: CGFloat) -> Bool {
			#if os(iOS)
			guard UIDevice.current.userInterfaceIdiom == .pad else {
					return false
			}

			let screenWidth = UIScreen.main.bounds.width
			return detailWidth < (screenWidth - 40)
			#else
			false
			#endif
	}

	private var macNavigation: some View {
			NavigationSplitView {
					FeedView(
							selectedItemIDs: $logic.selectedItemIDs,
							openSettings: { logic.openSettings() }
					)
			} detail: {
					detailContent(isSidebarVisible: false)
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
			.background(.background)
			.navigationTitle("")
			.platformMainKeyboardHandlers(
					canGoPrevious: canGoPrevious,
					canGoNext: canGoNext,
					isTextFieldFocused: isTextFieldFocused,
					selectPrevious: selectPrevious,
					selectNext: selectNext
			)
	}

	@ViewBuilder
	private var platformNavigation: some View {
			#if os(iOS)
			Group {
					if useSplitLayout {
							splitNavigation
					} else {
							phoneNavigation
					}
			}
			#elseif os(macOS)
			macNavigation
			#endif
	}

	@ViewBuilder
	private func detailContent(isSidebarVisible: Bool) -> some View {
			if let item = selectedItem {
					DetailView(item: item, openSettings: { logic.openSettings() }, isSidebarVisible: isSidebarVisible)
							.environmentObject(service)
			} else {
					EmptyDetailPlaceholderView(
							isConfigured: service.isConfigured,
							openSettings: { logic.openSettings() }
					)
			}
	}

	private func isTextFieldFocused() -> Bool {
			PlatformCapabilities.isTextInputFocused()
	}

	var body: some View {
			platformNavigation
					.environment(\.itemNavigation, ItemNavigation(
							selectPrevious: selectPrevious,
							selectNext: selectNext,
							canGoPrevious: canGoPrevious,
							canGoNext: canGoNext
					))
					.task {
							await logic.authenticateIfConfigured(using: service)
					}
					.onReceive(NotificationCenter.default.publisher(for: .navigateToPreviousItem)) { _ in
							selectPrevious()
					}
					.onReceive(NotificationCenter.default.publisher(for: .navigateToNextItem)) { _ in
							selectNext()
					}
					.platformSettingsPresentation(isPresented: $logic.showSettings) {
							SettingsView()
									.environmentObject(service)
					}
					.onChange(of: logic.selectedItemIDs, initial: false) { _, _ in
							logic.markSelectionAsReadIfNeeded(using: service, items: service.items)
					}
					.onChange(of: service.items, initial: false) { _, newItems in
							logic.reconcileSelection(with: newItems)
					}
					.onChange(of: scenePhase, initial: true) { _, newPhase in
							logic.handleScenePhase(newPhase, service: service)
					}
					.onDisappear {
							logic.stopAutoSyncLoop()
					}
					.platformOpenSelectedItemShortcut(url: selectedItem?.url) { url in
							openURL(url)
					}
	}
}

private struct ContentViewPreviewContainer: View {

	@StateObject private var service: FreshRSSService
	private let initialSelectedItemIDs: Set<String>

	init(preselectDetail: Bool = false, noUnreadItems: Bool = false) {
		let previewItemCount = noUnreadItems ? 0 : 10
		let previewService = AppBootstrap.makePreviewService(itemCount: previewItemCount)
		_service = StateObject(wrappedValue: previewService)

		if preselectDetail,
			 let id = PreviewSampleData.firstItemID(itemCount: previewItemCount) {
			initialSelectedItemIDs = [id]
		} else {
			initialSelectedItemIDs = []
		}
	}

		var body: some View {
			ContentView(initialSelectedItemIDs: initialSelectedItemIDs)
					.environmentObject(service)
		}
}

#Preview("ContentView") {
	#if os(macOS)
	ContentViewPreviewContainer()
		.frame(width: PreviewSampleData.previewFrame.width, height: PreviewSampleData.previewFrame.height)
	#else
	ContentViewPreviewContainer()
	#endif
}

#Preview("ContentView - Detail Selected") {
	#if os(macOS)
	ContentViewPreviewContainer(preselectDetail: true)
		.frame(width: PreviewSampleData.previewFrame.width, height: PreviewSampleData.previewFrame.height)
	#else
	ContentViewPreviewContainer(preselectDetail: true)
	#endif
}

#Preview("ContentView - No Unread Items") {
	#if os(macOS)
	ContentViewPreviewContainer(noUnreadItems: true)
		.frame(width: PreviewSampleData.previewFrame.width, height: PreviewSampleData.previewFrame.height)
	#else
	ContentViewPreviewContainer(noUnreadItems: true)
	#endif
}
