import SwiftUI

@MainActor
enum AppBootstrap {
    static func configure() {
        // Keep remote image caching lightweight: memory-only, no persistent disk cache.
        URLCache.shared = URLCache(memoryCapacity: 24 * 1024 * 1024, diskCapacity: 0, diskPath: nil)
    }

    /// True when the app is only a host process for the unit-test bundle.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static func makeService() -> FreshRSSService {
        if isRunningTests {
            // An unsigned test host has no CloudKit or Keychain entitlements.
            return FreshRSSService(store: .ephemeral(), passwordStore: InMemoryPasswordStore(), readStateSync: NoOpReadStateSync())
        }
        return FreshRSSService()
    }

    static func makePreviewService(itemCount: Int = 10) -> FreshRSSService {
        let service = FreshRSSService()

        // Clear credentials so isConfigured returns false and no real network
        // calls are made when the preview canvas initialises the view hierarchy.
        service.serverURL = ""
        service.username = ""
        service.password = ""

        service.subscriptions = PreviewSampleData.subscriptions
        service.items = PreviewSampleData.items(count: itemCount)
        service.sidebarMode = .new
        service.isAuthenticated = true
        service.errorMessage = nil
        service.selectedSubscriptionID = nil

        return service
    }
}
