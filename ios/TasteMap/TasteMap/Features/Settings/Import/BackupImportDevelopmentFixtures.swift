#if DEBUG
import Foundation

/// Synthetic, non-sensitive inputs used only by previews and UI automation.
/// Production builds do not compile these fixtures.
nonisolated enum BackupImportDevelopmentFixture: String, Sendable {
    case legacyValid
    case legacyBlocking
    case backupV1
    case transactionFailure

    static let environmentKey = "TASTEMAP_F1C2_IMPORT_UI_TEST"

    static var current: BackupImportDevelopmentFixture? {
        switch ProcessInfo.processInfo.environment[environmentKey] {
        case "legacy": .legacyValid
        case "blocking": .legacyBlocking
        case "backup": .backupV1
        case "failure": .transactionFailure
        default: nil
        }
    }

    var input: BackupImportFixtureInput {
        BackupImportFixtureInput(fileName: fileName, data: data, delay: .seconds(4))
    }

    var injectedFailurePoint: BackupImportFailurePoint? {
        self == .transactionFailure ? .beforeSave : nil
    }

    var fileName: String {
        switch self {
        case .legacyValid: "TasteMap-Legacy-v4-Fixture.json"
        case .legacyBlocking: "TasteMap-Legacy-v4-Broken-Reference.json"
        case .backupV1: "TasteMap-Backup-v1-Fixture.json"
        case .transactionFailure: "TasteMap-Legacy-v4-Failure-Fixture.json"
        }
    }

    var data: Data {
        var root = Self.emptyLegacyEnvelope
        switch self {
        case .legacyValid, .transactionFailure:
            root["restaurants"] = [Self.restaurant(id: "legacy-r-1")]
            root["visits"] = [Self.visit(id: "legacy-v-1", restaurantID: "legacy-r-1")]
        case .legacyBlocking:
            root["visits"] = [Self.visit(id: "legacy-v-broken", restaurantID: "missing-r")]
        case .backupV1:
            return Self.emptyBackupV1
        }
        // Every fixture value is a JSON primitive created in this file.
        return try! JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }

    private static let timestamp = "2026-08-29T12:00:00.000Z"

    private static var emptyLegacyEnvelope: [String: Any] {
        [
            "app": "Taste Map",
            "version": 4,
            "environment": "development",
            "databaseName": "FoodMapDB",
            "exportedAt": timestamp,
            "restaurants": [],
            "visits": [],
            "photos": [],
            "users": [],
            "friendships": [],
            "sharedMeals": [],
            "sharedMealParticipants": [],
            "restaurantLists": [],
            "restaurantListItems": [],
        ]
    }

    private static func restaurant(id: String) -> [String: Any] {
        [
            "id": id,
            "userId": "legacy-owner",
            "amapPoiId": "",
            "name": "P1-D 离线验收餐厅",
            "address": "杭州市上城区湖滨路 18 号",
            "city": "杭州",
            "latitude": 30.25901,
            "longitude": 120.168,
            "status": "visited",
            "preferenceLevel": "like",
            "overallRating": NSNull(),
            "foodRating": NSNull(),
            "environmentRating": NSNull(),
            "serviceRating": NSNull(),
            "valueRating": NSNull(),
            "tags": ["测试"],
            "longTermNote": "",
            "pricePerPerson": NSNull(),
            "phone": NSNull(),
            "openingHours": NSNull(),
            "markerType": "emoji",
            "markerImageData": NSNull(),
            "markerPhotoId": NSNull(),
            "merchantImageUrl": NSNull(),
            "markerEmoji": "🍜",
            "createdAt": timestamp,
            "updatedAt": timestamp,
            "deletedAt": NSNull(),
        ]
    }

    private static func visit(id: String, restaurantID: String) -> [String: Any] {
        [
            "id": id,
            "userId": "legacy-owner",
            "restaurantId": restaurantID,
            "visitedAt": timestamp,
            "rating": NSNull(),
            "visibility": "private",
            "diningMode": "dine_in",
            "totalPrice": NSNull(),
            "myActualSpend": NSNull(),
            "paymentMode": NSNull(),
            "pricePerPerson": NSNull(),
            "partySize": NSNull(),
            "queueDuration": NSNull(),
            "diningOccasions": [],
            "diningOccasion": NSNull(),
            "diningOccasionText": "",
            "valueRating": NSNull(),
            "environmentRating": NSNull(),
            "serviceRating": NSNull(),
            "valueTags": [],
            "environmentTags": [],
            "serviceTags": [],
            "noiseLevel": NSNull(),
            "diningDuration": NSNull(),
            "portionLevel": NSNull(),
            "transportConvenience": NSNull(),
            "specialNotes": "",
            "recommendationSourceType": NSNull(),
            "recommendationSourceUserId": NSNull(),
            "recommendationSourceText": "",
            "sharedMealId": NSNull(),
            "companions": [],
            "companionIds": [],
            "dishes": [],
            "note": "",
            "photos": [],
            "photoIds": [],
            "createdAt": timestamp,
            "updatedAt": timestamp,
            "deletedAt": NSNull(),
        ]
    }

    private static var emptyBackupV1: Data {
        let timestamp = try! BackupTimestampV1(Self.timestamp)
        let restaurantID = "f1c4-backup-v1-restaurant"
        let visitID = "f1c4-backup-v1-visit"
        let restaurant = BackupRestaurantV1(
            id: restaurantID,
            placeIdentities: [BackupPlaceIdentityV1(
                provider: .appleMaps,
                externalId: "apple-f1c4-backup-v1",
                isPrimary: true,
                createdAt: timestamp,
                updatedAt: timestamp
            )],
            name: "F1-C4 Backup v1 餐厅",
            address: "杭州市西湖区测试路 1 号",
            city: "杭州",
            latitude: 30.2601,
            longitude: 120.1501,
            status: .visited,
            preferenceLevel: .like,
            overallRating: nil,
            foodRating: nil,
            environmentRating: nil,
            serviceRating: nil,
            valueRating: nil,
            tags: ["Backup v1"],
            longTermNote: "F1-C4 Development fixture",
            pricePerPerson: nil,
            phone: nil,
            openingHours: nil,
            markerType: .emoji,
            markerPhotoId: nil,
            merchantImageUrl: nil,
            markerEmoji: "🍜",
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let visit = BackupVisitV1(
            id: visitID,
            restaurantId: restaurantID,
            visitedAt: timestamp,
            diningMode: .dineIn,
            visibility: .private,
            partySize: nil,
            totalPrice: nil,
            myActualSpend: nil,
            paymentMode: nil,
            pricePerPerson: nil,
            queueDuration: nil,
            diningOccasions: [],
            diningOccasionText: nil,
            rating: nil,
            valueRating: nil,
            environmentRating: nil,
            serviceRating: nil,
            valueTags: [],
            environmentTags: [],
            serviceTags: [],
            noiseLevel: nil,
            diningDuration: nil,
            portionLevel: nil,
            transportConvenience: nil,
            specialNotes: nil,
            companionIds: [],
            recommendationSourceId: nil,
            recommendationSourceType: nil,
            recommendationSourceText: nil,
            sharedMealReferenceHint: nil,
            note: "F1-C4 Backup v1 UI fixture",
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let entities = BackupEntitiesV1(
            restaurants: [restaurant], visits: [visit], dishes: [], visitDishes: [], photos: [],
            companions: [], recommendationSources: [], profiles: [],
            restaurantLists: [], restaurantListItems: []
        )
        let counts = BackupEntityCountsV1(
            restaurants: 1, visits: 1, dishes: 0, visitDishes: 0, photos: 0,
            companions: 0, recommendationSources: 0, profiles: 0,
            restaurantLists: 0, restaurantListItems: 0
        )
        let payload = BackupIntegrityPayloadV1(
            format: BackupV1Contract.format,
            schemaVersion: BackupV1Contract.schemaVersion,
            exportId: "11111111-aaaa-4aaa-8aaa-111111111111",
            exportedAt: timestamp,
            source: BackupSourceV1(
                platform: .ios, appVersion: "1.0", appBuild: "1", environment: .development
            ),
            scope: BackupScopeV1(),
            entities: entities,
            tombstones: [],
            metadata: BackupMetadataV1(entityCounts: counts, tombstoneCount: 0)
        )
        let digest = BackupCanonicalJSONV1.sha256Hex(
            of: try! BackupCanonicalJSONV1.canonicalString(for: payload)
        )
        let envelope = BackupEnvelopeV1(
            format: payload.format,
            schemaVersion: payload.schemaVersion,
            exportId: payload.exportId,
            exportedAt: payload.exportedAt,
            source: payload.source,
            scope: payload.scope,
            entities: payload.entities,
            tombstones: payload.tombstones,
            metadata: payload.metadata,
            integrity: try! BackupIntegrityV1(digest: digest)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try! encoder.encode(envelope)
    }
}
#endif
