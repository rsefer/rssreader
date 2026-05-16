import SwiftUI

struct ToggleDetailHeader: View {
	@Binding var isHeaderVisible: Bool

	var body: some View {
		Button(isHeaderVisible ? "Hide Info" : "Show Info", systemImage: isHeaderVisible ? "info.circle.fill" : "info.circle") {
			isHeaderVisible.toggle()
		}
		.help(isHeaderVisible ? "Hide Info" : "Show Info")
	}
}
