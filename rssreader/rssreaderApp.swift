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
				MarkAllAsUnreadButton()
					.environmentObject(service)
				Divider()
				PreviousNextItemButtons()

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

		#if os(macOS)
		Settings {
			SettingsView()
				.environmentObject(service)
		}
		.windowToolbarStyle(.unified)
		#endif

    }
}
