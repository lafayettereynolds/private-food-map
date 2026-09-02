import Foundation
import SwiftData

enum LocalDishStoreError: LocalizedError, Equatable {
    case restaurantNotFound
    case visitNotFound
    case dishNotFound
    case missingRemoteMapping

    var errorDescription: String? {
        switch self {
        case .restaurantNotFound: "没有找到这家餐厅。"
        case .visitNotFound: "没有找到这次到访。"
        case .dishNotFound: "没有找到这道菜。"
        case .missingRemoteMapping: "本地同步标识尚未准备好，请稍后重试。"
        }
    }
}

@MainActor
struct LocalDishStore {
    let context: ModelContext

    func activeDishes(restaurantID: UUID) throws -> [Dish] {
        try context.fetch(FetchDescriptor<Dish>())
            .filter { $0.restaurantId == restaurantID && $0.deletedAt == nil }
    }

    func activeAssociations(visitID: UUID) throws -> [VisitDish] {
        try context.fetch(FetchDescriptor<VisitDish>())
            .filter { $0.visitId == visitID && $0.deletedAt == nil }
            .sorted { $0.sortOrder == $1.sortOrder ? $0.createdAt < $1.createdAt : $0.sortOrder < $1.sortOrder }
    }

    func bootstrapLegacyAssociations() throws {
        let dishes = try context.fetch(FetchDescriptor<Dish>())
        let visits = try context.fetch(FetchDescriptor<Visit>())
        let associations = try context.fetch(FetchDescriptor<VisitDish>())
        for dish in dishes where dish.deletedAt == nil {
            guard !associations.contains(where: { $0.dishId == dish.id && $0.visitId == dish.visitId }),
                  let visit = visits.first(where: { $0.id == dish.visitId && $0.deletedAt == nil }),
                  let dishRemoteID = dish.remoteID,
                  let visitRemoteID = visit.remoteID else { continue }
            let association = VisitDish(
                ownerUserID: dish.ownerUserID,
                restaurantId: dish.restaurantId,
                visitId: visit.id,
                dishId: dish.id,
                sortOrder: dish.sortOrder,
                createdAt: dish.createdAt,
                updatedAt: dish.updatedAt,
                remoteID: DishIdentity.legacyAssociationRemoteID(
                    visitRemoteID: visitRemoteID,
                    dishRemoteID: dishRemoteID
                ),
                syncStatus: dish.serverVersion == 0 ? .pending : .synced
            )
            context.insert(association)
            if dish.serverVersion == 0 { try enqueue(association) }
        }
        try context.save()
    }

    @discardableResult
    func reconcile(
        restaurantID: UUID,
        visitID: UUID,
        drafts: [DishDraft],
        saveChanges: Bool = true
    ) throws -> [UUID: Dish] {
        let parents = try activeParents(restaurantID: restaurantID, visitID: visitID)
        return try reconcile(parents: parents, drafts: drafts, saveChanges: saveChanges)
    }

    /// Reconciles against already-resolved parents inside a larger transaction.
    /// This is required when a candidate Restaurant and its first Visit were
    /// inserted in the same transaction and are not fetch-visible yet.
    func reconcile(
        restaurant: Restaurant,
        visit: Visit,
        drafts: [DishDraft],
        pruneExistingAssociations: Bool = true,
        saveChanges: Bool = true
    ) throws -> [UUID: Dish] {
        guard restaurant.deletedAt == nil,
              visit.deletedAt == nil,
              visit.restaurantId == restaurant.id,
              visit.ownerUserID == restaurant.ownerUserID else {
            throw LocalDishStoreError.visitNotFound
        }
        return try reconcile(
            parents: (restaurant: restaurant, visit: visit),
            drafts: drafts,
            pruneExistingAssociations: pruneExistingAssociations,
            saveChanges: saveChanges
        )
    }

    private func reconcile(
        parents: (restaurant: Restaurant, visit: Visit),
        drafts: [DishDraft],
        pruneExistingAssociations: Bool = true,
        saveChanges: Bool
    ) throws -> [UUID: Dish] {
        let validated = try drafts.map { try $0.validated() }
        var result: [UUID: Dish] = [:]
        var desiredDishIDs = Set<UUID>()
        var normalizedInVisit = Set<String>()

        for (index, draft) in validated.enumerated() {
            let normalized = DishIdentity.normalizedName(draft.name)
            guard normalizedInVisit.insert(normalized).inserted else { continue }
            let dish = try resolveDish(draft, parents: parents)
            desiredDishIDs.insert(dish.id)
            try updateIfNeeded(dish, draft: draft)
            _ = try associate(dish, with: parents.visit, restaurant: parents.restaurant, sortOrder: index)
            result[draft.id] = dish
        }

        if pruneExistingAssociations {
            for association in try activeAssociations(visitID: parents.visit.id) where !desiredDishIDs.contains(association.dishId) {
                try remove(association, saveChanges: false)
            }
        }
        if saveChanges { try context.save() }
        return result
    }

    func remove(_ association: VisitDish, saveChanges: Bool = true) throws {
        let remoteID = association.remoteID ?? association.id.uuidString.lowercased()
        let queue = SwiftDataSyncQueue(context: context, ownerUserID: association.ownerUserID)
        if association.serverVersion == 0 {
            try queue.removeMutations(entityType: .visitDish, entityID: remoteID)
            context.delete(association)
        } else {
            association.deletedAt = .now
            association.updatedAt = association.deletedAt ?? .now
            association.syncStatus = .pending
            try queue.enqueueDelete(
                entityType: .visitDish,
                entityID: remoteID,
                baseVersion: association.serverVersion,
                timestamp: association.updatedAt
            )
        }
        if saveChanges { try context.save() }
    }

    func removeAssociations(for visitID: UUID) throws {
        for association in try activeAssociations(visitID: visitID) { try remove(association) }
    }

    private func resolveDish(
        _ draft: DishDraft,
        parents: (restaurant: Restaurant, visit: Visit)
    ) throws -> Dish {
        let dishes = try activeDishes(restaurantID: parents.restaurant.id)
        let normalized = DishIdentity.normalizedName(draft.name)
        let normalizedMatches = dishes
            .filter({ DishIdentity.normalizedName($0.name) == normalized })
            .sorted(by: { $0.createdAt == $1.createdAt ? ($0.remoteID ?? "") < ($1.remoteID ?? "") : $0.createdAt < $1.createdAt })
        if let dishID = draft.dishID,
           let current = dishes.first(where: { $0.id == dishID }) {
            if DishIdentity.normalizedName(current.name) == normalized { return current }
            if let existing = normalizedMatches.first(where: { $0.id != current.id }) { return existing }
            return current
        }
        if let existing = normalizedMatches.first { return existing }
        guard let restaurantRemoteID = parents.restaurant.remoteID else { throw LocalDishStoreError.missingRemoteMapping }
        let preferredRemoteID = DishIdentity.dishRemoteID(
            restaurantRemoteID: restaurantRemoteID,
            normalizedName: normalized
        )
        let remoteID = try context.fetch(FetchDescriptor<Dish>())
            .contains(where: { $0.remoteID == preferredRemoteID })
            ? DishIdentity.fallbackDishRemoteID()
            : preferredRemoteID
        let dish = Dish(
            ownerUserID: parents.restaurant.ownerUserID,
            restaurantId: parents.restaurant.id,
            visitId: parents.visit.id,
            name: draft.name,
            taste: draft.taste,
            rating: draft.rating,
            price: draft.price,
            remoteID: remoteID
        )
        context.insert(dish)
        try enqueue(dish, restaurant: parents.restaurant, originVisit: parents.visit)
        return dish
    }

    private func updateIfNeeded(_ dish: Dish, draft: DishDraft) throws {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let taste = draft.taste.trimmingCharacters(in: .whitespacesAndNewlines)
        guard dish.name != name || dish.taste != taste || dish.rating != draft.rating || dish.price != draft.price else { return }
        dish.name = name
        dish.taste = taste
        dish.rating = Visit.validatedRating(draft.rating)
        dish.price = draft.price
        dish.updatedAt = .now
        let parents = try activeParents(restaurantID: dish.restaurantId, visitID: dish.visitId)
        try enqueue(dish, restaurant: parents.restaurant, originVisit: parents.visit)
    }

    private func associate(
        _ dish: Dish,
        with visit: Visit,
        restaurant: Restaurant,
        sortOrder: Int
    ) throws -> VisitDish {
        let all = try context.fetch(FetchDescriptor<VisitDish>())
        if let existing = all.first(where: { $0.visitId == visit.id && $0.dishId == dish.id }) {
            existing.deletedAt = nil
            existing.sortOrder = sortOrder
            existing.updatedAt = .now
            try enqueue(existing, restaurant: restaurant, visit: visit, dish: dish)
            return existing
        }
        guard let visitRemoteID = visit.remoteID, let dishRemoteID = dish.remoteID else {
            throw LocalDishStoreError.missingRemoteMapping
        }
        let associationRemoteID = dish.visitId == visit.id
            ? DishIdentity.legacyAssociationRemoteID(
                visitRemoteID: visitRemoteID,
                dishRemoteID: dishRemoteID
            )
            : DishIdentity.associationRemoteID(
                visitRemoteID: visitRemoteID,
                dishRemoteID: dishRemoteID
            )
        let association = VisitDish(
            ownerUserID: visit.ownerUserID,
            restaurantId: restaurant.id,
            visitId: visit.id,
            dishId: dish.id,
            sortOrder: sortOrder,
            remoteID: associationRemoteID
        )
        context.insert(association)
        try enqueue(association, restaurant: restaurant, visit: visit, dish: dish)
        return association
    }

    private func enqueue(_ dish: Dish, restaurant: Restaurant, originVisit: Visit) throws {
        guard let restaurantRemoteID = restaurant.remoteID, let visitRemoteID = originVisit.remoteID,
              let remoteID = dish.remoteID else { throw LocalDishStoreError.missingRemoteMapping }
        dish.syncStatus = .pending
        try SwiftDataSyncQueue(context: context, ownerUserID: dish.ownerUserID).enqueueUpsert(
            entityType: .dish,
            entityID: remoteID,
            baseVersion: dish.serverVersion,
            payload: SyncRecordMapper.dishPayload(
                dish,
                restaurantRemoteID: restaurantRemoteID,
                visitRemoteID: visitRemoteID
            ),
            timestamp: dish.updatedAt
        )
    }

    private func enqueue(_ association: VisitDish) throws {
        guard let restaurant = try context.fetch(FetchDescriptor<Restaurant>()).first(where: { $0.id == association.restaurantId }),
              let visit = try context.fetch(FetchDescriptor<Visit>()).first(where: { $0.id == association.visitId }),
              let dish = try context.fetch(FetchDescriptor<Dish>()).first(where: { $0.id == association.dishId }),
              let restaurantRemoteID = restaurant.remoteID, let visitRemoteID = visit.remoteID,
              let dishRemoteID = dish.remoteID else { throw LocalDishStoreError.missingRemoteMapping }
        let remoteID = association.remoteID ?? DishIdentity.associationRemoteID(
            visitRemoteID: visitRemoteID,
            dishRemoteID: dishRemoteID
        )
        association.remoteID = remoteID
        association.syncStatus = .pending
        try SwiftDataSyncQueue(context: context, ownerUserID: association.ownerUserID).enqueueUpsert(
            entityType: .visitDish,
            entityID: remoteID,
            baseVersion: association.serverVersion,
            payload: SyncRecordMapper.visitDishPayload(
                association,
                restaurantRemoteID: restaurantRemoteID,
                visitRemoteID: visitRemoteID,
                dishRemoteID: dishRemoteID
            ),
            timestamp: association.updatedAt
        )
    }

    private func enqueue(
        _ association: VisitDish,
        restaurant: Restaurant,
        visit: Visit,
        dish: Dish
    ) throws {
        guard restaurant.id == association.restaurantId,
              visit.id == association.visitId,
              dish.id == association.dishId,
              restaurant.ownerUserID == association.ownerUserID,
              visit.ownerUserID == association.ownerUserID,
              dish.ownerUserID == association.ownerUserID,
              let restaurantRemoteID = restaurant.remoteID,
              let visitRemoteID = visit.remoteID,
              let dishRemoteID = dish.remoteID else {
            throw LocalDishStoreError.missingRemoteMapping
        }
        let remoteID = association.remoteID ?? DishIdentity.associationRemoteID(
            visitRemoteID: visitRemoteID,
            dishRemoteID: dishRemoteID
        )
        association.remoteID = remoteID
        association.syncStatus = .pending
        try SwiftDataSyncQueue(context: context, ownerUserID: association.ownerUserID).enqueueUpsert(
            entityType: .visitDish,
            entityID: remoteID,
            baseVersion: association.serverVersion,
            payload: SyncRecordMapper.visitDishPayload(
                association,
                restaurantRemoteID: restaurantRemoteID,
                visitRemoteID: visitRemoteID,
                dishRemoteID: dishRemoteID
            ),
            timestamp: association.updatedAt
        )
    }

    private func activeParents(
        restaurantID: UUID,
        visitID: UUID
    ) throws -> (restaurant: Restaurant, visit: Visit) {
        guard let restaurant = try context.fetch(FetchDescriptor<Restaurant>())
            .first(where: { $0.id == restaurantID && $0.deletedAt == nil }) else {
            throw LocalDishStoreError.restaurantNotFound
        }
        guard let visit = try context.fetch(FetchDescriptor<Visit>())
            .first(where: { $0.id == visitID && $0.restaurantId == restaurantID && $0.deletedAt == nil }) else {
            throw LocalDishStoreError.visitNotFound
        }
        guard restaurant.ownerUserID == visit.ownerUserID else {
            throw LocalDishStoreError.visitNotFound
        }
        return (restaurant, visit)
    }
}
