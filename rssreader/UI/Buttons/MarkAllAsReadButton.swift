import SwiftUI

struct MarkAllAsReadButton: View {
	@EnvironmentObject private var service: FreshRSSService

	var body: some View {
		Button {
				Task { await service.markAllAsRead() }
		} label: {
				Label("Mark All as Read", systemImage: "checkmark.circle")
		}
		.labelStyle(.iconOnly)
		.help("Mark all loaded unread items as read")
		.disabled(service.unreadCount == 0 || service.isLoading)
	}
}
