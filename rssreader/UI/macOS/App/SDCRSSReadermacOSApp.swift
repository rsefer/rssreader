import SwiftUI

#if MACOS_APP_TARGET
@main
struct SDCRSSReadermacOSApp: App {
    @StateObject private var service = AppBootstrap.makeService()
    @FocusedValue(\.itemNavigation) private var itemNavigation

    init() {
        AppBootstrap.configure()
    }

    var body: some Scene {
        WindowGroup {
            MacContentView()
                .environmentObject(service)
                .frame(minWidth: 900, minHeight: 600)
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

        Settings {
            SettingsView()
                .environmentObject(service)
        }
    }
}
#if DEBUG
private struct FeedViewPreviewContainer: View {
		@StateObject private var service = FreshRSSService()

		var body: some View {
                MacContentView()
                        .environmentObject(service)
		}
}

#Preview("FeedView") {
		FeedViewPreviewContainer()
}
#endif
#endif
