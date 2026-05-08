import SwiftUI

struct ItemNavigation {
    var selectPrevious: () -> Void
    var selectNext: () -> Void
    var canGoPrevious: Bool
    var canGoNext: Bool
}

extension Notification.Name {
    static let navigateToPreviousItem = Notification.Name("rssreader.navigateToPreviousItem")
    static let navigateToNextItem = Notification.Name("rssreader.navigateToNextItem")
}

struct ItemNavigationKey: EnvironmentKey {
    static let defaultValue: ItemNavigation? = nil
}

struct ItemNavigationFocusedKey: FocusedValueKey {
    typealias Value = ItemNavigation
}

extension EnvironmentValues {
    var itemNavigation: ItemNavigation? {
        get { self[ItemNavigationKey.self] }
        set { self[ItemNavigationKey.self] = newValue }
    }
}

extension FocusedValues {
    var itemNavigation: ItemNavigation? {
        get { self[ItemNavigationFocusedKey.self] }
        set { self[ItemNavigationFocusedKey.self] = newValue }
    }
}
