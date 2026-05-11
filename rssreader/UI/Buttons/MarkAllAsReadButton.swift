import SwiftUI

struct MarkAllAsReadButton: View {
	@EnvironmentObject private var service: FreshRSSService

	var body: some View {
		Button {
				Task { await service.markAllAsRead() }
		} label: {
				Label("Mark All as Read", systemImage: "checkmark.rectangle.stack")
		}
		.help("Mark All as Read")
		.disabled(service.unreadCount == 0 || service.isLoading)
	}
}
