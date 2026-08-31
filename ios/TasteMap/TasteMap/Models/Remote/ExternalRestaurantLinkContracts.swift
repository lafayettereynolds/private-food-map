import Foundation

enum ExternalRestaurantLinkSource: String, Codable, Sendable {
    case appleMaps = "apple_maps"
    case amap
    case genericURL = "generic_url"
    case sharedText = "shared_text"
}

enum ExternalRestaurantLinkConfidence: String, Codable, Sendable {
    case high = "HIGH"
    case medium = "MEDIUM"
    case low = "LOW"
    case none = "NONE"
}

struct ExternalRestaurantLinkRequestV1: Encodable, Sendable {
    let text: String
    let currentCity: String
}

struct ExternalRestaurantIdentitySuggestionV1: Codable, Equatable, Sendable {
    let provider: RestaurantPlaceProvider
    let externalId: String
    let isPrimary: Bool
}

struct ExternalRestaurantCandidateV1: Codable, Equatable, Sendable {
    let restaurantId: String?
    let amapPoiId: String?
    let name: String
    let address: String
    let city: String
    let latitude: Double
    let longitude: Double
    let merchantImageUrl: String?
    let phone: String?
    let openingHours: String?
    let placeIdentities: [ExternalRestaurantIdentitySuggestionV1]?

    var restaurantCandidate: RestaurantCandidate {
        var identities = (placeIdentities ?? []).map {
            RestaurantCandidatePlaceIdentity(
                provider: $0.provider,
                externalID: $0.externalId,
                isPrimary: $0.isPrimary
            )
        }
        if let amapPoiId = amapPoiId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !amapPoiId.isEmpty,
           !identities.contains(where: { $0.provider == .amap && $0.externalID == amapPoiId }) {
            identities.append(RestaurantCandidatePlaceIdentity(
                provider: .amap,
                externalID: amapPoiId,
                isPrimary: identities.isEmpty
            ))
        }
        return RestaurantCandidate(
            name: name,
            address: address,
            city: city,
            latitude: latitude,
            longitude: longitude,
            appleMapItemIdentifier: identities.first(where: { $0.provider == .appleMaps })?.externalID,
            placeIdentities: identities,
            photoURL: merchantImageUrl.flatMap(URL.init(string:)),
            phone: phone,
            openingHours: openingHours
        )
    }
}

struct ExternalRestaurantSearchFallbackV1: Codable, Equatable, Sendable {
    let keyword: String
    let city: String
    let addressHint: String
    let latitude: Double?
    let longitude: Double?
}

struct ExternalRestaurantLinkResponseV1: Codable, Equatable, Sendable {
    let apiVersion: Int?
    let sourceType: ExternalRestaurantLinkSource
    let sourceHost: String?
    let confidence: ExternalRestaurantLinkConfidence
    let matchType: String
    let candidates: [ExternalRestaurantCandidateV1]
    let searchFallback: ExternalRestaurantSearchFallbackV1?
    let sourceSuggestion: String
    let message: String
}
