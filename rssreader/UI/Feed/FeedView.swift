import SwiftUI

struct FeedView: View {
    @EnvironmentObject var service: FreshRSSService
    @Binding var selectedItemIDs: Set<String>
    let openSettings: () -> Void
    @State private var searchText = ""

    private var selectedSubscription: FeedSubscription? {
        guard let id = service.selectedSubscriptionID else { return nil }
        return service.subscriptions.first { $0.id == id }
    }

    private var displayedItems: [FeedItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return service.items.filter { item in
            let matchesQuery = query.isEmpty || matchesSearch(item, query: query)
            let matchesSub = service.selectedSubscriptionID == nil || item.subscriptionID == service.selectedSubscriptionID
            return matchesQuery && matchesSub
        }
    }

	@ViewBuilder
	var feedSubscriptionMenuDisplay: some View {
		if !service.subscriptions.isEmpty {
			FeedSubscriptionMenu(
					subscriptions: service.subscriptions,
					selectedSubscriptionID: service.selectedSubscriptionID,
					selectedTitle: selectedSubscription?.title ?? "All Feeds",
					onSelectAll: { service.selectedSubscriptionID = nil },
					onSelect: { service.selectedSubscriptionID = $0 }
			)
		}
	}

	@ViewBuilder
	var feedMainListDisplay: some View {
		if service.items.isEmpty && !service.isLoading {
				platformFeedEmptyState(
						isLoading: service.isLoading,
						errorMessage: service.errorMessage,
						retry: { Task { await service.authenticate() } },
						sync: { await service.syncCurrentMode() }
				)
		} else {
				List(displayedItems, selection: $selectedItemIDs) { item in
						FeedItemRow(
								item: item,
								isRead: service.isMarkedRead(item),
								loadImages: service.loadArticleImages,
								thumbnailSize: CGFloat(service.articleThumbnailSize),
								thumbnailAspectRatio: service.articleThumbnailAspectRatio,
								thumbnailDisplayMode: service.thumbnailDisplayMode
						)
								.tag(item.id)
								.contextMenu {
										FeedItemContextMenu(
												item: item,
												contextItems: contextSelection(for: item),
												onOpen: { selectedItemIDs = [item.id] },
												copyLink: copyLink
										)
								}
				}
				.platformFeedListStyle()
				.platformFeedListRefreshable {
						await service.syncCurrentMode()
				}
		}
	}


    var body: some View {
        platformContent
            .onChange(of: service.sidebarMode, initial: false) { _, _ in
                Task { @MainActor in
                    selectedItemIDs.removeAll()
                    await service.syncCurrentMode()
                }
            }
            .platformFeedStatusToolbar(errorMessage: service.errorMessage)
    }

    @ViewBuilder
    private var platformContent: some View {
        #if os(iOS)
        Group {
            feedMainListDisplay
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                FeedModePicker(sidebarMode: $service.sidebarMode)
                feedSubscriptionMenuDisplay
                Divider()
            }
            .background(Color(.systemBackground))
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search articles")
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                SyncButton()
                    .environmentObject(service)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                MarkAllAsReadButton()
                    .environmentObject(service)
                OpenSettingsButton(openSettings: openSettings)
            }
        }
        #elseif os(macOS)
        VStack(spacing: 0) {
            FeedModePicker(sidebarMode: $service.sidebarMode)
            feedSubscriptionMenuDisplay
            macSearchBar
            feedMainListDisplay
            FeedSidebarFooterView(
                statusText: service.isAuthenticated ? countLabel : "Not connected",
                openSettings: openSettings
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.background)
        .navigationTitle("")
        #endif
    }

    @ViewBuilder
    private var macSearchBar: some View {
        #if os(macOS)
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
            TextField("Search articles", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
        #endif
    }

    private var countLabel: String {
        let totalCount = service.items.count
        let unreadCount = service.unreadCount

        if totalCount == 0 {
            switch service.sidebarMode {
            case .new:
                return "No new items, 0 unread"
            case .today:
                return "No items today, 0 unread"
            case .archive:
                return "No archived items, 0 unread"
            }
        }

        let itemLabel = totalCount == 1 ? "item" : "items"
        return "\(totalCount) \(itemLabel) • \(unreadCount) unread"
    }

    private func matchesSearch(_ item: FeedItem, query: String) -> Bool {
        item.title.lowercased().contains(query) ||
        item.publication.lowercased().contains(query) ||
        (item.author?.lowercased().contains(query) ?? false)
    }

    private func contextSelection(for item: FeedItem) -> [FeedItem] {
        if selectedItemIDs.contains(item.id) {
            let selected = displayedItems.filter { selectedItemIDs.contains($0.id) }
            if !selected.isEmpty {
                return selected
            }
        }
        return [item]
    }

    private func copyLink(_ url: URL) {
        PlatformCapabilities.copyToPasteboard(url.absoluteString)
    }
}

private struct FeedViewPreviewContainer: View {
    @State private var selectedItemIDs: Set<String>
	@StateObject private var service = AppBootstrap.makePreviewService(itemCount: 10)

	init(preselectItem: Bool = false) {
		if preselectItem,
			 let firstID = PreviewSampleData.firstItemID(itemCount: 10) {
			_selectedItemIDs = State(initialValue: [firstID])
		} else {
			_selectedItemIDs = State(initialValue: [])
		}
	}

    var body: some View {
			NavigationStack {
				FeedView(
					selectedItemIDs: $selectedItemIDs,
					openSettings: {}
				)
				.environmentObject(service)
			}
    }
}

#Preview("FeedView") {
	#if os(macOS)
	FeedViewPreviewContainer()
		.frame(width: PreviewSampleData.previewFrame.width, height: PreviewSampleData.previewFrame.height)
	#else
	FeedViewPreviewContainer()
	#endif
}

#Preview("FeedView - Item Selected") {
	#if os(macOS)
	FeedViewPreviewContainer(preselectItem: true)
		.frame(width: PreviewSampleData.previewFrame.width, height: PreviewSampleData.previewFrame.height)
	#else
	FeedViewPreviewContainer(preselectItem: true)
	#endif
}
