import SwiftUI

#if os(macOS)
struct AppCommands: Commands {
	let service: FreshRSSService

	var body: some Commands {
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
			Divider()

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
		}
	}
}
#endif
