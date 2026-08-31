import Foundation
import SwiftData

@MainActor
struct LocalTasteMapStore {
    let context: ModelContext

    func restaurant(
        for candidate: RestaurantCandidate,
        among restaurants: [Restaurant],
        status: RestaurantStatus = .visited,
        actorUserID: String? = nil
    ) throws -> Restaurant {
        let ownerUserID = LocalAccountOwner.normalized(actorUserID ?? LocalAccountOwner.guest)
        let ownedRestaurants = restaurants.filter { $0.ownerUserID == ownerUserID }
        if let existing = RestaurantDeduplicator.match(for: candidate, in: ownedRestaurants) {
            if try merge(candidate: candidate, into: existing) {
                existing.updatedAt = .now
                try enqueue(existing)
            }
            return existing
        }

        let restaurant = Restaurant(
            ownerUserID: ownerUserID,
            name: candidate.name,
            address: candidate.address,
            latitude: candidate.latitude,
            longitude: candidate.longitude,
            appleMapItemIdentifier: candidate.appleMapItemIdentifier,
            city: candidate.city,
            status: status
        )
        // Preserve the legacy extension point used by Discovery: a candidate
        // without provider evidence is intentionally left unassigned so the
        // calling module can supply its authoritative identity contract before
        // the transaction is saved. Explicit manual and provider-backed
        // candidates always carry an identity and are persisted immediately.
        if !candidate.placeIdentities.isEmpty {
            restaurant.remoteRecordData = try recordData(
                for: restaurant,
                candidateIdentities: candidate.placeIdentities,
                replacingGeneratedIdentity: true
            )
        }
        context.insert(restaurant)
        if restaurant.remoteID == nil || restaurant.serverVersion == 0 {
            try enqueue(restaurant)
        }
        return restaurant
    }

    @discardableResult
    func addToWantToGo(
        candidate: RestaurantCandidate,
        among restaurants: [Restaurant],
        actorUserID: String? = nil
    ) throws -> Restaurant {
        let restaurant = try restaurant(
            for: candidate,
            among: restaurants,
            status: .wantToGo,
            actorUserID: actorUserID
        )
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
    func createVisit(
        restaurantId: UUID,
        draft: VisitDraft,
        actorUserID: String? = nil
    ) throws -> Visit {
        var createdVisit: Visit?
        try context.transaction {
            createdVisit = try createVisitInCurrentTransaction(
                restaurantId: restaurantId,
                draft: draft,
                actorUserID: actorUserID
            )
        }
        guard let createdVisit else { throw LocalTasteMapStoreError.visitCreationFailed }
        return createdVisit
    }

    /// Used by aggregate stores that already own the surrounding transaction.
    /// Keeping this body save-free lets Visit, Dish, associations, and their
    /// mutations commit or roll back as one business graph.
    func createVisitInCurrentTransaction(
        restaurantId: UUID,
        draft: VisitDraft,
        actorUserID: String? = nil
    ) throws -> Visit {
        var draft = draft
        guard let restaurant = try context.fetch(FetchDescriptor<Restaurant>())
            .first(where: { $0.id == restaurantId && $0.deletedAt == nil }) else {
            throw LocalTasteMapStoreError.restaurantNotFound
        }
        let ownerUserID = try ownerUserID(for: restaurant, actorUserID: actorUserID)
        try LocalCompanionSourceStore(context: context).materializeSelections(
            in: &draft,
            ownerUserID: ownerUserID
        )
        draft = try draft.validated()
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
            ownerUserID: ownerUserID,
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
        try SwiftDataSyncQueue(context: context, ownerUserID: ownerUserID).enqueueUpsert(
            entityType: .visit,
            entityID: visit.remoteID ?? visit.id.uuidString,
            baseVersion: visit.serverVersion,
            payload: SyncRecordMapper.visitPayload(visit, restaurantRemoteID: restaurantRemoteID),
            timestamp: visit.updatedAt
        )
        return visit
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

    func update(_ visit: Visit, draft: VisitDraft, actorUserID: String? = nil) throws {
        try context.transaction {
            try updateVisitInCurrentTransaction(visit, draft: draft, actorUserID: actorUserID)
        }
    }

    func updateVisitInCurrentTransaction(
        _ visit: Visit,
        draft: VisitDraft,
        actorUserID: String? = nil
    ) throws {
        var draft = draft
        guard let restaurant = try context.fetch(FetchDescriptor<Restaurant>())
            .first(where: { $0.id == visit.restaurantId && $0.deletedAt == nil }) else {
            throw LocalTasteMapStoreError.restaurantRemoteIDMissing
        }
        let ownerUserID = try ownerUserID(for: restaurant, actorUserID: actorUserID)
        try LocalCompanionSourceStore(context: context).materializeSelections(
            in: &draft,
            ownerUserID: ownerUserID
        )
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
        guard let restaurantRemoteID = restaurant.remoteID else {
            throw LocalTasteMapStoreError.restaurantRemoteIDMissing
        }
        try SwiftDataSyncQueue(context: context, ownerUserID: visit.ownerUserID).enqueueUpsert(
            entityType: .visit,
            entityID: visit.remoteID ?? visit.id.uuidString,
            baseVersion: visit.serverVersion,
            payload: SyncRecordMapper.visitPayload(visit, restaurantRemoteID: restaurantRemoteID),
            timestamp: visit.updatedAt
        )
    }

    func delete(_ visit: Visit, actorUserID: String? = nil) throws {
        if let actorUserID = Self.normalizedOptional(actorUserID),
           visit.ownerUserID != actorUserID {
            throw LocalTasteMapStoreError.restaurantOwnershipMismatch
        }
        try LocalDishStore(context: context).removeAssociations(for: visit.id)
        let queue = SwiftDataSyncQueue(context: context, ownerUserID: visit.ownerUserID)
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

    func updateDetails(
        _ restaurant: Restaurant,
        name: String,
        city: String,
        phone: String?,
        openingHours: String?,
        referencePrice: Decimal?,
        longTermNote: String?
    ) throws {
        let base = try SyncRecordMapper.restaurantRecord(restaurant)
        try updateDetails(
            restaurant,
            update: RestaurantDetailsUpdate(
                name: name,
                address: restaurant.address,
                city: city,
                status: restaurant.status,
                phone: phone,
                openingHours: openingHours,
                referencePrice: referencePrice,
                longTermNote: longTermNote,
                markerType: base.markerType,
                markerPhotoID: base.markerPhotoId,
                markerEmoji: base.markerEmoji
            )
        )
    }

    func updateDetails(
        _ restaurant: Restaurant,
        update: RestaurantDetailsUpdate,
        actorUserID: String? = nil
    ) throws {
        _ = try ownerUserID(for: restaurant, actorUserID: actorUserID)
        let trimmedName = update.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw LocalTasteMapStoreError.restaurantNameRequired
        }
        let normalizedPhone = Self.normalizedOptional(update.phone)
        if let normalizedPhone, RestaurantPhoneDialing.url(for: normalizedPhone) == nil {
            throw LocalTasteMapStoreError.invalidRestaurantPhone
        }
        if let referencePrice = update.referencePrice,
           NSDecimalNumber(decimal: referencePrice).compare(NSDecimalNumber.zero) != .orderedDescending {
            throw LocalTasteMapStoreError.invalidRestaurantReferencePrice
        }

        let base = try SyncRecordMapper.restaurantRecord(restaurant)
        let updatedAt = Date.now
        let updatedAddress = update.address.trimmingCharacters(in: .whitespacesAndNewlines)
        let updatedCity = update.city.trimmingCharacters(in: .whitespacesAndNewlines)
        let updatedMarkerPhotoID = Self.normalizedOptional(update.markerPhotoID)
        if let updatedMarkerPhotoID, updatedMarkerPhotoID != base.markerPhotoId {
            let ownsMarkerPhoto = try context.fetch(FetchDescriptor<PhotoAsset>()).contains { photo in
                photo.restaurantId == restaurant.id && photo.deletedAt == nil &&
                    photo.kind == .restaurantMarker &&
                    (photo.remoteID == updatedMarkerPhotoID ||
                     photo.id.uuidString.lowercased() == updatedMarkerPhotoID.lowercased())
            }
            guard ownsMarkerPhoto else { throw LocalTasteMapStoreError.invalidRestaurantMarkerPhoto }
        }
        let updatedMarkerEmoji = Self.normalizedOptional(update.markerEmoji) ?? "🍽️"
        let record = try RestaurantJSONContractV1(
            id: base.id,
            userId: base.userId,
            placeIdentities: base.placeIdentities,
            amapPoiId: base.amapPoiId,
            name: trimmedName,
            address: updatedAddress,
            city: updatedCity,
            latitude: restaurant.latitude,
            longitude: restaurant.longitude,
            status: update.status == .wantToGo ? .wantToGo : .visited,
            preferenceLevel: base.preferenceLevel,
            overallRating: base.overallRating,
            foodRating: base.foodRating,
            environmentRating: base.environmentRating,
            serviceRating: base.serviceRating,
            valueRating: base.valueRating,
            tags: base.tags,
            longTermNote: Self.normalizedOptional(update.longTermNote) ?? "",
            pricePerPerson: update.referencePrice.map { NSDecimalNumber(decimal: $0).doubleValue },
            phone: normalizedPhone,
            openingHours: Self.normalizedOptional(update.openingHours),
            markerType: update.markerType,
            markerPhotoId: updatedMarkerPhotoID,
            merchantImageUrl: base.merchantImageUrl,
            markerEmoji: updatedMarkerEmoji,
            createdAt: base.createdAt,
            updatedAt: SyncRecordMapper.dateString(updatedAt),
            deletedAt: base.deletedAt,
            isTestData: base.isTestData
        )
        let recordData = try JSONEncoder().encode(record)

        try context.transaction {
            restaurant.name = trimmedName
            restaurant.address = updatedAddress
            restaurant.city = updatedCity
            restaurant.status = update.status
            restaurant.updatedAt = updatedAt
            restaurant.syncStatus = .pending
            restaurant.remoteRecordData = recordData
            try enqueue(restaurant)
        }
        try context.save()
    }

    func markWantToGo(_ restaurant: Restaurant, actorUserID: String? = nil) throws {
        let base = try SyncRecordMapper.restaurantRecord(restaurant)
        try updateDetails(
            restaurant,
            update: RestaurantDetailsUpdate(
                name: restaurant.name,
                address: restaurant.address,
                city: restaurant.city,
                status: .wantToGo,
                phone: base.phone,
                openingHours: base.openingHours,
                referencePrice: base.pricePerPerson.map { Decimal($0) },
                longTermNote: base.longTermNote,
                markerType: base.markerType,
                markerPhotoID: base.markerPhotoId,
                markerEmoji: base.markerEmoji
            ),
            actorUserID: actorUserID
        )
    }

    func delete(_ restaurant: Restaurant, actorUserID: String? = nil) throws {
        let queue = SwiftDataSyncQueue(context: context, ownerUserID: restaurant.ownerUserID)
        let record = try? SyncRecordMapper.restaurantRecord(restaurant)
        if let actorUserID,
           let ownerUserID = record?.userId.trimmingCharacters(in: .whitespacesAndNewlines),
           !ownerUserID.isEmpty,
           ownerUserID != actorUserID {
            throw LocalTasteMapStoreError.restaurantOwnershipMismatch
        }

        let now = Date.now
        let visits = try context.fetch(FetchDescriptor<Visit>()).filter {
            $0.restaurantId == restaurant.id && $0.deletedAt == nil
        }
        let dishes = try context.fetch(FetchDescriptor<Dish>()).filter {
            $0.restaurantId == restaurant.id && $0.deletedAt == nil
        }
        let associations = try context.fetch(FetchDescriptor<VisitDish>()).filter {
            $0.restaurantId == restaurant.id && $0.deletedAt == nil
        }
        let photos = try context.fetch(FetchDescriptor<PhotoAsset>()).filter {
            $0.restaurantId == restaurant.id && $0.deletedAt == nil
        }
        let retainsChildTombstones = !photos.isEmpty ||
            visits.contains(where: { $0.serverVersion > 0 }) ||
            dishes.contains(where: { $0.serverVersion > 0 }) ||
            associations.contains(where: { $0.serverVersion > 0 })

        try context.transaction {
            // Child tombstones are queued first conceptually. SyncEntityType's
            // delete dependency priority guarantees Photo → VisitDish → Dish →
            // Visit → Restaurant even if these mutations are persisted together.
            for photo in photos {
                let remoteID = photo.remoteID ?? photo.id.uuidString.lowercased()
                photo.deletedAt = now
                photo.updatedAt = now
                photo.uploadState = .deleted
                photo.syncStatus = .pending
                if photo.serverVersion == 0 {
                    try queue.removeMutations(entityType: .photo, entityID: remoteID)
                } else {
                    try queue.enqueueDelete(
                        entityType: .photo,
                        entityID: remoteID,
                        baseVersion: photo.serverVersion,
                        timestamp: now
                    )
                }
            }

            for association in associations {
                let remoteID = association.remoteID ?? association.id.uuidString.lowercased()
                if association.serverVersion == 0 {
                    try queue.removeMutations(entityType: .visitDish, entityID: remoteID)
                    context.delete(association)
                } else {
                    association.deletedAt = now
                    association.updatedAt = now
                    association.syncStatus = .pending
                    try queue.enqueueDelete(
                        entityType: .visitDish,
                        entityID: remoteID,
                        baseVersion: association.serverVersion,
                        timestamp: now
                    )
                }
            }

            for dish in dishes {
                let remoteID = dish.remoteID ?? dish.id.uuidString.lowercased()
                if dish.serverVersion == 0 {
                    try queue.removeMutations(entityType: .dish, entityID: remoteID)
                    context.delete(dish)
                } else {
                    dish.deletedAt = now
                    dish.updatedAt = now
                    dish.syncStatus = .pending
                    try queue.enqueueDelete(
                        entityType: .dish,
                        entityID: remoteID,
                        baseVersion: dish.serverVersion,
                        timestamp: now
                    )
                }
            }

            for visit in visits {
                let remoteID = visit.remoteID ?? visit.id.uuidString.lowercased()
                if visit.serverVersion == 0 {
                    try queue.removeMutations(entityType: .visit, entityID: remoteID)
                    context.delete(visit)
                } else {
                    visit.deletedAt = now
                    visit.updatedAt = now
                    visit.syncStatus = .pending
                    try queue.enqueueDelete(
                        entityType: .visit,
                        entityID: remoteID,
                        baseVersion: visit.serverVersion,
                        timestamp: now
                    )
                }
            }

            let remoteID = restaurant.remoteID ?? restaurant.id.uuidString.lowercased()
            if restaurant.serverVersion == 0 {
                try queue.removeMutations(entityType: .restaurant, entityID: remoteID)
                // Local photo tombstones retain file paths until the established
                // photo cleanup lifecycle removes binaries. Keep their parent
                // tombstone so no retained object points at a missing Restaurant.
                if !retainsChildTombstones {
                    context.delete(restaurant)
                } else {
                    restaurant.deletedAt = now
                    restaurant.updatedAt = now
                    restaurant.syncStatus = .pending
                }
            } else {
                restaurant.deletedAt = now
                restaurant.updatedAt = now
                restaurant.syncStatus = .pending
                try queue.enqueueDelete(
                    entityType: .restaurant,
                    entityID: remoteID,
                    baseVersion: restaurant.serverVersion,
                    timestamp: now
                )
            }
        }
        try context.save()
        if !photos.isEmpty {
            NotificationCenter.default.post(name: .tasteMapPhotoTransferStateChanged, object: nil)
        }
    }

    private func enqueue(_ restaurant: Restaurant) throws {
        let remoteID = restaurant.remoteID ?? restaurant.id.uuidString
        restaurant.remoteID = remoteID
        restaurant.syncStatus = .pending
        try SwiftDataSyncQueue(context: context, ownerUserID: restaurant.ownerUserID).enqueueUpsert(
            entityType: .restaurant,
            entityID: remoteID,
            baseVersion: restaurant.serverVersion,
            payload: SyncRecordMapper.restaurantPayload(restaurant),
            timestamp: restaurant.updatedAt
        )
    }

    private func merge(candidate: RestaurantCandidate, into restaurant: Restaurant) throws -> Bool {
        var changed = false
        if restaurant.city.isEmpty, !candidate.city.isEmpty {
            restaurant.city = candidate.city
            changed = true
        }
        if restaurant.appleMapItemIdentifier == nil, let appleID = candidate.appleMapItemIdentifier {
            restaurant.appleMapItemIdentifier = appleID
            changed = true
        }
        guard !candidate.placeIdentities.isEmpty else { return changed }

        let before = try SyncRecordMapper.restaurantRecord(restaurant)
        let beforeKeys = Set(before.placeIdentities.map(Self.identityKey))
        let added = candidate.placeIdentities.contains { !beforeKeys.contains(Self.identityKey($0)) }
        guard added else { return changed }
        restaurant.remoteRecordData = try recordData(
            for: restaurant,
            candidateIdentities: candidate.placeIdentities,
            replacingGeneratedIdentity: false
        )
        return true
    }

    private func recordData(
        for restaurant: Restaurant,
        candidateIdentities: [RestaurantCandidatePlaceIdentity],
        replacingGeneratedIdentity: Bool
    ) throws -> Data {
        let base = try SyncRecordMapper.restaurantRecord(restaurant)
        let timestamp = SyncRecordMapper.dateString(restaurant.updatedAt)
        var identities = replacingGeneratedIdentity ? [] : base.placeIdentities
        var keys = Set(identities.map(Self.identityKey))
        for candidateIdentity in candidateIdentities where !candidateIdentity.externalID.isEmpty {
            let key = Self.identityKey(candidateIdentity)
            guard keys.insert(key).inserted else { continue }
            identities.append(try RestaurantPlaceIdentityContract(
                provider: candidateIdentity.provider,
                externalId: candidateIdentity.externalID,
                isPrimary: identities.isEmpty && candidateIdentity.isPrimary,
                createdAt: timestamp,
                updatedAt: timestamp
            ))
        }
        if identities.isEmpty { identities = base.placeIdentities }
        if !identities.contains(where: \.isPrimary), let first = identities.first {
            identities[0] = try RestaurantPlaceIdentityContract(
                provider: first.provider,
                externalId: first.externalId,
                isPrimary: true,
                createdAt: first.createdAt,
                updatedAt: first.updatedAt
            )
        }
        let amapID = identities.first(where: { $0.provider == .amap })?.externalId
        let value = try RestaurantJSONContractV1(
            id: base.id,
            userId: base.userId,
            placeIdentities: identities,
            amapPoiId: amapID,
            name: restaurant.name,
            address: restaurant.address,
            city: restaurant.city,
            latitude: restaurant.latitude,
            longitude: restaurant.longitude,
            status: restaurant.status == .wantToGo ? .wantToGo : .visited,
            preferenceLevel: base.preferenceLevel,
            overallRating: base.overallRating,
            foodRating: base.foodRating,
            environmentRating: base.environmentRating,
            serviceRating: base.serviceRating,
            valueRating: base.valueRating,
            tags: base.tags,
            longTermNote: base.longTermNote,
            pricePerPerson: base.pricePerPerson,
            phone: base.phone,
            openingHours: base.openingHours,
            markerType: base.markerType,
            markerPhotoId: base.markerPhotoId,
            merchantImageUrl: base.merchantImageUrl,
            markerEmoji: base.markerEmoji,
            createdAt: base.createdAt,
            updatedAt: timestamp,
            deletedAt: base.deletedAt,
            isTestData: base.isTestData
        )
        return try JSONEncoder().encode(value)
    }

    private static func identityKey(_ identity: RestaurantPlaceIdentityContract) -> String {
        "\(identity.provider.rawValue):\(identity.externalId)"
    }

    nonisolated private static func identityKey(_ identity: RestaurantCandidatePlaceIdentity) -> String {
        "\(identity.provider.rawValue):\(identity.externalID)"
    }

    nonisolated private static func normalizedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func ownerUserID(for restaurant: Restaurant, actorUserID: String?) throws -> String {
        let recordOwner = restaurant.ownerUserID
        if let actorUserID = Self.normalizedOptional(actorUserID),
           recordOwner.hasPrefix("tm_"),
           recordOwner != actorUserID {
            throw LocalTasteMapStoreError.restaurantOwnershipMismatch
        }
        // A newly-created local contract is intentionally unassigned until the
        // authenticated Worker overwrites its userId. Use the current actor for
        // private companion/source directory ownership without changing the
        // Restaurant identity contract locally.
        return Self.normalizedOptional(actorUserID) ?? recordOwner
    }
}

enum LocalTasteMapStoreError: Error {
    case restaurantNotFound
    case restaurantRemoteIDMissing
    case restaurantHasVisits
    case restaurantNameRequired
    case invalidRestaurantPhone
    case invalidRestaurantReferencePrice
    case invalidRestaurantMarkerPhoto
    case restaurantOwnershipMismatch
    case visitCreationFailed
}

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

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
