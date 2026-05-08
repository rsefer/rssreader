import SwiftUI

struct SyncButton: View {
	@EnvironmentObject private var service: FreshRSSService

	var body: some View {
		if service.isLoading {
				ProgressView()
						.scaleEffect(0.6)
						.frame(width: 18, height: 18)
						.help("Syncing")
		} else {
				Button {
						Task { await service.syncCurrentMode() }
				} label: {
						Label("Sync", systemImage: "arrow.clockwise")
				}
				.labelStyle(.iconOnly)
				.help("\(service.sidebarMode.syncLabel)")
				.keyboardShortcut("r", modifiers: .command)
		}
		
	}
}
