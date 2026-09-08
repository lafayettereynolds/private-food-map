import Foundation

@MainActor
struct BackupExportMapper {
    private let input: BackupExportInput
    private let currentUserID: String
    private var issues: [BackupExportValidationIssue] = []
    private var timestampCache: [Date: BackupTimestampV1] = [:]

    init(input: BackupExportInput, currentUserID: String) {
        self.input = input
        self.currentUserID = currentUserID
    }

    mutating func map() throws -> (entities: BackupEntitiesV1, tombstones: [BackupTombstoneV1]) {
        guard Self.isTasteMapUserID(currentUserID) else { throw BackupExportError.invalidCurrentUser }

        let profileOwners = Set(input.profiles.map(\.tasteMapUserID))
        let mayClaimDeviceLocalRecords = profileOwners == [currentUserID]

        var restaurantIDs: [UUID: String] = [:]
        var restaurantScope: [UUID: Bool] = [:]
        var restaurants: [BackupRestaurantV1] = []
        var tombstones: [BackupTombstoneV1] = []

        for model in input.restaurants {
            let stableID = try stableID(model.remoteID, fallback: model.id, entityType: .restaurant)
            let record = try restaurantRecord(for: model, stableID: stableID)
            restaurantIDs[model.id] = stableID
            let belongs = try belongsToCurrentUser(
                owner: record.userId,
                entityType: .restaurant,
                entityID: stableID,
                mayClaimDeviceLocalRecords: mayClaimDeviceLocalRecords
            )
            restaurantScope[model.id] = belongs
            guard belongs else { continue }
            if let deletedAt = model.deletedAt {
                tombstones.append(try tombstone(.restaurant, id: stableID, deletedAt: deletedAt))
            } else {
                restaurants.append(try mapRestaurant(model, record: record, id: stableID))
            }
        }

        let activeRestaurantLocalIDs = Set(input.restaurants.compactMap {
            restaurantScope[$0.id] == true && $0.deletedAt == nil ? $0.id : nil
        })
        let allRestaurantLocalIDs = Set(input.restaurants.map(\.id))

        var visits: [BackupVisitV1] = []
        var visitIDs: [UUID: String] = [:]
        var visitScope: [UUID: Bool] = [:]
        for model in input.visits {
            let stableID = try stableID(model.remoteID, fallback: model.id, entityType: .visit)
            visitIDs[model.id] = stableID
            guard allRestaurantLocalIDs.contains(model.restaurantId) else {
                addOrphan(.visit, id: stableID, field: "restaurantId", referenceID: model.restaurantId.uuidString)
                continue
            }
            let belongs = restaurantScope[model.restaurantId] == true && model.ownerUserID == currentUserID
            visitScope[model.id] = belongs
            guard belongs else { continue }
            if let deletedAt = model.deletedAt {
                tombstones.append(try tombstone(.visit, id: stableID, deletedAt: deletedAt))
            } else if activeRestaurantLocalIDs.contains(model.restaurantId),
                      let restaurantID = restaurantIDs[model.restaurantId] {
                visits.append(try mapVisit(model, id: stableID, restaurantID: restaurantID))
            } else {
                addOrphan(.visit, id: stableID, field: "restaurantId", referenceID: restaurantIDs[model.restaurantId])
            }
        }

        let activeVisitLocalIDs = Set(input.visits.compactMap {
            visitScope[$0.id] == true && $0.deletedAt == nil ? $0.id : nil
        })
        let allVisitLocalIDs = Set(input.visits.map(\.id))

        var dishes: [BackupDishV1] = []
        var dishIDs: [UUID: String] = [:]
        var dishScope: [UUID: Bool] = [:]
        for model in input.dishes {
            let stableID = try stableID(model.remoteID, fallback: model.id, entityType: .dish)
            dishIDs[model.id] = stableID
            guard allRestaurantLocalIDs.contains(model.restaurantId) else {
                addOrphan(.dish, id: stableID, field: "restaurantId", referenceID: model.restaurantId.uuidString)
                continue
            }
            let belongs = restaurantScope[model.restaurantId] == true && model.ownerUserID == currentUserID
            dishScope[model.id] = belongs
            guard belongs else { continue }
            guard allVisitLocalIDs.contains(model.visitId) else {
                addOrphan(.dish, id: stableID, field: "originVisitId", referenceID: model.visitId.uuidString)
                continue
            }
            if let deletedAt = model.deletedAt {
                tombstones.append(try tombstone(.dish, id: stableID, deletedAt: deletedAt))
            } else if activeRestaurantLocalIDs.contains(model.restaurantId),
                      activeVisitLocalIDs.contains(model.visitId),
                      let restaurantID = restaurantIDs[model.restaurantId],
                      let visitID = visitIDs[model.visitId] {
                dishes.append(try mapDish(model, id: stableID, restaurantID: restaurantID, visitID: visitID))
            } else {
                addOrphan(.dish, id: stableID, field: "originVisitId", referenceID: visitIDs[model.visitId])
            }
        }

        let activeDishLocalIDs = Set(input.dishes.compactMap {
            dishScope[$0.id] == true && $0.deletedAt == nil ? $0.id : nil
        })
        let allDishLocalIDs = Set(input.dishes.map(\.id))
        let dishRestaurantIDs = Dictionary(uniqueKeysWithValues: input.dishes.map { ($0.id, $0.restaurantId) })
        let visitRestaurantIDs = Dictionary(uniqueKeysWithValues: input.visits.map { ($0.id, $0.restaurantId) })

        var visitDishes: [BackupVisitDishV1] = []
        for model in input.visitDishes {
            let stableID = try stableID(model.remoteID, fallback: model.id, entityType: .visitDish)
            guard model.ownerUserID == currentUserID,
                  allRestaurantLocalIDs.contains(model.restaurantId),
                  allVisitLocalIDs.contains(model.visitId),
                  allDishLocalIDs.contains(model.dishId) else {
                addOrphan(.visitDish, id: stableID, field: "relationship", referenceID: nil)
                continue
            }
            let belongs = restaurantScope[model.restaurantId] == true
            guard belongs else { continue }
            if let deletedAt = model.deletedAt {
                tombstones.append(try tombstone(.visitDish, id: stableID, deletedAt: deletedAt))
            } else if activeRestaurantLocalIDs.contains(model.restaurantId),
                      activeVisitLocalIDs.contains(model.visitId),
                      activeDishLocalIDs.contains(model.dishId),
                      dishRestaurantIDs[model.dishId] == model.restaurantId,
                      visitRestaurantIDs[model.visitId] == model.restaurantId,
                      let restaurantID = restaurantIDs[model.restaurantId],
                      let visitID = visitIDs[model.visitId],
                      let dishID = dishIDs[model.dishId] {
                visitDishes.append(try mapVisitDish(
                    model, id: stableID, restaurantID: restaurantID, visitID: visitID, dishID: dishID
                ))
            } else {
                addOrphan(.visitDish, id: stableID, field: "relationship", referenceID: nil)
            }
        }

        var companions: [BackupDiningCompanionV1] = []
        for model in input.companions {
            let stableID = try stableID(model.remoteID, fallback: model.id, entityType: .companion)
            guard try belongsToCurrentUser(
                owner: model.ownerUserId,
                entityType: .companion,
                entityID: stableID,
                mayClaimDeviceLocalRecords: mayClaimDeviceLocalRecords
            ) else { continue }
            if let deletedAt = model.deletedAt {
                tombstones.append(try tombstone(.companion, id: stableID, deletedAt: deletedAt))
            } else {
                companions.append(try BackupDiningCompanionV1(
                    id: validID(stableID, entityType: .companion),
                    displayName: requiredText(model.displayName, maximum: 100, entityType: .companion, id: stableID, field: "displayName"),
                    createdAt: timestamp(model.createdAt, entityType: .companion, id: stableID, field: "createdAt"),
                    updatedAt: timestamp(model.updatedAt, entityType: .companion, id: stableID, field: "updatedAt")
                ))
            }
        }

        var sources: [BackupRecommendationSourceV1] = []
        for model in input.recommendationSources {
            let stableID = try stableID(model.remoteID, fallback: model.id, entityType: .recommendationSource)
            guard try belongsToCurrentUser(
                owner: model.ownerUserId,
                entityType: .recommendationSource,
                entityID: stableID,
                mayClaimDeviceLocalRecords: mayClaimDeviceLocalRecords
            ) else { continue }
            if let deletedAt = model.deletedAt {
                tombstones.append(try tombstone(.recommendationSource, id: stableID, deletedAt: deletedAt))
            } else {
                sources.append(BackupRecommendationSourceV1(
                    id: try validID(stableID, entityType: .recommendationSource),
                    displayName: try requiredText(model.displayName, maximum: 160, entityType: .recommendationSource, id: stableID, field: "displayName"),
                    sourceType: BackupRecommendationSourceTypeV1(rawValue: model.sourceType.rawValue) ?? .other,
                    createdAt: try timestamp(model.createdAt, entityType: .recommendationSource, id: stableID, field: "createdAt"),
                    updatedAt: try timestamp(model.updatedAt, entityType: .recommendationSource, id: stableID, field: "updatedAt")
                ))
            }
        }

        var profiles: [BackupUserProfileV1] = []
        var currentProfileIDs: [UUID: String] = [:]
        for model in input.profiles where model.tasteMapUserID == currentUserID {
            let stableID = try validID(model.id.uuidString.lowercased(), entityType: .profile)
            currentProfileIDs[model.id] = stableID
            if let deletedAt = model.deletedAt {
                tombstones.append(try tombstone(.profile, id: stableID, deletedAt: deletedAt))
            } else {
                profiles.append(try mapProfile(model, id: stableID))
            }
        }

        var lists: [BackupRestaurantListV1] = []
        var listIDs: [UUID: String] = [:]
        var listScope: [UUID: Bool] = [:]
        for model in input.restaurantLists {
            let stableID = try stableID(model.remoteID, fallback: model.id, entityType: .restaurantList)
            listIDs[model.id] = stableID
            let belongs = model.ownerUserID == currentUserID
            listScope[model.id] = belongs
            guard belongs else { continue }
            if let deletedAt = model.deletedAt {
                tombstones.append(try tombstone(.restaurantList, id: stableID, deletedAt: deletedAt))
            } else {
                lists.append(try mapList(model, id: stableID))
            }
        }

        let allListLocalIDs = Set(input.restaurantLists.map(\.id))
        let activeListLocalIDs = Set(input.restaurantLists.compactMap {
            listScope[$0.id] == true && $0.deletedAt == nil ? $0.id : nil
        })
        var listItems: [BackupRestaurantListItemV1] = []
        for model in input.restaurantListItems {
            let stableID = try stableID(model.remoteID, fallback: model.id, entityType: .restaurantListItem)
            guard model.ownerUserID == currentUserID else { continue }
            guard allListLocalIDs.contains(model.listID) else {
                addOrphan(.restaurantListItem, id: stableID, field: "listId", referenceID: model.listID.uuidString)
                continue
            }
            guard listScope[model.listID] == true else {
                addIssue(.invalidRelationship, .restaurantListItem, stableID, "listId", listIDs[model.listID], "榜单条目的 owner 与父榜单不一致。")
                continue
            }
            if let deletedAt = model.deletedAt {
                tombstones.append(try tombstone(.restaurantListItem, id: stableID, deletedAt: deletedAt))
            } else if activeListLocalIDs.contains(model.listID), let listID = listIDs[model.listID] {
                listItems.append(try mapListItem(model, id: stableID, listID: listID))
            } else {
                addOrphan(.restaurantListItem, id: stableID, field: "listId", referenceID: listIDs[model.listID])
            }
        }

        var photos: [BackupPhotoV1] = []
        let currentProfilePhotoParents: [String: String] = Dictionary(
            uniqueKeysWithValues: input.profiles.compactMap { profile -> (String, String)? in
            guard profile.tasteMapUserID == currentUserID, profile.deletedAt == nil,
                  let photoID = profile.avatarPhotoID, let profileID = currentProfileIDs[profile.id] else { return nil }
            return (photoID, profileID)
            }
        )
        let otherProfilePhotoIDs = Set(input.profiles.compactMap {
            $0.tasteMapUserID == currentUserID ? nil : $0.avatarPhotoID
        })
        for model in input.photos {
            guard model.ownerUserID == currentUserID else { continue }
            let stableID = try stableID(model.remoteID, fallback: model.id, entityType: .photo)
            let scope = photoScope(
                model,
                stableID: stableID,
                restaurantScope: restaurantScope,
                visitScope: visitScope,
                dishScope: dishScope,
                currentProfilePhotoParents: currentProfilePhotoParents,
                otherProfilePhotoIDs: otherProfilePhotoIDs
            )
            guard scope.belongs else {
                if scope.isInvalid { addOrphan(.photo, id: stableID, field: "parent", referenceID: scope.referenceID) }
                continue
            }
            if let deletedAt = model.deletedAt {
                tombstones.append(try tombstone(.photo, id: stableID, deletedAt: deletedAt))
            } else if let parent = try photoParent(
                model,
                stableID: stableID,
                restaurantIDs: restaurantIDs,
                visitIDs: visitIDs,
                dishIDs: dishIDs,
                currentProfilePhotoParents: currentProfilePhotoParents,
                activeRestaurantLocalIDs: activeRestaurantLocalIDs,
                activeVisitLocalIDs: activeVisitLocalIDs,
                activeDishLocalIDs: activeDishLocalIDs
            ) {
                photos.append(try mapPhoto(model, id: stableID, parent: parent))
            }
        }

        restaurants.sort { $0.id < $1.id }
        visits.sort { $0.id < $1.id }
        dishes.sort { $0.id < $1.id }
        visitDishes.sort { $0.id < $1.id }
        photos.sort { $0.id < $1.id }
        companions.sort { $0.id < $1.id }
        sources.sort { $0.id < $1.id }
        profiles.sort { $0.id < $1.id }
        lists.sort { $0.id < $1.id }
        listItems.sort {
            if $0.listId != $1.listId { return $0.listId < $1.listId }
            if $0.position != $1.position { return $0.position < $1.position }
            return $0.id < $1.id
        }
        tombstones.sort {
            if $0.entityType.rawValue != $1.entityType.rawValue {
                return $0.entityType.rawValue < $1.entityType.rawValue
            }
            return $0.id < $1.id
        }

        let entities = BackupEntitiesV1(
            restaurants: restaurants,
            visits: visits,
            dishes: dishes,
            visitDishes: visitDishes,
            photos: photos,
            companions: companions,
            recommendationSources: sources,
            profiles: profiles,
            restaurantLists: lists,
            restaurantListItems: listItems
        )
        validate(entities: entities, tombstones: tombstones)
        guard issues.isEmpty else {
            throw BackupExportError.validation(BackupExportValidationError(issues: issues))
        }
        return (entities, tombstones)
    }

    private mutating func mapRestaurant(
        _ model: Restaurant,
        record: RestaurantJSONContractV1,
        id: String
    ) throws -> BackupRestaurantV1 {
        let identities = try record.placeIdentities.map { identity in
            BackupPlaceIdentityV1(
                provider: BackupPlaceProviderV1(rawValue: identity.provider.rawValue) ?? .other,
                externalId: try validID(identity.externalId, entityType: .restaurant),
                isPrimary: identity.isPrimary,
                createdAt: try timestamp(identity.createdAt, entityType: .restaurant, id: id, field: "placeIdentities.createdAt"),
                updatedAt: try timestamp(identity.updatedAt, entityType: .restaurant, id: id, field: "placeIdentities.updatedAt")
            )
        }.sorted {
            if $0.provider.rawValue != $1.provider.rawValue { return $0.provider.rawValue < $1.provider.rawValue }
            return $0.externalId < $1.externalId
        }
        guard identities.count <= 16, identities.filter(\.isPrimary).count == 1 else {
            throw BackupExportError.invalidRestaurantRecord(entityID: id)
        }
        return BackupRestaurantV1(
            id: try validID(id, entityType: .restaurant),
            placeIdentities: identities,
            name: try requiredText(model.name, maximum: 300, entityType: .restaurant, id: id, field: "name"),
            address: try text(model.address, maximum: 1000, entityType: .restaurant, id: id, field: "address"),
            city: try text(model.city, maximum: 200, entityType: .restaurant, id: id, field: "city"),
            latitude: try coordinate(model.latitude, range: -90 ... 90, entityType: .restaurant, id: id, field: "latitude"),
            longitude: try coordinate(model.longitude, range: -180 ... 180, entityType: .restaurant, id: id, field: "longitude"),
            status: model.status == .visited ? .visited : .wantToGo,
            preferenceLevel: BackupRestaurantPreferenceV1(rawValue: record.preferenceLevel.rawValue) ?? .normal,
            overallRating: try rating(record.overallRating, entityType: .restaurant, id: id, field: "overallRating"),
            foodRating: try rating(record.foodRating, entityType: .restaurant, id: id, field: "foodRating"),
            environmentRating: try rating(record.environmentRating, entityType: .restaurant, id: id, field: "environmentRating"),
            serviceRating: try rating(record.serviceRating, entityType: .restaurant, id: id, field: "serviceRating"),
            valueRating: try rating(record.valueRating, entityType: .restaurant, id: id, field: "valueRating"),
            tags: try tagSet(record.tags, entityType: .restaurant, id: id, field: "tags"),
            longTermNote: try text(record.longTermNote, maximum: 20_000, entityType: .restaurant, id: id, field: "longTermNote"),
            pricePerPerson: try money(record.pricePerPerson, entityType: .restaurant, id: id, field: "pricePerPerson"),
            phone: try optionalText(record.phone, maximum: 100, entityType: .restaurant, id: id, field: "phone"),
            websiteUrl: try optionalWebURL(record.websiteUrl, entityType: .restaurant, id: id, field: "websiteUrl"),
            openingHours: try optionalText(record.openingHours, maximum: 2_000, entityType: .restaurant, id: id, field: "openingHours"),
            markerType: record.markerType == .image ? .image : .emoji,
            markerPhotoId: try optionalID(record.markerPhotoId, entityType: .restaurant),
            merchantImageUrl: try optionalHTTPSURL(record.merchantImageUrl, entityType: .restaurant, id: id, field: "merchantImageUrl"),
            markerEmoji: try text(record.markerEmoji, maximum: 32, entityType: .restaurant, id: id, field: "markerEmoji"),
            createdAt: try timestamp(model.createdAt, entityType: .restaurant, id: id, field: "createdAt"),
            updatedAt: try timestamp(model.updatedAt, entityType: .restaurant, id: id, field: "updatedAt")
        )
    }

    private mutating func mapVisit(_ model: Visit, id: String, restaurantID: String) throws -> BackupVisitV1 {
        let occasions = try model.diningOccasionRawValues.map { raw -> BackupDiningOccasionV1 in
            guard let value = BackupDiningOccasionV1(rawValue: raw) else {
                throw invalidField(.visit, id: id, field: "diningOccasions", message: "未知的用餐场景。")
            }
            return value
        }.uniquedAndSorted(by: \.rawValue)
        guard occasions.count <= 7 else { throw invalidField(.visit, id: id, field: "diningOccasions", message: "用餐场景数量超出 Backup v1 上限。") }
        if let partySize = model.partySize, !(1 ... 1_000).contains(partySize) {
            throw invalidField(.visit, id: id, field: "partySize", message: "用餐人数超出 Backup v1 范围。")
        }
        return BackupVisitV1(
            id: try validID(id, entityType: .visit),
            restaurantId: try validID(restaurantID, entityType: .restaurant),
            visitedAt: try timestamp(model.visitedAt, entityType: .visit, id: id, field: "visitedAt"),
            diningMode: model.diningMode == .dineIn ? .dineIn : .takeout,
            visibility: BackupVisibilityV1(rawValue: model.visibility.rawValue) ?? .private,
            partySize: model.partySize,
            totalPrice: try money(model.totalPrice, entityType: .visit, id: id, field: "totalPrice"),
            myActualSpend: try money(model.myActualSpend, entityType: .visit, id: id, field: "myActualSpend"),
            paymentMode: try enumValue(model.paymentModeRawValue, type: BackupPaymentModeV1.self, entityType: .visit, id: id, field: "paymentMode"),
            pricePerPerson: try money(model.pricePerPerson, entityType: .visit, id: id, field: "pricePerPerson"),
            queueDuration: try enumValue(model.queueDurationRawValue, type: BackupQueueDurationV1.self, entityType: .visit, id: id, field: "queueDuration"),
            diningOccasions: occasions,
            diningOccasionText: try optionalText(model.diningOccasionText, maximum: 20_000, entityType: .visit, id: id, field: "diningOccasionText"),
            rating: try rating(model.rating, entityType: .visit, id: id, field: "rating"),
            valueRating: try rating(model.valueRating, entityType: .visit, id: id, field: "valueRating"),
            environmentRating: try rating(model.environmentRating, entityType: .visit, id: id, field: "environmentRating"),
            serviceRating: try rating(model.serviceRating, entityType: .visit, id: id, field: "serviceRating"),
            valueTags: try tagSet(model.valueTags, entityType: .visit, id: id, field: "valueTags"),
            environmentTags: try tagSet(model.environmentTags, entityType: .visit, id: id, field: "environmentTags"),
            serviceTags: try tagSet(model.serviceTags, entityType: .visit, id: id, field: "serviceTags"),
            noiseLevel: try enumValue(model.noiseLevelRawValue, type: BackupNoiseLevelV1.self, entityType: .visit, id: id, field: "noiseLevel"),
            diningDuration: try enumValue(model.diningDurationRawValue, type: BackupDiningDurationV1.self, entityType: .visit, id: id, field: "diningDuration"),
            portionLevel: try enumValue(model.portionLevelRawValue, type: BackupPortionLevelV1.self, entityType: .visit, id: id, field: "portionLevel"),
            transportConvenience: try enumValue(model.transportConvenienceRawValue, type: BackupTransportConvenienceV1.self, entityType: .visit, id: id, field: "transportConvenience"),
            specialNotes: try optionalText(model.specialNotes, maximum: 20_000, entityType: .visit, id: id, field: "specialNotes"),
            companionIds: try model.companionIDs.map { try validID($0, entityType: .companion) }.uniquedAndSorted(),
            recommendationSourceId: try optionalID(model.recommendationSourceID, entityType: .recommendationSource),
            recommendationSourceType: try enumValue(model.recommendationSourceTypeRawValue, type: BackupRecommendationSourceTypeV1.self, entityType: .visit, id: id, field: "recommendationSourceType"),
            recommendationSourceText: try optionalText(model.recommendationSourceText, maximum: 20_000, entityType: .visit, id: id, field: "recommendationSourceText"),
            sharedMealReferenceHint: try optionalID(model.sharedMealID, entityType: .visit),
            note: try optionalText(model.note, maximum: 20_000, entityType: .visit, id: id, field: "note"),
            createdAt: try timestamp(model.createdAt, entityType: .visit, id: id, field: "createdAt"),
            updatedAt: try timestamp(model.updatedAt, entityType: .visit, id: id, field: "updatedAt")
        )
    }

    private mutating func mapDish(_ model: Dish, id: String, restaurantID: String, visitID: String) throws -> BackupDishV1 {
        BackupDishV1(
            id: try validID(id, entityType: .dish),
            restaurantId: try validID(restaurantID, entityType: .restaurant),
            originVisitId: try validID(visitID, entityType: .visit),
            name: try requiredText(model.name, maximum: 300, entityType: .dish, id: id, field: "name"),
            taste: try text(model.taste, maximum: 2_000, entityType: .dish, id: id, field: "taste"),
            rating: try rating(model.rating, entityType: .dish, id: id, field: "rating"),
            price: try money(model.price, entityType: .dish, id: id, field: "price"),
            photoId: try optionalID(model.photoRemoteID, entityType: .photo),
            sortOrder: try safeNonnegativeInteger(model.sortOrder, entityType: .dish, id: id, field: "sortOrder"),
            createdAt: try timestamp(model.createdAt, entityType: .dish, id: id, field: "createdAt"),
            updatedAt: try timestamp(model.updatedAt, entityType: .dish, id: id, field: "updatedAt")
        )
    }

    private mutating func mapVisitDish(
        _ model: VisitDish,
        id: String,
        restaurantID: String,
        visitID: String,
        dishID: String
    ) throws -> BackupVisitDishV1 {
        BackupVisitDishV1(
            id: try validID(id, entityType: .visitDish),
            restaurantId: try validID(restaurantID, entityType: .restaurant),
            visitId: try validID(visitID, entityType: .visit),
            dishId: try validID(dishID, entityType: .dish),
            sortOrder: try safeNonnegativeInteger(model.sortOrder, entityType: .visitDish, id: id, field: "sortOrder"),
            createdAt: try timestamp(model.createdAt, entityType: .visitDish, id: id, field: "createdAt"),
            updatedAt: try timestamp(model.updatedAt, entityType: .visitDish, id: id, field: "updatedAt")
        )
    }

    private mutating func mapPhoto(_ model: PhotoAsset, id: String, parent: BackupPhotoParentV1) throws -> BackupPhotoV1 {
        let fileName = try safeFileName(model.fileName, id: id)
        let mime = model.mimeType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard mime.count <= 255,
              mime.range(of: #"^[A-Za-z0-9!#$&^_.+-]+/[A-Za-z0-9!#$&^_.+-]+$"#, options: .regularExpression) != nil else {
            throw invalidField(.photo, id: id, field: "mimeType", message: "照片 MIME type 不安全或无效。")
        }
        let hash: String?
        if let rawHash = model.displayContentHash?.lowercased() {
            guard rawHash.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil else {
                throw BackupExportError.validation(BackupExportValidationError(issues: [
                    .init(code: .unsafePhotoMetadata, entityType: .photo, entityID: id, field: "contentSha256", referenceID: nil, message: "照片内容哈希无效，已阻止不安全导出。")
                ]))
            }
            hash = rawHash
        } else {
            hash = nil
        }
        return BackupPhotoV1(
            id: try validID(id, entityType: .photo),
            parent: parent,
            kind: BackupPhotoKindV1(rawValue: model.kind.rawValue) ?? .visit,
            fileName: fileName,
            mimeType: mime,
            byteSize: try safeNonnegativeInteger(model.byteSize, entityType: .photo, id: id, field: "byteSize"),
            width: try optionalPositiveInteger(model.width, entityType: .photo, id: id, field: "width"),
            height: try optionalPositiveInteger(model.height, entityType: .photo, id: id, field: "height"),
            sortOrder: try safeNonnegativeInteger(model.sortOrder, entityType: .photo, id: id, field: "sortOrder"),
            visibility: BackupVisibilityV1(rawValue: model.visibility.rawValue) ?? .private,
            contentSha256: hash,
            createdAt: try timestamp(model.createdAt, entityType: .photo, id: id, field: "createdAt"),
            updatedAt: try timestamp(model.updatedAt, entityType: .photo, id: id, field: "updatedAt")
        )
    }

    private mutating func mapProfile(_ model: UserProfile, id: String) throws -> BackupUserProfileV1 {
        BackupUserProfileV1(
            id: try validID(id, entityType: .profile),
            displayName: try requiredText(model.displayName, maximum: 200, entityType: .profile, id: id, field: "displayName"),
            bio: try text(model.bio, maximum: 160, entityType: .profile, id: id, field: "bio"),
            city: try text(model.city, maximum: 30, entityType: .profile, id: id, field: "city"),
            avatarPhotoId: try optionalID(model.avatarPhotoID, entityType: .photo),
            avatarPresetId: BackupProfileAvatarPresetV1(rawValue: model.avatarPreset.rawValue) ?? .polarBear,
            visibility: BackupVisibilityV1(rawValue: model.visibility.rawValue) ?? .private,
            createdAt: try timestamp(model.createdAt, entityType: .profile, id: id, field: "createdAt"),
            updatedAt: try timestamp(model.updatedAt, entityType: .profile, id: id, field: "updatedAt")
        )
    }

    private mutating func mapList(_ model: RestaurantList, id: String) throws -> BackupRestaurantListV1 {
        BackupRestaurantListV1(
            id: try validID(id, entityType: .restaurantList),
            title: try requiredText(model.title, maximum: 60, entityType: .restaurantList, id: id, field: "title"),
            description: try text(model.listDescription, maximum: 240, entityType: .restaurantList, id: id, field: "description"),
            visibility: BackupVisibilityV1(rawValue: model.visibility.rawValue) ?? .private,
            isRanked: model.isRanked,
            coverMode: model.coverMode == .automatic ? .automatic : .custom,
            customCoverPhotoId: try optionalID(model.customCoverPhotoID, entityType: .photo),
            createdAt: try timestamp(model.createdAt, entityType: .restaurantList, id: id, field: "createdAt"),
            updatedAt: try timestamp(model.updatedAt, entityType: .restaurantList, id: id, field: "updatedAt")
        )
    }

    private mutating func mapListItem(_ model: RestaurantListItem, id: String, listID: String) throws -> BackupRestaurantListItemV1 {
        guard let snapshot = model.restaurantSnapshot else {
            throw BackupExportError.invalidListSnapshot(entityID: id)
        }
        guard snapshot.restaurantId == model.restaurantReferenceID,
              snapshot.globalKey == model.restaurantGlobalKey else {
            throw BackupExportError.invalidListSnapshot(entityID: id)
        }
        let identities = try snapshot.placeIdentities.map {
            BackupRestaurantListPlaceIdentityV1(
                provider: BackupPlaceProviderV1(rawValue: $0.provider.rawValue) ?? .other,
                externalId: try validID($0.externalId, entityType: .restaurant),
                isPrimary: $0.isPrimary
            )
        }.sorted {
            if $0.provider.rawValue != $1.provider.rawValue { return $0.provider.rawValue < $1.provider.rawValue }
            return $0.externalId < $1.externalId
        }
        guard identities.count <= 16, identities.filter(\.isPrimary).count == 1 else {
            throw BackupExportError.invalidListSnapshot(entityID: id)
        }
        let place = BackupRestaurantListPlaceV1(
            globalKey: try validID(snapshot.globalKey, entityType: .restaurant),
            restaurantId: try validID(snapshot.restaurantId, entityType: .restaurant),
            placeIdentities: identities,
            name: try requiredText(snapshot.name, maximum: 300, entityType: .restaurantListItem, id: id, field: "restaurant.name"),
            address: try text(snapshot.address, maximum: 1_000, entityType: .restaurantListItem, id: id, field: "restaurant.address"),
            city: try text(snapshot.city, maximum: 200, entityType: .restaurantListItem, id: id, field: "restaurant.city"),
            latitude: try coordinate(snapshot.latitude, range: -90 ... 90, entityType: .restaurantListItem, id: id, field: "restaurant.latitude"),
            longitude: try coordinate(snapshot.longitude, range: -180 ... 180, entityType: .restaurantListItem, id: id, field: "restaurant.longitude"),
            markerPhotoId: try optionalID(snapshot.markerPhotoId, entityType: .photo),
            merchantImageUrl: try optionalHTTPSURL(snapshot.merchantImageUrl, entityType: .restaurantListItem, id: id, field: "restaurant.merchantImageUrl"),
            markerEmoji: try text(snapshot.markerEmoji, maximum: 32, entityType: .restaurantListItem, id: id, field: "restaurant.markerEmoji")
        )
        return BackupRestaurantListItemV1(
            id: try validID(id, entityType: .restaurantListItem),
            listId: try validID(listID, entityType: .restaurantList),
            restaurantId: place.restaurantId,
            restaurantGlobalKey: place.globalKey,
            position: try safeNonnegativeInteger(model.position, entityType: .restaurantListItem, id: id, field: "position"),
            note: try text(model.note, maximum: 160, entityType: .restaurantListItem, id: id, field: "note"),
            restaurant: place,
            createdAt: try timestamp(model.createdAt, entityType: .restaurantListItem, id: id, field: "createdAt"),
            updatedAt: try timestamp(model.updatedAt, entityType: .restaurantListItem, id: id, field: "updatedAt")
        )
    }

    private mutating func validate(entities: BackupEntitiesV1, tombstones: [BackupTombstoneV1]) {
        checkUnique(entities.restaurants.map(\.id), entityType: .restaurant)
        checkUnique(entities.visits.map(\.id), entityType: .visit)
        checkUnique(entities.dishes.map(\.id), entityType: .dish)
        checkUnique(entities.visitDishes.map(\.id), entityType: .visitDish)
        checkUnique(entities.photos.map(\.id), entityType: .photo)
        checkUnique(entities.companions.map(\.id), entityType: .companion)
        checkUnique(entities.recommendationSources.map(\.id), entityType: .recommendationSource)
        checkUnique(entities.profiles.map(\.id), entityType: .profile)
        checkUnique(entities.restaurantLists.map(\.id), entityType: .restaurantList)
        checkUnique(entities.restaurantListItems.map(\.id), entityType: .restaurantListItem)

        let restaurants = Set(entities.restaurants.map(\.id))
        let visits = Dictionary(uniqueKeysWithValues: entities.visits.map { ($0.id, $0) })
        let dishes = Dictionary(uniqueKeysWithValues: entities.dishes.map { ($0.id, $0) })
        let photos = Set(entities.photos.map(\.id))
        let companions = Set(entities.companions.map(\.id))
        let sources = Set(entities.recommendationSources.map(\.id))
        let profiles = Set(entities.profiles.map(\.id))
        let lists = Set(entities.restaurantLists.map(\.id))

        for visit in entities.visits {
            if !restaurants.contains(visit.restaurantId) {
                addOrphan(.visit, id: visit.id, field: "restaurantId", referenceID: visit.restaurantId)
            }
            for companionID in visit.companionIds where !companions.contains(companionID) {
                addOrphan(.visit, id: visit.id, field: "companionIds", referenceID: companionID)
            }
            if let sourceID = visit.recommendationSourceId, !sources.contains(sourceID) {
                addOrphan(.visit, id: visit.id, field: "recommendationSourceId", referenceID: sourceID)
            }
        }
        for dish in entities.dishes {
            if !restaurants.contains(dish.restaurantId) {
                addOrphan(.dish, id: dish.id, field: "restaurantId", referenceID: dish.restaurantId)
            }
            if visits[dish.originVisitId]?.restaurantId != dish.restaurantId {
                addOrphan(.dish, id: dish.id, field: "originVisitId", referenceID: dish.originVisitId)
            }
            if let photoID = dish.photoId, !photos.contains(photoID) {
                addOrphan(.dish, id: dish.id, field: "photoId", referenceID: photoID)
            }
        }
        for item in entities.visitDishes {
            if visits[item.visitId]?.restaurantId != item.restaurantId
                || dishes[item.dishId]?.restaurantId != item.restaurantId {
                addOrphan(.visitDish, id: item.id, field: "relationship", referenceID: nil)
            }
        }
        for photo in entities.photos {
            let isValid: Bool
            switch photo.parent.entityType {
            case .restaurant: isValid = restaurants.contains(photo.parent.entityId)
            case .visit: isValid = visits[photo.parent.entityId] != nil
            case .dish: isValid = dishes[photo.parent.entityId] != nil
            case .profile: isValid = profiles.contains(photo.parent.entityId)
            }
            if !isValid { addOrphan(.photo, id: photo.id, field: "parent", referenceID: photo.parent.entityId) }
        }
        for profile in entities.profiles {
            if let photoID = profile.avatarPhotoId, !photos.contains(photoID) {
                addOrphan(.profile, id: profile.id, field: "avatarPhotoId", referenceID: photoID)
            }
        }
        for item in entities.restaurantListItems where !lists.contains(item.listId) {
            addOrphan(.restaurantListItem, id: item.id, field: "listId", referenceID: item.listId)
        }
        let activeKeys = Set([
            entities.restaurants.map { "restaurant:\($0.id)" },
            entities.visits.map { "visit:\($0.id)" },
            entities.dishes.map { "dish:\($0.id)" },
            entities.visitDishes.map { "visitDish:\($0.id)" },
            entities.photos.map { "photo:\($0.id)" },
            entities.companions.map { "companion:\($0.id)" },
            entities.recommendationSources.map { "recommendationSource:\($0.id)" },
            entities.profiles.map { "profile:\($0.id)" },
            entities.restaurantLists.map { "restaurantList:\($0.id)" },
            entities.restaurantListItems.map { "restaurantListItem:\($0.id)" },
        ].flatMap { $0 })
        for tombstone in tombstones where activeKeys.contains("\(tombstone.entityType.rawValue):\(tombstone.id)") {
            addIssue(.invalidRelationship, tombstone.entityType, tombstone.id, "deletedAt", nil, "同一实体不能同时是 active 和 tombstone。")
        }
    }

    private func restaurantRecord(for model: Restaurant, stableID: String) throws -> RestaurantJSONContractV1 {
        if let data = model.remoteRecordData {
            do {
                let record = try JSONDecoder().decode(RestaurantJSONContractV1.self, from: data)
                guard record.id == stableID else { throw BackupExportError.invalidRestaurantRecord(entityID: stableID) }
                return record
            } catch let error as BackupExportError {
                throw error
            } catch {
                throw BackupExportError.invalidRestaurantRecord(entityID: stableID)
            }
        }
        do { return try SyncRecordMapper.restaurantRecord(model) }
        catch { throw BackupExportError.invalidRestaurantRecord(entityID: stableID) }
    }

    private func belongsToCurrentUser(
        owner: String,
        entityType: BackupEntityTypeV1,
        entityID: String,
        mayClaimDeviceLocalRecords: Bool
    ) throws -> Bool {
        if owner == currentUserID { return true }
        if owner == "local" {
            guard mayClaimDeviceLocalRecords else {
                throw BackupExportError.validation(BackupExportValidationError(issues: [
                    .init(code: .ambiguousLocalOwnership, entityType: entityType, entityID: entityID, field: nil, referenceID: nil, message: "本地记录缺少可证明的账号归属；为防止跨账号泄露，已停止导出。")
                ]))
            }
            return true
        }
        if Self.isTasteMapUserID(owner) { return false }
        throw BackupExportError.validation(BackupExportValidationError(issues: [
            .init(code: .unverifiedOwner, entityType: entityType, entityID: entityID, field: nil, referenceID: nil, message: "记录仍属于未验证的 legacy owner；不会自动绑定当前 Apple 登录用户。")
        ]))
    }

    private func photoScope(
        _ model: PhotoAsset,
        stableID: String,
        restaurantScope: [UUID: Bool],
        visitScope: [UUID: Bool],
        dishScope: [UUID: Bool],
        currentProfilePhotoParents: [String: String],
        otherProfilePhotoIDs: Set<String>
    ) -> (belongs: Bool, isInvalid: Bool, referenceID: String?) {
        switch model.kind {
        case .restaurantMarker:
            guard let id = model.restaurantId else { return (false, true, nil) }
            guard let belongs = restaurantScope[id] else { return (false, true, id.uuidString) }
            return (belongs, false, id.uuidString)
        case .visit:
            guard let id = model.visitId else { return (false, true, nil) }
            guard let belongs = visitScope[id] else { return (false, true, id.uuidString) }
            return (belongs, false, id.uuidString)
        case .dish:
            guard let id = model.dishId else { return (false, true, nil) }
            guard let belongs = dishScope[id] else { return (false, true, id.uuidString) }
            return (belongs, false, id.uuidString)
        case .avatar:
            if currentProfilePhotoParents[stableID] != nil { return (true, false, stableID) }
            if otherProfilePhotoIDs.contains(stableID) { return (false, false, stableID) }
            return (false, true, stableID)
        }
    }

    private mutating func photoParent(
        _ model: PhotoAsset,
        stableID: String,
        restaurantIDs: [UUID: String],
        visitIDs: [UUID: String],
        dishIDs: [UUID: String],
        currentProfilePhotoParents: [String: String],
        activeRestaurantLocalIDs: Set<UUID>,
        activeVisitLocalIDs: Set<UUID>,
        activeDishLocalIDs: Set<UUID>
    ) throws -> BackupPhotoParentV1? {
        switch model.kind {
        case .restaurantMarker:
            guard let localID = model.restaurantId, activeRestaurantLocalIDs.contains(localID),
                  let id = restaurantIDs[localID] else {
                addOrphan(.photo, id: stableID, field: "restaurantId", referenceID: model.restaurantId?.uuidString)
                return nil
            }
            return BackupPhotoParentV1(entityType: .restaurant, entityId: id)
        case .visit:
            guard let localID = model.visitId, activeVisitLocalIDs.contains(localID), let id = visitIDs[localID] else {
                addOrphan(.photo, id: stableID, field: "visitId", referenceID: model.visitId?.uuidString)
                return nil
            }
            return BackupPhotoParentV1(entityType: .visit, entityId: id)
        case .dish:
            guard let localID = model.dishId, activeDishLocalIDs.contains(localID), let id = dishIDs[localID] else {
                addOrphan(.photo, id: stableID, field: "dishId", referenceID: model.dishId?.uuidString)
                return nil
            }
            return BackupPhotoParentV1(entityType: .dish, entityId: id)
        case .avatar:
            guard let profileID = currentProfilePhotoParents[stableID] else {
                addOrphan(.photo, id: stableID, field: "profile", referenceID: nil)
                return nil
            }
            return BackupPhotoParentV1(entityType: .profile, entityId: profileID)
        }
    }

    private mutating func checkUnique(_ ids: [String], entityType: BackupEntityTypeV1) {
        var seen = Set<String>()
        for id in ids where !seen.insert(id).inserted {
            addIssue(.duplicateStableID, entityType, id, "id", id, "Backup v1 stable ID 重复。")
        }
    }

    private mutating func addOrphan(
        _ entityType: BackupEntityTypeV1,
        id: String,
        field: String,
        referenceID: String?
    ) {
        addIssue(.orphanedReference, entityType, id, field, referenceID, "发现 orphan 关联，已停止生成损坏的备份。")
    }

    private mutating func addIssue(
        _ code: BackupExportValidationIssue.Code,
        _ entityType: BackupEntityTypeV1?,
        _ entityID: String?,
        _ field: String?,
        _ referenceID: String?,
        _ message: String
    ) {
        issues.append(.init(
            code: code,
            entityType: entityType,
            entityID: entityID,
            field: field,
            referenceID: referenceID,
            message: message
        ))
    }

    private mutating func tombstone(_ type: BackupEntityTypeV1, id: String, deletedAt: Date) throws -> BackupTombstoneV1 {
        BackupTombstoneV1(
            entityType: type,
            id: try validID(id, entityType: type),
            deletedAt: try timestamp(deletedAt, entityType: type, id: id, field: "deletedAt")
        )
    }

    private func stableID(_ remoteID: String?, fallback: UUID, entityType: BackupEntityTypeV1) throws -> String {
        try validID(remoteID ?? fallback.uuidString.lowercased(), entityType: entityType)
    }

    private func validID(_ raw: String, entityType: BackupEntityTypeV1) throws -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 200 else {
            throw invalidField(entityType, id: raw, field: "id", message: "Backup v1 stable ID 无效。")
        }
        return value
    }

    private func optionalID(_ raw: String?, entityType: BackupEntityTypeV1) throws -> String? {
        guard let raw else { return nil }
        return try validID(raw, entityType: entityType)
    }

    private func requiredText(
        _ raw: String,
        maximum: Int,
        entityType: BackupEntityTypeV1,
        id: String,
        field: String
    ) throws -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= maximum else {
            throw invalidField(entityType, id: id, field: field, message: "字段 \(field) 为空或超出 Backup v1 上限。")
        }
        return value
    }

    private func text(
        _ raw: String,
        maximum: Int,
        entityType: BackupEntityTypeV1,
        id: String,
        field: String
    ) throws -> String {
        guard raw.count <= maximum else {
            throw invalidField(entityType, id: id, field: field, message: "字段 \(field) 超出 Backup v1 上限。")
        }
        return raw
    }

    private func optionalText(
        _ raw: String?,
        maximum: Int,
        entityType: BackupEntityTypeV1,
        id: String,
        field: String
    ) throws -> String? {
        guard let raw else { return nil }
        return try text(raw, maximum: maximum, entityType: entityType, id: id, field: field)
    }

    private func tagSet(
        _ values: [String],
        entityType: BackupEntityTypeV1,
        id: String,
        field: String
    ) throws -> [String] {
        let normalized = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard normalized.allSatisfy({ !$0.isEmpty && $0.count <= 100 }) else {
            throw invalidField(entityType, id: id, field: field, message: "标签为空或超出 Backup v1 上限。")
        }
        let sorted = normalized.uniquedAndSorted()
        guard sorted.count <= 100 else {
            throw invalidField(entityType, id: id, field: field, message: "标签数量超出 Backup v1 上限。")
        }
        return sorted
    }

    private func coordinate(
        _ value: Double,
        range: ClosedRange<Double>,
        entityType: BackupEntityTypeV1,
        id: String,
        field: String
    ) throws -> Double {
        guard value.isFinite, range.contains(value) else {
            throw invalidField(entityType, id: id, field: field, message: "坐标字段 \(field) 无效。")
        }
        return value
    }

    private func rating(
        _ value: Double?,
        entityType: BackupEntityTypeV1,
        id: String,
        field: String
    ) throws -> BackupRatingV1? {
        guard let value else { return nil }
        guard let result = BackupRatingV1(rawValue: value) else {
            throw BackupExportError.invalidRating(entityType: entityType, entityID: id, field: field)
        }
        return result
    }

    private func money(
        _ value: Double?,
        entityType: BackupEntityTypeV1,
        id: String,
        field: String
    ) throws -> BackupMoneyV1? {
        guard let value else { return nil }
        guard value.isFinite, let decimal = Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX")) else {
            throw BackupExportError.invalidMoney(entityType: entityType, entityID: id, field: field)
        }
        return try money(decimal, entityType: entityType, id: id, field: field)
    }

    private func money(
        _ value: Decimal?,
        entityType: BackupEntityTypeV1,
        id: String,
        field: String
    ) throws -> BackupMoneyV1? {
        guard var value else { return nil }
        guard value >= 0 else {
            throw BackupExportError.invalidMoney(entityType: entityType, entityID: id, field: field)
        }
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 2, .plain)
        guard rounded == value else {
            throw BackupExportError.invalidMoney(entityType: entityType, entityID: id, field: field)
        }
        let plain = NSDecimalNumber(decimal: rounded).stringValue
        guard !plain.lowercased().contains("e") else {
            throw BackupExportError.invalidMoney(entityType: entityType, entityID: id, field: field)
        }
        let pieces = plain.split(separator: ".", omittingEmptySubsequences: false)
        let output: String
        switch pieces.count {
        case 1: output = plain + ".00"
        case 2 where pieces[1].count == 1: output = plain + "0"
        case 2 where pieces[1].count == 2: output = plain
        default: throw BackupExportError.invalidMoney(entityType: entityType, entityID: id, field: field)
        }
        guard let result = BackupMoneyV1(rawValue: output) else {
            throw BackupExportError.invalidMoney(entityType: entityType, entityID: id, field: field)
        }
        return result
    }

    private mutating func timestamp(
        _ date: Date,
        entityType: BackupEntityTypeV1,
        id: String,
        field: String
    ) throws -> BackupTimestampV1 {
        if let cached = timestampCache[date] { return cached }
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let result = BackupTimestampV1(rawValue: formatter.string(from: date)) else {
            throw BackupExportError.invalidTimestamp(entityType: entityType, entityID: id, field: field)
        }
        timestampCache[date] = result
        return result
    }

    private func timestamp(
        _ raw: String,
        entityType: BackupEntityTypeV1,
        id: String,
        field: String
    ) throws -> BackupTimestampV1 {
        guard let result = BackupTimestampV1(rawValue: raw) else {
            throw BackupExportError.invalidTimestamp(entityType: entityType, entityID: id, field: field)
        }
        return result
    }

    private func enumValue<Value: RawRepresentable>(
        _ raw: String?,
        type: Value.Type,
        entityType: BackupEntityTypeV1,
        id: String,
        field: String
    ) throws -> Value? where Value.RawValue == String {
        guard let raw else { return nil }
        guard let value = Value(rawValue: raw) else {
            throw invalidField(entityType, id: id, field: field, message: "字段 \(field) 包含 Backup v1 不支持的枚举值。")
        }
        return value
    }

    private func optionalHTTPSURL(
        _ raw: String?,
        entityType: BackupEntityTypeV1,
        id: String,
        field: String
    ) throws -> String? {
        guard let raw else { return nil }
        guard raw.count <= 2_048, let components = URLComponents(string: raw),
              components.scheme?.lowercased() == "https", components.host != nil,
              components.user == nil, components.password == nil else {
            throw invalidField(entityType, id: id, field: field, message: "URL 字段必须是无凭据的 HTTPS URL。")
        }
        return raw
    }

    private func optionalWebURL(
        _ raw: String?,
        entityType: BackupEntityTypeV1,
        id: String,
        field: String
    ) throws -> String? {
        guard let raw else { return nil }
        guard raw.count <= 2_048, let components = URLComponents(string: raw),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              components.host != nil, components.user == nil, components.password == nil else {
            throw invalidField(entityType, id: id, field: field, message: "官网字段必须是无凭据的 HTTP 或 HTTPS URL。")
        }
        return raw
    }

    private func safeFileName(_ raw: String?, id: String) throws -> String? {
        guard let raw else { return nil }
        guard raw.count <= 512, !raw.contains("/"), !raw.contains("\\"),
              !raw.contains("\0"), raw != ".", raw != ".." else {
            throw BackupExportError.validation(BackupExportValidationError(issues: [
                .init(code: .unsafePhotoMetadata, entityType: .photo, entityID: id, field: "fileName", referenceID: nil, message: "照片文件名包含路径或不安全字符，已停止导出。")
            ]))
        }
        return raw
    }

    private func safeNonnegativeInteger<T: BinaryInteger>(
        _ value: T,
        entityType: BackupEntityTypeV1,
        id: String,
        field: String
    ) throws -> T {
        guard value >= 0, value <= 9_007_199_254_740_991 else {
            throw invalidField(entityType, id: id, field: field, message: "整数字段 \(field) 超出 Backup v1 安全范围。")
        }
        return value
    }

    private func optionalPositiveInteger(
        _ value: Int?,
        entityType: BackupEntityTypeV1,
        id: String,
        field: String
    ) throws -> Int? {
        guard let value else { return nil }
        guard value > 0, value <= 9_007_199_254_740_991 else {
            throw invalidField(entityType, id: id, field: field, message: "整数字段 \(field) 超出 Backup v1 安全范围。")
        }
        return value
    }

    private func invalidField(
        _ entityType: BackupEntityTypeV1,
        id: String,
        field: String,
        message: String
    ) -> BackupExportError {
        .validation(BackupExportValidationError(issues: [
            .init(code: .invalidField, entityType: entityType, entityID: id, field: field, referenceID: nil, message: message)
        ]))
    }

    private static func isTasteMapUserID(_ value: String) -> Bool {
        value.range(of: #"^tm_[A-Za-z0-9_-]{1,196}$"#, options: .regularExpression) != nil
    }
}

private extension Array where Element == String {
    func uniquedAndSorted() -> [String] { Array(Set(self)).sorted() }
}

private extension Array {
    func uniquedAndSorted<Key: Hashable & Comparable>(by keyPath: KeyPath<Element, Key>) -> [Element] {
        var seen = Set<Key>()
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
            .sorted { $0[keyPath: keyPath] < $1[keyPath: keyPath] }
    }
}
