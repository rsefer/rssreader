import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
final class ScrollCheckState: ObservableObject {
    @Published var skipped: Set<Int> = []
    @Published var firstItem = 0
}

struct ScrollCheckList: View {
    @ObservedObject var state: ScrollCheckState
    @Namespace private var viewport

    var body: some View {
        List {
            ForEach(state.firstItem..<80, id: \.self) { id in
                Text("Article \(id)")
                    .frame(height: 80)
                    .background {
                        FeedItemScrollFrame(id: String(id), coordinateSpace: viewport)
                    }
            }
        }
        #if os(macOS)
        .listStyle(.sidebar)
        #else
        .listStyle(.plain)
        #endif
        .modifier(FeedSkipTracking(
            coordinateSpace: viewport,
            itemIDs: (state.firstItem..<80).map(String.init),
            context: state.firstItem
        ) { ids in
            state.skipped.formUnion(ids.compactMap(Int.init))
        })
    }
}

@MainActor
enum ScrollCheckSequence {
    static func run(state: ScrollCheckState, scroll: (CGFloat) -> Void) async throws {
        precondition(state.skipped.isEmpty, "Initial layout must not skip articles")
        scroll(3000)
        try await Task.sleep(for: .milliseconds(300))
        precondition(state.skipped.contains(0), "A first fast scroll must skip initially visible articles")
        scroll(0)
        try await Task.sleep(for: .milliseconds(300))
        state.skipped.removeAll()
        scroll(40)
        try await Task.sleep(for: .milliseconds(200))
        precondition(state.skipped.isEmpty, "A partially visible article must not be skipped")
        for offset in stride(from: 0, through: 600, by: 20) {
            scroll(CGFloat(offset))
            try await Task.sleep(for: .milliseconds(20))
        }
        try await Task.sleep(for: .milliseconds(200))
        precondition(state.skipped.contains(0), "Scrolling past the first article must skip it")
        precondition(!state.skipped.contains(20), "Unseen articles must not be skipped")
        let skippedOnForwardScroll = state.skipped
        for offset in stride(from: 600, through: 0, by: -20) {
            scroll(CGFloat(offset))
            try await Task.sleep(for: .milliseconds(20))
        }
        precondition(state.skipped == skippedOnForwardScroll, "Reverse scrolling must not skip articles")
        state.skipped.removeAll()
        state.firstItem = 10
        try await Task.sleep(for: .milliseconds(300))
        precondition(state.skipped.isEmpty, "Filtering must not skip articles")
        state.firstItem = 0
        try await Task.sleep(for: .milliseconds(300))
        scroll(0)
        try await Task.sleep(for: .milliseconds(300))
        scroll(3000)
        try await Task.sleep(for: .milliseconds(300))
        precondition(state.skipped.contains(0), "Fast scrolling must skip articles that pass the top")
        precondition(!state.skipped.contains(70), "Fast scrolling must not skip unseen articles below")
    }
}

#if os(macOS)
@main
struct FeedScrollChecks {
    @MainActor
    static func scrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView { return scrollView }
        for child in view.subviews {
            if let scrollView = scrollView(in: child) { return scrollView }
        }
        return nil
    }

    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let state = ScrollCheckState()
        let hostingView = NSHostingView(rootView: ScrollCheckList(state: state))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 350, height: 400),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.orderFront(nil)

        let checks = Task { @MainActor in
            try await Task.sleep(for: .seconds(1))
            guard let scrollView = scrollView(in: hostingView) else {
                fatalError("List did not create a native scroll view")
            }
            try await ScrollCheckSequence.run(state: state) { offset in
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: offset))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
            print("Feed scroll checks passed")
            window.orderOut(nil)
            exit(0)
        }
        Task { @MainActor in
            do {
                try await checks.value
            } catch {
                fputs("Feed scroll checks failed: \(error)\n", stderr)
                window.orderOut(nil)
                exit(1)
            }
        }
        app.run()
    }
}
#else
@main
struct FeedScrollChecks: App {
    @StateObject private var state = ScrollCheckState()

    @MainActor
    static func scrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView { return scrollView }
        for child in view.subviews {
            if let scrollView = scrollView(in: child) { return scrollView }
        }
        return nil
    }

    var body: some Scene {
        WindowGroup {
            ScrollCheckList(state: state)
                .task {
                    do {
                        try await Task.sleep(for: .seconds(1))
                        let window = UIApplication.shared.connectedScenes
                            .compactMap { $0 as? UIWindowScene }
                            .flatMap(\.windows)
                            .first { $0.isKeyWindow }
                        guard let window, let scrollView = Self.scrollView(in: window) else {
                            fatalError("List did not create a native scroll view")
                        }
                        let top = -scrollView.adjustedContentInset.top
                        try await ScrollCheckSequence.run(state: state) { offset in
                            scrollView.setContentOffset(CGPoint(x: 0, y: top + offset), animated: false)
                        }
                        print("Feed scroll checks passed")
                        exit(0)
                    } catch {
                        fputs("Feed scroll checks failed: \(error)\n", stderr)
                        exit(1)
                    }
                }
        }
    }
}
#endif
