import Foundation
import SwiftData

@MainActor
struct LocalTasteMapStore {
    let context: ModelContext

    func restaurant(for candidate: RestaurantCandidate, among restaurants: [Restaurant]) throws -> Restaurant {
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
        if restaurant.remoteID == nil || restaurant.serverVersion == 0 {
            try enqueue(restaurant)
        }
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
        guard let restaurant = try context.fetch(FetchDescriptor<Restaurant>())
            .first(where: { $0.id == restaurantId && $0.deletedAt == nil }) else {
            throw LocalTasteMapStoreError.restaurantNotFound
        }
        if restaurant.remoteID == nil || restaurant.serverVersion == 0 {
            try enqueue(restaurant)
        }
        let visit = Visit(
            restaurantId: restaurantId,
            visitedAt: visitedAt,
            rating: rating,
            note: note,
            myActualSpend: myActualSpend,
            syncStatus: .pending
        )
        context.insert(visit)
        guard let restaurantRemoteID = restaurant.remoteID else {
            throw LocalTasteMapStoreError.restaurantRemoteIDMissing
        }
        try SwiftDataSyncQueue(context: context).enqueueUpsert(
            entityType: .visit,
            entityID: visit.remoteID ?? visit.id.uuidString,
            baseVersion: visit.serverVersion,
            payload: SyncRecordMapper.visitPayload(visit, restaurantRemoteID: restaurantRemoteID),
            timestamp: visit.updatedAt
        )
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
        guard let restaurant = try context.fetch(FetchDescriptor<Restaurant>())
            .first(where: { $0.id == visit.restaurantId }),
              let restaurantRemoteID = restaurant.remoteID else {
            throw LocalTasteMapStoreError.restaurantRemoteIDMissing
        }
        try SwiftDataSyncQueue(context: context).enqueueUpsert(
            entityType: .visit,
            entityID: visit.remoteID ?? visit.id.uuidString,
            baseVersion: visit.serverVersion,
            payload: SyncRecordMapper.visitPayload(visit, restaurantRemoteID: restaurantRemoteID),
            timestamp: visit.updatedAt
        )
        try context.save()
    }

    func delete(_ visit: Visit) throws {
        let queue = SwiftDataSyncQueue(context: context)
        guard let remoteID = visit.remoteID else {
            context.delete(visit)
            try context.save()
            return
        }
        if visit.serverVersion == 0 {
            try queue.removeMutations(entityType: .visit, entityID: remoteID)
            context.delete(visit)
        } else {
            visit.deletedAt = .now
            visit.updatedAt = visit.deletedAt ?? .now
            visit.syncStatus = .pending
            try queue.enqueueDelete(
                entityType: .visit,
                entityID: remoteID,
                baseVersion: visit.serverVersion,
                timestamp: visit.updatedAt
            )
        }
        try context.save()
    }

    func update(
        _ restaurant: Restaurant,
        name: String,
        address: String,
        latitude: Double,
        longitude: Double
    ) throws {
        restaurant.name = name
        restaurant.address = address
        restaurant.latitude = latitude
        restaurant.longitude = longitude
        restaurant.updatedAt = .now
        restaurant.syncStatus = .pending
        try enqueue(restaurant)
        try context.save()
    }

    func delete(_ restaurant: Restaurant) throws {
        let queue = SwiftDataSyncQueue(context: context)
        guard let remoteID = restaurant.remoteID else {
            context.delete(restaurant)
            try context.save()
            return
        }
        if restaurant.serverVersion == 0 {
            let hasVisits = try context.fetch(FetchDescriptor<Visit>())
                .contains { $0.restaurantId == restaurant.id && $0.deletedAt == nil }
            guard !hasVisits else { throw LocalTasteMapStoreError.restaurantHasVisits }
            try queue.removeMutations(entityType: .restaurant, entityID: remoteID)
            context.delete(restaurant)
        } else {
            restaurant.deletedAt = .now
            restaurant.updatedAt = restaurant.deletedAt ?? .now
            restaurant.syncStatus = .pending
            try queue.enqueueDelete(
                entityType: .restaurant,
                entityID: remoteID,
                baseVersion: restaurant.serverVersion,
                timestamp: restaurant.updatedAt
            )
        }
        try context.save()
    }

    private func enqueue(_ restaurant: Restaurant) throws {
        let remoteID = restaurant.remoteID ?? restaurant.id.uuidString
        restaurant.remoteID = remoteID
        restaurant.syncStatus = .pending
        try SwiftDataSyncQueue(context: context).enqueueUpsert(
            entityType: .restaurant,
            entityID: remoteID,
            baseVersion: restaurant.serverVersion,
            payload: SyncRecordMapper.restaurantPayload(restaurant),
            timestamp: restaurant.updatedAt
        )
    }
}

enum LocalTasteMapStoreError: Error {
    case restaurantNotFound
    case restaurantRemoteIDMissing
    case restaurantHasVisits
}

enum RestaurantDeduplicator {
    static func match(for candidate: RestaurantCandidate, in restaurants: [Restaurant]) -> Restaurant? {
        if let externalID = candidate.appleMapItemIdentifier,
           let match = restaurants.first(where: { $0.deletedAt == nil && $0.appleMapItemIdentifier == externalID }) {
            return match
        }

        let candidateName = normalized(candidate.name)
        let candidateAddress = normalized(candidate.address)
        return restaurants.first { restaurant in
            restaurant.deletedAt == nil
                && normalized(restaurant.name) == candidateName
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
