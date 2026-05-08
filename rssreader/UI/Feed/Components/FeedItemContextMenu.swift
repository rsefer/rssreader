import SwiftUI

struct FeedItemContextMenu: View {
    @EnvironmentObject private var service: FreshRSSService

    let item: FeedItem
    let contextItems: [FeedItem]
    let onOpen: () -> Void
    let copyLink: (URL) -> Void

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
        Button(action: onOpen) {
            Label("Open", systemImage: "doc.text.magnifyingglass")
        }
        .disabled(isBatch)

        Button {
            Task { await service.markAsRead(contextItems) }
        } label: {
            Label(isBatch ? "Mark Selection as Read" : "Mark as Read", systemImage: "checkmark.circle")
        }
        .disabled(!anyUnread)

        Button {
            Task { await service.markAsUnread(contextItems) }
        } label: {
            Label(isBatch ? "Mark Selection as Unread" : "Mark as Unread", systemImage: "circle.dotted")
        }
        .disabled(!anyRead)

        if !isBatch, let url = item.url {
            Divider()

            OpenInBrowserButton(url: url)

            ShareLink(item: url, subject: Text(item.title), message: Text(item.title)) {
                Label("Share", systemImage: "square.and.arrow.up")
            }

            Button {
                copyLink(url)
            } label: {
                Label("Copy Link", systemImage: "link")
            }
        }
    }
}
