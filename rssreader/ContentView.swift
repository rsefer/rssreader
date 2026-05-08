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
							detailContent
					}
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
			.background(.background)
	}

	private var splitNavigation: some View {
			NavigationSplitView {
					FeedView(
							selectedItemIDs: $logic.selectedItemIDs,
							openSettings: { logic.openSettings() }
					)
					.navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 420)
			} detail: {
					detailContent
			}
			.navigationSplitViewStyle(.balanced)
	}

	private var macNavigation: some View {
			NavigationSplitView {
					FeedView(
							selectedItemIDs: $logic.selectedItemIDs,
							openSettings: { logic.openSettings() }
					)
			} detail: {
					detailContent
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
			.background(.background)
			.platformMainToolbar(
					canGoPrevious: canGoPrevious,
					canGoNext: canGoNext,
					showSettings: { logic.openSettings() },
					selectPrevious: selectPrevious,
					selectNext: selectNext
			)
			.platformMainKeyboardHandlers(
					canGoPrevious: canGoPrevious,
					canGoNext: canGoNext,
					isTextFieldFocused: isTextFieldFocused,
					selectPrevious: selectPrevious,
					selectNext: selectNext
			)
			.focusedValue(\.itemNavigation, ItemNavigation(
					selectPrevious: selectPrevious,
					selectNext: selectNext,
					canGoPrevious: canGoPrevious,
					canGoNext: canGoNext
			))
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
	private var detailContent: some View {
			if let item = selectedItem {
					DetailView(item: item)
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
					.task {
							await logic.authenticateIfConfigured(using: service)
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

	@StateObject private var service = AppBootstrap.makePreviewService(itemCount: 10)
	private let initialSelectedItemIDs: Set<String>

	init(preselectDetail: Bool = false) {
		if preselectDetail,
			 let id = PreviewSampleData.firstItemID(itemCount: 10) {
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
	ContentViewPreviewContainer()
}

#Preview("ContentView - Detail Selected") {
	ContentViewPreviewContainer(preselectDetail: true)
}
