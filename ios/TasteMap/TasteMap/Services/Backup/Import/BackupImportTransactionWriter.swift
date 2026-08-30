import Foundation
import SwiftData

nonisolated enum BackupImportFailurePoint: String, Sendable {
    case afterRestaurants
    case afterVisits
    case beforeMutations
    case beforeSave
}

nonisolated struct BackupImportTransactionResult: Equatable, Sendable {
    let planID: UUID
    let writtenEntityCount: Int
    let queuedMutationCount: Int
    let transactionSeconds: Double
}

/// Executes a previously reviewed plan in one disposable SwiftData context.
/// The product UI intentionally does not call this until F1-C4.
@MainActor
struct BackupImportTransactionWriter {
    let container: ModelContainer
    var injectedFailurePoint: BackupImportFailurePoint?

    func execute(
        _ confirmed: ConfirmedBackupImportPlan,
        currentTasteMapUserID: String
    ) throws -> BackupImportTransactionResult {
        guard confirmed.plan.currentTasteMapUserID == currentTasteMapUserID else {
            throw BackupImportPlanningError.userChanged
        }
        guard confirmed.plan.sourceFileSHA256 == confirmed.sourceGraph.sourceFileSHA256 else {
            throw BackupImportPlanningError.sourceHashMismatch
        }
        guard confirmed.plan.canBeConfirmed else {
            throw BackupImportPlanningError.unresolvedReview(
                confirmed.plan.reviewItems.first?.id ?? "blocked"
            )
        }

        let clock = ContinuousClock()
        let started = clock.now
        var transactionContext: ModelContext? = ModelContext(container)
        var writtenCount = 0
        var mutationCount = 0
        do {
            try transactionContext!.transaction {
                guard let context = transactionContext else {
                    throw BackupImportPlanningError.transactionFailed
                }
                let freshSnapshot = try BackupImportLocalSnapshotBuilder(context: context)
                    .make(currentTasteMapUserID: currentTasteMapUserID)
                guard freshSnapshot.revision == confirmed.plan.localSnapshotRevision else {
                    throw BackupImportPlanningError.planStale
                }
                let regenerated = try BackupImportPlanEngine().makePlan(
                    source: confirmed.sourceGraph,
                    local: freshSnapshot,
                    decisions: confirmed.decisions,
                    generatedAt: confirmed.plan.generatedAt
                )
                guard regenerated == confirmed.plan else {
                    throw BackupImportPlanningError.planStale
                }

                let state = try writeEntities(
                    plan: confirmed.plan,
                    source: confirmed.sourceGraph,
                    decisions: confirmed.decisions,
                    currentUserID: currentTasteMapUserID,
                    context: context
                )
                try failIfRequested(.beforeSave)
                try context.save()
                writtenCount = state.writtenCount
                mutationCount = state.mutationCount
            }
            transactionContext = nil
            return BackupImportTransactionResult(
                planID: confirmed.plan.planID,
                writtenEntityCount: writtenCount,
                queuedMutationCount: mutationCount,
                transactionSeconds: Self.seconds(started.duration(to: clock.now))
            )
        } catch {
            transactionContext?.rollback()
            transactionContext = nil
            throw error
        }
    }

    private func writeEntities(
        plan: BackupImportPlan,
        source: BackupImportSourceGraph,
        decisions: [BackupImportReviewDecision],
        currentUserID: String,
        context: ModelContext
    ) throws -> WriteState {
        let actions = Dictionary(uniqueKeysWithValues: plan.actions.map { ($0.id, $0) })
        var state = WriteState()

        for value in source.restaurants.sorted(by: { $0.sourceID < $1.sourceID }) {
            guard let action = actions["restaurant:\(value.sourceID)"] else { continue }
            switch action.action {
            case .create:
                let model = try makeRestaurant(value, action: action, currentUserID: currentUserID)
                context.insert(model)
                state.restaurants[value.sourceID] = model
                state.mutations.append(.restaurant(model))
                state.writtenCount += 1
            case .exactMerge:
                let model: Restaurant = try existing(action, context: context)
                if try mergePlaceIdentities(value, into: model, currentUserID: currentUserID) {
                    model.syncStatus = .pending
                    state.mutations.append(.restaurant(model))
                    state.writtenCount += 1
                }
                state.restaurants[value.sourceID] = model
            case .exactDuplicate:
                state.restaurants[value.sourceID] = try existing(action, context: context)
            case .skip: break
            default: throw BackupImportPlanningError.unresolvedReview(action.id)
            }
        }
        try failIfRequested(.afterRestaurants)

        for value in source.companions.sorted(by: { $0.sourceID < $1.sourceID }) {
            guard let action = actions["companion:\(value.sourceID)"] else { continue }
            if action.action == .create {
                let id = try targetUUID(action)
                let model = DiningCompanion(
                    id: id, ownerUserId: currentUserID, displayName: value.displayName,
                    linkedTasteMapUserId: nil, createdAt: value.createdAt, updatedAt: value.updatedAt,
                    remoteID: id.uuidString.lowercased(), serverVersion: 0, syncStatus: .pending
                )
                context.insert(model); state.companions[value.sourceID] = model
                state.mutations.append(.companion(model)); state.writtenCount += 1
            } else if action.action == .exactMerge || action.action == .exactDuplicate {
                state.companions[value.sourceID] = try existing(action, context: context)
            } else if action.action != .skip { throw BackupImportPlanningError.unresolvedReview(action.id) }
        }

        for value in source.recommendationSources.sorted(by: { $0.sourceID < $1.sourceID }) {
            guard let action = actions["recommendationSource:\(value.sourceID)"] else { continue }
            if action.action == .create {
                let id = try targetUUID(action)
                let model = RecommendationSource(
                    id: id, ownerUserId: currentUserID, displayName: value.displayName,
                    sourceType: RecommendationSourceType(rawValue: value.sourceType) ?? .other,
                    linkedTasteMapUserId: nil, createdAt: value.createdAt, updatedAt: value.updatedAt,
                    remoteID: id.uuidString.lowercased(), serverVersion: 0, syncStatus: .pending
                )
                context.insert(model); state.recommendationSources[value.sourceID] = model
                state.mutations.append(.recommendationSource(model)); state.writtenCount += 1
            } else if action.action == .exactMerge || action.action == .exactDuplicate {
                state.recommendationSources[value.sourceID] = try existing(action, context: context)
            } else if action.action != .skip { throw BackupImportPlanningError.unresolvedReview(action.id) }
        }

        for value in source.restaurantLists.sorted(by: { $0.sourceID < $1.sourceID }) {
            guard let action = actions["restaurantList:\(value.sourceID)"] else { continue }
            if action.action == .create {
                let id = try targetUUID(action)
                let model = RestaurantList(
                    id: id, remoteID: id.uuidString.lowercased(), ownerUserID: currentUserID,
                    title: value.title, listDescription: value.listDescription,
                    visibility: RestaurantListVisibility(rawValue: value.visibility) ?? .private,
                    isRanked: value.isRanked, coverMode: .automatic, customCoverPhotoID: nil,
                    createdAt: value.createdAt, updatedAt: value.updatedAt,
                    serverVersion: 0, syncStatus: .pending
                )
                context.insert(model); state.lists[value.sourceID] = model
                state.mutations.append(.list(model)); state.writtenCount += 1
            } else if action.action == .exactDuplicate || action.action == .exactMerge {
                state.lists[value.sourceID] = try existing(action, context: context)
            } else if action.action != .skip { throw BackupImportPlanningError.unresolvedReview(action.id) }
        }

        for value in source.profiles.sorted(by: { $0.sourceID < $1.sourceID }) {
            guard let action = actions["profile:\(value.sourceID)"] else { continue }
            if action.action == .create {
                let id = try targetUUID(action)
                let model = UserProfile(
                    id: id, tasteMapUserID: currentUserID, displayName: value.displayName,
                    bio: value.bio, city: value.city, avatarPhotoID: nil,
                    avatarPreset: ProfileAvatarPreset(rawValue: value.avatarPresetID) ?? .polarBear,
                    visibility: ProfileVisibility(rawValue: value.visibility) ?? .private,
                    createdAt: value.createdAt, updatedAt: value.updatedAt,
                    serverVersion: 0, syncStatus: .pending
                )
                context.insert(model); state.mutations.append(.profile(model)); state.writtenCount += 1
            } else if action.action == .exactMerge {
                let model: UserProfile = try existing(action, context: context)
                let original = (model.displayName, model.bio, model.city, model.visibility, model.avatarPreset)
                model.displayName = resolvedProfileValue("displayName", current: model.displayName, source: value.displayName, sourceID: value.sourceID, decisions: decisions)
                model.bio = resolvedProfileValue("bio", current: model.bio, source: value.bio, sourceID: value.sourceID, decisions: decisions)
                model.city = resolvedProfileValue("city", current: model.city, source: value.city, sourceID: value.sourceID, decisions: decisions)
                let visibility = resolvedProfileValue("visibility", current: model.visibility.rawValue, source: value.visibility, sourceID: value.sourceID, decisions: decisions)
                model.visibility = ProfileVisibility(rawValue: visibility) ?? model.visibility
                let avatarPreset = resolvedProfileValue("avatarPresetID", current: model.avatarPreset.rawValue, source: value.avatarPresetID, sourceID: value.sourceID, decisions: decisions)
                model.avatarPreset = ProfileAvatarPreset(rawValue: avatarPreset) ?? model.avatarPreset
                if original.0 != model.displayName || original.1 != model.bio || original.2 != model.city || original.3 != model.visibility || original.4 != model.avatarPreset {
                    model.updatedAt = .now; model.syncStatus = .pending
                    state.mutations.append(.profile(model)); state.writtenCount += 1
                }
            } else if action.action != .exactDuplicate && action.action != .skip {
                throw BackupImportPlanningError.unresolvedReview(action.id)
            }
        }

        for value in source.visits.sorted(by: { $0.sourceID < $1.sourceID }) {
            guard let action = actions["visit:\(value.sourceID)"] else { continue }
            if action.action == .create {
                guard let restaurant = state.restaurants[value.sourceRestaurantID] else {
                    throw BackupImportPlanningError.transactionFailed
                }
                let id = try targetUUID(action)
                let companions = value.companionSourceIDs.compactMap { state.companions[$0] }
                let recommendation = value.recommendationSourceID.flatMap { state.recommendationSources[$0] }
                let model = Visit(
                    id: id, ownerUserID: currentUserID,
                    restaurantId: restaurant.id, visitedAt: value.visitedAt,
                    rating: value.rating, valueRating: value.valueRating,
                    environmentRating: value.environmentRating, serviceRating: value.serviceRating,
                    note: value.note, myActualSpend: value.myActualSpend, totalPrice: value.totalPrice,
                    pricePerPerson: value.pricePerPerson,
                    diningMode: DiningMode(rawValue: value.diningMode) ?? .dineIn,
                    visibility: VisitVisibility(rawValue: value.visibility) ?? .private,
                    paymentMode: value.paymentMode.flatMap(VisitPaymentMode.init(rawValue:)),
                    queueDuration: value.queueDuration.flatMap(VisitQueueDuration.init(rawValue:)),
                    diningOccasions: value.diningOccasions.compactMap(VisitDiningOccasion.init(rawValue:)),
                    diningOccasionText: value.diningOccasionText,
                    valueTags: value.valueTags, environmentTags: value.environmentTags,
                    serviceTags: value.serviceTags,
                    noiseLevel: value.noiseLevel.flatMap(VisitNoiseLevel.init(rawValue:)),
                    diningDuration: value.diningDuration.flatMap(VisitDiningDuration.init(rawValue:)),
                    portionLevel: value.portionLevel.flatMap(VisitPortionLevel.init(rawValue:)),
                    transportConvenience: value.transportConvenience.flatMap(VisitTransportConvenience.init(rawValue:)),
                    specialNotes: value.specialNotes,
                    companionIDs: companions.compactMap(\.remoteID), companionNames: companions.map(\.displayName),
                    recommendationSourceID: recommendation?.remoteID,
                    recommendationSourceType: recommendation?.sourceType,
                    recommendationSourceUserID: nil,
                    recommendationSourceText: value.recommendationSourceText,
                    sharedMealID: nil, partySize: value.partySize,
                    createdAt: value.createdAt, updatedAt: value.updatedAt,
                    remoteID: id.uuidString.lowercased(), serverVersion: 0, syncStatus: .pending
                )
                model.paymentModeRawValue = value.paymentMode
                model.queueDurationRawValue = value.queueDuration
                model.diningOccasionRawValues = value.diningOccasions
                model.noiseLevelRawValue = value.noiseLevel
                model.diningDurationRawValue = value.diningDuration
                model.portionLevelRawValue = value.portionLevel
                model.transportConvenienceRawValue = value.transportConvenience
                model.recommendationSourceTypeRawValue = recommendation?.sourceType.rawValue ?? value.recommendationSourceType
                context.insert(model); state.visits[value.sourceID] = model
                state.mutations.append(.visit(model, restaurant)); state.writtenCount += 1
            } else if action.action == .exactDuplicate {
                state.visits[value.sourceID] = try existing(action, context: context)
            } else if action.action != .skip { throw BackupImportPlanningError.unresolvedReview(action.id) }
        }
        try failIfRequested(.afterVisits)

        for value in source.dishes.sorted(by: { $0.sourceID < $1.sourceID }) {
            guard let action = actions["dish:\(value.sourceID)"],
                  let restaurant = state.restaurants[value.sourceRestaurantID],
                  let visit = state.visits[value.sourceVisitID] else { continue }
            if action.action == .create {
                let id = try targetUUID(action)
                let model = Dish(
                    id: id, ownerUserID: currentUserID,
                    restaurantId: restaurant.id, visitId: visit.id, name: value.name,
                    taste: value.taste, rating: value.rating, price: value.price,
                    photoRemoteID: nil, sortOrder: value.sortOrder,
                    createdAt: value.createdAt, updatedAt: value.updatedAt,
                    remoteID: id.uuidString.lowercased(), serverVersion: 0, syncStatus: .pending
                )
                context.insert(model); state.dishes[value.sourceID] = model
                state.mutations.append(.dish(model, restaurant, visit)); state.writtenCount += 1
            } else if action.action == .exactDuplicate || action.action == .exactMerge {
                let model: Dish = try existing(action, context: context)
                state.dishes[value.sourceID] = model
            } else if action.action != .skip { throw BackupImportPlanningError.unresolvedReview(action.id) }
        }

        for value in source.restaurantListItems.sorted(by: { ($0.sourceListID, $0.position, $0.sourceID) < ($1.sourceListID, $1.position, $1.sourceID) }) {
            guard let action = actions["restaurantListItem:\(value.sourceID)"],
                  let list = state.lists[value.sourceListID],
                  let restaurant = state.restaurants[value.sourceRestaurantID] else { continue }
            if action.action == .create {
                let id = try targetUUID(action)
                let place = try makeListPlace(restaurant)
                let model = try RestaurantListItem(
                    id: id, remoteID: id.uuidString.lowercased(), ownerUserID: currentUserID,
                    listID: list.id, listRemoteID: list.remoteID ?? list.id.uuidString.lowercased(),
                    restaurantReferenceID: restaurant.remoteID ?? restaurant.id.uuidString.lowercased(),
                    localRestaurantID: restaurant.id, restaurantGlobalKey: place.globalKey,
                    restaurantSnapshot: place, position: value.position, note: value.note,
                    createdAt: value.createdAt, updatedAt: value.updatedAt,
                    serverVersion: 0, syncStatus: .pending
                )
                context.insert(model); state.mutations.append(.listItem(model)); state.writtenCount += 1
                list.activeItemCount += 1
            } else if action.action != .exactDuplicate && action.action != .skip {
                throw BackupImportPlanningError.unresolvedReview(action.id)
            }
        }

        for value in source.visitDishes.sorted(by: { $0.sourceID < $1.sourceID }) {
            guard let action = actions["visitDish:\(value.sourceID)"],
                  let restaurant = state.restaurants[value.sourceRestaurantID],
                  let visit = state.visits[value.sourceVisitID],
                  let dish = state.dishes[value.sourceDishID] else { continue }
            if action.action == .create {
                let id = try targetUUID(action)
                let model = VisitDish(
                    id: id, ownerUserID: currentUserID,
                    restaurantId: restaurant.id, visitId: visit.id, dishId: dish.id,
                    sortOrder: value.sortOrder, createdAt: value.createdAt, updatedAt: value.updatedAt,
                    remoteID: id.uuidString.lowercased(), serverVersion: 0, syncStatus: .pending
                )
                context.insert(model); state.mutations.append(.visitDish(model, restaurant, visit, dish)); state.writtenCount += 1
            } else if action.action != .exactDuplicate && action.action != .skip {
                throw BackupImportPlanningError.unresolvedReview(action.id)
            }
        }

        try failIfRequested(.beforeMutations)
        let queue = SwiftDataSyncQueue(context: context, ownerUserID: currentUserID)
        var mutationCount = 0
        for mutation in state.mutations.sorted(by: { $0.priority < $1.priority }) {
            try mutation.enqueue(queue)
            mutationCount += 1
        }
        state.mutationCount = mutationCount
        return state
    }

    private func makeRestaurant(
        _ value: BackupImportSourceRestaurant,
        action: BackupImportPlannedAction,
        currentUserID: String
    ) throws -> Restaurant {
        let id = try targetUUID(action)
        let identities = try normalizedIdentities(value.placeIdentities, fallbackID: id.uuidString.lowercased(), createdAt: value.createdAt, updatedAt: value.updatedAt)
        let contract = try RestaurantJSONContractV1(
            id: id.uuidString.lowercased(), userId: currentUserID, placeIdentities: identities,
            amapPoiId: nil, name: value.name, address: value.address, city: value.city,
            latitude: value.latitude, longitude: value.longitude,
            status: RestaurantJSONContractV1.RestaurantStatusContract(rawValue: value.status) ?? .visited,
            preferenceLevel: RestaurantJSONContractV1.RestaurantPreferenceContract(rawValue: value.preferenceLevel) ?? .normal,
            overallRating: value.overallRating, foodRating: value.foodRating,
            environmentRating: value.environmentRating, serviceRating: value.serviceRating,
            valueRating: value.valueRating, tags: value.tags, longTermNote: value.longTermNote,
            pricePerPerson: value.pricePerPerson.map { NSDecimalNumber(decimal: $0).doubleValue },
            phone: value.phone, openingHours: value.openingHours,
            markerType: RestaurantJSONContractV1.RestaurantMarkerTypeContract(rawValue: value.markerType) ?? .emoji,
            markerPhotoId: nil, merchantImageUrl: value.merchantImageURL,
            markerEmoji: value.markerEmoji, createdAt: SyncRecordMapper.dateString(value.createdAt),
            updatedAt: SyncRecordMapper.dateString(value.updatedAt), deletedAt: nil
        )
        let model = Restaurant(
            id: id, ownerUserID: currentUserID,
            name: value.name, address: value.address, latitude: value.latitude,
            longitude: value.longitude,
            appleMapItemIdentifier: identities.first(where: { $0.provider == .appleMaps })?.externalId,
            city: value.city,
            status: value.status == "wantToGo" ? .wantToGo : .visited,
            createdAt: value.createdAt, updatedAt: value.updatedAt,
            remoteID: id.uuidString.lowercased(), serverVersion: 0,
            syncStatus: .pending, remoteRecordData: try JSONEncoder().encode(contract)
        )
        return model
    }

    private func mergePlaceIdentities(
        _ value: BackupImportSourceRestaurant,
        into model: Restaurant,
        currentUserID: String
    ) throws -> Bool {
        let current = try SyncRecordMapper.restaurantRecord(model)
        guard current.userId == currentUserID else { throw BackupImportPlanningError.userChanged }
        var identities = current.placeIdentities
        var didChange = false
        for incoming in value.placeIdentities {
            guard let provider = RestaurantPlaceProvider(rawValue: incoming.provider),
                  !identities.contains(where: { $0.provider == provider && $0.externalId == incoming.externalID }) else { continue }
            identities.append(try RestaurantPlaceIdentityContract(
                provider: provider, externalId: incoming.externalID, isPrimary: false,
                createdAt: SyncRecordMapper.dateString(value.createdAt),
                updatedAt: SyncRecordMapper.dateString(value.updatedAt)
            ))
            didChange = true
        }
        guard didChange else { return false }
        let merged = try RestaurantJSONContractV1(
            id: current.id, userId: currentUserID, placeIdentities: identities,
            amapPoiId: current.amapPoiId, name: current.name, address: current.address,
            city: current.city, latitude: current.latitude, longitude: current.longitude,
            status: current.status, preferenceLevel: current.preferenceLevel,
            overallRating: current.overallRating, foodRating: current.foodRating,
            environmentRating: current.environmentRating, serviceRating: current.serviceRating,
            valueRating: current.valueRating, tags: current.tags, longTermNote: current.longTermNote,
            pricePerPerson: current.pricePerPerson, phone: current.phone,
            openingHours: current.openingHours, markerType: current.markerType,
            markerPhotoId: current.markerPhotoId, merchantImageUrl: current.merchantImageUrl,
            markerEmoji: current.markerEmoji, createdAt: current.createdAt,
            updatedAt: SyncRecordMapper.dateString(.now), deletedAt: current.deletedAt,
            isTestData: current.isTestData
        )
        model.remoteRecordData = try JSONEncoder().encode(merged)
        model.updatedAt = .now
        return true
    }

    private func normalizedIdentities(
        _ source: [BackupImportSourcePlaceIdentity], fallbackID: String,
        createdAt: Date, updatedAt: Date
    ) throws -> [RestaurantPlaceIdentityContract] {
        var values = source.compactMap { value -> (RestaurantPlaceProvider, String, Bool)? in
            guard let provider = RestaurantPlaceProvider(rawValue: value.provider),
                  !value.externalID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return (provider, value.externalID, value.isPrimary)
        }
        if values.isEmpty { values = [(.manual, "tastemap:\(fallbackID)", true)] }
        let primaryIndex = values.firstIndex(where: { $0.2 }) ?? 0
        return try values.enumerated().map { index, value in
            try RestaurantPlaceIdentityContract(
                provider: value.0, externalId: value.1, isPrimary: index == primaryIndex,
                createdAt: SyncRecordMapper.dateString(createdAt), updatedAt: SyncRecordMapper.dateString(updatedAt)
            )
        }
    }

    private func makeListPlace(_ restaurant: Restaurant) throws -> RestaurantListPlaceContractV1 {
        let record = try SyncRecordMapper.restaurantRecord(restaurant)
        let identities = record.placeIdentities.map {
            RestaurantListPlaceIdentityContractV1(provider: $0.provider, externalId: $0.externalId, isPrimary: $0.isPrimary)
        }
        let primary = identities.first(where: \.isPrimary)!
        return try RestaurantListPlaceContractV1(
            globalKey: "\(primary.provider.rawValue):\(primary.externalId)",
            restaurantId: restaurant.remoteID ?? restaurant.id.uuidString.lowercased(),
            placeIdentities: identities, name: restaurant.name, address: restaurant.address,
            city: restaurant.city, latitude: restaurant.latitude, longitude: restaurant.longitude,
            markerPhotoId: nil, merchantImageUrl: record.merchantImageUrl, markerEmoji: record.markerEmoji
        )
    }

    private func resolvedProfileValue(
        _ field: String, current: String, source: String, sourceID: String,
        decisions: [BackupImportReviewDecision]
    ) -> String {
        if current.isEmpty { return source }
        let reviewID = "profile:\(sourceID):\(field)"
        return decisions.first(where: { $0.reviewItemID == reviewID })?.selectedOptionID == "useBackup"
            ? source
            : current
    }

    private func targetUUID(_ action: BackupImportPlannedAction) throws -> UUID {
        guard let value = action.targetID, let id = UUID(uuidString: value) else {
            throw BackupImportPlanningError.transactionFailed
        }
        return id
    }

    private func existing<T: PersistentModel>(
        _ action: BackupImportPlannedAction,
        context: ModelContext
    ) throws -> T {
        guard let raw = action.matchedLocalID ?? action.targetID,
              let id = UUID(uuidString: raw) else { throw BackupImportPlanningError.transactionFailed }
        let values = try context.fetch(FetchDescriptor<T>())
        guard let value = values.first(where: { model in
            if let model = model as? Restaurant { return model.id == id }
            if let model = model as? Visit { return model.id == id }
            if let model = model as? Dish { return model.id == id }
            if let model = model as? DiningCompanion { return model.id == id }
            if let model = model as? RecommendationSource { return model.id == id }
            if let model = model as? UserProfile { return model.id == id }
            if let model = model as? RestaurantList { return model.id == id }
            return false
        }) else { throw BackupImportPlanningError.planStale }
        return value
    }

    private func failIfRequested(_ point: BackupImportFailurePoint) throws {
        if injectedFailurePoint == point { throw BackupImportPlanningError.injectedFailure(point.rawValue) }
    }

    private static func seconds(_ duration: Duration) -> Double {
        let value = duration.components
        return Double(value.seconds) + Double(value.attoseconds) / 1e18
    }
}

@MainActor
private struct WriteState {
    var restaurants: [String: Restaurant] = [:]
    var visits: [String: Visit] = [:]
    var dishes: [String: Dish] = [:]
    var companions: [String: DiningCompanion] = [:]
    var recommendationSources: [String: RecommendationSource] = [:]
    var lists: [String: RestaurantList] = [:]
    var mutations: [BackupImportPendingMutation] = []
    var writtenCount = 0
    var mutationCount = 0
}

@MainActor
private enum BackupImportPendingMutation {
    case restaurant(Restaurant)
    case companion(DiningCompanion)
    case recommendationSource(RecommendationSource)
    case list(RestaurantList)
    case profile(UserProfile)
    case visit(Visit, Restaurant)
    case dish(Dish, Restaurant, Visit)
    case listItem(RestaurantListItem)
    case visitDish(VisitDish, Restaurant, Visit, Dish)

    var priority: Int {
        switch self {
        case .restaurant, .companion, .recommendationSource, .list: 0
        case .visit, .listItem: 1
        case .dish: 2
        case .visitDish: 3
        case .profile: 5
        }
    }

    func enqueue(_ queue: SwiftDataSyncQueue) throws {
        switch self {
        case let .restaurant(value):
            try queue.enqueueUpsert(entityType: .restaurant, entityID: value.remoteID!, baseVersion: value.serverVersion, payload: SyncRecordMapper.restaurantPayload(value))
        case let .companion(value):
            try queue.enqueueUpsert(entityType: .companion, entityID: value.remoteID!, baseVersion: value.serverVersion, payload: SyncRecordMapper.companionPayload(value))
        case let .recommendationSource(value):
            try queue.enqueueUpsert(entityType: .recommendationSource, entityID: value.remoteID!, baseVersion: value.serverVersion, payload: SyncRecordMapper.recommendationSourcePayload(value))
        case let .list(value):
            try queue.enqueueUpsert(entityType: .restaurantList, entityID: value.remoteID!, baseVersion: value.serverVersion, payload: SyncRecordMapper.restaurantListPayload(value))
        case let .profile(value):
            try queue.enqueueUpsert(entityType: .profile, entityID: value.tasteMapUserID, baseVersion: value.serverVersion, payload: SyncRecordMapper.profilePayload(value))
        case let .visit(value, restaurant):
            try queue.enqueueUpsert(entityType: .visit, entityID: value.remoteID!, baseVersion: value.serverVersion, payload: SyncRecordMapper.visitPayload(value, restaurantRemoteID: restaurant.remoteID!))
        case let .dish(value, restaurant, visit):
            try queue.enqueueUpsert(entityType: .dish, entityID: value.remoteID!, baseVersion: value.serverVersion, payload: SyncRecordMapper.dishPayload(value, restaurantRemoteID: restaurant.remoteID!, visitRemoteID: visit.remoteID!))
        case let .listItem(value):
            try queue.enqueueUpsert(entityType: .restaurantListItem, entityID: value.remoteID!, baseVersion: value.serverVersion, payload: SyncRecordMapper.restaurantListItemPayload(value))
        case let .visitDish(value, restaurant, visit, dish):
            try queue.enqueueUpsert(entityType: .visitDish, entityID: value.remoteID!, baseVersion: value.serverVersion, payload: SyncRecordMapper.visitDishPayload(value, restaurantRemoteID: restaurant.remoteID!, visitRemoteID: visit.remoteID!, dishRemoteID: dish.remoteID!))
        }
    }
}
