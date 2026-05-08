import SwiftUI

struct ContentToolbarView: ToolbarContent {
    @EnvironmentObject private var service: FreshRSSService

    let canGoPrevious: Bool
    let canGoNext: Bool
    let showSettings: () -> Void
    let selectPrevious: () -> Void
    let selectNext: () -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            SyncButton()
							.environmentObject(service)
            MarkAllAsReadButton()
							.environmentObject(service)
        }

        ToolbarItemGroup(placement: .primaryAction) {
					PreviousItemButton()
						.labelStyle(.iconOnly)
						.help("Previous item")
					NextItemButton()
						.labelStyle(.iconOnly)
						.help("Next item")
            

            Button(action: showSettings) {
                Label("Settings", systemImage: "gearshape")
            }
            .labelStyle(.iconOnly)
            .help("Settings")
        }
    }
}
