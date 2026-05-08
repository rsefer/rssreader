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
            Button(action: selectPrevious) {
                Label("Previous Item", systemImage: "chevron.up")
            }
            .labelStyle(.iconOnly)
            .help("Previous item")
            .disabled(!canGoPrevious)
					
					NextItemButton()
						.labelStyle(.iconOnly)
						.help("Next item")
            Button(action: selectNext) {
                Label("Next Item", systemImage: "chevron.down")
            }
            .labelStyle(.iconOnly)
            .help("Next item")
            .disabled(!canGoNext)

            Button(action: showSettings) {
                Label("Settings", systemImage: "gearshape")
            }
            .labelStyle(.iconOnly)
            .help("Settings")
        }
    }
}
