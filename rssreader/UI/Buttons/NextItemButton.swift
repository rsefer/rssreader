import SwiftUI

struct NextItemButton: View {
	@FocusedValue(\.itemNavigation) private var itemNavigation

	var body: some View {
		Button("Next Item", systemImage: "chevron.down") {
				itemNavigation?.selectNext()
		}
		.disabled(!(itemNavigation?.canGoNext ?? false))
	}
}
