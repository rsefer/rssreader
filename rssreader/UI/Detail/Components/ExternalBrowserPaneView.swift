import SwiftUI

struct ExternalBrowserPaneView: View {
    let url: URL
    let openInBrowser: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "safari")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("Opening in your default browser")
                .font(.title3)

            Text("This article's webpage is configured to open outside the app.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(action: openInBrowser) {
                Label("Open Again", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.borderedProminent)

            Text(url.absoluteString)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .textSelection(.enabled)
                .frame(maxWidth: 480)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
