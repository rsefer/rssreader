import SwiftUI

struct EmptyDetailPlaceholderView: View {
    let isConfigured: Bool
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "newspaper")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("Select an article to read")
                .font(.title3)
                .foregroundStyle(.secondary)

            if !isConfigured {
                Button("Open Settings", action: openSettings)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
