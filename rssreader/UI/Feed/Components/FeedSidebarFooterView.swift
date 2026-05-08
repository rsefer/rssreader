import SwiftUI

struct FeedSidebarFooterView: View {
    let statusText: String
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }
}
