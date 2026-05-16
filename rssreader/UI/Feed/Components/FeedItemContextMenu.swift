import SwiftUI

struct FeedItemContextMenu: View {
    @EnvironmentObject private var service: FreshRSSService
	@State private var isHeaderVisible = false

    let item: FeedItem
    let contextItems: [FeedItem]
    let onOpen: () -> Void

    private var anyUnread: Bool {
        contextItems.contains(where: { !service.isMarkedRead($0) })
    }

    private var anyRead: Bool {
        contextItems.contains(where: { service.isMarkedRead($0) })
    }

    private var isBatch: Bool {
        contextItems.count > 1
    }

    var body: some View {

        if isBatch {
					Button {
							Task { await service.markAsRead(contextItems) }
					} label: {
							Label(isBatch ? "Mark Selection as Read" : "Mark as Read", systemImage: "checkmark.rectangle.stack")
					}
					.disabled(!anyUnread)

					Button {
							Task { await service.markAsUnread(contextItems) }
					} label: {
							Label(isBatch ? "Mark Selection as Unread" : "Mark as Unread", systemImage: "circle.dotted.and.circle")
					}
					.disabled(!anyRead)

				} else {
					Button(action: onOpen) {
							Label("Open", systemImage: "doc.text.magnifyingglass")
					}
					.disabled(isBatch)
					Divider()
					ItemActionsButtons(item: item, isHeaderVisible: $isHeaderVisible)
				}
    }
}
