import SwiftUI

struct NextItemButton: View {
	@Environment(\.itemNavigation) private var itemNavigation

	private var canNavigate: Bool {
		itemNavigation?.canGoNext ?? true
	}

	var body: some View {
		Button("Next Item", systemImage: "chevron.down") {
			if let itemNavigation {
				itemNavigation.selectNext()
			} else {
				NotificationCenter.default.post(name: .navigateToNextItem, object: nil)
			}
		}
		.disabled(!canNavigate)
		.labelStyle(.iconOnly)
	}
}
