import SwiftUI

struct RSSFeedFilterButton: View {
    let subscriptions: [FeedSubscription]
    let selectedSubscriptionID: String?
    let selectedTitle: String
    let onSelectAll: () -> Void
    let onSelect: (String) -> Void

	var body: some View {
		Menu {
			Button("All Feeds", action: onSelectAll)
			Divider()

			ForEach(subscriptions) { subscription in
				Button {
					onSelect(subscription.id)
				} label: {
					HStack {
						Text(subscription.title)
						if selectedSubscriptionID == subscription.id {
							Spacer()
							Image(systemName: "checkmark")
						}
					}
				}
			}
		} label: {
			Label(selectedTitle, systemImage: "line.3.horizontal.decrease.circle" + (selectedSubscriptionID != nil ? ".fill" : ""))
		}
	}
}
