import Foundation

/// Current-account projection shared by every local business surface. Core
/// entities carry a first-class owner; quarantined legacy rows are fail-closed.
nonisolated enum ProfileOwnedContentScope {
    static let localOwnerID = LocalAccountOwner.guest

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
        let ownedRestaurants = restaurants.filter { isOwned($0.ownerUserID, by: owner) }
        let restaurantIDs = Set(ownedRestaurants.map(\.id))
        let ownedVisits = visits.filter {
            isOwned($0.ownerUserID, by: owner) && restaurantIDs.contains($0.restaurantId)
        }
        let visitIDs = Set(ownedVisits.map(\.id))
        let ownedDishes = dishes.filter {
            isOwned($0.ownerUserID, by: owner) && restaurantIDs.contains($0.restaurantId)
        }
        let dishIDs = Set(ownedDishes.map(\.id))

        return Snapshot(
            restaurants: ownedRestaurants,
            visits: ownedVisits,
            photos: photos.filter { photo in
                guard isOwned(photo.ownerUserID, by: owner) else { return false }
                if photo.kind == .avatar { return true }
                guard let restaurantID = photo.restaurantId else { return false }
                return restaurantIDs.contains(restaurantID)
            },
            dishes: ownedDishes,
            visitDishes: visitDishes.filter {
                isOwned($0.ownerUserID, by: owner) &&
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
        isOwned(restaurant.ownerUserID, by: normalized(currentUserID))
    }

    @MainActor
    static func isSafeListCover(_ photo: PhotoAsset, ownedBy currentUserID: String) -> Bool {
        guard photo.deletedAt == nil,
              photo.binaryDeletedAt == nil,
              photo.uploadState == .uploaded,
              photo.visibility == .public,
              photo.kind != .avatar,
              photo.restaurantId != nil else { return false }
        return isOwned(photo.ownerUserID, by: normalized(currentUserID))
    }

    static func isOwned(_ ownerUserID: String, by currentUserID: String) -> Bool {
        let owner = normalized(ownerUserID)
        return owner == currentUserID
    }

    private static func normalized(_ value: String?) -> String {
        let result = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return result.isEmpty ? localOwnerID : result
    }
}
