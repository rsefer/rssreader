import SwiftUI

struct PreviousItemButton: View {
	@FocusedValue(\.itemNavigation) private var itemNavigation

	var body: some View {
		Button("Previous Item", systemImage: "chevron.up") {
				itemNavigation?.selectPrevious()
		}
		.disabled(!(itemNavigation?.canGoPrevious ?? false))
	}
}
