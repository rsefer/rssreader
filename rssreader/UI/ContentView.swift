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
	#if os(macOS)
	@Environment(\.openSettings) private var openSettings
	#endif
    @EnvironmentObject var service: FreshRSSService
	@StateObject private var logic: ContentLogic
	@State private var splitColumnVisibility: NavigationSplitViewVisibility = .all
	@State private var macSplitColumnVisibility: NavigationSplitViewVisibility = .all

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
							openSettings: { presentSettings() },
							isSidebarVisible: false
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
							openSettings: { presentSettings() },
							isSidebarVisible: splitColumnVisibility != .detailOnly
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

		let screenWidth = UIApplication.shared.connectedScenes
			.compactMap { ($0 as? UIWindowScene)?.screen }
			.first?.bounds.width ?? 0
		return detailWidth < (screenWidth - 40)
		#else
		false
		#endif
	}

	private var macNavigation: some View {
			NavigationSplitView(columnVisibility: $macSplitColumnVisibility) {
					FeedView(
							selectedItemIDs: $logic.selectedItemIDs,
							openSettings: { presentSettings() },
							isSidebarVisible: macSplitColumnVisibility != .detailOnly
					)
					.frame(minWidth: 300)
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
					DetailView(item: item, openSettings: { presentSettings() }, isSidebarVisible: isSidebarVisible)
							.environmentObject(service)
			} else {
					EmptyDetailPlaceholderView(
							isConfigured: service.isConfigured,
							openSettings: { presentSettings() }
					)
						.environmentObject(service)
			}
	}

	private func presentSettings() {
		#if os(macOS)
		openSettings()
		#else
		logic.openSettings()
		#endif
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
							if service.isConfigured {
									await logic.authenticateIfConfigured(using: service)
							} else {
									presentSettings()
							}
					}
					.onReceive(NotificationCenter.default.publisher(for: .navigateToPreviousItem)) { _ in
							selectPrevious()
					}
					.onReceive(NotificationCenter.default.publisher(for: .navigateToNextItem)) { _ in
							selectNext()
					}
					#if os(iOS)
					.platformSettingsPresentation(isPresented: $logic.showSettings) {
							SettingsView()
									.environmentObject(service)
					}
					#endif
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
