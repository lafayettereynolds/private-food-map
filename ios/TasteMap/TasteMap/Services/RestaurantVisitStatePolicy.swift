import Foundation

// Shared, read-only identity and status projection. Persistence reconciliation
// remains in LocalTasteMapStore; the Bridge Package uses this exact projection
// without importing the App's sync queue or mutating source records on reads.
enum RestaurantDeduplicator {
    enum MatchKind: Equatable {
        case exactProviderIdentity
        case probableCrossProvider
    }

    struct Match {
        let restaurant: Restaurant
        let kind: MatchKind
    }

    static func match(for candidate: RestaurantCandidate, in restaurants: [Restaurant]) -> Restaurant? {
        classifiedMatch(for: candidate, in: restaurants)?.restaurant
    }

    static func classifiedMatch(
        for candidate: RestaurantCandidate,
        in restaurants: [Restaurant]
    ) -> Match? {
        let candidateIdentityKeys = Set(candidate.placeIdentities.map(identityKey))
        if !candidateIdentityKeys.isEmpty,
           let match = restaurants.first(where: {
               $0.deletedAt == nil && !candidateIdentityKeys.isDisjoint(with: identityKeys(for: $0))
           }) {
            return Match(restaurant: match, kind: .exactProviderIdentity)
        }

        let candidateName = normalized(candidate.name)
        let candidateAddress = normalized(candidate.address)
        return restaurants.first { restaurant in
            guard restaurant.deletedAt == nil,
                  normalized(restaurant.name) == candidateName else { return false }
            let restaurantAddress = normalized(restaurant.address)
            let addressesCompatible = candidateAddress.isEmpty
                || restaurantAddress.isEmpty
                || restaurantAddress == candidateAddress
            let citiesCompatible = candidate.city.isEmpty
                || restaurant.city.isEmpty
                || normalizedCity(restaurant.city) == normalizedCity(candidate.city)
            return addressesCompatible && citiesCompatible && distanceInMeters(
                    latitudeA: restaurant.latitude,
                    longitudeA: restaurant.longitude,
                    latitudeB: candidate.latitude,
                    longitudeB: candidate.longitude
                ) < 80
        }.map { Match(restaurant: $0, kind: .probableCrossProvider) }
    }

    static func candidate(for restaurant: Restaurant) -> RestaurantCandidate {
        let record = restaurant.remoteRecordData.flatMap {
            try? JSONDecoder().decode(RestaurantJSONContractV1.self, from: $0)
        }
        return RestaurantCandidate(
            id: restaurant.id,
            name: restaurant.name,
            address: restaurant.address,
            city: restaurant.city,
            latitude: restaurant.latitude,
            longitude: restaurant.longitude,
            appleMapItemIdentifier: restaurant.appleMapItemIdentifier,
            placeIdentities: record?.placeIdentities.map {
                RestaurantCandidatePlaceIdentity(
                    provider: $0.provider,
                    externalID: $0.externalId,
                    isPrimary: $0.isPrimary
                )
            } ?? [],
            photoURL: record?.merchantImageUrl.flatMap(URL.init(string:)),
            phone: record?.phone,
            websiteURL: record?.websiteUrl.flatMap(URL.init(string:)),
            openingHours: record?.openingHours,
            categoryHints: record?.tags ?? []
        )
    }

    static func representsSamePlace(_ left: Restaurant, _ right: Restaurant) -> Bool {
        classifiedMatch(for: candidate(for: left), in: [right]) != nil
    }

    private static func identityKeys(for restaurant: Restaurant) -> Set<String> {
        var values = Set<String>()
        if let appleID = restaurant.appleMapItemIdentifier, !appleID.isEmpty {
            values.insert("\(RestaurantPlaceProvider.appleMaps.rawValue):\(appleID)")
        }
        if let data = restaurant.remoteRecordData,
           let record = try? JSONDecoder().decode(RestaurantJSONContractV1.self, from: data) {
            values.formUnion(record.placeIdentities.map(identityKey))
        }
        return values
    }

    nonisolated private static func identityKey(_ identity: RestaurantCandidatePlaceIdentity) -> String {
        "\(identity.provider.rawValue):\(identity.externalID)"
    }

    nonisolated private static func identityKey(_ identity: RestaurantPlaceIdentityContract) -> String {
        "\(identity.provider.rawValue):\(identity.externalId)"
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .filter { !$0.isWhitespace && !$0.isPunctuation }
    }

    private static func normalizedCity(_ value: String) -> String {
        let value = normalized(value)
        return value.hasSuffix("市") ? String(value.dropLast()) : value
    }

    private static func distanceInMeters(
        latitudeA: Double,
        longitudeA: Double,
        latitudeB: Double,
        longitudeB: Double
    ) -> Double {
        let latitudeScale = 111_000.0
        let longitudeScale = latitudeScale * cos((latitudeA + latitudeB) * .pi / 360)
        let latitudeDistance = (latitudeA - latitudeB) * latitudeScale
        let longitudeDistance = (longitudeA - longitudeB) * longitudeScale
        return hypot(latitudeDistance, longitudeDistance)
    }
}

/// Canonical status precedence shared by Native and Hybrid lists.
///
/// An active Visit makes the Restaurant visited even when an old import or a
/// sync conflict left its stored status as WantToGo. A duplicate WantToGo row
/// for the same physical place is also hidden when a visited row exists.
@MainActor
enum RestaurantVisitStatePolicy {
    struct Partition {
        let visited: [Restaurant]
        let wantToGo: [Restaurant]
    }

    static func partition(restaurants: [Restaurant], visits: [Visit]) -> Partition {
        let activeRestaurants = restaurants.filter { $0.deletedAt == nil }
        let activeRestaurantIDs = Set(activeRestaurants.map(\.id))
        let activeVisitRestaurantIDs = Set(visits.filter {
            $0.deletedAt == nil && activeRestaurantIDs.contains($0.restaurantId)
        }.map(\.restaurantId))
        // Stored status is historical metadata, not evidence of a remaining
        // Visit. Deleting the last Visit must remove the visited marker/count
        // without deleting the Restaurant, its lists or its other material.
        let visited = activeRestaurants.filter {
            activeVisitRestaurantIDs.contains($0.id)
        }
        let wantToGo = activeRestaurants.filter { candidate in
            guard candidate.status == .wantToGo,
                  !activeVisitRestaurantIDs.contains(candidate.id) else { return false }
            return !visited.contains { RestaurantDeduplicator.representsSamePlace(candidate, $0) }
        }
        return Partition(visited: visited, wantToGo: wantToGo)
    }
}
