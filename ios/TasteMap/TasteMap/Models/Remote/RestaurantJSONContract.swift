import Foundation

enum RestaurantPlaceProvider: String, Codable, CaseIterable, Sendable {
    case amap
    case appleMaps = "apple_maps"
    case manual
    case other
}

struct RestaurantPlaceIdentityContract: Codable, Equatable, Sendable {
    let provider: RestaurantPlaceProvider
    let externalId: String
    let isPrimary: Bool
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case provider, externalId, isPrimary, createdAt, updatedAt
    }

    init(
        provider: RestaurantPlaceProvider,
        externalId: String,
        isPrimary: Bool,
        createdAt: String,
        updatedAt: String
    ) throws {
        guard !externalId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RestaurantContractDecodingError.invalidIdentity
        }
        self.provider = provider
        self.externalId = externalId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isPrimary = isPrimary
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            provider: container.decode(RestaurantPlaceProvider.self, forKey: .provider),
            externalId: container.decode(String.self, forKey: .externalId),
            isPrimary: container.decode(Bool.self, forKey: .isPrimary),
            createdAt: container.decode(String.self, forKey: .createdAt),
            updatedAt: container.decode(String.self, forKey: .updatedAt)
        )
    }
}

enum RestaurantContractDecodingError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
    case missingLegacyAmapIdentity
    case invalidIdentity
    case invalidPrimaryIdentityCount
    case duplicateIdentity
}

struct RestaurantJSONContractV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let version: Int
    let id: String
    let userId: String
    let placeIdentities: [RestaurantPlaceIdentityContract]
    let amapPoiId: String?
    let name: String
    let address: String
    let city: String
    let latitude: Double
    let longitude: Double
    let status: RestaurantStatusContract
    let preferenceLevel: RestaurantPreferenceContract
    let overallRating: Double?
    let foodRating: Double?
    let environmentRating: Double?
    let serviceRating: Double?
    let valueRating: Double?
    let tags: [String]
    let longTermNote: String
    let pricePerPerson: Double?
    let phone: String?
    let openingHours: String?
    let markerType: RestaurantMarkerTypeContract
    let markerPhotoId: String?
    let merchantImageUrl: String?
    let markerEmoji: String
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?
    let isTestData: Bool?

    enum RestaurantStatusContract: String, Codable, Sendable {
        case visited
        case wantToGo
    }

    enum RestaurantPreferenceContract: String, Codable, Sendable {
        case favorite
        case like
        case normal
        case avoid
    }

    enum RestaurantMarkerTypeContract: String, Codable, Sendable {
        case image
        case emoji
    }

    enum CodingKeys: String, CodingKey {
        case version = "schemaVersion"
        case id, userId, placeIdentities, amapPoiId, name, address, city
        case latitude, longitude, status, preferenceLevel
        case overallRating, foodRating, environmentRating, serviceRating, valueRating
        case tags, longTermNote, pricePerPerson, phone, openingHours, markerType
        case markerPhotoId, merchantImageUrl, markerEmoji, createdAt, updatedAt
        case deletedAt, isTestData
    }

    init(
        id: String,
        userId: String,
        placeIdentities: [RestaurantPlaceIdentityContract],
        amapPoiId: String? = nil,
        name: String,
        address: String,
        city: String,
        latitude: Double,
        longitude: Double,
        status: RestaurantStatusContract,
        preferenceLevel: RestaurantPreferenceContract,
        overallRating: Double?,
        foodRating: Double?,
        environmentRating: Double?,
        serviceRating: Double?,
        valueRating: Double?,
        tags: [String],
        longTermNote: String,
        pricePerPerson: Double?,
        phone: String?,
        openingHours: String?,
        markerType: RestaurantMarkerTypeContract,
        markerPhotoId: String?,
        merchantImageUrl: String?,
        markerEmoji: String,
        createdAt: String,
        updatedAt: String,
        deletedAt: String?,
        isTestData: Bool? = nil
    ) throws {
        try Self.validate(placeIdentities)
        version = Self.schemaVersion
        self.id = id
        self.userId = userId
        self.placeIdentities = placeIdentities
        self.amapPoiId = amapPoiId
        self.name = name
        self.address = address
        self.city = city
        self.latitude = latitude
        self.longitude = longitude
        self.status = status
        self.preferenceLevel = preferenceLevel
        self.overallRating = overallRating
        self.foodRating = foodRating
        self.environmentRating = environmentRating
        self.serviceRating = serviceRating
        self.valueRating = valueRating
        self.tags = tags
        self.longTermNote = longTermNote
        self.pricePerPerson = pricePerPerson
        self.phone = phone
        self.openingHours = openingHours
        self.markerType = markerType
        self.markerPhotoId = markerPhotoId
        self.merchantImageUrl = merchantImageUrl
        self.markerEmoji = markerEmoji
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.isTestData = isTestData
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let incomingVersion = try container.decodeIfPresent(Int.self, forKey: .version)
        if let incomingVersion, incomingVersion != Self.schemaVersion {
            throw RestaurantContractDecodingError.unsupportedSchemaVersion(incomingVersion)
        }

        id = try container.decode(String.self, forKey: .id)
        userId = try container.decode(String.self, forKey: .userId)
        name = try container.decode(String.self, forKey: .name)
        address = try container.decode(String.self, forKey: .address)
        city = try container.decode(String.self, forKey: .city)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        status = try container.decode(RestaurantStatusContract.self, forKey: .status)
        preferenceLevel = try container.decode(RestaurantPreferenceContract.self, forKey: .preferenceLevel)
        overallRating = try container.decode(Double?.self, forKey: .overallRating)
        foodRating = try container.decode(Double?.self, forKey: .foodRating)
        environmentRating = try container.decode(Double?.self, forKey: .environmentRating)
        serviceRating = try container.decode(Double?.self, forKey: .serviceRating)
        valueRating = try container.decode(Double?.self, forKey: .valueRating)
        tags = try container.decode([String].self, forKey: .tags)
        longTermNote = try container.decode(String.self, forKey: .longTermNote)
        pricePerPerson = try container.decode(Double?.self, forKey: .pricePerPerson)
        phone = try container.decode(String?.self, forKey: .phone)
        openingHours = try container.decode(String?.self, forKey: .openingHours)
        markerType = try container.decode(RestaurantMarkerTypeContract.self, forKey: .markerType)
        markerPhotoId = try container.decode(String?.self, forKey: .markerPhotoId)
        merchantImageUrl = try container.decode(String?.self, forKey: .merchantImageUrl)
        markerEmoji = try container.decode(String.self, forKey: .markerEmoji)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        deletedAt = try container.decode(String?.self, forKey: .deletedAt)
        amapPoiId = try container.decodeIfPresent(String.self, forKey: .amapPoiId)
        isTestData = try container.decodeIfPresent(Bool.self, forKey: .isTestData)

        if incomingVersion == nil {
            guard let amapPoiId, !amapPoiId.isEmpty else {
                throw RestaurantContractDecodingError.missingLegacyAmapIdentity
            }
            placeIdentities = [try RestaurantPlaceIdentityContract(
                provider: .amap,
                externalId: amapPoiId,
                isPrimary: true,
                createdAt: createdAt,
                updatedAt: updatedAt
            )]
        } else {
            placeIdentities = try container.decode([RestaurantPlaceIdentityContract].self, forKey: .placeIdentities)
        }
        version = Self.schemaVersion
        try Self.validate(placeIdentities)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.schemaVersion, forKey: .version)
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encode(placeIdentities, forKey: .placeIdentities)
        try container.encodeIfPresent(amapPoiId, forKey: .amapPoiId)
        try container.encode(name, forKey: .name)
        try container.encode(address, forKey: .address)
        try container.encode(city, forKey: .city)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encode(status, forKey: .status)
        try container.encode(preferenceLevel, forKey: .preferenceLevel)
        try container.encode(overallRating, forKey: .overallRating)
        try container.encode(foodRating, forKey: .foodRating)
        try container.encode(environmentRating, forKey: .environmentRating)
        try container.encode(serviceRating, forKey: .serviceRating)
        try container.encode(valueRating, forKey: .valueRating)
        try container.encode(tags, forKey: .tags)
        try container.encode(longTermNote, forKey: .longTermNote)
        try container.encode(pricePerPerson, forKey: .pricePerPerson)
        try container.encode(phone, forKey: .phone)
        try container.encode(openingHours, forKey: .openingHours)
        try container.encode(markerType, forKey: .markerType)
        try container.encode(markerPhotoId, forKey: .markerPhotoId)
        try container.encode(merchantImageUrl, forKey: .merchantImageUrl)
        try container.encode(markerEmoji, forKey: .markerEmoji)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(deletedAt, forKey: .deletedAt)
        try container.encodeIfPresent(isTestData, forKey: .isTestData)
    }

    private static func validate(_ identities: [RestaurantPlaceIdentityContract]) throws {
        guard identities.filter(\.isPrimary).count == 1 else {
            throw RestaurantContractDecodingError.invalidPrimaryIdentityCount
        }
        let keys = identities.map { "\($0.provider.rawValue):\($0.externalId)" }
        guard Set(keys).count == keys.count else {
            throw RestaurantContractDecodingError.duplicateIdentity
        }
    }
}
