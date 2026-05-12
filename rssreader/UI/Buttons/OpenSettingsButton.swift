import SwiftUI

struct OpenSettingsButton: View {
	let openSettings: () -> Void

	var body: some View {
		Button("Settings", systemImage: "gearshape") {
			openSettings()
		}
		.help("Settings")
		
	}
}
