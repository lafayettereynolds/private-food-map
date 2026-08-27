import Foundation

@MainActor
enum SyncRecordMapper {
    static func restaurantPayload(_ restaurant: Restaurant) throws -> Data {
        try JSONEncoder().encode(restaurantRecord(restaurant))
    }

    static func visitPayload(_ visit: Visit, restaurantRemoteID: String) throws -> Data {
        try JSONEncoder().encode(visitRecord(visit, restaurantRemoteID: restaurantRemoteID))
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
