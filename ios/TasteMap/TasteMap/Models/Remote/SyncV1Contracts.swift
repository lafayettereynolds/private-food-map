import Foundation

enum SyncV1Contract {
    static let apiVersion = 1
    static let schemaVersion = 1
}

struct VisitSyncContractV1: Codable, Equatable {
    let schemaVersion: Int
    let id: String
    let userId: String
    let restaurantId: String
    let visitedAt: String
    let diningMode: DiningMode
    let visibility: VisitVisibility
    let partySize: Int?
    let totalPrice: Double?
    let paymentMode: String?
    let pricePerPerson: Double?
    let queueDuration: String?
    let diningOccasions: [String]
    let diningOccasionText: String?
    let rating: Double?
    let valueRating: Double?
    let environmentRating: Double?
    let serviceRating: Double?
    let valueTags: [String]
    let environmentTags: [String]
    let serviceTags: [String]
    let noiseLevel: String?
    let diningDuration: String?
    let portionLevel: String?
    let transportConvenience: String?
    let specialNotes: String?
    let companions: [String]
    let companionIds: [String]
    let recommendationSourceId: String?
    let recommendationSourceType: String?
    let recommendationSourceUserId: String?
    let recommendationSourceText: String?
    let sharedMealId: String?
    let note: String?
    let myActualSpend: Double?
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?

    init(
        schemaVersion: Int,
        id: String,
        userId: String,
        restaurantId: String,
        visitedAt: String,
        diningMode: DiningMode,
        visibility: VisitVisibility,
        partySize: Int?,
        totalPrice: Double?,
        paymentMode: String?,
        pricePerPerson: Double?,
        queueDuration: String?,
        diningOccasions: [String],
        diningOccasionText: String?,
        rating: Double?,
        valueRating: Double?,
        environmentRating: Double?,
        serviceRating: Double?,
        valueTags: [String],
        environmentTags: [String],
        serviceTags: [String],
        noiseLevel: String?,
        diningDuration: String?,
        portionLevel: String?,
        transportConvenience: String?,
        specialNotes: String?,
        companions: [String] = [],
        companionIds: [String] = [],
        recommendationSourceId: String? = nil,
        recommendationSourceType: String? = nil,
        recommendationSourceUserId: String? = nil,
        recommendationSourceText: String? = nil,
        sharedMealId: String? = nil,
        note: String?,
        myActualSpend: Double?,
        createdAt: String,
        updatedAt: String,
        deletedAt: String?
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.userId = userId
        self.restaurantId = restaurantId
        self.visitedAt = visitedAt
        self.diningMode = diningMode
        self.visibility = visibility
        self.partySize = partySize
        self.totalPrice = totalPrice
        self.paymentMode = paymentMode
        self.pricePerPerson = pricePerPerson
        self.queueDuration = queueDuration
        self.diningOccasions = diningOccasions
        self.diningOccasionText = diningOccasionText
        self.rating = rating
        self.valueRating = valueRating
        self.environmentRating = environmentRating
        self.serviceRating = serviceRating
        self.valueTags = valueTags
        self.environmentTags = environmentTags
        self.serviceTags = serviceTags
        self.noiseLevel = noiseLevel
        self.diningDuration = diningDuration
        self.portionLevel = portionLevel
        self.transportConvenience = transportConvenience
        self.specialNotes = specialNotes
        self.companions = companions
        self.companionIds = companionIds
        self.recommendationSourceId = recommendationSourceId
        self.recommendationSourceType = recommendationSourceType
        self.recommendationSourceUserId = recommendationSourceUserId
        self.recommendationSourceText = recommendationSourceText
        self.sharedMealId = sharedMealId
        self.note = note
        self.myActualSpend = myActualSpend
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

private extension VisitSyncContractV1 {
    enum CodingKeys: String, CodingKey {
        case schemaVersion, id, userId, restaurantId, visitedAt, diningMode, visibility, partySize
        case totalPrice, paymentMode, pricePerPerson, queueDuration, diningOccasions, diningOccasionText
        case rating, valueRating, environmentRating, serviceRating
        case valueTags, environmentTags, serviceTags, noiseLevel, diningDuration
        case portionLevel, transportConvenience, specialNotes
        case companions, companionIds, recommendationSourceId, recommendationSourceType
        case recommendationSourceUserId, recommendationSourceText, sharedMealId
        case note, myActualSpend, createdAt, updatedAt, deletedAt
    }
}

extension VisitSyncContractV1 {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        id = try container.decode(String.self, forKey: .id)
        userId = try container.decode(String.self, forKey: .userId)
        restaurantId = try container.decode(String.self, forKey: .restaurantId)
        visitedAt = try container.decode(String.self, forKey: .visitedAt)
        diningMode = try container.decodeIfPresent(DiningMode.self, forKey: .diningMode) ?? .dineIn
        visibility = try container.decodeIfPresent(VisitVisibility.self, forKey: .visibility) ?? .private
        partySize = try container.decodeIfPresent(Int.self, forKey: .partySize)
        if let partySize, partySize < 1 {
            throw DecodingError.dataCorruptedError(
                forKey: .partySize,
                in: container,
                debugDescription: "partySize must be null or a positive integer."
            )
        }
        totalPrice = try container.decodeIfPresent(Double.self, forKey: .totalPrice)
        paymentMode = Self.normalizedOptionalString(try container.decodeIfPresent(String.self, forKey: .paymentMode))
        pricePerPerson = try container.decodeIfPresent(Double.self, forKey: .pricePerPerson)
        queueDuration = Self.normalizedOptionalString(try container.decodeIfPresent(String.self, forKey: .queueDuration))
        diningOccasions = VisitStringArrayStorage.normalized(
            try container.decodeIfPresent([String].self, forKey: .diningOccasions) ?? []
        )
        diningOccasionText = Self.normalizedOptionalString(
            try container.decodeIfPresent(String.self, forKey: .diningOccasionText)
        )
        rating = try container.decode(Double?.self, forKey: .rating)
        valueRating = try container.decodeIfPresent(Double.self, forKey: .valueRating)
        environmentRating = try container.decodeIfPresent(Double.self, forKey: .environmentRating)
        serviceRating = try container.decodeIfPresent(Double.self, forKey: .serviceRating)
        for (key, value) in [
            (CodingKeys.rating, rating),
            (CodingKeys.valueRating, valueRating),
            (CodingKeys.environmentRating, environmentRating),
            (CodingKeys.serviceRating, serviceRating),
        ] where Visit.validatedRating(value) != value {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Rating must be null or a half-step from 0.5 through 5.0."
            )
        }
        valueTags = VisitStringArrayStorage.normalized(
            try container.decodeIfPresent([String].self, forKey: .valueTags) ?? []
        )
        environmentTags = VisitStringArrayStorage.normalized(
            try container.decodeIfPresent([String].self, forKey: .environmentTags) ?? []
        )
        serviceTags = VisitStringArrayStorage.normalized(
            try container.decodeIfPresent([String].self, forKey: .serviceTags) ?? []
        )
        noiseLevel = Self.normalizedOptionalString(try container.decodeIfPresent(String.self, forKey: .noiseLevel))
        diningDuration = Self.normalizedOptionalString(try container.decodeIfPresent(String.self, forKey: .diningDuration))
        portionLevel = Self.normalizedOptionalString(try container.decodeIfPresent(String.self, forKey: .portionLevel))
        transportConvenience = Self.normalizedOptionalString(
            try container.decodeIfPresent(String.self, forKey: .transportConvenience)
        )
        specialNotes = Self.normalizedOptionalString(try container.decodeIfPresent(String.self, forKey: .specialNotes))
        companions = VisitStringArrayStorage.normalized(
            try container.decodeIfPresent([String].self, forKey: .companions) ?? []
        )
        companionIds = VisitStringArrayStorage.normalized(
            try container.decodeIfPresent([String].self, forKey: .companionIds) ?? []
        )
        if !companionIds.isEmpty, companionIds.count != companions.count {
            throw DecodingError.dataCorruptedError(
                forKey: .companionIds,
                in: container,
                debugDescription: "companionIds must be empty for legacy data or parallel companions."
            )
        }
        recommendationSourceId = Self.normalizedOptionalString(
            try container.decodeIfPresent(String.self, forKey: .recommendationSourceId)
        )
        recommendationSourceType = Self.normalizedOptionalString(
            try container.decodeIfPresent(String.self, forKey: .recommendationSourceType)
        )
        if let recommendationSourceType,
           RecommendationSourceType(rawValue: recommendationSourceType) == nil {
            throw DecodingError.dataCorruptedError(
                forKey: .recommendationSourceType,
                in: container,
                debugDescription: "recommendationSourceType is not supported."
            )
        }
        recommendationSourceUserId = Self.normalizedOptionalString(
            try container.decodeIfPresent(String.self, forKey: .recommendationSourceUserId)
        )
        recommendationSourceText = Self.normalizedOptionalString(
            try container.decodeIfPresent(String.self, forKey: .recommendationSourceText)
        )
        sharedMealId = Self.normalizedOptionalString(
            try container.decodeIfPresent(String.self, forKey: .sharedMealId)
        )
        note = try container.decode(String?.self, forKey: .note)
        myActualSpend = try container.decode(Double?.self, forKey: .myActualSpend)
        for (key, value) in [
            (CodingKeys.totalPrice, totalPrice),
            (CodingKeys.pricePerPerson, pricePerPerson),
            (CodingKeys.myActualSpend, myActualSpend),
        ] where value.map({ !$0.isFinite || $0 < 0 }) ?? false {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Visit money fields must be null or non-negative finite numbers."
            )
        }
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        deletedAt = try container.decode(String?.self, forKey: .deletedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encode(restaurantId, forKey: .restaurantId)
        try container.encode(visitedAt, forKey: .visitedAt)
        try container.encode(diningMode, forKey: .diningMode)
        try container.encode(visibility, forKey: .visibility)
        try container.encode(partySize, forKey: .partySize)
        try container.encode(totalPrice, forKey: .totalPrice)
        try container.encode(paymentMode, forKey: .paymentMode)
        try container.encode(pricePerPerson, forKey: .pricePerPerson)
        try container.encode(queueDuration, forKey: .queueDuration)
        try container.encode(diningOccasions, forKey: .diningOccasions)
        try container.encode(diningOccasionText, forKey: .diningOccasionText)
        try container.encode(rating, forKey: .rating)
        try container.encode(valueRating, forKey: .valueRating)
        try container.encode(environmentRating, forKey: .environmentRating)
        try container.encode(serviceRating, forKey: .serviceRating)
        try container.encode(valueTags, forKey: .valueTags)
        try container.encode(environmentTags, forKey: .environmentTags)
        try container.encode(serviceTags, forKey: .serviceTags)
        try container.encode(noiseLevel, forKey: .noiseLevel)
        try container.encode(diningDuration, forKey: .diningDuration)
        try container.encode(portionLevel, forKey: .portionLevel)
        try container.encode(transportConvenience, forKey: .transportConvenience)
        try container.encode(specialNotes, forKey: .specialNotes)
        try container.encode(companions, forKey: .companions)
        try container.encode(companionIds, forKey: .companionIds)
        try container.encode(recommendationSourceId, forKey: .recommendationSourceId)
        try container.encode(recommendationSourceType, forKey: .recommendationSourceType)
        try container.encode(recommendationSourceUserId, forKey: .recommendationSourceUserId)
        try container.encode(recommendationSourceText, forKey: .recommendationSourceText)
        try container.encode(sharedMealId, forKey: .sharedMealId)
        try container.encode(note, forKey: .note)
        try container.encode(myActualSpend, forKey: .myActualSpend)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(deletedAt, forKey: .deletedAt)
    }

    private static func normalizedOptionalString(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct DiningCompanionSyncContractV1: Codable, Equatable {
    let schemaVersion: Int
    let id: String
    let userId: String
    let displayName: String
    let linkedTasteMapUserId: String?
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?
}

struct RecommendationSourceSyncContractV1: Codable, Equatable {
    let schemaVersion: Int
    let id: String
    let userId: String
    let displayName: String
    let sourceType: RecommendationSourceType
    let linkedTasteMapUserId: String?
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?
}

enum RichRecordContractError: Error, Equatable {
    case invalidDish
    case invalidVisitDish
    case invalidPhoto
}

private struct RichRecordCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

struct DishSyncContractV1: Codable, Equatable {
    let schemaVersion: Int
    let id: String
    let userId: String
    let restaurantId: String
    let visitId: String
    let name: String
    let taste: String
    let rating: Double?
    let price: Double?
    let photoId: String?
    let sortOrder: Int
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?

    init(
        schemaVersion: Int = SyncV1Contract.schemaVersion,
        id: String,
        userId: String,
        restaurantId: String,
        visitId: String,
        name: String,
        taste: String,
        rating: Double?,
        price: Double?,
        photoId: String?,
        sortOrder: Int,
        createdAt: String,
        updatedAt: String,
        deletedAt: String?
    ) throws {
        guard schemaVersion == SyncV1Contract.schemaVersion,
              isRichRecordNonBlank(id), isRichRecordNonBlank(userId),
              isRichRecordNonBlank(restaurantId), isRichRecordNonBlank(visitId),
              Visit.validatedRating(rating) == rating,
              price.map({ $0.isFinite && $0 >= 0 }) ?? true,
              sortOrder >= 0,
              isRichRecordISODateTime(createdAt), isRichRecordISODateTime(updatedAt),
              deletedAt.map(isRichRecordISODateTime) ?? true else {
            throw RichRecordContractError.invalidDish
        }
        self.schemaVersion = schemaVersion
        self.id = id
        self.userId = userId
        self.restaurantId = restaurantId
        self.visitId = visitId
        self.name = name
        self.taste = taste
        self.rating = rating
        self.price = price
        self.photoId = photoId
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, id, userId, restaurantId, visitId, name, taste
        case rating, price, photoId, sortOrder, createdAt, updatedAt, deletedAt
    }

    init(from decoder: Decoder) throws {
        try assertRichRecordKeys(
            decoder,
            allowed: ["schemaVersion", "id", "userId", "restaurantId", "visitId", "name", "taste",
                      "rating", "price", "photoId", "sortOrder", "createdAt", "updatedAt", "deletedAt"],
            error: .invalidDish
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            schemaVersion: values.decode(Int.self, forKey: .schemaVersion),
            id: values.decode(String.self, forKey: .id),
            userId: values.decode(String.self, forKey: .userId),
            restaurantId: values.decode(String.self, forKey: .restaurantId),
            visitId: values.decode(String.self, forKey: .visitId),
            name: values.decode(String.self, forKey: .name),
            taste: values.decode(String.self, forKey: .taste),
            rating: values.decode(Double?.self, forKey: .rating),
            price: values.decode(Double?.self, forKey: .price),
            photoId: values.decode(String?.self, forKey: .photoId),
            sortOrder: values.decode(Int.self, forKey: .sortOrder),
            createdAt: values.decode(String.self, forKey: .createdAt),
            updatedAt: values.decode(String.self, forKey: .updatedAt),
            deletedAt: values.decode(String?.self, forKey: .deletedAt)
        )
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(id, forKey: .id)
        try values.encode(userId, forKey: .userId)
        try values.encode(restaurantId, forKey: .restaurantId)
        try values.encode(visitId, forKey: .visitId)
        try values.encode(name, forKey: .name)
        try values.encode(taste, forKey: .taste)
        try values.encode(rating, forKey: .rating)
        try values.encode(price, forKey: .price)
        try values.encode(photoId, forKey: .photoId)
        try values.encode(sortOrder, forKey: .sortOrder)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encode(updatedAt, forKey: .updatedAt)
        try values.encode(deletedAt, forKey: .deletedAt)
    }
}

struct VisitDishSyncContractV1: Codable, Equatable {
    let schemaVersion: Int
    let id: String
    let userId: String
    let restaurantId: String
    let visitId: String
    let dishId: String
    let sortOrder: Int
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?

    init(
        schemaVersion: Int = SyncV1Contract.schemaVersion,
        id: String,
        userId: String,
        restaurantId: String,
        visitId: String,
        dishId: String,
        sortOrder: Int,
        createdAt: String,
        updatedAt: String,
        deletedAt: String?
    ) throws {
        guard schemaVersion == SyncV1Contract.schemaVersion,
              isRichRecordNonBlank(id), isRichRecordNonBlank(userId),
              isRichRecordNonBlank(restaurantId), isRichRecordNonBlank(visitId),
              isRichRecordNonBlank(dishId), sortOrder >= 0,
              isRichRecordISODateTime(createdAt), isRichRecordISODateTime(updatedAt),
              deletedAt.map(isRichRecordISODateTime) ?? true else {
            throw RichRecordContractError.invalidVisitDish
        }
        self.schemaVersion = schemaVersion
        self.id = id
        self.userId = userId
        self.restaurantId = restaurantId
        self.visitId = visitId
        self.dishId = dishId
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, id, userId, restaurantId, visitId, dishId
        case sortOrder, createdAt, updatedAt, deletedAt
    }

    init(from decoder: Decoder) throws {
        try assertRichRecordKeys(
            decoder,
            allowed: ["schemaVersion", "id", "userId", "restaurantId", "visitId", "dishId",
                      "sortOrder", "createdAt", "updatedAt", "deletedAt"],
            error: .invalidVisitDish
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            schemaVersion: values.decode(Int.self, forKey: .schemaVersion),
            id: values.decode(String.self, forKey: .id),
            userId: values.decode(String.self, forKey: .userId),
            restaurantId: values.decode(String.self, forKey: .restaurantId),
            visitId: values.decode(String.self, forKey: .visitId),
            dishId: values.decode(String.self, forKey: .dishId),
            sortOrder: values.decode(Int.self, forKey: .sortOrder),
            createdAt: values.decode(String.self, forKey: .createdAt),
            updatedAt: values.decode(String.self, forKey: .updatedAt),
            deletedAt: values.decode(String?.self, forKey: .deletedAt)
        )
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(id, forKey: .id)
        try values.encode(userId, forKey: .userId)
        try values.encode(restaurantId, forKey: .restaurantId)
        try values.encode(visitId, forKey: .visitId)
        try values.encode(dishId, forKey: .dishId)
        try values.encode(sortOrder, forKey: .sortOrder)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encode(updatedAt, forKey: .updatedAt)
        try values.encode(deletedAt, forKey: .deletedAt)
    }
}

struct PhotoSyncContractV1: Codable, Equatable {
    let schemaVersion: Int
    let id: String
    let userId: String
    let restaurantId: String?
    let visitId: String?
    let dishId: String?
    let kind: PhotoAssetKind
    let storageProvider: PhotoStorageProviderID
    let storageKey: String
    let providerAccountId: String?
    let thumbnailStorageKey: String?
    let fileName: String?
    let mimeType: String
    let byteSize: Int64
    let width: Int?
    let height: Int?
    let sortOrder: Int
    let visibility: PhotoVisibility
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?

    init(
        schemaVersion: Int = SyncV1Contract.schemaVersion,
        id: String,
        userId: String,
        restaurantId: String?,
        visitId: String?,
        dishId: String?,
        kind: PhotoAssetKind,
        storageProvider: PhotoStorageProviderID,
        storageKey: String,
        providerAccountId: String?,
        thumbnailStorageKey: String?,
        fileName: String?,
        mimeType: String,
        byteSize: Int64,
        width: Int?,
        height: Int?,
        sortOrder: Int,
        visibility: PhotoVisibility,
        createdAt: String,
        updatedAt: String,
        deletedAt: String?
    ) throws {
        let validRelationship = switch kind {
        case .restaurantMarker: restaurantId != nil
        case .visit: restaurantId != nil && visitId != nil
        case .dish: restaurantId != nil && visitId != nil && dishId != nil
        case .avatar: true
        }
        guard schemaVersion == SyncV1Contract.schemaVersion,
              isRichRecordNonBlank(id), isRichRecordNonBlank(userId),
              isRichRecordNonBlank(storageKey), isRichRecordNonBlank(mimeType),
              byteSize >= 0, width.map({ $0 > 0 }) ?? true,
              height.map({ $0 > 0 }) ?? true, sortOrder >= 0,
              validRelationship,
              isRichRecordISODateTime(createdAt), isRichRecordISODateTime(updatedAt),
              deletedAt.map(isRichRecordISODateTime) ?? true else {
            throw RichRecordContractError.invalidPhoto
        }
        self.schemaVersion = schemaVersion
        self.id = id
        self.userId = userId
        self.restaurantId = restaurantId
        self.visitId = visitId
        self.dishId = dishId
        self.kind = kind
        self.storageProvider = storageProvider
        self.storageKey = storageKey
        self.providerAccountId = providerAccountId
        self.thumbnailStorageKey = thumbnailStorageKey
        self.fileName = fileName
        self.mimeType = mimeType
        self.byteSize = byteSize
        self.width = width
        self.height = height
        self.sortOrder = sortOrder
        self.visibility = visibility
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, id, userId, restaurantId, visitId, dishId, kind
        case storageProvider, storageKey, providerAccountId, thumbnailStorageKey
        case fileName, mimeType, byteSize, width, height, sortOrder, visibility
        case createdAt, updatedAt, deletedAt
    }

    init(from decoder: Decoder) throws {
        try assertRichRecordKeys(
            decoder,
            allowed: ["schemaVersion", "id", "userId", "restaurantId", "visitId", "dishId", "kind",
                      "storageProvider", "storageKey", "providerAccountId", "thumbnailStorageKey", "fileName",
                      "mimeType", "byteSize", "width", "height", "sortOrder", "visibility", "createdAt",
                      "updatedAt", "deletedAt"],
            error: .invalidPhoto
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            schemaVersion: values.decode(Int.self, forKey: .schemaVersion),
            id: values.decode(String.self, forKey: .id),
            userId: values.decode(String.self, forKey: .userId),
            restaurantId: values.decode(String?.self, forKey: .restaurantId),
            visitId: values.decode(String?.self, forKey: .visitId),
            dishId: values.decode(String?.self, forKey: .dishId),
            kind: values.decode(PhotoAssetKind.self, forKey: .kind),
            storageProvider: values.decode(PhotoStorageProviderID.self, forKey: .storageProvider),
            storageKey: values.decode(String.self, forKey: .storageKey),
            providerAccountId: values.decode(String?.self, forKey: .providerAccountId),
            thumbnailStorageKey: values.decode(String?.self, forKey: .thumbnailStorageKey),
            fileName: values.decode(String?.self, forKey: .fileName),
            mimeType: values.decode(String.self, forKey: .mimeType),
            byteSize: values.decode(Int64.self, forKey: .byteSize),
            width: values.decode(Int?.self, forKey: .width),
            height: values.decode(Int?.self, forKey: .height),
            sortOrder: values.decode(Int.self, forKey: .sortOrder),
            visibility: values.decode(PhotoVisibility.self, forKey: .visibility),
            createdAt: values.decode(String.self, forKey: .createdAt),
            updatedAt: values.decode(String.self, forKey: .updatedAt),
            deletedAt: values.decode(String?.self, forKey: .deletedAt)
        )
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(id, forKey: .id)
        try values.encode(userId, forKey: .userId)
        try values.encode(restaurantId, forKey: .restaurantId)
        try values.encode(visitId, forKey: .visitId)
        try values.encode(dishId, forKey: .dishId)
        try values.encode(kind, forKey: .kind)
        try values.encode(storageProvider, forKey: .storageProvider)
        try values.encode(storageKey, forKey: .storageKey)
        try values.encode(providerAccountId, forKey: .providerAccountId)
        try values.encode(thumbnailStorageKey, forKey: .thumbnailStorageKey)
        try values.encode(fileName, forKey: .fileName)
        try values.encode(mimeType, forKey: .mimeType)
        try values.encode(byteSize, forKey: .byteSize)
        try values.encode(width, forKey: .width)
        try values.encode(height, forKey: .height)
        try values.encode(sortOrder, forKey: .sortOrder)
        try values.encode(visibility, forKey: .visibility)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encode(updatedAt, forKey: .updatedAt)
        try values.encode(deletedAt, forKey: .deletedAt)
    }
}

private func assertRichRecordKeys(
    _ decoder: Decoder,
    allowed: Set<String>,
    error: RichRecordContractError
) throws {
    let values = try decoder.container(keyedBy: RichRecordCodingKey.self)
    if values.allKeys.contains(where: { !allowed.contains($0.stringValue) }) { throw error }
}

private func isRichRecordNonBlank(_ value: String) -> Bool {
    !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

private func isRichRecordISODateTime(_ value: String) -> Bool {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if fractional.date(from: value) != nil { return true }
    return ISO8601DateFormatter().date(from: value) != nil
}

enum SyncMutationPayload: Encodable {
    case restaurant(RestaurantJSONContractV1)
    case visit(VisitSyncContractV1)
    case dish(DishSyncContractV1)
    case visitDish(VisitDishSyncContractV1)
    case photo(PhotoSyncContractV1)
    case companion(DiningCompanionSyncContractV1)
    case recommendationSource(RecommendationSourceSyncContractV1)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .restaurant(let restaurant): try container.encode(restaurant)
        case .visit(let visit): try container.encode(visit)
        case .dish(let dish): try container.encode(dish)
        case .visitDish(let visitDish): try container.encode(visitDish)
        case .photo(let photo): try container.encode(photo)
        case .companion(let companion): try container.encode(companion)
        case .recommendationSource(let source): try container.encode(source)
        }
    }
}

struct SyncMutationRequestV1: Encodable {
    let mutationId: String
    let entityType: SyncEntityType
    let entityId: String
    let operation: SyncMutationOperation
    let baseVersion: Int64
    let clientTimestamp: String
    let payload: SyncMutationPayload?
}

struct SyncPushRequestV1: Encodable {
    let apiVersion = SyncV1Contract.apiVersion
    let schemaVersion = SyncV1Contract.schemaVersion
    let mutations: [SyncMutationRequestV1]
}

struct SyncMutationAcknowledgementV1: Codable, Equatable {
    enum Status: String, Codable {
        case applied
        case conflict
    }

    let mutationId: String
    let entityType: SyncEntityType
    let entityId: String
    let status: Status
    let duplicate: Bool
    let serverVersion: Int64
    let revision: Int64?
    let conflictReason: String?
}

struct SyncPushResponseV1: Decodable {
    let apiVersion: Int
    let acknowledgements: [SyncMutationAcknowledgementV1]
    let serverTime: String
}

struct RestaurantSyncRecordEnvelopeV1: Decodable {
    let serverVersion: Int64
    let record: RestaurantJSONContractV1
}

struct VisitSyncRecordEnvelopeV1: Decodable {
    let serverVersion: Int64
    let record: VisitSyncContractV1
}

struct DishSyncRecordEnvelopeV1: Decodable {
    let serverVersion: Int64
    let record: DishSyncContractV1
}

struct VisitDishSyncRecordEnvelopeV1: Decodable {
    let serverVersion: Int64
    let record: VisitDishSyncContractV1
}

struct PhotoSyncRecordEnvelopeV1: Decodable {
    let serverVersion: Int64
    let record: PhotoSyncContractV1
}

struct DiningCompanionSyncRecordEnvelopeV1: Decodable {
    let serverVersion: Int64
    let record: DiningCompanionSyncContractV1
}

struct RecommendationSourceSyncRecordEnvelopeV1: Decodable {
    let serverVersion: Int64
    let record: RecommendationSourceSyncContractV1
}

struct SyncTombstoneV1: Codable, Equatable {
    let entityType: SyncEntityType
    let entityId: String
    let serverVersion: Int64
    let deletedAt: String
}

struct SyncPullResponseV1: Decodable {
    let apiVersion: Int
    let schemaVersion: Int
    let restaurants: [RestaurantSyncRecordEnvelopeV1]
    let visits: [VisitSyncRecordEnvelopeV1]
    let dishes: [DishSyncRecordEnvelopeV1]
    let visitDishes: [VisitDishSyncRecordEnvelopeV1]
    let photos: [PhotoSyncRecordEnvelopeV1]
    let companions: [DiningCompanionSyncRecordEnvelopeV1]
    let recommendationSources: [RecommendationSourceSyncRecordEnvelopeV1]
    let tombstones: [SyncTombstoneV1]
    let nextCursor: String
    let hasMore: Bool
    let serverTime: String

    init(
        apiVersion: Int,
        schemaVersion: Int,
        restaurants: [RestaurantSyncRecordEnvelopeV1],
        visits: [VisitSyncRecordEnvelopeV1],
        dishes: [DishSyncRecordEnvelopeV1] = [],
        visitDishes: [VisitDishSyncRecordEnvelopeV1] = [],
        photos: [PhotoSyncRecordEnvelopeV1] = [],
        companions: [DiningCompanionSyncRecordEnvelopeV1] = [],
        recommendationSources: [RecommendationSourceSyncRecordEnvelopeV1] = [],
        tombstones: [SyncTombstoneV1],
        nextCursor: String,
        hasMore: Bool,
        serverTime: String
    ) {
        self.apiVersion = apiVersion
        self.schemaVersion = schemaVersion
        self.restaurants = restaurants
        self.visits = visits
        self.dishes = dishes
        self.visitDishes = visitDishes
        self.photos = photos
        self.companions = companions
        self.recommendationSources = recommendationSources
        self.tombstones = tombstones
        self.nextCursor = nextCursor
        self.hasMore = hasMore
        self.serverTime = serverTime
    }

    enum CodingKeys: String, CodingKey {
        case apiVersion, schemaVersion, restaurants, visits, dishes, visitDishes, photos
        case companions, recommendationSources
        case tombstones, nextCursor, hasMore, serverTime
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        apiVersion = try values.decode(Int.self, forKey: .apiVersion)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        restaurants = try values.decode([RestaurantSyncRecordEnvelopeV1].self, forKey: .restaurants)
        visits = try values.decode([VisitSyncRecordEnvelopeV1].self, forKey: .visits)
        dishes = try values.decodeIfPresent([DishSyncRecordEnvelopeV1].self, forKey: .dishes) ?? []
        visitDishes = try values.decodeIfPresent([VisitDishSyncRecordEnvelopeV1].self, forKey: .visitDishes) ?? []
        photos = try values.decodeIfPresent([PhotoSyncRecordEnvelopeV1].self, forKey: .photos) ?? []
        companions = try values.decodeIfPresent([DiningCompanionSyncRecordEnvelopeV1].self, forKey: .companions) ?? []
        recommendationSources = try values.decodeIfPresent(
            [RecommendationSourceSyncRecordEnvelopeV1].self,
            forKey: .recommendationSources
        ) ?? []
        tombstones = try values.decode([SyncTombstoneV1].self, forKey: .tombstones)
        nextCursor = try values.decode(String.self, forKey: .nextCursor)
        hasMore = try values.decode(Bool.self, forKey: .hasMore)
        serverTime = try values.decode(String.self, forKey: .serverTime)
    }
}
