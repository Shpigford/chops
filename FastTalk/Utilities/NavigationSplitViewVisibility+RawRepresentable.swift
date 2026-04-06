import SwiftUI

// MARK: - @SceneStorage support for NavigationSplitViewVisibility

extension NavigationSplitViewVisibility: @retroactive RawRepresentable {
    public init?(rawValue: String) {
        switch rawValue {
        case "all": self = .all
        case "doubleColumn": self = .doubleColumn
        case "detailOnly": self = .detailOnly
        default: self = .all
        }
    }

    public var rawValue: String {
        switch self {
        case .doubleColumn: return "doubleColumn"
        case .detailOnly: return "detailOnly"
        default: return "all"
        }
    }
}
