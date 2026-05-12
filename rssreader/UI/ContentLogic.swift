import SwiftUI
import Combine

@MainActor
final class ContentLogic: ObservableObject {
    @Published var selectedItemIDs: Set<String> = []
    @Published var showSettings = false

    private var autoSyncTask: Task<Void, Never>?

    init(initialSelectedItemIDs: Set<String> = []) {
        selectedItemIDs = initialSelectedItemIDs
    }

    func openSettings() {
        showSettings = true
    }

    func clearSelection() {
        selectedItemIDs.removeAll()
    }

    func selectedItem(in items: [FeedItem]) -> FeedItem? {
        items.first(where: { selectedItemIDs.contains($0.id) })
    }

    func selectedIndex(in items: [FeedItem]) -> Int? {
        items.firstIndex(where: { selectedItemIDs.contains($0.id) })
    }

    func canGoPrevious(in items: [FeedItem]) -> Bool {
        guard let idx = selectedIndex(in: items) else { return false }
        return idx > 0
    }

    func canGoNext(in items: [FeedItem]) -> Bool {
        guard let idx = selectedIndex(in: items) else { return false }
        return idx < items.count - 1
    }

    func selectPrevious(in items: [FeedItem]) {
        guard let idx = selectedIndex(in: items), idx > 0 else { return }
        selectedItemIDs = [items[idx - 1].id]
    }

    func selectNext(in items: [FeedItem]) {
        guard let idx = selectedIndex(in: items), idx < items.count - 1 else { return }
        selectedItemIDs = [items[idx + 1].id]
    }

    func markSelectionAsReadIfNeeded(using service: FreshRSSService, items: [FeedItem]) {
        guard let item = selectedItem(in: items) else { return }
        Task {
            await service.markAsRead(item)
        }
    }

    func reconcileSelection(with items: [FeedItem]) {
        let validIDs = Set(items.map(\.id))
        selectedItemIDs = selectedItemIDs.intersection(validIDs)
    }

    func authenticateIfConfigured(using service: FreshRSSService) async {
        if service.isConfigured {
            await service.authenticateSilently()
        }
    }

    func handleScenePhase(_ phase: ScenePhase, service: FreshRSSService) {
        if phase == .active {
            startAutoSyncLoop(using: service)
        } else {
            stopAutoSyncLoop()
        }
    }

    func stopAutoSyncLoop() {
        autoSyncTask?.cancel()
        autoSyncTask = nil
    }

    private func startAutoSyncLoop(using service: FreshRSSService) {
        guard autoSyncTask == nil else { return }

        autoSyncTask = Task { [weak self] in
            guard let self else { return }
            await self.syncIfNeededForForegroundOrInterval(using: service)

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
                if Task.isCancelled { return }
                await self.syncIfNeededForForegroundOrInterval(using: service)
            }
        }
    }

    private func syncIfNeededForForegroundOrInterval(using service: FreshRSSService) async {
        guard service.shouldAutoSync() else { return }
        await service.syncCurrentMode()
    }
}
