import Foundation
import SwiftData

@MainActor
struct LocalTasteMapStore {
    let context: ModelContext

    func restaurant(
        for candidate: RestaurantCandidate,
        among restaurants: [Restaurant],
        status: RestaurantStatus = .visited
    ) throws -> Restaurant {
        if let existing = RestaurantDeduplicator.match(for: candidate, in: restaurants) {
            return existing
        }

        let restaurant = Restaurant(
            name: candidate.name,
            address: candidate.address,
            latitude: candidate.latitude,
            longitude: candidate.longitude,
            appleMapItemIdentifier: candidate.appleMapItemIdentifier,
            status: status
        )
        context.insert(restaurant)
        if restaurant.remoteID == nil || restaurant.serverVersion == 0 {
            try enqueue(restaurant)
        }
        return restaurant
    }

    @discardableResult
    func addToWantToGo(
        candidate: RestaurantCandidate,
        among restaurants: [Restaurant]
    ) throws -> Restaurant {
        let restaurant = try restaurant(for: candidate, among: restaurants, status: .wantToGo)
        try context.save()
        return restaurant
    }

    @discardableResult
    func createVisit(
        restaurantId: UUID,
        visitedAt: Date = .now,
        rating: Double? = nil,
        valueRating: Double? = nil,
        environmentRating: Double? = nil,
        serviceRating: Double? = nil,
        note: String? = nil,
        myActualSpend: Decimal? = nil,
        diningMode: DiningMode = .dineIn,
        partySize: Int? = nil
    ) throws -> Visit {
        try createVisit(
            restaurantId: restaurantId,
            draft: VisitDraft(
                visitedAt: visitedAt,
                diningMode: diningMode,
                partySize: partySize,
                rating: rating,
                valueRating: valueRating,
                environmentRating: environmentRating,
                serviceRating: serviceRating,
                myActualSpend: myActualSpend,
                note: note ?? ""
            )
        )
    }

    @discardableResult
    func createVisit(restaurantId: UUID, draft: VisitDraft) throws -> Visit {
        var draft = draft
        var createdVisit: Visit?
        try context.transaction {
            try LocalCompanionSourceStore(context: context).materializeSelections(in: &draft)
            draft = try draft.validated()
            guard let restaurant = try context.fetch(FetchDescriptor<Restaurant>())
                .first(where: { $0.id == restaurantId && $0.deletedAt == nil }) else {
                throw LocalTasteMapStoreError.restaurantNotFound
            }
            let isTransitioningFromWantToGo = restaurant.status == .wantToGo
            if isTransitioningFromWantToGo {
                restaurant.status = .visited
                restaurant.updatedAt = .now
                restaurant.syncStatus = .pending
            }
            if isTransitioningFromWantToGo || restaurant.remoteID == nil || restaurant.serverVersion == 0 {
                try enqueue(restaurant)
            }
            let visit = Visit(
                restaurantId: restaurantId,
                visitedAt: draft.visitedAt,
                rating: draft.rating,
                valueRating: draft.valueRating,
                environmentRating: draft.environmentRating,
                serviceRating: draft.serviceRating,
                note: draft.note,
                myActualSpend: draft.myActualSpend,
                totalPrice: draft.totalPrice,
                pricePerPerson: draft.calculatedPricePerPerson,
                diningMode: draft.diningMode,
                visibility: draft.visibility,
                paymentMode: draft.paymentMode,
                queueDuration: draft.queueDuration,
                diningOccasions: draft.diningOccasions,
                diningOccasionText: draft.diningOccasionText,
                valueTags: draft.valueTags,
                environmentTags: draft.environmentTags,
                serviceTags: draft.serviceTags,
                noiseLevel: draft.noiseLevel,
                diningDuration: draft.diningDuration,
                portionLevel: draft.portionLevel,
                transportConvenience: draft.transportConvenience,
                specialNotes: draft.specialNotes,
                companionIDs: draft.companionIDs,
                companionNames: draft.companionNames,
                recommendationSourceID: draft.recommendationSourceID,
                recommendationSourceType: draft.recommendationSourceTypeRawValue.flatMap(RecommendationSourceType.init(rawValue:)),
                recommendationSourceUserID: draft.recommendationSourceUserID,
                recommendationSourceText: draft.recommendationSourceText,
                sharedMealID: draft.sharedMealID,
                partySize: draft.partySize,
                syncStatus: .pending
            )
            visit.paymentModeRawValue = draft.paymentModeRawValue
            visit.queueDurationRawValue = draft.queueDurationRawValue
            visit.diningOccasionRawValues = draft.diningOccasionRawValues
            visit.noiseLevelRawValue = draft.noiseLevelRawValue
            visit.diningDurationRawValue = draft.diningDurationRawValue
            visit.portionLevelRawValue = draft.portionLevelRawValue
            visit.transportConvenienceRawValue = draft.transportConvenienceRawValue
            visit.recommendationSourceTypeRawValue = draft.recommendationSourceTypeRawValue
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
            createdVisit = visit
        }
        guard let createdVisit else { throw LocalTasteMapStoreError.visitCreationFailed }
        return createdVisit
    }

    func update(
        _ visit: Visit,
        visitedAt: Date,
        rating: Double?,
        note: String?,
        myActualSpend: Decimal?
    ) throws {
        var draft = VisitDraft(visit: visit)
        draft.visitedAt = visitedAt
        draft.rating = rating
        draft.myActualSpend = myActualSpend
        draft.note = note ?? ""
        try update(visit, draft: draft)
    }

    func update(_ visit: Visit, draft: VisitDraft) throws {
        var draft = draft
        try context.transaction {
            try LocalCompanionSourceStore(context: context).materializeSelections(in: &draft)
            draft = try draft.validated()
            visit.visitedAt = draft.visitedAt
            visit.rating = Visit.validatedRating(draft.rating)
            visit.valueRating = Visit.validatedRating(draft.valueRating)
            visit.environmentRating = Visit.validatedRating(draft.environmentRating)
            visit.serviceRating = Visit.validatedRating(draft.serviceRating)
            visit.note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            visit.myActualSpend = draft.myActualSpend
            visit.totalPrice = draft.totalPrice
            visit.pricePerPerson = draft.calculatedPricePerPerson
            visit.diningMode = draft.diningMode
            visit.visibility = draft.visibility
            visit.paymentModeRawValue = draft.paymentModeRawValue
            visit.queueDurationRawValue = draft.queueDurationRawValue
            visit.diningOccasionRawValues = draft.diningOccasionRawValues
            visit.diningOccasionText = draft.diningOccasionText
                .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            visit.valueTags = draft.valueTags
            visit.environmentTags = draft.environmentTags
            visit.serviceTags = draft.serviceTags
            visit.noiseLevelRawValue = draft.noiseLevelRawValue
            visit.diningDurationRawValue = draft.diningDurationRawValue
            visit.portionLevelRawValue = draft.portionLevelRawValue
            visit.transportConvenienceRawValue = draft.transportConvenienceRawValue
            visit.specialNotes = draft.specialNotes
                .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            visit.companionIDs = draft.companionIDs
            visit.companionNames = draft.companionNames
            visit.recommendationSourceID = draft.recommendationSourceID
            visit.recommendationSourceTypeRawValue = draft.recommendationSourceTypeRawValue
            visit.recommendationSourceUserID = draft.recommendationSourceUserID
            visit.recommendationSourceText = draft.recommendationSourceText
                .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            visit.sharedMealID = draft.sharedMealID
            visit.partySize = draft.partySize
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
        }
    }

    func delete(_ visit: Visit) throws {
        try LocalDishStore(context: context).removeAssociations(for: visit.id)
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

    func updateBasics(
        _ restaurant: Restaurant,
        name: String,
        city: String
    ) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw LocalTasteMapStoreError.restaurantNameRequired
        }

        restaurant.name = trimmedName
        restaurant.city = city.trimmingCharacters(in: .whitespacesAndNewlines)
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
    case restaurantNameRequired
    case visitCreationFailed
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
