import SwiftUI

struct FeedView: View {
    @EnvironmentObject var service: FreshRSSService
    @Binding var selectedItemIDs: Set<String>
    let openSettings: () -> Void
	let isSidebarVisible: Bool
    @State private var searchText = ""
    @State private var visibleCount = 50
    private static let pageSize = 50

	init(
		selectedItemIDs: Binding<Set<String>>,
		openSettings: @escaping () -> Void,
		isSidebarVisible: Bool = true
	) {
		self._selectedItemIDs = selectedItemIDs
		self.openSettings = openSettings
		self.isSidebarVisible = isSidebarVisible
	}

	private var searchFieldPlacement: SearchFieldPlacement {
		#if os(macOS)
		return .sidebar
		#else
		return .toolbar
		#endif
	}

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

    private var visibleItems: [FeedItem] {
        Array(displayedItems.prefix(visibleCount))
    }

    var body: some View {
        platformContent
            .onChange(of: service.sidebarMode, initial: false) { _, _ in
                visibleCount = Self.pageSize
                Task { @MainActor in
                    selectedItemIDs.removeAll()
                    await service.syncCurrentMode()
                }
            }
            .onChange(of: searchText) { _, _ in visibleCount = Self.pageSize }
            .onChange(of: service.selectedSubscriptionID) { _, _ in visibleCount = Self.pageSize }
            .platformFeedStatusToolbar(errorMessage: service.errorMessage)
    }

    @ViewBuilder
    private var platformContent: some View {
			VStack(spacing: 0) {
				HStack(spacing: 8) {
					FeedModePicker(sidebarMode: $service.sidebarMode)
						.frame(maxWidth: .infinity)
					if !service.subscriptions.isEmpty {
						RSSFeedFilterButton(
							subscriptions: service.subscriptions,
							selectedSubscriptionID: service.selectedSubscriptionID,
							selectedTitle: selectedSubscription?.title ?? "All Feeds",
							onSelectAll: { service.selectedSubscriptionID = nil },
							onSelect: { service.selectedSubscriptionID = $0 }
						)
						.labelStyle(.iconOnly)
						.buttonStyle(.borderless)
					}
				}
					.frame(maxWidth: .infinity, alignment: .leading)
					#if os(macOS)
					.padding(.top, 8)
					#endif
					.padding(.bottom, service.selectedSubscriptionID != nil ? 8 : 16)
					.padding(.horizontal, 16)
				if ((service.selectedSubscriptionID) != nil) {
					Text(selectedSubscription?.title ?? " ")
						.font(.caption)
						.multilineTextAlignment(.center)
						.padding(.bottom, 8)
						.transition(.move(edge: .top).combined(with: .opacity))
				}
				Divider()
				Group {
					if service.items.isEmpty && !service.isLoading {
							platformFeedEmptyState(
									isLoading: service.isLoading,
									errorMessage: service.errorMessage,
									retry: { Task { await service.authenticate() } },
									sync: { await service.syncCurrentMode() }
							)
							.transition(.opacity)
					} else {
							List(selection: $selectedItemIDs) {
									Section {
											ForEach(visibleItems) { item in
																							let isRead = service.isMarkedRead(item)
													FeedItemRow(
															item: item,
																											isRead: isRead,
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
																	onOpen: { selectedItemIDs = [item.id] }
															)
													}
													#if os(iOS)
													.swipeActions(edge: .trailing, allowsFullSwipe: true) {
														ToggleItemReadStatusButton(item: item)
															.environmentObject(service)
															.tint(isRead ? .orange : .blue)
													}
													#endif
													.onAppear {
														if item.id == visibleItems.last?.id && visibleCount < displayedItems.count {
															visibleCount += Self.pageSize
														}
													}
											}
									}
									#if os(iOS)
									.listSectionSeparator(.hidden, edges: .top)
									#endif
							}
							#if os(macOS)
							.padding(.top, 8)
							#endif
							.platformFeedListStyle()
							.platformFeedListRefreshable {
									await service.syncCurrentMode()
							}
							.transition(.opacity)
					}
				}
					.animation(.easeInOut(duration: 0.2), value: service.selectedSubscriptionID)
					.animation(.easeInOut(duration: 0.2), value: service.items.isEmpty)
					.animation(.easeInOut(duration: 0.2), value: service.isLoading)
					.searchable(text: $searchText, placement: searchFieldPlacement, prompt: "Search articles")
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
			.navigationTitle("")
			.toolbar {
				#if os(macOS)
				if isSidebarVisible {
					ToolbarItem(placement: .principal) {
						FeedCountsView()
							.environmentObject(service)
					}
				}
				#else
				ToolbarItemGroup(placement: .navigation) {
					OpenSettingsButton(openSettings: openSettings)
				}
				ToolbarItem(placement: .principal) {
					FeedCountsView()
						.environmentObject(service)
				}
				ToolbarItemGroup(placement: .bottomBar) {
					SyncButton()
						.environmentObject(service)
					Spacer()
					MarkAllAsReadButton()
						.environmentObject(service)
				}
				#endif
			}
			#if os(iOS)
			.navigationBarTitleDisplayMode(.inline)
			#endif
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
}

private struct FeedViewPreviewContainer: View {
    @State private var selectedItemIDs: Set<String>
	@StateObject private var service: FreshRSSService

	init(preselectItem: Bool = false, preselectFeed: Bool = false) {
		let previewService = AppBootstrap.makePreviewService(itemCount: 10)

		if preselectItem,
			 let firstID = PreviewSampleData.firstItemID(itemCount: 10) {
			_selectedItemIDs = State(initialValue: [firstID])
		} else {
			_selectedItemIDs = State(initialValue: [])
		}

		if preselectFeed {
			previewService.selectedSubscriptionID = previewService.items.first?.subscriptionID
		}

		_service = StateObject(wrappedValue: previewService)
	}

    var body: some View {
			NavigationStack {
				FeedView(
					selectedItemIDs: $selectedItemIDs,
					openSettings: {},
					isSidebarVisible: true
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

#Preview("FeedView - First Feed Selected") {
	#if os(macOS)
	FeedViewPreviewContainer(preselectFeed: true)
		.frame(width: PreviewSampleData.previewFrame.width, height: PreviewSampleData.previewFrame.height)
	#else
	FeedViewPreviewContainer(preselectFeed: true)
	#endif
}
