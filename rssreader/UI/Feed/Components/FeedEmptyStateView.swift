import SwiftUI

struct FeedEmptyStateView: View {
    let isLoading: Bool
    let errorMessage: String?
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            if isLoading {
                ProgressView("Loading…")
            } else if let errorMessage {
                Image(systemName: "wifi.exclamationmark")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)

                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button("Retry", action: retry)
                    .buttonStyle(.bordered)
            } else {
                Image(systemName: "checkmark.circle")
                    .font(.largeTitle)
                    .foregroundStyle(.green)
                Text("All caught up!")
                    .font(.headline)
                Text("No unread articles.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
