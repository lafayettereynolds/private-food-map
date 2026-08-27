import Foundation

enum DiningMode: String, Codable, CaseIterable, Identifiable {
    case dineIn = "dine_in"
    case takeout

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dineIn: "到店"
        case .takeout: "外卖"
        }
    }

    var systemImage: String {
        switch self {
        case .dineIn: "fork.knife"
        case .takeout: "takeoutbag.and.cup.and.straw.fill"
        }
    }
}
