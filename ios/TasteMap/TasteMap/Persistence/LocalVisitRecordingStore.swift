import Foundation
import SwiftData

struct VisitSubmissionGate: Equatable, Sendable {
    private(set) var isSubmitting = false

    mutating func begin() -> Bool {
        guard !isSubmitting else { return false }
        isSubmitting = true
        return true
    }

    mutating func finish() {
        isSubmitting = false
    }
}

struct VisitRecordingCommitResult {
    let restaurant: Restaurant
    let visit: Visit
    let dishesByDraftID: [UUID: Dish]
}

enum LocalVisitRecordingStoreError: Error {
    case missingRestaurant
    case commitDidNotProduceResult
}

/// Commits the business graph for one meal as one SwiftData transaction.
/// Photo binary transfer is intentionally outside this transaction: a failed
/// upload must never make a valid Visit fail or create a duplicate on retry.
@MainActor
struct LocalVisitRecordingStore {
    let context: ModelContext

    func commit(
        restaurant: Restaurant?,
        candidate: RestaurantCandidate?,
        existingVisit: Visit?,
        allRestaurants: [Restaurant],
        draft: VisitDraft,
        dishDrafts: [DishDraft],
        actorUserID: String?
    ) throws -> VisitRecordingCommitResult {
        let validatedDraft = try draft.validated()
        // Validate the complete child set before creating or changing the Visit.
        // A bad Dish can therefore never leave a partially-created meal record.
        _ = try dishDrafts.map { try $0.validated() }

        var result: VisitRecordingCommitResult?
        try context.transaction {
            let tasteMapStore = LocalTasteMapStore(context: context)
            let resolvedRestaurant: Restaurant
            if let restaurant {
                resolvedRestaurant = restaurant
            } else if let candidate {
                resolvedRestaurant = try tasteMapStore.restaurant(
                    for: candidate,
                    among: allRestaurants,
                    status: .visited,
                    actorUserID: actorUserID
                )
            } else {
                throw LocalVisitRecordingStoreError.missingRestaurant
            }

            let savedVisit: Visit
            if let existingVisit {
                guard existingVisit.restaurantId == resolvedRestaurant.id else {
                    throw LocalVisitRecordingStoreError.missingRestaurant
                }
                try tasteMapStore.updateVisitInCurrentTransaction(
                    existingVisit,
                    draft: validatedDraft,
                    actorUserID: actorUserID
                )
                savedVisit = existingVisit
            } else {
                savedVisit = try tasteMapStore.createVisitInCurrentTransaction(
                    restaurantId: resolvedRestaurant.id,
                    draft: validatedDraft,
                    actorUserID: actorUserID
                )
            }

            let dishMap = try LocalDishStore(context: context).reconcile(
                restaurant: resolvedRestaurant,
                visit: savedVisit,
                drafts: dishDrafts,
                pruneExistingAssociations: existingVisit != nil,
                saveChanges: false
            )
            result = VisitRecordingCommitResult(
                restaurant: resolvedRestaurant,
                visit: savedVisit,
                dishesByDraftID: dishMap
            )
            // `ModelContext.transaction` supplies rollback semantics, but it
            // does not replace the explicit durable save used by the former
            // Visit and Dish paths. Persist the complete graph only after all
            // children and sync mutations have been prepared successfully.
            try context.save()
        }
        guard let result else { throw LocalVisitRecordingStoreError.commitDidNotProduceResult }
        return result
    }
}
