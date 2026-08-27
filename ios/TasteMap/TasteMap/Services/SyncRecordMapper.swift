import Foundation

@MainActor
enum SyncRecordMapper {
    static func restaurantPayload(_ restaurant: Restaurant) throws -> Data {
        try JSONEncoder().encode(restaurantRecord(restaurant))
    }

    static func visitPayload(_ visit: Visit, restaurantRemoteID: String) throws -> Data {
        try JSONEncoder().encode(visitRecord(visit, restaurantRemoteID: restaurantRemoteID))
    }

    static func dishPayload(
        _ dish: Dish,
        restaurantRemoteID: String,
        visitRemoteID: String
    ) throws -> Data {
        try JSONEncoder().encode(try dishRecord(
            dish,
            restaurantRemoteID: restaurantRemoteID,
            visitRemoteID: visitRemoteID
        ))
    }

    static func photoPayload(
        _ photo: PhotoAsset,
        restaurantRemoteID: String?,
        visitRemoteID: String?,
        dishRemoteID: String?
    ) throws -> Data {
        try JSONEncoder().encode(try photoRecord(
            photo,
            restaurantRemoteID: restaurantRemoteID,
            visitRemoteID: visitRemoteID,
            dishRemoteID: dishRemoteID
        ))
    }

    static func visitDishPayload(
        _ association: VisitDish,
        restaurantRemoteID: String,
        visitRemoteID: String,
        dishRemoteID: String
    ) throws -> Data {
        try JSONEncoder().encode(try visitDishRecord(
            association,
            restaurantRemoteID: restaurantRemoteID,
            visitRemoteID: visitRemoteID,
            dishRemoteID: dishRemoteID
        ))
    }

    static func restaurantRecord(_ restaurant: Restaurant) throws -> RestaurantJSONContractV1 {
        let remoteID = restaurant.remoteID ?? restaurant.id.uuidString
        let previous = restaurant.remoteRecordData.flatMap {
            try? JSONDecoder().decode(RestaurantJSONContractV1.self, from: $0)
        }
        let identities: [RestaurantPlaceIdentityContract]
        if let previous {
            identities = previous.placeIdentities
        } else if let appleID = restaurant.appleMapItemIdentifier, !appleID.isEmpty {
            identities = [try RestaurantPlaceIdentityContract(
                provider: .appleMaps,
                externalId: appleID,
                isPrimary: true,
                createdAt: dateString(restaurant.createdAt),
                updatedAt: dateString(restaurant.updatedAt)
            )]
        } else {
            identities = [try RestaurantPlaceIdentityContract(
                provider: .manual,
                externalId: "tastemap:\(remoteID)",
                isPrimary: true,
                createdAt: dateString(restaurant.createdAt),
                updatedAt: dateString(restaurant.updatedAt)
            )]
        }
        return try RestaurantJSONContractV1(
            id: remoteID,
            userId: previous?.userId ?? "local",
            placeIdentities: identities,
            amapPoiId: previous?.amapPoiId,
            name: restaurant.name,
            address: restaurant.address,
            city: restaurant.city,
            latitude: restaurant.latitude,
            longitude: restaurant.longitude,
            status: restaurant.status.contractValue,
            preferenceLevel: previous?.preferenceLevel ?? .normal,
            overallRating: previous?.overallRating,
            foodRating: previous?.foodRating,
            environmentRating: previous?.environmentRating,
            serviceRating: previous?.serviceRating,
            valueRating: previous?.valueRating,
            tags: previous?.tags ?? [],
            longTermNote: previous?.longTermNote ?? "",
            pricePerPerson: previous?.pricePerPerson,
            phone: previous?.phone,
            openingHours: previous?.openingHours,
            markerType: previous?.markerType ?? .emoji,
            markerPhotoId: previous?.markerPhotoId,
            merchantImageUrl: previous?.merchantImageUrl,
            markerEmoji: previous?.markerEmoji ?? "🍽️",
            createdAt: dateString(restaurant.createdAt),
            updatedAt: dateString(restaurant.updatedAt),
            deletedAt: restaurant.deletedAt.map(dateString),
            isTestData: previous?.isTestData
        )
    }

    static func visitRecord(_ visit: Visit, restaurantRemoteID: String) -> VisitSyncContractV1 {
        VisitSyncContractV1(
            schemaVersion: SyncV1Contract.schemaVersion,
            id: visit.remoteID ?? visit.id.uuidString,
            userId: "local",
            restaurantId: restaurantRemoteID,
            visitedAt: dateString(visit.visitedAt),
            diningMode: visit.diningMode,
            partySize: visit.partySize,
            rating: visit.rating,
            note: visit.note,
            myActualSpend: visit.myActualSpend.map { NSDecimalNumber(decimal: $0).doubleValue },
            createdAt: dateString(visit.createdAt),
            updatedAt: dateString(visit.updatedAt),
            deletedAt: visit.deletedAt.map(dateString)
        )
    }

    static func dishRecord(
        _ dish: Dish,
        restaurantRemoteID: String,
        visitRemoteID: String
    ) throws -> DishSyncContractV1 {
        try DishSyncContractV1(
            id: dish.remoteID ?? dish.id.uuidString.lowercased(),
            userId: "local",
            restaurantId: restaurantRemoteID,
            visitId: visitRemoteID,
            name: dish.name,
            taste: dish.taste,
            rating: dish.rating,
            price: dish.price.map { NSDecimalNumber(decimal: $0).doubleValue },
            photoId: dish.photoRemoteID,
            sortOrder: dish.sortOrder,
            createdAt: dateString(dish.createdAt),
            updatedAt: dateString(dish.updatedAt),
            deletedAt: dish.deletedAt.map(dateString)
        )
    }

    static func visitDishRecord(
        _ association: VisitDish,
        restaurantRemoteID: String,
        visitRemoteID: String,
        dishRemoteID: String
    ) throws -> VisitDishSyncContractV1 {
        try VisitDishSyncContractV1(
            id: association.remoteID ?? association.id.uuidString.lowercased(),
            userId: "local",
            restaurantId: restaurantRemoteID,
            visitId: visitRemoteID,
            dishId: dishRemoteID,
            sortOrder: association.sortOrder,
            createdAt: dateString(association.createdAt),
            updatedAt: dateString(association.updatedAt),
            deletedAt: association.deletedAt.map(dateString)
        )
    }

    static func photoRecord(
        _ photo: PhotoAsset,
        restaurantRemoteID: String?,
        visitRemoteID: String?,
        dishRemoteID: String?
    ) throws -> PhotoSyncContractV1 {
        guard let provider = photo.storageProvider,
              let storageKey = photo.storageKey, !storageKey.isEmpty else {
            throw RichRecordContractError.invalidPhoto
        }
        return try PhotoSyncContractV1(
            id: photo.remoteID ?? photo.id.uuidString.lowercased(),
            userId: "local",
            restaurantId: restaurantRemoteID,
            visitId: visitRemoteID,
            dishId: dishRemoteID,
            kind: photo.kind,
            storageProvider: provider,
            storageKey: storageKey,
            providerAccountId: photo.providerAccountId,
            thumbnailStorageKey: photo.thumbnailStorageKey,
            fileName: photo.fileName,
            mimeType: photo.mimeType,
            byteSize: photo.byteSize,
            width: photo.width,
            height: photo.height,
            sortOrder: photo.sortOrder,
            visibility: photo.visibility,
            createdAt: dateString(photo.createdAt),
            updatedAt: dateString(photo.updatedAt),
            deletedAt: photo.deletedAt.map(dateString)
        )
    }

    static func dateString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}

private extension RestaurantStatus {
    var contractValue: RestaurantJSONContractV1.RestaurantStatusContract {
        switch self {
        case .visited: .visited
        case .wantToGo: .wantToGo
        }
    }
}
