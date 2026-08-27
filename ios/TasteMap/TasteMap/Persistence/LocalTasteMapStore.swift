import Foundation
import SwiftData

@MainActor
struct LocalTasteMapStore {
    let context: ModelContext

    func restaurant(for candidate: RestaurantCandidate, among restaurants: [Restaurant]) -> Restaurant {
        if let existing = RestaurantDeduplicator.match(for: candidate, in: restaurants) {
            return existing
        }

        let restaurant = Restaurant(
            name: candidate.name,
            address: candidate.address,
            latitude: candidate.latitude,
            longitude: candidate.longitude,
            appleMapItemIdentifier: candidate.appleMapItemIdentifier
        )
        context.insert(restaurant)
        return restaurant
    }

    @discardableResult
    func createVisit(
        restaurantId: UUID,
        visitedAt: Date = .now,
        rating: Double? = nil,
        note: String? = nil,
        myActualSpend: Decimal? = nil
    ) throws -> Visit {
        let visit = Visit(
            restaurantId: restaurantId,
            visitedAt: visitedAt,
            rating: rating,
            note: note,
            myActualSpend: myActualSpend,
            syncStatus: .pending
        )
        context.insert(visit)
        try context.save()
        return visit
    }

    func update(
        _ visit: Visit,
        visitedAt: Date,
        rating: Double?,
        note: String?,
        myActualSpend: Decimal?
    ) throws {
        visit.visitedAt = visitedAt
        visit.rating = Visit.validatedRating(rating)
        visit.note = note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        visit.myActualSpend = myActualSpend
        visit.updatedAt = .now
        visit.syncStatus = .pending
        try context.save()
    }

    func delete(_ visit: Visit) throws {
        context.delete(visit)
        try context.save()
    }
}

enum RestaurantDeduplicator {
    static func match(for candidate: RestaurantCandidate, in restaurants: [Restaurant]) -> Restaurant? {
        if let externalID = candidate.appleMapItemIdentifier,
           let match = restaurants.first(where: { $0.appleMapItemIdentifier == externalID }) {
            return match
        }

        let candidateName = normalized(candidate.name)
        let candidateAddress = normalized(candidate.address)
        return restaurants.first { restaurant in
            normalized(restaurant.name) == candidateName
                && normalized(restaurant.address) == candidateAddress
                && distanceInMeters(
                    latitudeA: restaurant.latitude,
                    longitudeA: restaurant.longitude,
                    latitudeB: candidate.latitude,
                    longitudeB: candidate.longitude
                ) < 80
        }
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .filter { !$0.isWhitespace && !$0.isPunctuation }
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

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
