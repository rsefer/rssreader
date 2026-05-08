import SwiftUI

extension View {
    @ViewBuilder
    func platformSettingsPresentation<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            self.fullScreenCover(isPresented: isPresented, content: content)
        } else {
            self.sheet(isPresented: isPresented, content: content)
        }
        #else
        self.sheet(isPresented: isPresented, content: content)
        #endif
    }

    @ViewBuilder
    func platformFeedListRefreshable(_ action: @escaping () async -> Void) -> some View {
        #if os(iOS)
        self.refreshable {
            await action()
        }
        #else
        self
        #endif
    }

    @ViewBuilder
    func platformMainToolbar(
        canGoPrevious: Bool,
        canGoNext: Bool,
        showSettings: @escaping () -> Void,
        selectPrevious: @escaping () -> Void,
        selectNext: @escaping () -> Void
    ) -> some View {
        #if os(macOS)
        self
            .navigationTitle("")
            .toolbar {
                ContentToolbarView(
                    canGoPrevious: canGoPrevious,
                    canGoNext: canGoNext,
                    showSettings: showSettings,
                    selectPrevious: selectPrevious,
                    selectNext: selectNext
                )
            }
        #else
        self
        #endif
    }

    @ViewBuilder
    func platformMainKeyboardHandlers(
        canGoPrevious: Bool,
        canGoNext: Bool,
        isTextFieldFocused: @escaping () -> Bool,
        selectPrevious: @escaping () -> Void,
        selectNext: @escaping () -> Void
    ) -> some View {
        #if os(macOS)
        self
            .onKeyPress("j") {
                guard canGoNext else { return .ignored }
                guard !isTextFieldFocused() else { return .ignored }
                selectNext()
                return .handled
            }
            .onKeyPress("k") {
                guard canGoPrevious else { return .ignored }
                guard !isTextFieldFocused() else { return .ignored }
                selectPrevious()
                return .handled
            }
        #else
        self
        #endif
    }

    @ViewBuilder
    func platformOpenSelectedItemShortcut(url: URL?, openURL: @escaping (URL) -> Void) -> some View {
        self.background {
            #if os(macOS)
            if let url {
                Button("") { openURL(url) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .hidden()
            }
            #endif
        }
    }

    @ViewBuilder
    func platformFeedStatusToolbar(errorMessage: String?) -> some View {
        #if os(macOS)
        self.toolbar {
            ToolbarItem(placement: .status) {
                if let error = errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                        .lineLimit(1)
                        .help(error)
                }
            }
        }
        #else
        self
        #endif
    }

    @ViewBuilder
    func platformFeedListStyle() -> some View {
        #if os(iOS)
        self.listStyle(.plain)
        #else
        self.listStyle(.sidebar)
        #endif
    }
}

@ViewBuilder
func platformFeedEmptyState(
    isLoading: Bool,
    errorMessage: String?,
    retry: @escaping () -> Void,
    sync: @escaping () async -> Void
) -> some View {
    #if os(iOS)
    ScrollView {
        FeedEmptyStateView(
            isLoading: isLoading,
            errorMessage: errorMessage,
            retry: retry
        )
    }
    .refreshable {
        await sync()
    }
    #else
    FeedEmptyStateView(
        isLoading: isLoading,
        errorMessage: errorMessage,
        retry: retry
    )
    #endif
}
