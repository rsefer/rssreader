import SwiftUI

enum AppBootstrap {
    static func configure() {
        // Keep remote image caching lightweight: memory-only, no persistent disk cache.
        URLCache.shared = URLCache(memoryCapacity: 24 * 1024 * 1024, diskCapacity: 0, diskPath: nil)
    }

    static func makeService() -> FreshRSSService {
        FreshRSSService()
    }
}
