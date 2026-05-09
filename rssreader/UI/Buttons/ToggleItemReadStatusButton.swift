import SwiftUI

struct ToggleItemReadStatusButton: View {
	let item: FeedItem
	
	@EnvironmentObject private var service: FreshRSSService

	var body: some View {
		Button(service.isMarkedRead(item) ? "Mark as Unread" : "Mark as Read", systemImage: service.isMarkedRead(item) ? "circle.dotted" : "checkmark.circle.fill") {
			Task {
				if service.isMarkedRead(item) {
					await service.markAsUnread(item)
				} else {
					await service.markAsRead(item)
				}
			}
		}
		.help(service.isMarkedRead(item) ? "Mark as Unread" : "Mark as Read")
		.disabled(service.isLoading)
		
	}
}
