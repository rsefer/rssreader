import SwiftUI

struct OpenSettingsButton: View {
	let openSettings: () -> Void

	var body: some View {
		Button(action: openSettings) {
				Image(systemName: "gearshape")
		}
		.accessibilityLabel("Settings")
		.help("Settings")
		
	}
}
