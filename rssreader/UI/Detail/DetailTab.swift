import Foundation

enum DetailTab: String, CaseIterable {
    case web = "Web"
    case reader = "Reader"

    var icon: String {
        switch self {
        case .web: return "globe"
        case .reader: return "text.alignleft"
        }
    }
}
