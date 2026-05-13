import SwiftUI

struct RSSFeedFilterButton: View {
		let subscriptions: [FeedSubscription]
		@Binding var selectedSubscriptionID: String?
		let selectedTitle: String

	var body: some View {
		Menu {
			Button("All Feeds") { selectedSubscriptionID = nil }
			Divider()
			ForEach(subscriptions) { subscription in
				Button {
					selectedSubscriptionID = subscription.id
				} label: {
					Label(subscription.title, systemImage: selectedSubscriptionID == subscription.id ? "checkmark" : "")
				}
			}
		} label: {
			Image(systemName: "line.3.horizontal.decrease.circle" + (selectedSubscriptionID != nil ? ".fill" : ""))
				.imageScale(.large)
		}
	}
}
