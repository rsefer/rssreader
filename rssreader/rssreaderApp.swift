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
	@FocusedValue(\.itemNavigation) private var itemNavigation

	init() {
			AppBootstrap.configure()
	}
	
    var body: some Scene {
        WindowGroup {
            ContentView()
						.environmentObject(service)
        }
				.commands {
										CommandGroup(replacing: .newItem) {}
										CommandMenu("Feeds") {
												SyncButton()
														.environmentObject(service)
												MarkAllAsReadButton()
														.environmentObject(service)

												Button("Mark All as Unread") {
														Task { await service.markAllAsUnread() }
												}

												Divider()

												Button("Previous Item") {
														itemNavigation?.selectPrevious()
												}
												.keyboardShortcut("k", modifiers: [])
												.disabled(!(itemNavigation?.canGoPrevious ?? false))

												Button("Next Item") {
														itemNavigation?.selectNext()
												}
												.keyboardShortcut("j", modifiers: [])
												.disabled(!(itemNavigation?.canGoNext ?? false))

												Button("New") {
														service.sidebarMode = .new
												}
												.keyboardShortcut("1", modifiers: .command)

												Button("Today") {
														service.sidebarMode = .today
												}
												.keyboardShortcut("2", modifiers: .command)

												Button("Archive") {
														service.sidebarMode = .archive
												}
												.keyboardShortcut("3", modifiers: .command)

												Divider()
										}
								}
    }
}
