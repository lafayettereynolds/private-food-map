#if DEBUG
import Foundation

/// Synthetic, non-sensitive inputs used only by previews and UI automation.
/// Production builds do not compile these fixtures.
nonisolated enum BackupImportDevelopmentFixture: String, Sendable {
    case legacyValid
    case legacyBlocking

    static let environmentKey = "TASTEMAP_F1C2_IMPORT_UI_TEST"

    static var current: BackupImportDevelopmentFixture? {
        switch ProcessInfo.processInfo.environment[environmentKey] {
        case "legacy": .legacyValid
        case "blocking": .legacyBlocking
        default: nil
        }
    }

    var fileName: String {
        switch self {
        case .legacyValid: "TasteMap-Legacy-v4-Fixture.json"
        case .legacyBlocking: "TasteMap-Legacy-v4-Broken-Reference.json"
        }
    }

    var data: Data {
        var root = Self.emptyLegacyEnvelope
        switch self {
        case .legacyValid:
            root["restaurants"] = [Self.restaurant(id: "legacy-r-1")]
            root["visits"] = [Self.visit(id: "legacy-v-1", restaurantID: "legacy-r-1")]
        case .legacyBlocking:
            root["visits"] = [Self.visit(id: "legacy-v-broken", restaurantID: "missing-r")]
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
            "name": "预检测试餐厅",
            "address": "测试路 1 号",
            "city": "上海",
            "latitude": 31.2304,
            "longitude": 121.4737,
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
}
#endif
