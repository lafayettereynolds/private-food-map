import Foundation

nonisolated struct OnThisDayContext: Sendable {
    let referenceDate: Date
    let calendar: Calendar

    static func live(referenceDate: Date = .now) -> OnThisDayContext {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .autoupdatingCurrent
        calendar.timeZone = .autoupdatingCurrent
        return OnThisDayContext(referenceDate: referenceDate, calendar: calendar)
    }
}

nonisolated struct OnThisDayInput: Sendable {
    static let localOwnerID = "local"

    nonisolated struct RestaurantRecord: Sendable {
        let id: UUID
        let ownerUserID: String
        let name: String
        let city: String
        let updatedAt: Date
        let deletedAt: Date?
    }

    nonisolated struct VisitRecord: Sendable {
        let id: UUID
        let ownerUserID: String
        let restaurantID: UUID
        let visitedAt: Date
        let rating: Double?
        let note: String?
        let myActualSpend: Decimal?
        let companionNames: [String]
        let recommendationSource: String?
        let updatedAt: Date
        let deletedAt: Date?
    }

    nonisolated struct DishRecord: Sendable {
        let id: UUID
        let restaurantID: UUID
        let name: String
        let sortOrder: Int
        let updatedAt: Date
        let deletedAt: Date?
    }

    nonisolated struct VisitDishRecord: Sendable {
        let visitID: UUID
        let dishID: UUID
        let sortOrder: Int
        let deletedAt: Date?
    }

    nonisolated struct PhotoRecord: Sendable {
        let id: UUID
        let restaurantID: UUID?
        let visitID: UUID?
        let dishID: UUID?
        let kind: PhotoAssetKind
        let sortOrder: Int
        let updatedAt: Date
        let binaryDeletedAt: Date?
        let deletedAt: Date?
    }

    let currentUserID: String
    let restaurants: [RestaurantRecord]
    let visits: [VisitRecord]
    let dishes: [DishRecord]
    let visitDishes: [VisitDishRecord]
    let photos: [PhotoRecord]

    @MainActor
    static func capture(
        currentUserID: String,
        restaurants: [Restaurant],
        visits: [Visit],
        dishes: [Dish],
        visitDishes: [VisitDish],
        photos: [PhotoAsset],
        companions: [DiningCompanion],
        recommendationSources: [RecommendationSource]
    ) -> OnThisDayInput {
        let normalizedCurrentUserID = normalizedOwner(currentUserID)
        let contractsByRestaurantID = Dictionary(uniqueKeysWithValues: restaurants.map { restaurant in
            (restaurant.id, restaurant.remoteRecordData.flatMap {
                try? JSONDecoder().decode(RestaurantJSONContractV1.self, from: $0)
            })
        })
        let ownerByLocalRestaurantID = Dictionary(uniqueKeysWithValues: restaurants.map { restaurant in
            let contract = contractsByRestaurantID[restaurant.id] ?? nil
            return (restaurant.id, normalizedOwner(contract?.userId))
        })
        let ownedRestaurants = restaurants.filter {
            isOwned(ownerByLocalRestaurantID[$0.id] ?? localOwnerID, by: normalizedCurrentUserID)
        }
        let identity = AnalysisRestaurantIdentity.projection(for: ownedRestaurants)
        let canonicalOwnerByRestaurantID = ownedRestaurants.reduce(into: [UUID: String]()) { result, restaurant in
            let canonicalID = identity.canonicalID(for: restaurant.id)
            let owner = ownerByLocalRestaurantID[restaurant.id] ?? localOwnerID
            if result[canonicalID] == nil || owner != localOwnerID { result[canonicalID] = owner }
            result[restaurant.id] = owner
        }

        let companionNamesByIdentifier = companions
            .filter { $0.deletedAt == nil && isOwned($0.ownerUserId, by: normalizedCurrentUserID) }
            .reduce(into: [String: String]()) { result, companion in
                result[companion.id.uuidString.lowercased()] = companion.displayName
                if let remoteID = companion.remoteID { result[remoteID] = companion.displayName }
            }
        let sourceNamesByIdentifier = recommendationSources
            .filter { $0.deletedAt == nil && isOwned($0.ownerUserId, by: normalizedCurrentUserID) }
            .reduce(into: [String: String]()) { result, source in
                result[source.id.uuidString.lowercased()] = source.displayName
                if let remoteID = source.remoteID { result[remoteID] = source.displayName }
            }

        return OnThisDayInput(
            currentUserID: normalizedCurrentUserID,
            restaurants: ownedRestaurants.filter { restaurant in
                restaurant.deletedAt != nil || identity.representativeIDs.contains(restaurant.id)
            }.map { restaurant in
                RestaurantRecord(
                    id: identity.canonicalID(for: restaurant.id),
                    ownerUserID: ownerByLocalRestaurantID[restaurant.id] ?? localOwnerID,
                    name: restaurant.name,
                    city: restaurant.city,
                    updatedAt: restaurant.updatedAt,
                    deletedAt: restaurant.deletedAt
                )
            },
            visits: visits.compactMap { visit in
                guard let owner = canonicalOwnerByRestaurantID[visit.restaurantId],
                      isOwned(owner, by: normalizedCurrentUserID) else { return nil }
                let resolvedCompanions = visit.companionIDs.enumerated().compactMap { index, identifier in
                    companionNamesByIdentifier[identifier]
                        ?? visit.companionNames[safe: index]?.onThisDayNonEmpty
                }
                let fallbackCompanions = resolvedCompanions.isEmpty
                    ? visit.companionNames.compactMap(\.onThisDayNonEmpty)
                    : resolvedCompanions
                let source = visit.recommendationSourceID.flatMap { sourceNamesByIdentifier[$0] }
                    ?? visit.recommendationSourceText?.onThisDayNonEmpty
                    ?? visit.recommendationSourceType?.title
                return VisitRecord(
                    id: visit.id,
                    ownerUserID: owner,
                    restaurantID: identity.canonicalID(for: visit.restaurantId),
                    visitedAt: visit.visitedAt,
                    rating: visit.rating,
                    note: visit.note?.onThisDayNonEmpty,
                    myActualSpend: visit.myActualSpend,
                    companionNames: unique(fallbackCompanions),
                    recommendationSource: source?.onThisDayNonEmpty,
                    updatedAt: visit.updatedAt,
                    deletedAt: visit.deletedAt
                )
            },
            dishes: dishes.compactMap { dish in
                guard canonicalOwnerByRestaurantID[dish.restaurantId] != nil else { return nil }
                return DishRecord(
                    id: dish.id,
                    restaurantID: identity.canonicalID(for: dish.restaurantId),
                    name: dish.name,
                    sortOrder: dish.sortOrder,
                    updatedAt: dish.updatedAt,
                    deletedAt: dish.deletedAt
                )
            },
            visitDishes: visitDishes.map {
                VisitDishRecord(
                    visitID: $0.visitId,
                    dishID: $0.dishId,
                    sortOrder: $0.sortOrder,
                    deletedAt: $0.deletedAt
                )
            },
            photos: photos.compactMap { photo in
                if let restaurantID = photo.restaurantId,
                   canonicalOwnerByRestaurantID[restaurantID] == nil { return nil }
                return PhotoRecord(
                    id: photo.id,
                    restaurantID: identity.canonicalID(for: photo.restaurantId),
                    visitID: photo.visitId,
                    dishID: photo.dishId,
                    kind: photo.kind,
                    sortOrder: photo.sortOrder,
                    updatedAt: photo.updatedAt,
                    binaryDeletedAt: photo.binaryDeletedAt,
                    deletedAt: photo.deletedAt
                )
            }
        )
    }

    private static func normalizedOwner(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).onThisDayNonEmpty ?? localOwnerID
    }

    static func isOwned(_ ownerUserID: String, by currentUserID: String) -> Bool {
        ownerUserID == currentUserID || ownerUserID == localOwnerID
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}

nonisolated struct OnThisDayMemory: Identifiable, Hashable, Sendable {
    let id: UUID
    let restaurantID: UUID
    let year: Int
    let yearsAgo: Int
    let visitedAt: Date
    let restaurantName: String
    let city: String
    let rating: Double?
    let note: String?
    let spend: Decimal?
    let companions: [String]
    let recommendationSource: String?
    let dishNames: [String]
    let imageReference: AnalysisImageReference
}

nonisolated struct OnThisDayYearGroup: Identifiable, Hashable, Sendable {
    let year: Int
    let memories: [OnThisDayMemory]
    var id: Int { year }
}

nonisolated struct OnThisDayReport: Hashable, Sendable {
    let referenceDate: Date
    let month: Int
    let day: Int
    let groups: [OnThisDayYearGroup]

    var memories: [OnThisDayMemory] { groups.flatMap(\.memories) }
    var hasMemories: Bool { !groups.isEmpty }
}

extension String {
    nonisolated fileprivate var onThisDayNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

extension Collection {
    nonisolated fileprivate subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
