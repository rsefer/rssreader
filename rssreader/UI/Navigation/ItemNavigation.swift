import SwiftUI

struct ItemNavigation {
    var selectPrevious: () -> Void
    var selectNext: () -> Void
    var canGoPrevious: Bool
    var canGoNext: Bool
}

struct ItemNavigationKey: FocusedValueKey {
    typealias Value = ItemNavigation
}

extension FocusedValues {
    var itemNavigation: ItemNavigation? {
        get { self[ItemNavigationKey.self] }
        set { self[ItemNavigationKey.self] = newValue }
    }
}
