import SwiftUI

struct FeedScrollFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct FeedItemScrollFrame: View {
    let id: String
    let coordinateSpace: Namespace.ID

    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: FeedScrollFramesKey.self,
                value: [id: proxy.frame(in: .named(coordinateSpace))]
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct FeedScrollTracker {
    private var visibleIDs: Set<String> = []

    mutating func update(frames: [String: CGRect], itemIDs: [String], height: CGFloat) -> Set<String> {
        guard height > 0 else { return [] }
        let indices = Dictionary(uniqueKeysWithValues: itemIDs.enumerated().map { ($1, $0) })
        let currentlyVisibleIDs = Set(frames.compactMap { id, frame in
            frame.maxY > 0 && frame.minY < height && indices[id] != nil ? id : nil
        })
        guard let firstVisibleIndex = currentlyVisibleIDs.compactMap({ indices[$0] }).min() else {
            return []
        }
        // A virtualized List can discard a row before reporting its final offscreen frame.
        let skipped = visibleIDs.filter { id in
            guard let index = indices[id] else { return false }
            return index < firstVisibleIndex
        }
        visibleIDs = currentlyVisibleIDs
        return skipped
    }
}

struct FeedSkipTracking<Context: Hashable>: ViewModifier {
    let coordinateSpace: Namespace.ID
    let itemIDs: [String]
    let context: Context
    let onSkip: (Set<String>) -> Void
    @State private var tracker = FeedScrollTracker()
    @State private var previousContext: Context?
    @State private var viewportHeight: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .coordinateSpace(name: coordinateSpace)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                viewportHeight = height
            }
            .onPreferenceChange(FeedScrollFramesKey.self) { frames in
                if previousContext != context {
                    tracker = FeedScrollTracker()
                    previousContext = context
                }
                let skipped = tracker.update(frames: frames, itemIDs: itemIDs, height: viewportHeight)
                if !skipped.isEmpty {
                    onSkip(skipped)
                }
            }
    }
}
