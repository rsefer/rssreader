//
//  rssreaderApp.swift
//  rssreader
//
//  Created by Robert Sefer on 5/8/26.
//

import SwiftUI

@main
struct rssreaderApp: App {

	@StateObject private var service = AppBootstrap.makeService()

	init() {
		AppBootstrap.configure()
	}

    var body: some Scene {
		#if os(macOS)
		WindowGroup {
			ContentView()
				.environmentObject(service)
		}
		.commands {
			AppCommands(service: service)
		}

		Window("Settings", id: "settings") {
			SettingsView()
				.environmentObject(service)
		}
		.windowStyle(.hiddenTitleBar)
		.windowResizability(.contentSize)
		#else
		WindowGroup {
			ContentView()
				.environmentObject(service)
		}
		#endif

    }
}

private struct ContentViewPreviewContainer: View {

	@StateObject private var service: FreshRSSService
	private let initialSelectedItemIDs: Set<String>

	init(preselectDetail: Bool = false, noItems: Bool = false, isRefreshingList: Bool = false) {
		let previewService = AppBootstrap.makePreviewService(itemCount: 10)
		if noItems {
			previewService.items = []
		}
		if isRefreshingList {
			previewService.isLoading = true
		}
		_service = StateObject(wrappedValue: previewService)

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

#Preview("ContentView - No Items") {
	#if os(macOS)
	ContentViewPreviewContainer(noItems: true)
		.frame(width: PreviewSampleData.previewFrame.width, height: PreviewSampleData.previewFrame.height)
	#else
	ContentViewPreviewContainer(noItems: true)
	#endif
}

#Preview("ContentView - No Items with List Refreshing") {
	#if os(macOS)
	ContentViewPreviewContainer(noItems: true, isRefreshingList: true)
		.frame(width: PreviewSampleData.previewFrame.width, height: PreviewSampleData.previewFrame.height)
	#else
	ContentViewPreviewContainer(noItems: true, isRefreshingList: true)
	#endif
}

private struct SettingsPreviewHost: View {
		@StateObject private var service = AppBootstrap.makeService()

		var body: some View {
				SettingsView()
						.environmentObject(service)
		}
}

#Preview("SettingsView") {
		SettingsPreviewHost()
}
