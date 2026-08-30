import Foundation
import SwiftData

@MainActor
struct LocalDiscoveryStore {
    let context: ModelContext

    func replaceCache(page: DiscoveryPageV1, currentUserID: String, trendWindowDays: Int) throws {
        let generatedAt = Self.date(page.generatedAt) ?? .now
        let placements = try context.fetch(FetchDescriptor<CachedDiscoveryPlacement>())
        for placement in placements where placement.currentUserID == currentUserID &&
            placement.modeValue == page.mode.rawValue && placement.city == page.city &&
            placement.trendWindowDays == trendWindowDays {
            context.delete(placement)
        }
        try cache(page: page, currentUserID: currentUserID, trendWindowDays: trendWindowDays,
                  generatedAt: generatedAt)
    }

    func appendCache(page: DiscoveryPageV1, currentUserID: String, trendWindowDays: Int) throws {
        try cache(page: page, currentUserID: currentUserID, trendWindowDays: trendWindowDays,
                  generatedAt: Self.date(page.generatedAt) ?? .now)
    }

    func cachedPage(mode: DiscoveryModeV1, city: String, currentUserID: String,
                    trendWindowDays: Int) throws -> (cards: [DiscoveryCardV1], updatedAt: Date)? {
        let restaurants = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<CachedDiscoveryRestaurant>())
            .filter { $0.currentUserID == currentUserID }
            .compactMap { cached -> (String, DiscoveryRestaurantProjectionV1)? in
                cached.projection.map { (cached.globalKey, $0) }
            })
        let placements = try context.fetch(FetchDescriptor<CachedDiscoveryPlacement>())
            .filter { $0.currentUserID == currentUserID && $0.modeValue == mode.rawValue &&
                $0.city == city && $0.trendWindowDays == trendWindowDays }
        let cards = placements.compactMap { placement -> DiscoveryCardV1? in
            guard let restaurant = restaurants[placement.globalKey], let value = placement.context else { return nil }
            return value.card(restaurant: restaurant)
        }.sorted { $0.rank < $1.rank || ($0.rank == $1.rank && $0.score > $1.score) }
        guard !cards.isEmpty else { return nil }
        return (cards, placements.map(\.generatedAt).max() ?? .now)
    }

    @discardableResult
    func addToWantToGo(
        projection: DiscoveryRestaurantProjectionV1,
        among restaurants: [Restaurant],
        currentUserID: String = LocalAccountOwner.guest
    ) throws -> Restaurant {
        let ownedRestaurants = restaurants.filter { $0.ownerUserID == currentUserID }
        if let existing = localRestaurant(for: projection, among: ownedRestaurants) {
            // A recorded visit always wins. Discovery must never regress it to WantToGo.
            if existing.status == .visited { return existing }
            let knownIdentities = identityKeys(for: existing)
            let projectedIdentities = Set(projection.placeIdentities.map(Self.identityKey))
            if !projectedIdentities.isSubset(of: knownIdentities) {
                existing.appleMapItemIdentifier = existing.appleMapItemIdentifier ??
                    projection.placeIdentities.first { $0.provider == .appleMaps }?.externalId
                existing.city = projection.city
                existing.updatedAt = .now
                existing.syncStatus = .pending
                existing.remoteRecordData = try discoveryRecordData(for: existing, projection: projection)
                try SwiftDataSyncQueue(context: context, ownerUserID: currentUserID).enqueueUpsert(
                    entityType: .restaurant,
                    entityID: existing.remoteID ?? existing.id.uuidString,
                    baseVersion: existing.serverVersion,
                    payload: SyncRecordMapper.restaurantPayload(existing),
                    timestamp: existing.updatedAt
                )
                try context.save()
            }
            return existing
        }
        let candidate = projection.restaurantCandidate
        let restaurant = try LocalTasteMapStore(context: context)
            .addToWantToGo(
                candidate: candidate,
                among: ownedRestaurants,
                actorUserID: currentUserID
            )
        restaurant.city = projection.city
        restaurant.updatedAt = .now
        restaurant.remoteRecordData = try discoveryRecordData(for: restaurant, projection: projection)
        try SwiftDataSyncQueue(context: context, ownerUserID: currentUserID).enqueueUpsert(
            entityType: .restaurant,
            entityID: restaurant.remoteID ?? restaurant.id.uuidString,
            baseVersion: restaurant.serverVersion,
            payload: SyncRecordMapper.restaurantPayload(restaurant),
            timestamp: restaurant.updatedAt
        )
        try context.save()
        return restaurant
    }

    func updateViewerState(globalKey: String, currentUserID: String,
                           state: DiscoveryViewerRestaurantStateV1) throws {
        let restaurants = try context.fetch(FetchDescriptor<CachedDiscoveryRestaurant>())
        guard restaurants.contains(where: { $0.currentUserID == currentUserID && $0.globalKey == globalKey }) else { return }
        for placement in try context.fetch(FetchDescriptor<CachedDiscoveryPlacement>())
        where placement.currentUserID == currentUserID && placement.globalKey == globalKey {
            guard let value = placement.context else { continue }
            let updated = DiscoveryCachedCardContext(
                id: value.id, mode: value.mode, viewerState: state, ratings: value.ratings,
                reasons: value.reasons, sourceUser: value.sourceUser, similarity: value.similarity,
                trend: value.trend, cacheScope: value.cacheScope, rank: value.rank, score: value.score
            )
            placement.contextData = try JSONEncoder().encode(updated)
        }
        try context.save()
    }

    private func cache(page: DiscoveryPageV1, currentUserID: String, trendWindowDays: Int,
                       generatedAt: Date) throws {
        let existingRestaurants = try context.fetch(FetchDescriptor<CachedDiscoveryRestaurant>())
        let existingPlacements = try context.fetch(FetchDescriptor<CachedDiscoveryPlacement>())
        // Friends-only projections are intentionally memory-only. A removed
        // friendship therefore cannot leave an authorization-sensitive cache.
        for card in page.items where card.cacheScope == .public {
            let restaurantCacheID = "\(currentUserID)|\(card.restaurant.globalKey)"
            if let existing = existingRestaurants.first(where: { $0.cacheID == restaurantCacheID }) {
                existing.projectionData = try JSONEncoder().encode(card.restaurant)
                existing.fetchedAt = generatedAt
            } else {
                context.insert(try CachedDiscoveryRestaurant(
                    currentUserID: currentUserID, projection: card.restaurant, fetchedAt: generatedAt
                ))
            }
            let placementID = CachedDiscoveryPlacement.id(
                currentUserID: currentUserID, mode: card.mode, city: page.city,
                trendWindowDays: trendWindowDays, globalKey: card.restaurant.globalKey
            )
            if let existing = existingPlacements.first(where: { $0.cacheID == placementID }) {
                existing.contextData = try JSONEncoder().encode(DiscoveryCachedCardContext(card: card))
                existing.generatedAt = generatedAt
            } else {
                context.insert(try CachedDiscoveryPlacement(
                    currentUserID: currentUserID, city: page.city,
                    trendWindowDays: trendWindowDays, card: card, generatedAt: generatedAt
                ))
            }
        }
        try context.save()
    }

    func localRestaurant(
        for projection: DiscoveryRestaurantProjectionV1,
        among restaurants: [Restaurant]
    ) -> Restaurant? {
        let projectedKeys = Set(projection.placeIdentities.map { "\($0.provider.rawValue):\($0.externalId)" })
        if let identityMatch = restaurants.first(where: { restaurant in
            guard restaurant.deletedAt == nil else { return false }
            var keys = Set<String>()
            if let apple = restaurant.appleMapItemIdentifier { keys.insert("apple_maps:\(apple)") }
            if let data = restaurant.remoteRecordData,
               let record = try? JSONDecoder().decode(RestaurantJSONContractV1.self, from: data) {
                keys.formUnion(record.placeIdentities.map { "\($0.provider.rawValue):\($0.externalId)" })
            }
            return !keys.isDisjoint(with: projectedKeys)
        }) { return identityMatch }
        return RestaurantDeduplicator.match(for: projection.restaurantCandidate, in: restaurants)
    }

    private func discoveryRecordData(for restaurant: Restaurant,
                                     projection: DiscoveryRestaurantProjectionV1) throws -> Data {
        let date = ISO8601DateFormatter().string(from: restaurant.updatedAt)
        let previous = restaurant.remoteRecordData.flatMap {
            try? JSONDecoder().decode(RestaurantJSONContractV1.self, from: $0)
        }
        var identityValues = previous?.placeIdentities ?? []
        if let appleID = restaurant.appleMapItemIdentifier, !appleID.isEmpty,
           !identityValues.contains(where: { $0.provider == .appleMaps && $0.externalId == appleID }) {
            identityValues.append(try RestaurantPlaceIdentityContract(
                provider: .appleMaps, externalId: appleID, isPrimary: false,
                createdAt: date, updatedAt: date
            ))
        }
        for identity in projection.placeIdentities {
            guard !identityValues.contains(where: {
                $0.provider == identity.provider && $0.externalId == identity.externalId
            }) else { continue }
            identityValues.append(try RestaurantPlaceIdentityContract(
                provider: identity.provider, externalId: identity.externalId,
                isPrimary: false, createdAt: date, updatedAt: date
            ))
        }
        let preferredPrimary = previous?.placeIdentities.first(where: \.isPrimary).map(Self.identityKey) ??
            projection.placeIdentities.first(where: \.isPrimary).map(Self.identityKey) ??
            identityValues.first.map(Self.identityKey)
        let identities = try identityValues.map { identity in
            try RestaurantPlaceIdentityContract(
                provider: identity.provider, externalId: identity.externalId,
                isPrimary: Self.identityKey(identity) == preferredPrimary,
                createdAt: identity.createdAt, updatedAt: date
            )
        }
        let record = try RestaurantJSONContractV1(
            id: restaurant.remoteID ?? restaurant.id.uuidString.lowercased(),
            userId: restaurant.ownerUserID,
            placeIdentities: identities, amapPoiId: identities.first { $0.provider == .amap }?.externalId,
            name: projection.name, address: projection.address, city: projection.city,
            latitude: projection.latitude, longitude: projection.longitude, status: .wantToGo,
            preferenceLevel: .normal, overallRating: nil, foodRating: nil,
            environmentRating: nil, serviceRating: nil, valueRating: nil,
            tags: projection.tags, longTermNote: "", pricePerPerson: projection.pricePerPerson,
            phone: nil, openingHours: nil, markerType: .emoji, markerPhotoId: nil,
            merchantImageUrl: projection.merchantImageUrl, markerEmoji: projection.markerEmoji,
            createdAt: ISO8601DateFormatter().string(from: restaurant.createdAt), updatedAt: date,
            deletedAt: nil
        )
        return try JSONEncoder().encode(record)
    }

    private func identityKeys(for restaurant: Restaurant) -> Set<String> {
        var keys = Set<String>()
        if let apple = restaurant.appleMapItemIdentifier { keys.insert("apple_maps:\(apple)") }
        if let data = restaurant.remoteRecordData,
           let record = try? JSONDecoder().decode(RestaurantJSONContractV1.self, from: data) {
            keys.formUnion(record.placeIdentities.map(Self.identityKey))
        }
        return keys
    }

    private static func identityKey(_ identity: DiscoveryPlaceIdentityV1) -> String {
        "\(identity.provider.rawValue):\(identity.externalId)"
    }

    private static func identityKey(_ identity: RestaurantPlaceIdentityContract) -> String {
        "\(identity.provider.rawValue):\(identity.externalId)"
    }

    private static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

private extension DiscoveryCachedCardContext {
    init(id: String, mode: DiscoveryModeV1, viewerState: DiscoveryViewerRestaurantStateV1,
         ratings: DiscoveryRatingsV1, reasons: [DiscoveryReasonV1],
         sourceUser: DiscoveryPublicUserProjectionV1?, similarity: DiscoverySimilarityContextV1?,
         trend: DiscoveryTrendContextV1?, cacheScope: DiscoveryCacheScopeV1,
         rank: Int, score: Double) {
        self.id = id; self.mode = mode; self.viewerState = viewerState; self.ratings = ratings
        self.reasons = reasons; self.sourceUser = sourceUser; self.similarity = similarity
        self.trend = trend; self.cacheScope = cacheScope; self.rank = rank; self.score = score
    }
}
