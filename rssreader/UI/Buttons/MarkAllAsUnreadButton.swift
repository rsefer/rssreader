import SwiftUI

struct MarkAllAsUnreadButton: View {
	@EnvironmentObject private var service: FreshRSSService

	var body: some View {
		Button("Mark All as Unread") {
				Task { await service.markAllAsUnread() }
		}
	}
}
