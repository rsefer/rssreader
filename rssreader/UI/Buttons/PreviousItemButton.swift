import SwiftUI

struct PreviousItemButton: View {
	@Environment(\.itemNavigation) private var itemNavigation

	private var canNavigate: Bool {
		itemNavigation?.canGoPrevious ?? true
	}

	var body: some View {
		Button("Previous Item", systemImage: "chevron.up") {
			if let itemNavigation {
				itemNavigation.selectPrevious()
			} else {
				NotificationCenter.default.post(name: .navigateToPreviousItem, object: nil)
			}
		}
		.help("Previous Item")
		.disabled(!canNavigate)
	}
}
