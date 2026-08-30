import Foundation

enum PublicShareEntityTypeV1: String, Codable, CaseIterable, Sendable {
    case restaurant
    case profile
    case list
}

struct CreatePublicShareRequestV1: Codable, Equatable, Sendable {
    let entityType: PublicShareEntityTypeV1
    let entityId: String
}

struct CreatePublicShareResponseV1: Codable, Equatable, Sendable {
    let apiVersion: Int
    let shareId: String
    let entityType: PublicShareEntityTypeV1
    let url: URL
}

struct PublicRestaurantShareV1: Codable, Equatable, Sendable {
    let shareId: String
    let name: String
    let address: String
    let city: String
    let cuisines: [String]
    let pricePerPerson: Double?
    let merchantImageUrl: URL?
}

struct PublicProfileShareStatisticsV1: Codable, Equatable, Sendable {
    let restaurantCount: Int
    let visitCount: Int
}

struct PublicProfileShareV1: Codable, Equatable, Sendable {
    let shareId: String
    let displayName: String
    let bio: String?
    let city: String?
    let statistics: PublicProfileShareStatisticsV1
}

struct PublicListRestaurantShareV1: Codable, Equatable, Identifiable, Sendable {
    var id: String { "\(name)|\(address)|\(city)" }
    let name: String
    let address: String
    let city: String
    let note: String?
    let merchantImageUrl: URL?
}

struct PublicListShareV1: Codable, Equatable, Sendable {
    let shareId: String
    let title: String
    let description: String
    let ownerDisplayName: String
    let isRanked: Bool
    let restaurantCount: Int
    let restaurants: [PublicListRestaurantShareV1]
}

enum PublicShareEntityV1: Equatable, Sendable {
    case restaurant(PublicRestaurantShareV1)
    case profile(PublicProfileShareV1)
    case list(PublicListShareV1)
}

struct PublicShareResponseV1: Decodable, Equatable, Sendable {
    let apiVersion: Int
    let shareId: String
    let entityType: PublicShareEntityTypeV1
    let entity: PublicShareEntityV1

    private enum CodingKeys: String, CodingKey { case apiVersion, shareId, entityType, entity }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        apiVersion = try values.decode(Int.self, forKey: .apiVersion)
        shareId = try values.decode(String.self, forKey: .shareId)
        entityType = try values.decode(PublicShareEntityTypeV1.self, forKey: .entityType)
        switch entityType {
        case .restaurant:
            entity = .restaurant(try values.decode(PublicRestaurantShareV1.self, forKey: .entity))
        case .profile:
            entity = .profile(try values.decode(PublicProfileShareV1.self, forKey: .entity))
        case .list:
            entity = .list(try values.decode(PublicListShareV1.self, forKey: .entity))
        }
    }
}

enum PublicShareRoute {
    static func shareID(from url: URL) -> String? {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count == 2, components[0] == "share",
              components[1].range(of: "^[A-Za-z0-9_-]{32}$", options: .regularExpression) != nil else {
            return nil
        }
        return components[1]
    }
}
