import Foundation
import SwiftData
import SwiftUI

/// Installation-local ownership boundaries. `local` is an explicit signed-out
/// workspace. Rows created by older schemas receive the quarantine owner and
/// are never exposed or uploaded until ownership can be proven.
nonisolated enum LocalAccountOwner {
    static let guest = "local"
    static let legacyQuarantine = "legacy-unscoped"

    static func normalized(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? legacyQuarantine : trimmed
    }
}

#if !TASTEMAP_HYBRID_BRIDGE_CORE

nonisolated enum LocalAccountScope: Equatable, Sendable {
    case restoring
    case guest
    case authenticated(String)

    var ownerUserID: String? {
        switch self {
        case .restoring: nil
        case .guest: LocalAccountOwner.guest
        case .authenticated(let userID): LocalAccountOwner.normalized(userID)
        }
    }

    var authenticatedUserID: String? {
        guard case .authenticated(let userID) = self else { return nil }
        return LocalAccountOwner.normalized(userID)
    }

    func contains(ownerUserID: String) -> Bool {
        guard let owner = self.ownerUserID else { return false }
        return LocalAccountOwner.normalized(ownerUserID) == owner
    }
}

private struct LocalAccountScopeEnvironmentKey: EnvironmentKey {
    static let defaultValue: LocalAccountScope = .guest
}

extension EnvironmentValues {
    var localAccountScope: LocalAccountScope {
        get { self[LocalAccountScopeEnvironmentKey.self] }
        set { self[LocalAccountScopeEnvironmentKey.self] = newValue }
    }
}

/// Performs only evidence-based ownership migration. Explicit guest rows may
/// be claimed when a user signs in. Legacy quarantine rows require a signed
/// server snapshot or an owned parent; unknown rows remain quarantined.
@MainActor
struct LocalAccountOwnershipMigrator {
    let context: ModelContext

    func activate(userID: String) throws {
        let userID = LocalAccountOwner.normalized(userID)
        guard userID.hasPrefix("tm_") else { return }

        let restaurants = try context.fetch(FetchDescriptor<Restaurant>())
        for restaurant in restaurants {
            if restaurant.ownerUserID == LocalAccountOwner.guest {
                restaurant.ownerUserID = userID
            } else if restaurant.ownerUserID == LocalAccountOwner.legacyQuarantine,
                      reliableRestaurantOwner(restaurant) == userID {
                restaurant.ownerUserID = userID
            }
        }

        let ownerByRestaurant = Dictionary(uniqueKeysWithValues: restaurants.map { ($0.id, $0.ownerUserID) })
        let visits = try context.fetch(FetchDescriptor<Visit>())
        for visit in visits where shouldInherit(visit.ownerUserID, parent: ownerByRestaurant[visit.restaurantId], userID: userID) {
            visit.ownerUserID = userID
        }

        let ownerByVisit = Dictionary(uniqueKeysWithValues: visits.map { ($0.id, $0.ownerUserID) })
        let dishes = try context.fetch(FetchDescriptor<Dish>())
        for dish in dishes where shouldInherit(
            dish.ownerUserID,
            parent: ownerByVisit[dish.visitId] ?? ownerByRestaurant[dish.restaurantId],
            userID: userID
        ) {
            dish.ownerUserID = userID
        }

        let ownerByDish = Dictionary(uniqueKeysWithValues: dishes.map { ($0.id, $0.ownerUserID) })
        let associations = try context.fetch(FetchDescriptor<VisitDish>())
        for association in associations where shouldInherit(
            association.ownerUserID,
            parent: ownerByVisit[association.visitId] ?? ownerByDish[association.dishId],
            userID: userID
        ) {
            association.ownerUserID = userID
        }

        let photos = try context.fetch(FetchDescriptor<PhotoAsset>())
        for photo in photos {
            let parent = photo.visitId.flatMap { ownerByVisit[$0] }
                ?? photo.dishId.flatMap { ownerByDish[$0] }
                ?? photo.restaurantId.flatMap { ownerByRestaurant[$0] }
                ?? reliablePhotoOwner(photo)
            if shouldInherit(photo.ownerUserID, parent: parent, userID: userID) {
                photo.ownerUserID = userID
            }
        }

        let mutations = try context.fetch(FetchDescriptor<SyncMutation>())
        for mutation in mutations where mutation.ownerUserID == LocalAccountOwner.guest {
            mutation.ownerUserID = userID
        }
        for mutation in mutations where mutation.ownerUserID == LocalAccountOwner.legacyQuarantine {
            if reliableMutationOwner(mutation, userID: userID, restaurants: restaurants, visits: visits,
                                     dishes: dishes, associations: associations, photos: photos) {
                mutation.ownerUserID = userID
            }
        }

        try context.save()
    }

    private func shouldInherit(_ current: String, parent: String?, userID: String) -> Bool {
        guard current == LocalAccountOwner.guest || current == LocalAccountOwner.legacyQuarantine else {
            return false
        }
        if current == LocalAccountOwner.guest { return true }
        return parent == userID
    }

    private func reliableRestaurantOwner(_ restaurant: Restaurant) -> String? {
        restaurant.remoteRecordData
            .flatMap { try? JSONDecoder().decode(RestaurantJSONContractV1.self, from: $0) }
            .map(\.userId)
            .map(LocalAccountOwner.normalized)
    }

    private func reliablePhotoOwner(_ photo: PhotoAsset) -> String? {
        photo.remoteRecordData
            .flatMap { try? JSONDecoder().decode(PhotoSyncContractV1.self, from: $0) }
            .map(\.userId)
            .map(LocalAccountOwner.normalized)
    }

    private func reliableMutationOwner(
        _ mutation: SyncMutation,
        userID: String,
        restaurants: [Restaurant],
        visits: [Visit],
        dishes: [Dish],
        associations: [VisitDish],
        photos: [PhotoAsset]
    ) -> Bool {
        switch mutation.entityType {
        case .restaurant:
            return restaurants.contains { $0.remoteID == mutation.entityID && $0.ownerUserID == userID }
        case .visit:
            return visits.contains { $0.remoteID == mutation.entityID && $0.ownerUserID == userID }
        case .dish:
            return dishes.contains { $0.remoteID == mutation.entityID && $0.ownerUserID == userID }
        case .visitDish:
            return associations.contains { $0.remoteID == mutation.entityID && $0.ownerUserID == userID }
        case .photo:
            return photos.contains { $0.remoteID == mutation.entityID && $0.ownerUserID == userID }
        case .companion:
            return (try? context.fetch(FetchDescriptor<DiningCompanion>()))?.contains {
                $0.remoteID == mutation.entityID && $0.ownerUserId == userID
            } == true
        case .recommendationSource:
            return (try? context.fetch(FetchDescriptor<RecommendationSource>()))?.contains {
                $0.remoteID == mutation.entityID && $0.ownerUserId == userID
            } == true
        case .profile:
            return mutation.entityID == userID
        case .restaurantList:
            return (try? context.fetch(FetchDescriptor<RestaurantList>()))?.contains {
                $0.remoteID == mutation.entityID && $0.ownerUserID == userID
            } == true
        case .restaurantListItem:
            return (try? context.fetch(FetchDescriptor<RestaurantListItem>()))?.contains {
                $0.remoteID == mutation.entityID && $0.ownerUserID == userID
            } == true
        }
    }
}
#endif
