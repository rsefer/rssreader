import SwiftUI

struct SyncButton: View {
	@EnvironmentObject private var service: FreshRSSService

	var body: some View {
		Button {
				Task { await service.syncCurrentMode() }
		} label: {
				Label {
						Text(service.isLoading ? "Syncing" : "\(service.sidebarMode.syncLabel)")
				} icon: {
						if service.isLoading {
								Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
										.rotationEffect(.degrees(360))
										.animation(
												.linear(duration: 0.9).repeatForever(autoreverses: false),
												value: service.isLoading
										)
						} else {
								Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
						}
				}
		}
		.help(service.isLoading ? "Syncing" : "\(service.sidebarMode.syncLabel)")
		.keyboardShortcut("r", modifiers: .command)
		.disabled(service.isLoading)
	}
}
