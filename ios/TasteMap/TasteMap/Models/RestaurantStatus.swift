import Foundation

enum RestaurantStatus: String, Codable, CaseIterable, Sendable {
    case visited
    case wantToGo

    var title: String {
        switch self {
        case .visited: "去过"
        case .wantToGo: "想吃"
        }
    }

    var systemImage: String {
        switch self {
        case .visited: "checkmark.circle"
        case .wantToGo: "bookmark.fill"
        }
    }
}
