import Foundation

nonisolated struct LegacyWebV4SourceMetadata: Codable, Equatable, Sendable {
    let sourceLineage: LegacyBackupSourceLineage
    let app: String
    let version: Int
    let environment: String
    let databaseName: String
    let exportedAt: BackupTimestampV1
    /// SHA-256 of the exact source bytes. It namespaces file-local derived
    /// source IDs and is never a target business identifier.
    let sourceFingerprint: String
}

nonisolated struct LegacyStagingPlaceIdentity: Codable, Equatable, Sendable {
    let sourceLineage: LegacyBackupSourceLineage
    let provider: BackupPlaceProviderV1
    let externalID: String
    let isPrimary: Bool
    let createdAt: BackupTimestampV1?
    let updatedAt: BackupTimestampV1?
}

nonisolated struct LegacyStagingRestaurant: Codable, Equatable, Sendable {
    let sourceLineage: LegacyBackupSourceLineage
    let sourceID: String
    let placeIdentities: [LegacyStagingPlaceIdentity]
    let name: String
    let address: String?
    let city: String?
    let latitude: Double
    let longitude: Double
    let status: BackupRestaurantStatusV1?
    let preferenceLevel: BackupRestaurantPreferenceV1?
    let overallRating: BackupRatingV1?
    let foodRating: BackupRatingV1?
    let environmentRating: BackupRatingV1?
    let serviceRating: BackupRatingV1?
    let valueRating: BackupRatingV1?
    let tags: [String]?
    let longTermNote: String?
    let pricePerPerson: BackupMoneyV1?
    let phone: String?
    let openingHours: String?
    let markerType: BackupMarkerTypeV1?
    let markerPhotoSourceID: String?
    let merchantImageURL: String?
    let markerEmoji: String?
    let createdAt: BackupTimestampV1?
    let updatedAt: BackupTimestampV1?
}

nonisolated struct LegacyStagingVisit: Codable, Equatable, Sendable {
    let sourceLineage: LegacyBackupSourceLineage
    let sourceID: String
    let sourceRestaurantID: String
    let visitedAt: BackupTimestampV1?
    let diningMode: BackupDiningModeV1?
    let visibility: BackupVisibilityV1?
    let totalPrice: BackupMoneyV1?
    let myActualSpend: BackupMoneyV1?
    let paymentMode: BackupPaymentModeV1?
    let pricePerPerson: BackupMoneyV1?
    let partySize: Int?
    let queueDuration: BackupQueueDurationV1?
    let diningOccasions: [BackupDiningOccasionV1]?
    let diningOccasionText: String?
    let rating: BackupRatingV1?
    let valueRating: BackupRatingV1?
    let environmentRating: BackupRatingV1?
    let serviceRating: BackupRatingV1?
    let valueTags: [String]?
    let environmentTags: [String]?
    let serviceTags: [String]?
    let noiseLevel: BackupNoiseLevelV1?
    let diningDuration: BackupDiningDurationV1?
    let portionLevel: BackupPortionLevelV1?
    let transportConvenience: BackupTransportConvenienceV1?
    let specialNotes: String?
    let recommendationSourceID: String?
    let recommendationSourceType: BackupRecommendationSourceTypeV1?
    let recommendationSourceText: String?
    let sharedMealReferenceHint: String?
    let companionSourceIDs: [String]
    let note: String?
    let createdAt: BackupTimestampV1?
    let updatedAt: BackupTimestampV1?
}

nonisolated struct LegacyStagingDish: Codable, Equatable, Sendable {
    let sourceLineage: LegacyBackupSourceLineage
    let sourceID: String
    let sourceLegacyDishID: String?
    let sourceRestaurantID: String
    let sourceVisitID: String
    let name: String
    let sourcePhotoID: String?
}

nonisolated struct LegacyStagingVisitDish: Codable, Equatable, Sendable {
    let sourceLineage: LegacyBackupSourceLineage
    let sourceID: String
    let sourceVisitID: String
    let sourceRestaurantID: String
    let sourceDishID: String
    let tasteNote: String?
    let rating: BackupRatingV1?
    let price: BackupMoneyV1?
    let sourceOrder: Int
}

nonisolated struct LegacyStagingDiningCompanion: Codable, Equatable, Sendable {
    let sourceLineage: LegacyBackupSourceLineage
    let sourceID: String
    let displayName: String
    let firstObservedAt: BackupTimestampV1?
    let lastObservedAt: BackupTimestampV1?
}

nonisolated struct LegacyStagingRecommendationSource: Codable, Equatable, Sendable {
    let sourceLineage: LegacyBackupSourceLineage
    let sourceID: String
    let displayName: String
    let sourceType: BackupRecommendationSourceTypeV1?
    let firstObservedAt: BackupTimestampV1?
    let lastObservedAt: BackupTimestampV1?
}

nonisolated struct LegacyStagingPhotoParent: Codable, Equatable, Sendable {
    let entityType: BackupPhotoParentEntityTypeV1
    let sourceID: String
}

nonisolated struct LegacyStagingPhoto: Codable, Equatable, Sendable {
    let sourceLineage: LegacyBackupSourceLineage
    let sourceID: String
    let kind: BackupPhotoKindV1
    let parent: LegacyStagingPhotoParent
    let fileName: String?
    let mimeType: String?
    let byteSize: Int?
    let width: Int?
    let height: Int?
    let sourceOrder: Int
    let visibility: BackupVisibilityV1?
    let createdAt: BackupTimestampV1?
    let updatedAt: BackupTimestampV1?
    let binaryAvailable: Bool
}

nonisolated struct LegacyStagingProfile: Codable, Equatable, Sendable {
    let sourceLineage: LegacyBackupSourceLineage
    let sourceID: String
    let displayName: String?
    let bio: String?
    let city: String?
    let avatarPhotoSourceID: String?
    let avatarPresetID: BackupProfileAvatarPresetV1?
    let visibility: BackupVisibilityV1?
    let createdAt: BackupTimestampV1?
    let updatedAt: BackupTimestampV1?
}

nonisolated struct LegacyStagingRestaurantList: Codable, Equatable, Sendable {
    let sourceLineage: LegacyBackupSourceLineage
    let sourceID: String
    let title: String
    let listDescription: String?
    let visibility: BackupVisibilityV1?
    let isRanked: Bool?
    let coverMode: BackupRestaurantListCoverModeV1?
    let customCoverPhotoSourceID: String?
    let createdAt: BackupTimestampV1?
    let updatedAt: BackupTimestampV1?
}

nonisolated struct LegacyStagingRestaurantListItem: Codable, Equatable, Sendable {
    let sourceLineage: LegacyBackupSourceLineage
    let sourceID: String
    let sourceListID: String
    let sourceRestaurantID: String
    let position: Int?
    let note: String?
    let createdAt: BackupTimestampV1?
    let updatedAt: BackupTimestampV1?
}

nonisolated struct LegacyStagingTombstone: Codable, Equatable, Sendable {
    let sourceLineage: LegacyBackupSourceLineage
    let entityType: BackupEntityTypeV1
    let sourceID: String
    let deletedAt: BackupTimestampV1
}

nonisolated struct LegacyBackupStagingGraph: Codable, Equatable, Sendable {
    let sourceMetadata: LegacyWebV4SourceMetadata
    let restaurants: [LegacyStagingRestaurant]
    let visits: [LegacyStagingVisit]
    let dishes: [LegacyStagingDish]
    let visitDishes: [LegacyStagingVisitDish]
    let photos: [LegacyStagingPhoto]
    let companions: [LegacyStagingDiningCompanion]
    let recommendationSources: [LegacyStagingRecommendationSource]
    let profiles: [LegacyStagingProfile]
    let restaurantLists: [LegacyStagingRestaurantList]
    let restaurantListItems: [LegacyStagingRestaurantListItem]
    let tombstones: [LegacyStagingTombstone]
    let conversionReport: LegacyBackupConversionReport
}
