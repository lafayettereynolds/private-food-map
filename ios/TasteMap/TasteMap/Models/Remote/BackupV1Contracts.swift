import CryptoKit
import Foundation

nonisolated enum BackupV1Contract {
    static let format = "com.tastemap.backup"
    static let schemaVersion = 1
    static let canonicalization = "tastemap-backup-v1"
    static let integrityAlgorithm = "sha256"
}

nonisolated enum BackupV1ContractError: Error, Equatable {
    case invalidFormat
    case invalidSchemaVersion
    case invalidExportID
    case invalidScope
    case invalidTimestamp
    case invalidMoney
    case invalidRating
    case invalidIntegrityMetadata
    case invalidDigest
    case invalidCanonicalJSON
}

nonisolated struct BackupTimestampV1: Codable, Equatable, Hashable, Sendable, RawRepresentable {
    let rawValue: String

    init?(rawValue: String) {
        guard Self.isValid(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    init(_ rawValue: String) throws {
        guard Self.isValid(rawValue) else { throw BackupV1ContractError.invalidTimestamp }
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(String.self))
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    private static func isValid(_ value: String) -> Bool {
        let pattern = #"^[0-9]{4}-(0[1-9]|1[0-2])-([0-2][0-9]|3[01])T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]\.[0-9]{3}Z$"#
        guard value.range(of: pattern, options: .regularExpression) != nil else { return false }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) != nil
    }
}

nonisolated struct BackupMoneyV1: Codable, Equatable, Hashable, Sendable, RawRepresentable {
    let rawValue: String

    init?(rawValue: String) {
        guard Self.isValid(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    init(_ rawValue: String) throws {
        guard Self.isValid(rawValue) else { throw BackupV1ContractError.invalidMoney }
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(String.self))
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var decimalValue: Decimal {
        Decimal(string: rawValue, locale: Locale(identifier: "en_US_POSIX")) ?? .zero
    }

    private static func isValid(_ value: String) -> Bool {
        value.range(
            of: #"^(0|[1-9][0-9]{0,15})\.[0-9]{2}$"#,
            options: .regularExpression
        ) != nil
    }
}

nonisolated struct BackupRatingV1: Codable, Equatable, Hashable, Sendable, RawRepresentable {
    let rawValue: Double

    init?(rawValue: Double) {
        guard rawValue.isFinite, (0.5 ... 5).contains(rawValue),
              (rawValue * 2).rounded() == rawValue * 2 else { return nil }
        self.rawValue = rawValue
    }

    init(_ rawValue: Double) throws {
        guard let value = Self(rawValue: rawValue) else { throw BackupV1ContractError.invalidRating }
        self = value
    }

    init(from decoder: Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(Double.self))
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

nonisolated enum BackupPlatformV1: String, Codable, Sendable { case ios, web }
nonisolated enum BackupEnvironmentV1: String, Codable, Sendable { case development, production }
nonisolated enum BackupVisibilityV1: String, Codable, Sendable { case `private`, friends, `public` }
nonisolated enum BackupRestaurantStatusV1: String, Codable, Sendable { case visited, wantToGo }
nonisolated enum BackupRestaurantPreferenceV1: String, Codable, Sendable { case favorite, like, normal, avoid }
nonisolated enum BackupPlaceProviderV1: String, Codable, Sendable {
    case amap
    case appleMaps = "apple_maps"
    case manual
    case other
}
nonisolated enum BackupMarkerTypeV1: String, Codable, Sendable { case image, emoji }
nonisolated enum BackupDiningModeV1: String, Codable, Sendable { case dineIn = "dine_in", takeout }
nonisolated enum BackupPaymentModeV1: String, Codable, Sendable { case aa, myTreat = "my_treat", treated, separate, other }
nonisolated enum BackupQueueDurationV1: String, Codable, Sendable {
    case none, under15, under30, under60, under90, under120, over120
}
nonisolated enum BackupDiningOccasionV1: String, Codable, Sendable {
    case solo, date, friends, family, business, celebration, other
}
nonisolated enum BackupNoiseLevelV1: String, Codable, Sendable { case quiet, normal, loud, veryLoud = "very_loud" }
nonisolated enum BackupDiningDurationV1: String, Codable, Sendable {
    case under15, under30, under45, under60, under90, under120, over120
}
nonisolated enum BackupPortionLevelV1: String, Codable, Sendable { case small, normal, generous }
nonisolated enum BackupTransportConvenienceV1: String, Codable, Sendable {
    case veryConvenient = "very_convenient", convenient, normal, inconvenient
}
nonisolated enum BackupRecommendationSourceTypeV1: String, Codable, Sendable {
    case friend, xiaohongshu, douyin, dianping, blogger, `self`, other
}
nonisolated enum BackupPhotoKindV1: String, Codable, Sendable {
    case restaurantMarker = "restaurant-marker"
    case visit, dish, avatar
}
nonisolated enum BackupPhotoParentEntityTypeV1: String, Codable, Sendable {
    case restaurant, visit, dish, profile
}
nonisolated enum BackupRestaurantListCoverModeV1: String, Codable, Sendable { case automatic, custom }
nonisolated enum BackupProfileAvatarPresetV1: String, Codable, Sendable {
    case polarBear = "polar-bear"
    case penguin, cat, dog, parrot, dinosaur, shiba, panda, otter, hedgehog
    case rabbit, koala, fox, raccoon, deer, whale
}
nonisolated enum BackupEntityTypeV1: String, Codable, Sendable {
    case restaurant, visit, dish, visitDish, photo, companion
    case recommendationSource, profile, restaurantList, restaurantListItem
}

nonisolated struct BackupSourceV1: Codable, Equatable, Sendable {
    let platform: BackupPlatformV1
    let appVersion: String
    let appBuild: String
    let environment: BackupEnvironmentV1
}

nonisolated struct BackupScopeV1: Codable, Equatable, Sendable {
    let kind: String
    let includesPhotoBinaries: Bool

    init() {
        kind = "user-data"
        includesPhotoBinaries = false
    }
}

nonisolated struct BackupPlaceIdentityV1: Codable, Equatable, Sendable {
    let provider: BackupPlaceProviderV1
    let externalId: String
    let isPrimary: Bool
    let createdAt: BackupTimestampV1
    let updatedAt: BackupTimestampV1
}

nonisolated struct BackupRestaurantV1: Codable, Equatable, Sendable {
    let id: String
    let placeIdentities: [BackupPlaceIdentityV1]
    let name: String
    let address: String
    let city: String
    let latitude: Double
    let longitude: Double
    let status: BackupRestaurantStatusV1
    let preferenceLevel: BackupRestaurantPreferenceV1
    let overallRating: BackupRatingV1?
    let foodRating: BackupRatingV1?
    let environmentRating: BackupRatingV1?
    let serviceRating: BackupRatingV1?
    let valueRating: BackupRatingV1?
    let tags: [String]
    let longTermNote: String
    let pricePerPerson: BackupMoneyV1?
    let phone: String?
    let openingHours: String?
    let markerType: BackupMarkerTypeV1
    let markerPhotoId: String?
    let merchantImageUrl: String?
    let markerEmoji: String
    let createdAt: BackupTimestampV1
    let updatedAt: BackupTimestampV1
}

nonisolated struct BackupVisitV1: Codable, Equatable, Sendable {
    let id: String
    let restaurantId: String
    let visitedAt: BackupTimestampV1
    let diningMode: BackupDiningModeV1
    let visibility: BackupVisibilityV1
    let partySize: Int?
    let totalPrice: BackupMoneyV1?
    let myActualSpend: BackupMoneyV1?
    let paymentMode: BackupPaymentModeV1?
    let pricePerPerson: BackupMoneyV1?
    let queueDuration: BackupQueueDurationV1?
    let diningOccasions: [BackupDiningOccasionV1]
    let diningOccasionText: String?
    let rating: BackupRatingV1?
    let valueRating: BackupRatingV1?
    let environmentRating: BackupRatingV1?
    let serviceRating: BackupRatingV1?
    let valueTags: [String]
    let environmentTags: [String]
    let serviceTags: [String]
    let noiseLevel: BackupNoiseLevelV1?
    let diningDuration: BackupDiningDurationV1?
    let portionLevel: BackupPortionLevelV1?
    let transportConvenience: BackupTransportConvenienceV1?
    let specialNotes: String?
    let companionIds: [String]
    let recommendationSourceId: String?
    let recommendationSourceType: BackupRecommendationSourceTypeV1?
    let recommendationSourceText: String?
    /// This value never recreates shared-meal acceptance without server proof.
    let sharedMealReferenceHint: String?
    let note: String?
    let createdAt: BackupTimestampV1
    let updatedAt: BackupTimestampV1
}

nonisolated struct BackupDishV1: Codable, Equatable, Sendable {
    let id: String
    let restaurantId: String
    let originVisitId: String
    let name: String
    let taste: String
    let rating: BackupRatingV1?
    let price: BackupMoneyV1?
    let photoId: String?
    let sortOrder: Int
    let createdAt: BackupTimestampV1
    let updatedAt: BackupTimestampV1
}

nonisolated struct BackupVisitDishV1: Codable, Equatable, Sendable {
    let id: String
    let restaurantId: String
    let visitId: String
    let dishId: String
    let sortOrder: Int
    let createdAt: BackupTimestampV1
    let updatedAt: BackupTimestampV1
}

nonisolated struct BackupPhotoParentV1: Codable, Equatable, Sendable {
    let entityType: BackupPhotoParentEntityTypeV1
    let entityId: String
}

nonisolated struct BackupPhotoV1: Codable, Equatable, Sendable {
    let id: String
    let parent: BackupPhotoParentV1
    let kind: BackupPhotoKindV1
    let fileName: String?
    let mimeType: String
    let byteSize: Int64
    let width: Int?
    let height: Int?
    let sortOrder: Int
    let visibility: BackupVisibilityV1
    let contentSha256: String?
    let createdAt: BackupTimestampV1
    let updatedAt: BackupTimestampV1
}

nonisolated struct BackupDiningCompanionV1: Codable, Equatable, Sendable {
    let id: String
    let displayName: String
    let createdAt: BackupTimestampV1
    let updatedAt: BackupTimestampV1
}

nonisolated struct BackupRecommendationSourceV1: Codable, Equatable, Sendable {
    let id: String
    let displayName: String
    let sourceType: BackupRecommendationSourceTypeV1
    let createdAt: BackupTimestampV1
    let updatedAt: BackupTimestampV1
}

nonisolated struct BackupUserProfileV1: Codable, Equatable, Sendable {
    let id: String
    let displayName: String
    let bio: String
    let city: String
    let avatarPhotoId: String?
    let avatarPresetId: BackupProfileAvatarPresetV1
    let visibility: BackupVisibilityV1
    let createdAt: BackupTimestampV1
    let updatedAt: BackupTimestampV1
}

nonisolated struct BackupRestaurantListV1: Codable, Equatable, Sendable {
    let id: String
    let title: String
    let description: String
    let visibility: BackupVisibilityV1
    let isRanked: Bool
    let coverMode: BackupRestaurantListCoverModeV1
    let customCoverPhotoId: String?
    let createdAt: BackupTimestampV1
    let updatedAt: BackupTimestampV1
}

nonisolated struct BackupRestaurantListPlaceIdentityV1: Codable, Equatable, Sendable {
    let provider: BackupPlaceProviderV1
    let externalId: String
    let isPrimary: Bool
}

nonisolated struct BackupRestaurantListPlaceV1: Codable, Equatable, Sendable {
    let globalKey: String
    let restaurantId: String
    let placeIdentities: [BackupRestaurantListPlaceIdentityV1]
    let name: String
    let address: String
    let city: String
    let latitude: Double
    let longitude: Double
    let markerPhotoId: String?
    let merchantImageUrl: String?
    let markerEmoji: String
}

nonisolated struct BackupRestaurantListItemV1: Codable, Equatable, Sendable {
    let id: String
    let listId: String
    let restaurantId: String
    let restaurantGlobalKey: String
    let position: Int
    let note: String
    let restaurant: BackupRestaurantListPlaceV1
    let createdAt: BackupTimestampV1
    let updatedAt: BackupTimestampV1
}

nonisolated struct BackupEntitiesV1: Codable, Equatable, Sendable {
    let restaurants: [BackupRestaurantV1]
    let visits: [BackupVisitV1]
    let dishes: [BackupDishV1]
    let visitDishes: [BackupVisitDishV1]
    let photos: [BackupPhotoV1]
    let companions: [BackupDiningCompanionV1]
    let recommendationSources: [BackupRecommendationSourceV1]
    let profiles: [BackupUserProfileV1]
    let restaurantLists: [BackupRestaurantListV1]
    let restaurantListItems: [BackupRestaurantListItemV1]
}

nonisolated struct BackupTombstoneV1: Codable, Equatable, Sendable {
    let entityType: BackupEntityTypeV1
    let id: String
    let deletedAt: BackupTimestampV1
}

nonisolated struct BackupEntityCountsV1: Codable, Equatable, Sendable {
    let restaurants: Int
    let visits: Int
    let dishes: Int
    let visitDishes: Int
    let photos: Int
    let companions: Int
    let recommendationSources: Int
    let profiles: Int
    let restaurantLists: Int
    let restaurantListItems: Int
}

nonisolated struct BackupMetadataV1: Codable, Equatable, Sendable {
    let entityCounts: BackupEntityCountsV1
    let tombstoneCount: Int
}

nonisolated struct BackupIntegrityV1: Codable, Equatable, Sendable {
    let canonicalization: String
    let algorithm: String
    let digest: String

    init(
        canonicalization: String = BackupV1Contract.canonicalization,
        algorithm: String = BackupV1Contract.integrityAlgorithm,
        digest: String
    ) throws {
        guard canonicalization == BackupV1Contract.canonicalization,
              algorithm == BackupV1Contract.integrityAlgorithm else {
            throw BackupV1ContractError.invalidIntegrityMetadata
        }
        guard digest.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil else {
            throw BackupV1ContractError.invalidDigest
        }
        self.canonicalization = canonicalization
        self.algorithm = algorithm
        self.digest = digest
    }
}

nonisolated struct BackupIntegrityPayloadV1: Codable, Equatable, Sendable {
    let format: String
    let schemaVersion: Int
    let exportId: String
    let exportedAt: BackupTimestampV1
    let source: BackupSourceV1
    let scope: BackupScopeV1
    let entities: BackupEntitiesV1
    let tombstones: [BackupTombstoneV1]
    let metadata: BackupMetadataV1
}

nonisolated struct BackupEnvelopeV1: Codable, Equatable, Sendable {
    let format: String
    let schemaVersion: Int
    let exportId: String
    let exportedAt: BackupTimestampV1
    let source: BackupSourceV1
    let scope: BackupScopeV1
    let entities: BackupEntitiesV1
    let tombstones: [BackupTombstoneV1]
    let metadata: BackupMetadataV1
    let integrity: BackupIntegrityV1

    var integrityPayload: BackupIntegrityPayloadV1 {
        BackupIntegrityPayloadV1(
            format: format,
            schemaVersion: schemaVersion,
            exportId: exportId,
            exportedAt: exportedAt,
            source: source,
            scope: scope,
            entities: entities,
            tombstones: tombstones,
            metadata: metadata
        )
    }
}

extension BackupScopeV1 {
    private nonisolated enum CodingKeys: String, CodingKey {
        case kind, includesPhotoBinaries
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try values.decode(String.self, forKey: .kind)
        let includesPhotoBinaries = try values.decode(Bool.self, forKey: .includesPhotoBinaries)
        guard kind == "user-data", includesPhotoBinaries == false else {
            throw BackupV1ContractError.invalidScope
        }
        self.kind = kind
        self.includesPhotoBinaries = includesPhotoBinaries
    }
}

extension BackupIntegrityV1 {
    private nonisolated enum CodingKeys: String, CodingKey {
        case canonicalization, algorithm, digest
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            canonicalization: values.decode(String.self, forKey: .canonicalization),
            algorithm: values.decode(String.self, forKey: .algorithm),
            digest: values.decode(String.self, forKey: .digest)
        )
    }
}

extension BackupEnvelopeV1 {
    private nonisolated enum CodingKeys: String, CodingKey {
        case format, schemaVersion, exportId, exportedAt, source, scope, entities
        case tombstones, metadata, integrity
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let format = try values.decode(String.self, forKey: .format)
        guard format == BackupV1Contract.format else {
            throw BackupV1ContractError.invalidFormat
        }
        let schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == BackupV1Contract.schemaVersion else {
            throw BackupV1ContractError.invalidSchemaVersion
        }
        let exportId = try values.decode(String.self, forKey: .exportId)
        guard UUID(uuidString: exportId) != nil else {
            throw BackupV1ContractError.invalidExportID
        }

        self.format = format
        self.schemaVersion = schemaVersion
        self.exportId = exportId
        exportedAt = try values.decode(BackupTimestampV1.self, forKey: .exportedAt)
        source = try values.decode(BackupSourceV1.self, forKey: .source)
        scope = try values.decode(BackupScopeV1.self, forKey: .scope)
        entities = try values.decode(BackupEntitiesV1.self, forKey: .entities)
        tombstones = try values.decode([BackupTombstoneV1].self, forKey: .tombstones)
        metadata = try values.decode(BackupMetadataV1.self, forKey: .metadata)
        integrity = try values.decode(BackupIntegrityV1.self, forKey: .integrity)
    }
}

// Backup v1 distinguishes explicit null from omission. The schema validates
// missing keys before DTO decoding; these encoders make every nullable key
// explicit so Swift never silently turns nil into a missing field.
extension BackupRestaurantV1 {
    private enum CodingKeys: String, CodingKey {
        case id, placeIdentities, name, address, city, latitude, longitude, status, preferenceLevel
        case overallRating, foodRating, environmentRating, serviceRating, valueRating, tags, longTermNote
        case pricePerPerson, phone, openingHours, markerType, markerPhotoId, merchantImageUrl, markerEmoji
        case createdAt, updatedAt
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(placeIdentities, forKey: .placeIdentities)
        try values.encode(name, forKey: .name)
        try values.encode(address, forKey: .address)
        try values.encode(city, forKey: .city)
        try values.encode(latitude, forKey: .latitude)
        try values.encode(longitude, forKey: .longitude)
        try values.encode(status, forKey: .status)
        try values.encode(preferenceLevel, forKey: .preferenceLevel)
        try values.encode(overallRating, forKey: .overallRating)
        try values.encode(foodRating, forKey: .foodRating)
        try values.encode(environmentRating, forKey: .environmentRating)
        try values.encode(serviceRating, forKey: .serviceRating)
        try values.encode(valueRating, forKey: .valueRating)
        try values.encode(tags, forKey: .tags)
        try values.encode(longTermNote, forKey: .longTermNote)
        try values.encode(pricePerPerson, forKey: .pricePerPerson)
        try values.encode(phone, forKey: .phone)
        try values.encode(openingHours, forKey: .openingHours)
        try values.encode(markerType, forKey: .markerType)
        try values.encode(markerPhotoId, forKey: .markerPhotoId)
        try values.encode(merchantImageUrl, forKey: .merchantImageUrl)
        try values.encode(markerEmoji, forKey: .markerEmoji)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encode(updatedAt, forKey: .updatedAt)
    }
}

extension BackupVisitV1 {
    private enum CodingKeys: String, CodingKey {
        case id, restaurantId, visitedAt, diningMode, visibility, partySize, totalPrice, myActualSpend
        case paymentMode, pricePerPerson, queueDuration, diningOccasions, diningOccasionText
        case rating, valueRating, environmentRating, serviceRating, valueTags, environmentTags, serviceTags
        case noiseLevel, diningDuration, portionLevel, transportConvenience, specialNotes, companionIds
        case recommendationSourceId, recommendationSourceType, recommendationSourceText
        case sharedMealReferenceHint, note, createdAt, updatedAt
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(restaurantId, forKey: .restaurantId)
        try values.encode(visitedAt, forKey: .visitedAt)
        try values.encode(diningMode, forKey: .diningMode)
        try values.encode(visibility, forKey: .visibility)
        try values.encode(partySize, forKey: .partySize)
        try values.encode(totalPrice, forKey: .totalPrice)
        try values.encode(myActualSpend, forKey: .myActualSpend)
        try values.encode(paymentMode, forKey: .paymentMode)
        try values.encode(pricePerPerson, forKey: .pricePerPerson)
        try values.encode(queueDuration, forKey: .queueDuration)
        try values.encode(diningOccasions, forKey: .diningOccasions)
        try values.encode(diningOccasionText, forKey: .diningOccasionText)
        try values.encode(rating, forKey: .rating)
        try values.encode(valueRating, forKey: .valueRating)
        try values.encode(environmentRating, forKey: .environmentRating)
        try values.encode(serviceRating, forKey: .serviceRating)
        try values.encode(valueTags, forKey: .valueTags)
        try values.encode(environmentTags, forKey: .environmentTags)
        try values.encode(serviceTags, forKey: .serviceTags)
        try values.encode(noiseLevel, forKey: .noiseLevel)
        try values.encode(diningDuration, forKey: .diningDuration)
        try values.encode(portionLevel, forKey: .portionLevel)
        try values.encode(transportConvenience, forKey: .transportConvenience)
        try values.encode(specialNotes, forKey: .specialNotes)
        try values.encode(companionIds, forKey: .companionIds)
        try values.encode(recommendationSourceId, forKey: .recommendationSourceId)
        try values.encode(recommendationSourceType, forKey: .recommendationSourceType)
        try values.encode(recommendationSourceText, forKey: .recommendationSourceText)
        try values.encode(sharedMealReferenceHint, forKey: .sharedMealReferenceHint)
        try values.encode(note, forKey: .note)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encode(updatedAt, forKey: .updatedAt)
    }
}

extension BackupDishV1 {
    private enum CodingKeys: String, CodingKey {
        case id, restaurantId, originVisitId, name, taste, rating, price, photoId, sortOrder, createdAt, updatedAt
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(restaurantId, forKey: .restaurantId)
        try values.encode(originVisitId, forKey: .originVisitId)
        try values.encode(name, forKey: .name)
        try values.encode(taste, forKey: .taste)
        try values.encode(rating, forKey: .rating)
        try values.encode(price, forKey: .price)
        try values.encode(photoId, forKey: .photoId)
        try values.encode(sortOrder, forKey: .sortOrder)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encode(updatedAt, forKey: .updatedAt)
    }
}

extension BackupPhotoV1 {
    private enum CodingKeys: String, CodingKey {
        case id, parent, kind, fileName, mimeType, byteSize, width, height, sortOrder
        case visibility, contentSha256, createdAt, updatedAt
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(parent, forKey: .parent)
        try values.encode(kind, forKey: .kind)
        try values.encode(fileName, forKey: .fileName)
        try values.encode(mimeType, forKey: .mimeType)
        try values.encode(byteSize, forKey: .byteSize)
        try values.encode(width, forKey: .width)
        try values.encode(height, forKey: .height)
        try values.encode(sortOrder, forKey: .sortOrder)
        try values.encode(visibility, forKey: .visibility)
        try values.encode(contentSha256, forKey: .contentSha256)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encode(updatedAt, forKey: .updatedAt)
    }
}

extension BackupUserProfileV1 {
    private enum CodingKeys: String, CodingKey {
        case id, displayName, bio, city, avatarPhotoId, avatarPresetId, visibility, createdAt, updatedAt
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(displayName, forKey: .displayName)
        try values.encode(bio, forKey: .bio)
        try values.encode(city, forKey: .city)
        try values.encode(avatarPhotoId, forKey: .avatarPhotoId)
        try values.encode(avatarPresetId, forKey: .avatarPresetId)
        try values.encode(visibility, forKey: .visibility)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encode(updatedAt, forKey: .updatedAt)
    }
}

extension BackupRestaurantListV1 {
    private enum CodingKeys: String, CodingKey {
        case id, title, description, visibility, isRanked, coverMode, customCoverPhotoId, createdAt, updatedAt
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(title, forKey: .title)
        try values.encode(description, forKey: .description)
        try values.encode(visibility, forKey: .visibility)
        try values.encode(isRanked, forKey: .isRanked)
        try values.encode(coverMode, forKey: .coverMode)
        try values.encode(customCoverPhotoId, forKey: .customCoverPhotoId)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encode(updatedAt, forKey: .updatedAt)
    }
}

extension BackupRestaurantListPlaceV1 {
    private enum CodingKeys: String, CodingKey {
        case globalKey, restaurantId, placeIdentities, name, address, city, latitude, longitude
        case markerPhotoId, merchantImageUrl, markerEmoji
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(globalKey, forKey: .globalKey)
        try values.encode(restaurantId, forKey: .restaurantId)
        try values.encode(placeIdentities, forKey: .placeIdentities)
        try values.encode(name, forKey: .name)
        try values.encode(address, forKey: .address)
        try values.encode(city, forKey: .city)
        try values.encode(latitude, forKey: .latitude)
        try values.encode(longitude, forKey: .longitude)
        try values.encode(markerPhotoId, forKey: .markerPhotoId)
        try values.encode(merchantImageUrl, forKey: .merchantImageUrl)
        try values.encode(markerEmoji, forKey: .markerEmoji)
    }
}

nonisolated enum BackupCanonicalJSONV1 {
    static func canonicalString<T: Encodable>(for value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return try canonicalString(forJSONObject: object)
    }

    static func canonicalString(forJSONObject value: Any) throws -> String {
        if value is NSNull { return "null" }
        if let string = value as? String {
            let encoded = try JSONSerialization.data(
                withJSONObject: [string],
                options: [.withoutEscapingSlashes]
            )
            guard var result = String(data: encoded, encoding: .utf8),
                  result.first == "[",
                  result.last == "]" else {
                throw BackupV1ContractError.invalidCanonicalJSON
            }
            result.removeFirst()
            result.removeLast()
            return result
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return try ecmaScriptNumberString(number.doubleValue)
        }
        if let array = value as? [Any] {
            return "[" + (try array.map(canonicalString(forJSONObject:)).joined(separator: ",")) + "]"
        }
        if let object = value as? [String: Any] {
            let fields = try object.keys.sorted().map { key in
                let encodedKey = try canonicalString(forJSONObject: key)
                guard let field = object[key] else { throw BackupV1ContractError.invalidCanonicalJSON }
                return encodedKey + ":" + (try canonicalString(forJSONObject: field))
            }
            return "{" + fields.joined(separator: ",") + "}"
        }
        throw BackupV1ContractError.invalidCanonicalJSON
    }

    /// Matches the finite-number spelling produced by ECMAScript
    /// `JSON.stringify`, including its decimal/exponent thresholds and `-0`.
    private static func ecmaScriptNumberString(_ value: Double) throws -> String {
        guard value.isFinite else { throw BackupV1ContractError.invalidCanonicalJSON }
        guard value != 0 else { return "0" }

        let raw = String(value)
        guard let exponentIndex = raw.firstIndex(where: { $0 == "e" || $0 == "E" }) else {
            return raw.hasSuffix(".0") ? String(raw.dropLast(2)) : raw
        }

        var coefficient = String(raw[..<exponentIndex])
        let rawExponent = raw[raw.index(after: exponentIndex)...]
        guard let exponent = Int(rawExponent) else {
            throw BackupV1ContractError.invalidCanonicalJSON
        }

        if (-6 ..< 21).contains(exponent) {
            let isNegative = coefficient.first == "-"
            if isNegative {
                coefficient.removeFirst()
            }
            let components = coefficient.split(separator: ".", omittingEmptySubsequences: false)
            guard let whole = components.first, components.count <= 2 else {
                throw BackupV1ContractError.invalidCanonicalJSON
            }
            let fraction = components.count == 2 ? components[1] : Substring()
            let digits = String(whole + fraction)
            let decimalPosition = whole.count + exponent
            let expanded: String
            if decimalPosition <= 0 {
                expanded = "0." + String(repeating: "0", count: -decimalPosition) + digits
            } else if decimalPosition >= digits.count {
                expanded = digits + String(repeating: "0", count: decimalPosition - digits.count)
            } else {
                let split = digits.index(digits.startIndex, offsetBy: decimalPosition)
                expanded = String(digits[..<split]) + "." + String(digits[split...])
            }
            return isNegative ? "-" + expanded : expanded
        }

        if coefficient.hasSuffix(".0") {
            coefficient.removeLast(2)
        }
        return coefficient + "e" + (exponent >= 0 ? "+" : "") + String(exponent)
    }

    static func sha256Hex(of canonicalJSON: String) -> String {
        SHA256.hash(data: Data(canonicalJSON.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
