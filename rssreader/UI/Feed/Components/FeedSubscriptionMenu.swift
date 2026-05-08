import SwiftUI

struct FeedSubscriptionMenu: View {
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
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease.circle" + (selectedSubscriptionID != nil ? ".fill" : ""))
                Text(selectedTitle)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
