import SwiftUI

#if os(iOS)
struct OtherContentView: View {
		@Environment(\.scenePhase) private var scenePhase
		@Environment(\.openURL) private var openURL
		@EnvironmentObject var service: FreshRSSService
		@StateObject private var logic = ContentLogic()

		private var isDetailPresented: Binding<Bool> {
				Binding(
						get: { selectedItem != nil },
						set: { isPresented in
								if !isPresented { logic.clearSelection() }
						}
				)
		}

		private var selectedItem: FeedItem? {
				logic.selectedItem(in: service.items)
		}

		private var canGoPrevious: Bool {
				logic.canGoPrevious(in: service.items)
		}

		private var canGoNext: Bool {
				logic.canGoNext(in: service.items)
		}

		private func selectPrevious() {
				logic.selectPrevious(in: service.items)
		}

		private func selectNext() {
				logic.selectNext(in: service.items)
		}

	let items = ["Apple", "Banana", "Orange", "Grape", "Mango"]

		var body: some View {
			List(items, id: \.self) { item in
									Text(item)
							}

		}

		@ViewBuilder
		private var detailContent: some View {
				if let item = selectedItem {
						DetailView(item: item)
								.environmentObject(service)
				} else {
						EmptyDetailPlaceholderView(
								isConfigured: service.isConfigured,
								openSettings: { logic.openSettings() }
						)
				}
		}

		private func isTextFieldFocused() -> Bool {
				PlatformCapabilities.isTextInputFocused()
		}
}

private struct OtherContentViewPreviewContainer: View {
	@StateObject private var service = AppBootstrap.makeService()

	var body: some View {
		OtherContentView()
			.environmentObject(service)
	}
}

#Preview {
	OtherContentViewPreviewContainer()
}
#endif
