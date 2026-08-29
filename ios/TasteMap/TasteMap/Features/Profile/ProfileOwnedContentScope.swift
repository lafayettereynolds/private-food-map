import Foundation

/// Read-only presentation scoping for local-first records whose owner is carried by
/// the sync contract rather than duplicated onto every SwiftData model.
///
/// A record without a remote contract remains device-local legacy content. It can be
/// displayed to the active account for compatibility, but this helper never claims,
/// rewrites, or uploads that ownership.
nonisolated enum ProfileOwnedContentScope {
    static let localOwnerID = "local"

    struct Snapshot {
        let restaurants: [Restaurant]
        let visits: [Visit]
        let photos: [PhotoAsset]
        let dishes: [Dish]
        let visitDishes: [VisitDish]
        let companions: [DiningCompanion]
        let recommendationSources: [RecommendationSource]

        var restaurantIDs: Set<UUID> { Set(restaurants.map(\.id)) }
    }

    @MainActor
    static func capture(
        currentUserID: String?,
        restaurants: [Restaurant],
        visits: [Visit] = [],
        photos: [PhotoAsset] = [],
        dishes: [Dish] = [],
        visitDishes: [VisitDish] = [],
        companions: [DiningCompanion] = [],
        recommendationSources: [RecommendationSource] = []
    ) -> Snapshot {
        let owner = normalized(currentUserID)
        let ownedRestaurants = restaurants.filter { isRestaurant($0, ownedBy: owner) }
        let restaurantIDs = Set(ownedRestaurants.map(\.id))
        let ownedVisits = visits.filter { restaurantIDs.contains($0.restaurantId) }
        let visitIDs = Set(ownedVisits.map(\.id))
        let ownedDishes = dishes.filter { restaurantIDs.contains($0.restaurantId) }
        let dishIDs = Set(ownedDishes.map(\.id))

        return Snapshot(
            restaurants: ownedRestaurants,
            visits: ownedVisits,
            photos: photos.filter { photo in
                if photo.kind == .avatar { return photoOwner(photo) == owner }
                guard let restaurantID = photo.restaurantId else { return false }
                return restaurantIDs.contains(restaurantID)
            },
            dishes: ownedDishes,
            visitDishes: visitDishes.filter {
                visitIDs.contains($0.visitId) && dishIDs.contains($0.dishId)
            },
            companions: companions.filter { isOwned($0.ownerUserId, by: owner) },
            recommendationSources: recommendationSources.filter {
                isOwned($0.ownerUserId, by: owner)
            }
        )
    }

    @MainActor
    static func isRestaurant(_ restaurant: Restaurant, ownedBy currentUserID: String?) -> Bool {
        let current = normalized(currentUserID)
        let owner = restaurant.remoteRecordData
            .flatMap { try? JSONDecoder().decode(RestaurantJSONContractV1.self, from: $0) }
            .map(\.userId) ?? localOwnerID
        return isOwned(owner, by: current)
    }

    @MainActor
    static func isSafeListCover(_ photo: PhotoAsset, ownedBy currentUserID: String) -> Bool {
        guard photo.deletedAt == nil,
              photo.binaryDeletedAt == nil,
              photo.uploadState == .uploaded,
              photo.visibility == .public,
              photo.kind != .avatar,
              photo.restaurantId != nil else { return false }
        return isOwned(photoOwner(photo), by: normalized(currentUserID))
    }

    static func isOwned(_ ownerUserID: String, by currentUserID: String) -> Bool {
        let owner = normalized(ownerUserID)
        return owner == currentUserID || owner == localOwnerID
    }

    @MainActor
    private static func photoOwner(_ photo: PhotoAsset) -> String {
        photo.remoteRecordData
            .flatMap { try? JSONDecoder().decode(PhotoSyncContractV1.self, from: $0) }
            .map(\.userId) ?? localOwnerID
    }

    private static func normalized(_ value: String?) -> String {
        let result = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return result.isEmpty ? localOwnerID : result
    }
}
