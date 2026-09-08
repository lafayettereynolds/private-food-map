import CryptoKit
import Foundation
import SwiftData

nonisolated struct BackupImportLocalRecord<Value>: Codable, Equatable, Sendable
where Value: Codable & Equatable & Sendable {
    let localID: UUID
    let remoteID: String
    let deletedAt: Date?
    let value: Value
}

nonisolated struct BackupImportLocalSnapshot: Codable, Equatable, Sendable {
    let currentTasteMapUserID: String
    let revision: String
    let restaurants: [BackupImportLocalRecord<BackupImportSourceRestaurant>]
    let visits: [BackupImportLocalRecord<BackupImportSourceVisit>]
    let dishes: [BackupImportLocalRecord<BackupImportSourceDish>]
    let visitDishes: [BackupImportLocalRecord<BackupImportSourceVisitDish>]
    let photos: [BackupImportLocalRecord<BackupImportSourcePhoto>]
    let companions: [BackupImportLocalRecord<BackupImportSourceCompanion>]
    let recommendationSources: [BackupImportLocalRecord<BackupImportSourceRecommendationSource>]
    let profiles: [BackupImportLocalRecord<BackupImportSourceProfile>]
    let restaurantLists: [BackupImportLocalRecord<BackupImportSourceRestaurantList>]
    let restaurantListItems: [BackupImportLocalRecord<BackupImportSourceRestaurantListItem>]
}

@MainActor
struct BackupImportLocalSnapshotBuilder {
    let context: ModelContext

    func make(currentTasteMapUserID: String) throws -> BackupImportLocalSnapshot {
        guard Self.isTasteMapUserID(currentTasteMapUserID) else {
            throw BackupImportPlanningError.invalidCurrentUser
        }

        let allRestaurants = try context.fetch(FetchDescriptor<Restaurant>())
        var restaurants: [BackupImportLocalRecord<BackupImportSourceRestaurant>] = []
        var restaurantRemoteIDs: [UUID: String] = [:]
        for model in allRestaurants {
            let remoteID = model.remoteID ?? model.id.uuidString.lowercased()
            let record: RestaurantJSONContractV1
            do { record = try SyncRecordMapper.restaurantRecord(model) }
            catch {
                throw BackupImportPlanningError.invalidLocalRecord(
                    entityType: .restaurant,
                    entityID: remoteID
                )
            }
            if record.userId == "local" {
                throw BackupImportPlanningError.ambiguousLocalOwnership(
                    entityType: .restaurant,
                    entityID: remoteID
                )
            }
            guard record.userId == currentTasteMapUserID else { continue }
            restaurantRemoteIDs[model.id] = remoteID
            restaurants.append(BackupImportLocalRecord(
                localID: model.id,
                remoteID: remoteID,
                deletedAt: model.deletedAt,
                value: BackupImportSourceRestaurant(
                    sourceID: remoteID,
                    placeIdentities: record.placeIdentities.map {
                        BackupImportSourcePlaceIdentity(
                            provider: $0.provider.rawValue,
                            externalID: $0.externalId,
                            isPrimary: $0.isPrimary
                        )
                    },
                    name: model.name,
                    address: model.address,
                    city: model.city,
                    latitude: model.latitude,
                    longitude: model.longitude,
                    status: model.status == .visited ? "visited" : "wantToGo",
                    preferenceLevel: record.preferenceLevel.rawValue,
                    overallRating: record.overallRating,
                    foodRating: record.foodRating,
                    environmentRating: record.environmentRating,
                    serviceRating: record.serviceRating,
                    valueRating: record.valueRating,
                    tags: record.tags,
                    longTermNote: record.longTermNote,
                    pricePerPerson: record.pricePerPerson.map { Decimal($0) },
                    phone: record.phone,
                    websiteURL: record.websiteUrl,
                    openingHours: record.openingHours,
                    markerType: record.markerType.rawValue,
                    markerPhotoSourceID: record.markerPhotoId,
                    merchantImageURL: record.merchantImageUrl,
                    markerEmoji: record.markerEmoji,
                    createdAt: model.createdAt,
                    updatedAt: model.updatedAt
                )
            ))
        }

        let allVisits = try context.fetch(FetchDescriptor<Visit>())
        var visitRemoteIDs: [UUID: String] = [:]
        let visits = allVisits.compactMap { model -> BackupImportLocalRecord<BackupImportSourceVisit>? in
            guard model.ownerUserID == currentTasteMapUserID else { return nil }
            guard let restaurantRemoteID = restaurantRemoteIDs[model.restaurantId] else { return nil }
            let remoteID = model.remoteID ?? model.id.uuidString.lowercased()
            visitRemoteIDs[model.id] = remoteID
            return BackupImportLocalRecord(
                localID: model.id,
                remoteID: remoteID,
                deletedAt: model.deletedAt,
                value: BackupImportSourceVisit(
                    sourceID: remoteID,
                    sourceRestaurantID: restaurantRemoteID,
                    visitedAt: model.visitedAt,
                    diningMode: model.diningMode.rawValue,
                    visibility: model.visibility.rawValue,
                    partySize: model.partySize,
                    totalPrice: model.totalPrice,
                    myActualSpend: model.myActualSpend,
                    paymentMode: model.paymentModeRawValue,
                    pricePerPerson: model.pricePerPerson,
                    queueDuration: model.queueDurationRawValue,
                    diningOccasions: model.diningOccasionRawValues,
                    diningOccasionText: model.diningOccasionText,
                    rating: model.rating,
                    valueRating: model.valueRating,
                    environmentRating: model.environmentRating,
                    serviceRating: model.serviceRating,
                    valueTags: model.valueTags,
                    environmentTags: model.environmentTags,
                    serviceTags: model.serviceTags,
                    noiseLevel: model.noiseLevelRawValue,
                    diningDuration: model.diningDurationRawValue,
                    portionLevel: model.portionLevelRawValue,
                    transportConvenience: model.transportConvenienceRawValue,
                    specialNotes: model.specialNotes,
                    companionSourceIDs: model.companionIDs,
                    recommendationSourceID: model.recommendationSourceID,
                    recommendationSourceType: model.recommendationSourceTypeRawValue,
                    recommendationSourceText: model.recommendationSourceText,
                    note: model.note,
                    createdAt: model.createdAt,
                    updatedAt: model.updatedAt
                )
            )
        }

        let allDishes = try context.fetch(FetchDescriptor<Dish>())
        var dishRemoteIDs: [UUID: String] = [:]
        let dishes = allDishes.compactMap { model -> BackupImportLocalRecord<BackupImportSourceDish>? in
            guard model.ownerUserID == currentTasteMapUserID else { return nil }
            guard let restaurantRemoteID = restaurantRemoteIDs[model.restaurantId],
                  let visitRemoteID = visitRemoteIDs[model.visitId] else { return nil }
            let remoteID = model.remoteID ?? model.id.uuidString.lowercased()
            dishRemoteIDs[model.id] = remoteID
            return BackupImportLocalRecord(
                localID: model.id,
                remoteID: remoteID,
                deletedAt: model.deletedAt,
                value: BackupImportSourceDish(
                    sourceID: remoteID,
                    sourceRestaurantID: restaurantRemoteID,
                    sourceVisitID: visitRemoteID,
                    name: model.name,
                    taste: model.taste,
                    rating: model.rating,
                    price: model.price,
                    sourcePhotoID: model.photoRemoteID,
                    sortOrder: model.sortOrder,
                    createdAt: model.createdAt,
                    updatedAt: model.updatedAt
                )
            )
        }

        let visitDishes = try context.fetch(FetchDescriptor<VisitDish>()).compactMap {
            model -> BackupImportLocalRecord<BackupImportSourceVisitDish>? in
            guard model.ownerUserID == currentTasteMapUserID else { return nil }
            guard let restaurantRemoteID = restaurantRemoteIDs[model.restaurantId],
                  let visitRemoteID = visitRemoteIDs[model.visitId],
                  let dishRemoteID = dishRemoteIDs[model.dishId] else { return nil }
            let remoteID = model.remoteID ?? model.id.uuidString.lowercased()
            return BackupImportLocalRecord(
                localID: model.id,
                remoteID: remoteID,
                deletedAt: model.deletedAt,
                value: BackupImportSourceVisitDish(
                    sourceID: remoteID,
                    sourceRestaurantID: restaurantRemoteID,
                    sourceVisitID: visitRemoteID,
                    sourceDishID: dishRemoteID,
                    sortOrder: model.sortOrder,
                    createdAt: model.createdAt,
                    updatedAt: model.updatedAt
                )
            )
        }

        let companions = try context.fetch(FetchDescriptor<DiningCompanion>()).compactMap {
            model -> BackupImportLocalRecord<BackupImportSourceCompanion>? in
            let remoteID = model.remoteID ?? model.id.uuidString.lowercased()
            if model.ownerUserId == "local" {
                throw BackupImportPlanningError.ambiguousLocalOwnership(
                    entityType: .companion,
                    entityID: remoteID
                )
            }
            guard model.ownerUserId == currentTasteMapUserID else { return nil }
            return BackupImportLocalRecord(
                localID: model.id,
                remoteID: remoteID,
                deletedAt: model.deletedAt,
                value: BackupImportSourceCompanion(
                    sourceID: remoteID,
                    displayName: model.displayName,
                    createdAt: model.createdAt,
                    updatedAt: model.updatedAt
                )
            )
        }

        let recommendationSources = try context.fetch(FetchDescriptor<RecommendationSource>()).compactMap {
            model -> BackupImportLocalRecord<BackupImportSourceRecommendationSource>? in
            let remoteID = model.remoteID ?? model.id.uuidString.lowercased()
            if model.ownerUserId == "local" {
                throw BackupImportPlanningError.ambiguousLocalOwnership(
                    entityType: .recommendationSource,
                    entityID: remoteID
                )
            }
            guard model.ownerUserId == currentTasteMapUserID else { return nil }
            return BackupImportLocalRecord(
                localID: model.id,
                remoteID: remoteID,
                deletedAt: model.deletedAt,
                value: BackupImportSourceRecommendationSource(
                    sourceID: remoteID,
                    displayName: model.displayName,
                    sourceType: model.sourceType.rawValue,
                    createdAt: model.createdAt,
                    updatedAt: model.updatedAt
                )
            )
        }

        let profiles = try context.fetch(FetchDescriptor<UserProfile>()).compactMap {
            model -> BackupImportLocalRecord<BackupImportSourceProfile>? in
            guard model.tasteMapUserID == currentTasteMapUserID else { return nil }
            return BackupImportLocalRecord(
                localID: model.id,
                remoteID: model.id.uuidString.lowercased(),
                deletedAt: model.deletedAt,
                value: BackupImportSourceProfile(
                    sourceID: model.id.uuidString.lowercased(),
                    displayName: model.displayName,
                    bio: model.bio,
                    city: model.city,
                    avatarPhotoSourceID: model.avatarPhotoID,
                    avatarPresetID: model.avatarPreset.rawValue,
                    visibility: model.visibility.rawValue,
                    createdAt: model.createdAt,
                    updatedAt: model.updatedAt
                )
            )
        }

        let lists = try context.fetch(FetchDescriptor<RestaurantList>()).compactMap {
            model -> BackupImportLocalRecord<BackupImportSourceRestaurantList>? in
            guard model.ownerUserID == currentTasteMapUserID else { return nil }
            let remoteID = model.remoteID ?? model.id.uuidString.lowercased()
            return BackupImportLocalRecord(
                localID: model.id,
                remoteID: remoteID,
                deletedAt: model.deletedAt,
                value: BackupImportSourceRestaurantList(
                    sourceID: remoteID,
                    title: model.title,
                    listDescription: model.listDescription,
                    visibility: model.visibility.rawValue,
                    isRanked: model.isRanked,
                    coverMode: model.coverMode.rawValue,
                    customCoverPhotoSourceID: model.customCoverPhotoID,
                    createdAt: model.createdAt,
                    updatedAt: model.updatedAt
                )
            )
        }
        let listRemoteIDs = Dictionary(uniqueKeysWithValues: lists.map { ($0.localID, $0.remoteID) })

        let listItems = try context.fetch(FetchDescriptor<RestaurantListItem>()).compactMap {
            model -> BackupImportLocalRecord<BackupImportSourceRestaurantListItem>? in
            guard model.ownerUserID == currentTasteMapUserID,
                  let listRemoteID = listRemoteIDs[model.listID] else { return nil }
            let remoteID = model.remoteID ?? model.id.uuidString.lowercased()
            return BackupImportLocalRecord(
                localID: model.id,
                remoteID: remoteID,
                deletedAt: model.deletedAt,
                value: BackupImportSourceRestaurantListItem(
                    sourceID: remoteID,
                    sourceListID: listRemoteID,
                    sourceRestaurantID: model.restaurantReferenceID,
                    position: model.position,
                    note: model.note,
                    createdAt: model.createdAt,
                    updatedAt: model.updatedAt
                )
            )
        }

        let currentProfilePhotoIDs = Set(profiles.compactMap(\.value.avatarPhotoSourceID))
        let photos = try context.fetch(FetchDescriptor<PhotoAsset>()).compactMap {
            model -> BackupImportLocalRecord<BackupImportSourcePhoto>? in
            guard model.ownerUserID == currentTasteMapUserID else { return nil }
            let belongs = model.restaurantId.flatMap { restaurantRemoteIDs[$0] } != nil
                || model.visitId.flatMap { visitRemoteIDs[$0] } != nil
                || model.dishId.flatMap { dishRemoteIDs[$0] } != nil
                || currentProfilePhotoIDs.contains(model.remoteID ?? model.id.uuidString.lowercased())
            guard belongs else { return nil }
            let remoteID = model.remoteID ?? model.id.uuidString.lowercased()
            let parent: (String, String)?
            if let id = model.restaurantId.flatMap({ restaurantRemoteIDs[$0] }) { parent = ("restaurant", id) }
            else if let id = model.visitId.flatMap({ visitRemoteIDs[$0] }) { parent = ("visit", id) }
            else if let id = model.dishId.flatMap({ dishRemoteIDs[$0] }) { parent = ("dish", id) }
            else if let profile = profiles.first(where: { $0.value.avatarPhotoSourceID == remoteID }) {
                parent = ("profile", profile.remoteID)
            } else { parent = nil }
            guard let parent else { return nil }
            return BackupImportLocalRecord(
                localID: model.id,
                remoteID: remoteID,
                deletedAt: model.deletedAt,
                value: BackupImportSourcePhoto(
                    sourceID: remoteID,
                    parentEntityType: parent.0,
                    parentSourceID: parent.1,
                    kind: model.kind.rawValue,
                    fileName: model.fileName,
                    mimeType: model.mimeType,
                    byteSize: model.byteSize,
                    width: model.width,
                    height: model.height,
                    sortOrder: model.sortOrder,
                    visibility: model.visibility.rawValue,
                    createdAt: model.createdAt,
                    updatedAt: model.updatedAt,
                    binaryAvailable: model.localFileRelativePath != nil || model.storageKey != nil
                )
            )
        }

        let payload = RevisionPayload(
            currentTasteMapUserID: currentTasteMapUserID,
            restaurants: restaurants.sorted(by: Self.recordSort),
            visits: visits.sorted(by: Self.recordSort),
            dishes: dishes.sorted(by: Self.recordSort),
            visitDishes: visitDishes.sorted(by: Self.recordSort),
            photos: photos.sorted(by: Self.recordSort),
            companions: companions.sorted(by: Self.recordSort),
            recommendationSources: recommendationSources.sorted(by: Self.recordSort),
            profiles: profiles.sorted(by: Self.recordSort),
            restaurantLists: lists.sorted(by: Self.recordSort),
            restaurantListItems: listItems.sorted(by: Self.recordSort)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        let revision = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return BackupImportLocalSnapshot(
            currentTasteMapUserID: currentTasteMapUserID,
            revision: revision,
            restaurants: payload.restaurants,
            visits: payload.visits,
            dishes: payload.dishes,
            visitDishes: payload.visitDishes,
            photos: payload.photos,
            companions: payload.companions,
            recommendationSources: payload.recommendationSources,
            profiles: payload.profiles,
            restaurantLists: payload.restaurantLists,
            restaurantListItems: payload.restaurantListItems
        )
    }

    private static func recordSort<Value>(
        _ lhs: BackupImportLocalRecord<Value>,
        _ rhs: BackupImportLocalRecord<Value>
    ) -> Bool where Value: Codable & Equatable & Sendable {
        lhs.remoteID < rhs.remoteID
    }

    private static func isTasteMapUserID(_ value: String) -> Bool {
        value.range(of: #"^tm_[A-Za-z0-9_-]{3,120}$"#, options: .regularExpression) != nil
    }
}

private nonisolated struct RevisionPayload: Codable, Sendable {
    let currentTasteMapUserID: String
    let restaurants: [BackupImportLocalRecord<BackupImportSourceRestaurant>]
    let visits: [BackupImportLocalRecord<BackupImportSourceVisit>]
    let dishes: [BackupImportLocalRecord<BackupImportSourceDish>]
    let visitDishes: [BackupImportLocalRecord<BackupImportSourceVisitDish>]
    let photos: [BackupImportLocalRecord<BackupImportSourcePhoto>]
    let companions: [BackupImportLocalRecord<BackupImportSourceCompanion>]
    let recommendationSources: [BackupImportLocalRecord<BackupImportSourceRecommendationSource>]
    let profiles: [BackupImportLocalRecord<BackupImportSourceProfile>]
    let restaurantLists: [BackupImportLocalRecord<BackupImportSourceRestaurantList>]
    let restaurantListItems: [BackupImportLocalRecord<BackupImportSourceRestaurantListItem>]
}
