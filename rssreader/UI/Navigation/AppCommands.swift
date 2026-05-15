import SwiftUI

#if os(macOS)
struct AppCommands: Commands {
	let service: FreshRSSService
	@Environment(\.openWindow) private var openWindow

	var body: some Commands {
		CommandGroup(replacing: .newItem) {}

		CommandGroup(replacing: .appSettings) {
			Button("Settings…") {
				openWindow(id: "settings")
			}
			.keyboardShortcut(",", modifiers: .command)
		}

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
