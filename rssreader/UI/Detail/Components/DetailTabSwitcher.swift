import SwiftUI

struct DetailTabSwitcher: View {
	@Binding var activeTab: ContentTab
	let hasWebURL: Bool

	var body: some View {
		HStack(spacing: 0) {
			ForEach(ContentTab.allCases, id: \.self) { tab in
				Button {
					activeTab = tab
				} label: {
					Image(systemName: tab.icon)
						.font(.system(size: 17, weight: .medium))
						.frame(width: 40, height: 32)
						.foregroundStyle(activeTab == tab ? .primary : .secondary)
						.background {
							if activeTab == tab {
								RoundedRectangle(cornerRadius: 18, style: .continuous)
									.fill(.quaternary)
							}
						}
				}
				.buttonStyle(.plain)
				.disabled(tab == .web && !hasWebURL)
				.accessibilityLabel(tab.rawValue)
			}
		}
	}
}
