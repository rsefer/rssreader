import Foundation

enum ContentTab: String, CaseIterable {
    case web = "Web"
    case reader = "Reader"
    case content = "Content"

    var icon: String {
        switch self {
        case .web: return "globe"
        case .reader: return "text.alignleft"
        case .content: return "doc.text"
        }
    }
}
