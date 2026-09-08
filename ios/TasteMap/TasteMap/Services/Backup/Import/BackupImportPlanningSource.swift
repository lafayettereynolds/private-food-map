import Foundation

nonisolated enum BackupImportPlanningSourceMapper {
    static func graph(from run: BackupImportPreflightRun) throws -> BackupImportSourceGraph {
        guard run.result.blockingCount == 0 else { throw BackupImportPlanningError.preflightBlocked }
        switch run.validatedSource {
        case let .backupV1(envelope):
            return map(envelope, sourceFileSHA256: run.result.sourceFileSHA256)
        case let .legacyWebV4(graph):
            guard graph.sourceMetadata.sourceFingerprint == run.result.sourceFileSHA256 else {
                throw BackupImportPlanningError.sourceHashMismatch
            }
            return map(graph, sourceFileSHA256: run.result.sourceFileSHA256)
        }
    }

    private static func map(
        _ envelope: BackupEnvelopeV1,
        sourceFileSHA256: String
    ) -> BackupImportSourceGraph {
        let entities = envelope.entities
        return BackupImportSourceGraph(
            sourceFileSHA256: sourceFileSHA256,
            sourceFormat: .backupV1,
            restaurants: entities.restaurants.map { value in
                BackupImportSourceRestaurant(
                    sourceID: value.id,
                    placeIdentities: value.placeIdentities.map {
                        BackupImportSourcePlaceIdentity(
                            provider: $0.provider.rawValue,
                            externalID: $0.externalId,
                            isPrimary: $0.isPrimary
                        )
                    },
                    name: value.name,
                    address: value.address,
                    city: value.city,
                    latitude: value.latitude,
                    longitude: value.longitude,
                    status: value.status.rawValue,
                    preferenceLevel: value.preferenceLevel.rawValue,
                    overallRating: value.overallRating?.rawValue,
                    foodRating: value.foodRating?.rawValue,
                    environmentRating: value.environmentRating?.rawValue,
                    serviceRating: value.serviceRating?.rawValue,
                    valueRating: value.valueRating?.rawValue,
                    tags: value.tags,
                    longTermNote: value.longTermNote,
                    pricePerPerson: value.pricePerPerson?.decimalValue,
                    phone: value.phone,
                    websiteURL: value.websiteUrl,
                    openingHours: value.openingHours,
                    markerType: value.markerType.rawValue,
                    markerPhotoSourceID: value.markerPhotoId,
                    merchantImageURL: value.merchantImageUrl,
                    markerEmoji: value.markerEmoji,
                    createdAt: date(value.createdAt),
                    updatedAt: date(value.updatedAt)
                )
            },
            visits: entities.visits.map { value in
                BackupImportSourceVisit(
                    sourceID: value.id,
                    sourceRestaurantID: value.restaurantId,
                    visitedAt: date(value.visitedAt),
                    diningMode: value.diningMode.rawValue,
                    visibility: value.visibility.rawValue,
                    partySize: value.partySize,
                    totalPrice: value.totalPrice?.decimalValue,
                    myActualSpend: value.myActualSpend?.decimalValue,
                    paymentMode: value.paymentMode?.rawValue,
                    pricePerPerson: value.pricePerPerson?.decimalValue,
                    queueDuration: value.queueDuration?.rawValue,
                    diningOccasions: value.diningOccasions.map(\.rawValue),
                    diningOccasionText: value.diningOccasionText,
                    rating: value.rating?.rawValue,
                    valueRating: value.valueRating?.rawValue,
                    environmentRating: value.environmentRating?.rawValue,
                    serviceRating: value.serviceRating?.rawValue,
                    valueTags: value.valueTags,
                    environmentTags: value.environmentTags,
                    serviceTags: value.serviceTags,
                    noiseLevel: value.noiseLevel?.rawValue,
                    diningDuration: value.diningDuration?.rawValue,
                    portionLevel: value.portionLevel?.rawValue,
                    transportConvenience: value.transportConvenience?.rawValue,
                    specialNotes: value.specialNotes,
                    companionSourceIDs: value.companionIds,
                    recommendationSourceID: value.recommendationSourceId,
                    recommendationSourceType: value.recommendationSourceType?.rawValue,
                    recommendationSourceText: value.recommendationSourceText,
                    note: value.note,
                    createdAt: date(value.createdAt),
                    updatedAt: date(value.updatedAt)
                )
            },
            dishes: entities.dishes.map { value in
                BackupImportSourceDish(
                    sourceID: value.id,
                    sourceRestaurantID: value.restaurantId,
                    sourceVisitID: value.originVisitId,
                    name: value.name,
                    taste: value.taste,
                    rating: value.rating?.rawValue,
                    price: value.price?.decimalValue,
                    sourcePhotoID: value.photoId,
                    sortOrder: value.sortOrder,
                    createdAt: date(value.createdAt),
                    updatedAt: date(value.updatedAt)
                )
            },
            visitDishes: entities.visitDishes.map { value in
                BackupImportSourceVisitDish(
                    sourceID: value.id,
                    sourceRestaurantID: value.restaurantId,
                    sourceVisitID: value.visitId,
                    sourceDishID: value.dishId,
                    sortOrder: value.sortOrder,
                    createdAt: date(value.createdAt),
                    updatedAt: date(value.updatedAt)
                )
            },
            photos: entities.photos.map { value in
                BackupImportSourcePhoto(
                    sourceID: value.id,
                    parentEntityType: value.parent.entityType.rawValue,
                    parentSourceID: value.parent.entityId,
                    kind: value.kind.rawValue,
                    fileName: value.fileName,
                    mimeType: value.mimeType,
                    byteSize: value.byteSize,
                    width: value.width,
                    height: value.height,
                    sortOrder: value.sortOrder,
                    visibility: value.visibility.rawValue,
                    createdAt: date(value.createdAt),
                    updatedAt: date(value.updatedAt),
                    binaryAvailable: false
                )
            },
            companions: entities.companions.map {
                BackupImportSourceCompanion(
                    sourceID: $0.id,
                    displayName: $0.displayName,
                    createdAt: date($0.createdAt),
                    updatedAt: date($0.updatedAt)
                )
            },
            recommendationSources: entities.recommendationSources.map {
                BackupImportSourceRecommendationSource(
                    sourceID: $0.id,
                    displayName: $0.displayName,
                    sourceType: $0.sourceType.rawValue,
                    createdAt: date($0.createdAt),
                    updatedAt: date($0.updatedAt)
                )
            },
            profiles: entities.profiles.map {
                BackupImportSourceProfile(
                    sourceID: $0.id,
                    displayName: $0.displayName,
                    bio: $0.bio,
                    city: $0.city,
                    avatarPhotoSourceID: $0.avatarPhotoId,
                    avatarPresetID: $0.avatarPresetId.rawValue,
                    visibility: $0.visibility.rawValue,
                    createdAt: date($0.createdAt),
                    updatedAt: date($0.updatedAt)
                )
            },
            restaurantLists: entities.restaurantLists.map {
                BackupImportSourceRestaurantList(
                    sourceID: $0.id,
                    title: $0.title,
                    listDescription: $0.description,
                    visibility: $0.visibility.rawValue,
                    isRanked: $0.isRanked,
                    coverMode: $0.coverMode.rawValue,
                    customCoverPhotoSourceID: $0.customCoverPhotoId,
                    createdAt: date($0.createdAt),
                    updatedAt: date($0.updatedAt)
                )
            },
            restaurantListItems: entities.restaurantListItems.map {
                BackupImportSourceRestaurantListItem(
                    sourceID: $0.id,
                    sourceListID: $0.listId,
                    sourceRestaurantID: $0.restaurantId,
                    position: $0.position,
                    note: $0.note,
                    createdAt: date($0.createdAt),
                    updatedAt: date($0.updatedAt)
                )
            },
            tombstones: envelope.tombstones.compactMap { tombstone in
                BackupImportEntityKind(rawValue: tombstone.entityType.rawValue).map {
                    BackupImportSourceTombstone(
                        entityType: $0,
                        sourceID: tombstone.id,
                        deletedAt: date(tombstone.deletedAt)
                    )
                }
            }
        )
    }

    private static func map(
        _ graph: LegacyBackupStagingGraph,
        sourceFileSHA256: String
    ) -> BackupImportSourceGraph {
        let visitDishByDish = Dictionary(uniqueKeysWithValues: graph.visitDishes.map { ($0.sourceDishID, $0) })
        let fallbackDate = date(graph.sourceMetadata.exportedAt)
        return BackupImportSourceGraph(
            sourceFileSHA256: sourceFileSHA256,
            sourceFormat: .legacyWebV4,
            restaurants: graph.restaurants.map { value in
                BackupImportSourceRestaurant(
                    sourceID: value.sourceID,
                    placeIdentities: value.placeIdentities.map {
                        BackupImportSourcePlaceIdentity(
                            provider: $0.provider.rawValue,
                            externalID: $0.externalID,
                            isPrimary: $0.isPrimary
                        )
                    },
                    name: value.name,
                    address: value.address ?? "",
                    city: value.city ?? "",
                    latitude: value.latitude,
                    longitude: value.longitude,
                    status: value.status?.rawValue ?? BackupRestaurantStatusV1.visited.rawValue,
                    preferenceLevel: value.preferenceLevel?.rawValue ?? BackupRestaurantPreferenceV1.normal.rawValue,
                    overallRating: value.overallRating?.rawValue,
                    foodRating: value.foodRating?.rawValue,
                    environmentRating: value.environmentRating?.rawValue,
                    serviceRating: value.serviceRating?.rawValue,
                    valueRating: value.valueRating?.rawValue,
                    tags: value.tags ?? [],
                    longTermNote: value.longTermNote ?? "",
                    pricePerPerson: value.pricePerPerson?.decimalValue,
                    phone: value.phone,
                    websiteURL: nil,
                    openingHours: value.openingHours,
                    markerType: value.markerType?.rawValue ?? BackupMarkerTypeV1.emoji.rawValue,
                    markerPhotoSourceID: value.markerPhotoSourceID,
                    merchantImageURL: value.merchantImageURL,
                    markerEmoji: value.markerEmoji ?? "🍽️",
                    createdAt: value.createdAt.map(date) ?? fallbackDate,
                    updatedAt: value.updatedAt.map(date) ?? fallbackDate
                )
            },
            visits: graph.visits.map { value in
                BackupImportSourceVisit(
                    sourceID: value.sourceID,
                    sourceRestaurantID: value.sourceRestaurantID,
                    visitedAt: value.visitedAt.map(date) ?? fallbackDate,
                    diningMode: value.diningMode?.rawValue ?? BackupDiningModeV1.dineIn.rawValue,
                    visibility: value.visibility?.rawValue ?? BackupVisibilityV1.private.rawValue,
                    partySize: value.partySize,
                    totalPrice: value.totalPrice?.decimalValue,
                    myActualSpend: value.myActualSpend?.decimalValue,
                    paymentMode: value.paymentMode?.rawValue,
                    pricePerPerson: value.pricePerPerson?.decimalValue,
                    queueDuration: value.queueDuration?.rawValue,
                    diningOccasions: value.diningOccasions?.map(\.rawValue) ?? [],
                    diningOccasionText: value.diningOccasionText,
                    rating: value.rating?.rawValue,
                    valueRating: value.valueRating?.rawValue,
                    environmentRating: value.environmentRating?.rawValue,
                    serviceRating: value.serviceRating?.rawValue,
                    valueTags: value.valueTags ?? [],
                    environmentTags: value.environmentTags ?? [],
                    serviceTags: value.serviceTags ?? [],
                    noiseLevel: value.noiseLevel?.rawValue,
                    diningDuration: value.diningDuration?.rawValue,
                    portionLevel: value.portionLevel?.rawValue,
                    transportConvenience: value.transportConvenience?.rawValue,
                    specialNotes: value.specialNotes,
                    companionSourceIDs: value.companionSourceIDs,
                    recommendationSourceID: value.recommendationSourceID,
                    recommendationSourceType: value.recommendationSourceType?.rawValue,
                    recommendationSourceText: value.recommendationSourceText,
                    note: value.note,
                    createdAt: value.createdAt.map(date) ?? fallbackDate,
                    updatedAt: value.updatedAt.map(date) ?? fallbackDate
                )
            },
            dishes: graph.dishes.map { value in
                let association = visitDishByDish[value.sourceID]
                return BackupImportSourceDish(
                    sourceID: value.sourceID,
                    sourceRestaurantID: value.sourceRestaurantID,
                    sourceVisitID: value.sourceVisitID,
                    name: value.name,
                    taste: association?.tasteNote ?? "",
                    rating: association?.rating?.rawValue,
                    price: association?.price?.decimalValue,
                    sourcePhotoID: value.sourcePhotoID,
                    sortOrder: association?.sourceOrder ?? 0,
                    createdAt: fallbackDate,
                    updatedAt: fallbackDate
                )
            },
            visitDishes: graph.visitDishes.map {
                BackupImportSourceVisitDish(
                    sourceID: $0.sourceID,
                    sourceRestaurantID: $0.sourceRestaurantID,
                    sourceVisitID: $0.sourceVisitID,
                    sourceDishID: $0.sourceDishID,
                    sortOrder: $0.sourceOrder,
                    createdAt: fallbackDate,
                    updatedAt: fallbackDate
                )
            },
            photos: graph.photos.map {
                BackupImportSourcePhoto(
                    sourceID: $0.sourceID,
                    parentEntityType: $0.parent.entityType.rawValue,
                    parentSourceID: $0.parent.sourceID,
                    kind: $0.kind.rawValue,
                    fileName: $0.fileName,
                    mimeType: $0.mimeType ?? "application/octet-stream",
                    byteSize: Int64($0.byteSize ?? 0),
                    width: $0.width,
                    height: $0.height,
                    sortOrder: $0.sourceOrder,
                    visibility: $0.visibility?.rawValue ?? BackupVisibilityV1.private.rawValue,
                    createdAt: $0.createdAt.map(date) ?? fallbackDate,
                    updatedAt: $0.updatedAt.map(date) ?? fallbackDate,
                    binaryAvailable: false
                )
            },
            companions: graph.companions.map {
                BackupImportSourceCompanion(
                    sourceID: $0.sourceID,
                    displayName: $0.displayName,
                    createdAt: $0.firstObservedAt.map(date) ?? fallbackDate,
                    updatedAt: $0.lastObservedAt.map(date) ?? fallbackDate
                )
            },
            recommendationSources: graph.recommendationSources.map {
                BackupImportSourceRecommendationSource(
                    sourceID: $0.sourceID,
                    displayName: $0.displayName,
                    sourceType: $0.sourceType?.rawValue ?? BackupRecommendationSourceTypeV1.other.rawValue,
                    createdAt: $0.firstObservedAt.map(date) ?? fallbackDate,
                    updatedAt: $0.lastObservedAt.map(date) ?? fallbackDate
                )
            },
            profiles: graph.profiles.map {
                BackupImportSourceProfile(
                    sourceID: $0.sourceID,
                    displayName: $0.displayName ?? "",
                    bio: $0.bio ?? "",
                    city: $0.city ?? "",
                    avatarPhotoSourceID: $0.avatarPhotoSourceID,
                    avatarPresetID: $0.avatarPresetID?.rawValue ?? BackupProfileAvatarPresetV1.polarBear.rawValue,
                    visibility: $0.visibility?.rawValue ?? BackupVisibilityV1.private.rawValue,
                    createdAt: $0.createdAt.map(date) ?? fallbackDate,
                    updatedAt: $0.updatedAt.map(date) ?? fallbackDate
                )
            },
            restaurantLists: graph.restaurantLists.map {
                BackupImportSourceRestaurantList(
                    sourceID: $0.sourceID,
                    title: $0.title,
                    listDescription: $0.listDescription ?? "",
                    visibility: $0.visibility?.rawValue ?? BackupVisibilityV1.private.rawValue,
                    isRanked: $0.isRanked ?? false,
                    coverMode: $0.coverMode?.rawValue ?? BackupRestaurantListCoverModeV1.automatic.rawValue,
                    customCoverPhotoSourceID: $0.customCoverPhotoSourceID,
                    createdAt: $0.createdAt.map(date) ?? fallbackDate,
                    updatedAt: $0.updatedAt.map(date) ?? fallbackDate
                )
            },
            restaurantListItems: graph.restaurantListItems.map {
                BackupImportSourceRestaurantListItem(
                    sourceID: $0.sourceID,
                    sourceListID: $0.sourceListID,
                    sourceRestaurantID: $0.sourceRestaurantID,
                    position: $0.position ?? 0,
                    note: $0.note ?? "",
                    createdAt: $0.createdAt.map(date) ?? fallbackDate,
                    updatedAt: $0.updatedAt.map(date) ?? fallbackDate
                )
            },
            tombstones: graph.tombstones.compactMap { tombstone in
                BackupImportEntityKind(rawValue: tombstone.entityType.rawValue).map {
                    BackupImportSourceTombstone(
                        entityType: $0,
                        sourceID: tombstone.sourceID,
                        deletedAt: date(tombstone.deletedAt)
                    )
                }
            }
        )
    }

    private static func date(_ timestamp: BackupTimestampV1) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: timestamp.rawValue) ?? Date(timeIntervalSince1970: 0)
    }
}
