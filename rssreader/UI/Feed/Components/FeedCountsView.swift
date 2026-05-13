import SwiftUI

struct FeedCountsView: View {
	@EnvironmentObject private var service: FreshRSSService

	private var filteredItems: [FeedItem] {
		guard let selectedSubscriptionID = service.selectedSubscriptionID else {
			return service.items
		}
		return service.items.filter { $0.subscriptionID == selectedSubscriptionID }
	}

	private var countLabel: String {
		let totalCount = filteredItems.count
		let unreadCount = filteredItems.filter { !service.isMarkedRead($0) }.count

		if totalCount == 0 {
			switch service.sidebarMode {
			case .new:
				return "No new items"
			case .today:
				return "No items today"
			case .archive:
				return "No archived items"
			}
		}

		let itemLabel = totalCount == 1 ? "item" : "items"
		return "\(totalCount) \(itemLabel) • \(unreadCount) unread"
	}

	var body: some View {
		Text(service.isAuthenticated ? countLabel : "Not connected")
			.font(.subheadline)
			.foregroundStyle(.secondary)
			.lineLimit(1)
	}

}
