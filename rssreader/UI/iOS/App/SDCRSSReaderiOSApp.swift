import SwiftUI

#if IOS_APP_TARGET
@main
struct SDCRSSReaderiOSApp: App {
	
	@StateObject private var service = AppBootstrap.makeService()

	init() {
			AppBootstrap.configure()
	}

    var body: some Scene {
        WindowGroup {
					IOSContentView()
							.environmentObject(service)
							.frame(maxWidth: .infinity, maxHeight: .infinity)
							.background(Color(.systemBackground))
        }
    }
}
#endif
