import Foundation

/// Query-time provenance only. Never infer or rewrite the datum of saved data.
enum RestaurantCoordinateReference: String, Hashable, Sendable {
    case unspecified
    case wgs84
    case gcj02
}

struct RestaurantCoordinate: Hashable, Sendable {
    let latitude: Double
    let longitude: Double
    var reference: RestaurantCoordinateReference = .unspecified

    var isValid: Bool {
        (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
}

struct RestaurantCandidatePlaceIdentity: Hashable, Sendable {
    let provider: RestaurantPlaceProvider
    let externalID: String
    let isPrimary: Bool

    init(provider: RestaurantPlaceProvider, externalID: String, isPrimary: Bool = false) {
        self.provider = provider
        self.externalID = externalID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isPrimary = isPrimary
    }
}

struct RestaurantCandidate: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let address: String
    let city: String
    let district: String
    let latitude: Double
    let longitude: Double
    let appleMapItemIdentifier: String?
    let placeIdentities: [RestaurantCandidatePlaceIdentity]
    let distanceMeters: Double?
    let photoURL: URL?
    let phone: String?
    let websiteURL: URL?
    let openingHours: String?
    let categoryHints: [String]
    let coordinateReference: RestaurantCoordinateReference
    /// Ephemeral provider evidence for a name + independently resolved place query.
    /// Never written to Restaurant name/address or the saved record contract.
    var resolvedSearchQuery: String? = nil

    var coordinate: RestaurantCoordinate {
        RestaurantCoordinate(latitude: latitude, longitude: longitude, reference: coordinateReference)
    }

    init(
        id: UUID = UUID(),
        name: String,
        address: String,
        city: String = "",
        district: String = "",
        latitude: Double,
        longitude: Double,
        appleMapItemIdentifier: String? = nil,
        placeIdentities: [RestaurantCandidatePlaceIdentity] = [],
        distanceMeters: Double? = nil,
        photoURL: URL? = nil,
        phone: String? = nil,
        websiteURL: URL? = nil,
        openingHours: String? = nil,
        categoryHints: [String] = [],
        coordinateReference: RestaurantCoordinateReference = .unspecified
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        self.city = city.trimmingCharacters(in: .whitespacesAndNewlines)
        self.district = district.trimmingCharacters(in: .whitespacesAndNewlines)
        self.latitude = latitude
        self.longitude = longitude
        self.coordinateReference = coordinateReference
        let appleID = appleMapItemIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.appleMapItemIdentifier = appleID?.isEmpty == false ? appleID : nil
        self.placeIdentities = Self.normalizedIdentities(
            placeIdentities,
            appleMapItemIdentifier: self.appleMapItemIdentifier
        )
        self.distanceMeters = distanceMeters
        self.photoURL = photoURL
        self.phone = Self.normalizedOptional(phone)
        self.websiteURL = Self.normalizedWebURL(websiteURL)
        self.openingHours = Self.normalizedOptional(openingHours)
        self.categoryHints = Self.categoryLabels(categoryHints)
    }

    static func categoryLabels(_ values: [String]) -> [String] {
        let labels = ["MKPOICategoryRestaurant": "餐厅", "MKPOICategoryCafe": "咖啡馆", "MKPOICategoryBakery": "烘焙", "MKPOICategoryBrewery": "精酿啤酒", "MKPOICategoryWinery": "酒庄", "MKPOICategoryFoodMarket": "食品市场"]
        return Array(Set(values.map { value in
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return labels[text] ?? (text.hasPrefix("MKPOICategory") ? "" : text)
        }.filter { !$0.isEmpty })).sorted()
    }

    static func manual(
        id: UUID = UUID(),
        name: String,
        city: String,
        address: String,
        coordinate: RestaurantCoordinate
    ) -> RestaurantCandidate {
        RestaurantCandidate(
            id: id,
            name: name,
            address: address,
            city: city,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            placeIdentities: [
                RestaurantCandidatePlaceIdentity(
                    provider: .manual,
                    externalID: "tastemap:\(id.uuidString.lowercased())",
                    isPrimary: true
                )
            ]
        )
    }

    private static func normalizedIdentities(
        _ values: [RestaurantCandidatePlaceIdentity],
        appleMapItemIdentifier: String?
    ) -> [RestaurantCandidatePlaceIdentity] {
        var source = values.filter { !$0.externalID.isEmpty }
        if let appleMapItemIdentifier,
           !source.contains(where: { $0.provider == .appleMaps && $0.externalID == appleMapItemIdentifier }) {
            source.append(RestaurantCandidatePlaceIdentity(
                provider: .appleMaps,
                externalID: appleMapItemIdentifier,
                isPrimary: source.isEmpty
            ))
        }

        var seen = Set<String>()
        var result: [RestaurantCandidatePlaceIdentity] = []
        for value in source {
            let key = "\(value.provider.rawValue):\(value.externalID)"
            guard seen.insert(key).inserted else { continue }
            result.append(value)
        }
        guard !result.isEmpty else { return [] }

        let primaryIndex = result.firstIndex(where: \.isPrimary) ?? result.startIndex
        return result.enumerated().map { index, value in
            RestaurantCandidatePlaceIdentity(
                provider: value.provider,
                externalID: value.externalID,
                isPrimary: index == primaryIndex
            )
        }
    }

    private static func normalizedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private static func normalizedWebURL(_ value: URL?) -> URL? {
        guard let value,
              let scheme = value.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              value.host?.isEmpty == false else { return nil }
        return value
    }
}

#if !TASTEMAP_HYBRID_BRIDGE_CORE
extension DiscoveryRestaurantProjectionV1 {
    /// Provider-neutral conversion used only after an explicit viewer action.
    /// Public author Visits, notes and photos are intentionally not part of it.
    var restaurantCandidate: RestaurantCandidate {
        RestaurantCandidate(
            name: name,
            address: address,
            city: city,
            latitude: latitude,
            longitude: longitude,
            appleMapItemIdentifier: placeIdentities.first { $0.provider == .appleMaps }?.externalId,
            placeIdentities: placeIdentities.map {
                RestaurantCandidatePlaceIdentity(
                    provider: $0.provider,
                    externalID: $0.externalId,
                    isPrimary: $0.isPrimary
                )
            },
            photoURL: merchantImageUrl.flatMap(URL.init(string:)),
            phone: phone,
            websiteURL: websiteUrl.flatMap(URL.init(string:)),
            openingHours: openingHours,
            categoryHints: tags
        )
    }
}
#endif
