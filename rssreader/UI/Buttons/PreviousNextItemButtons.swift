import SwiftUI

struct PreviousNextItemButtons: View {
	@Environment(\.itemNavigation) private var itemNavigation

	private var canNavigatePrevious: Bool {
		itemNavigation?.canGoPrevious ?? true
	}
	
	private var canNavigateNext: Bool {
		itemNavigation?.canGoNext ?? true
	}

	var body: some View {
		PreviousItemButton()
			.disabled(!canNavigatePrevious)
		NextItemButton()
			.disabled(!canNavigateNext)
	}
}
