import Foundation

/// Boundary for Task 09 to supply a real, privacy-reviewed public Restaurant URL.
/// The default implementation intentionally returns nil: this task must not invent
/// a host or expose a private deep link as if it were publicly shareable.
protocol RestaurantPublicURLProviding: Sendable {
    func publicURL(forRestaurantGlobalID globalID: String) -> URL?
}

struct UnconfiguredRestaurantPublicURLProvider: RestaurantPublicURLProviding {
    func publicURL(forRestaurantGlobalID globalID: String) -> URL? { nil }
}

struct RestaurantSharePayload: Equatable, Sendable {
    let subject: String
    let message: String
    let publicURL: URL?

    var activityText: String {
        guard let publicURL else { return message }
        return "\(message)\n\(publicURL.absoluteString)"
    }
}

@MainActor
enum RestaurantSharingService {
    static func payload(
        restaurant: Restaurant,
        metadata: RestaurantDetailMetadata,
        publicURLProvider: any RestaurantPublicURLProviding = UnconfiguredRestaurantPublicURLProvider()
    ) -> RestaurantSharePayload {
        var publicFacts = [restaurant.name]
        if !restaurant.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            publicFacts.append(restaurant.address)
        } else if !restaurant.city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            publicFacts.append(restaurant.city)
        }
        if let referencePrice = metadata.referencePrice {
            publicFacts.append("参考人均 \(RestaurantDetailFormatting.currency(referencePrice))")
        }

        // Deliberately excludes visits, personal ratings, spend, companions,
        // recommendation sources, long-term notes and private photo URLs.
        return RestaurantSharePayload(
            subject: restaurant.name,
            message: publicFacts.joined(separator: " · "),
            publicURL: publicURLProvider.publicURL(
                forRestaurantGlobalID: restaurant.remoteID ?? restaurant.id.uuidString.lowercased()
            )
        )
    }
}

struct RestaurantDetailsUpdate: Equatable, Sendable {
    let name: String
    let address: String
    let city: String
    let status: RestaurantStatus
    let phone: String?
    let openingHours: String?
    let referencePrice: Decimal?
    let longTermNote: String?
    let markerType: RestaurantJSONContractV1.RestaurantMarkerTypeContract
    let markerPhotoID: String?
    let markerEmoji: String
}
