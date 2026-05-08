import SwiftUI

struct GlobalActionsButtons: View {
	@EnvironmentObject private var service: FreshRSSService
	let openSettings: () -> Void

	var body: some View {
		SyncButton()
			.environmentObject(service)
		MarkAllAsReadButton()
			.environmentObject(service)
		OpenSettingsButton(openSettings: openSettings)
		
	}
}
