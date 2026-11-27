import SwiftUI

struct SaveToKarakeepButton: View {
    let item: FeedItem
    @ObservedObject var service: KarakeepService

    var body: some View {
        Button("Save to Karakeep", systemImage: "bookmark") {
            guard service.isConfigured else {
                service.saveFeedback = .init(
                    message: "Add your server URL and API key in Settings > Karakeep first.", isError: true
                )
                return
            }
            service.saveFeedback = .init(message: "Saving to Karakeep...")
            Task { @MainActor in
                do {
                    let result = try await service.save(item)
                    let links = try KarakeepClient.bookmarkLinks(
                        server: service.serverURL, bookmarkID: result.bookmarkID
                    )
                    let message: String
                    switch result {
                    case .saved:
                        message = "Saved to Karakeep."
                    case .alreadyExists:
                        message = "This article is already in Karakeep."
                    }
                    service.saveFeedback = .init(message: message, bookmarkLinks: links)
                } catch {
                    service.saveFeedback = .init(
                        message: "Could not save to Karakeep: \(error.localizedDescription)", isError: true
                    )
                }
            }
        }
        .disabled(item.url == nil || service.isSaving)
        .help("Save this article to Karakeep")
    }
}

struct KarakeepSaveFeedback: ViewModifier {
    @ObservedObject var service: KarakeepService
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content
        .safeAreaInset(edge: .bottom) {
            if let feedback = service.saveFeedback {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        if service.isSaving {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityLabel("Saving to Karakeep")
                        } else {
                            Image(systemName: feedback.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(feedback.isError ? Color.red : Color.green)
                                .accessibilityHidden(true)
                        }
                        Text(feedback.message)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !service.isSaving {
                        HStack {
                            if let links = feedback.bookmarkLinks {
                                Button("Open Karakeep", systemImage: "arrow.up.forward.app") {
                                    openURL(links.appURL) { accepted in
                                        if !accepted {
                                            openURL(links.webURL) { webAccepted in
                                                if !webAccepted {
                                                    service.saveFeedback = .init(
                                                        message: "The bookmark was saved, but Karakeep could not be opened.",
                                                        isError: true
                                                    )
                                                }
                                            }
                                        }
                                    }
                                }
                                .buttonStyle(.bordered)
                            }
                            Spacer()
                            Button("Dismiss") { service.saveFeedback = nil }
                                .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: 480)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .padding(12)
            }
        }
    }
}
