import Foundation

enum RestaurantListContractError: Error, Equatable {
    case invalidTitle
    case invalidDescription
    case invalidNote
    case invalidPlace
}

struct RestaurantListPlaceIdentityContractV1: Codable, Equatable, Sendable {
    let provider: RestaurantPlaceProvider
    let externalId: String
    let isPrimary: Bool
}

struct RestaurantListPlaceContractV1: Codable, Equatable, Identifiable, Sendable {
    let globalKey: String
    let restaurantId: String
    let placeIdentities: [RestaurantListPlaceIdentityContractV1]
    let name: String
    let address: String
    let city: String
    let latitude: Double
    let longitude: Double
    let markerPhotoId: String?
    let merchantImageUrl: String?
    let markerEmoji: String

    var id: String { globalKey }

    private enum CodingKeys: String, CodingKey {
        case globalKey, restaurantId, placeIdentities, name, address, city, latitude, longitude
        case markerPhotoId, merchantImageUrl, markerEmoji
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(globalKey, forKey: .globalKey)
        try values.encode(restaurantId, forKey: .restaurantId)
        try values.encode(placeIdentities, forKey: .placeIdentities)
        try values.encode(name, forKey: .name)
        try values.encode(address, forKey: .address)
        try values.encode(city, forKey: .city)
        try values.encode(latitude, forKey: .latitude)
        try values.encode(longitude, forKey: .longitude)
        // The shared wire contract requires explicit null, not an omitted key.
        try values.encode(markerPhotoId, forKey: .markerPhotoId)
        try values.encode(merchantImageUrl, forKey: .merchantImageUrl)
        try values.encode(markerEmoji, forKey: .markerEmoji)
    }

    init(
        globalKey: String,
        restaurantId: String,
        placeIdentities: [RestaurantListPlaceIdentityContractV1],
        name: String,
        address: String,
        city: String,
        latitude: Double,
        longitude: Double,
        markerPhotoId: String?,
        merchantImageUrl: String?,
        markerEmoji: String
    ) throws {
        guard !globalKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !restaurantId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              placeIdentities.contains(where: \.isPrimary),
              (-90 ... 90).contains(latitude), (-180 ... 180).contains(longitude) else {
            throw RestaurantListContractError.invalidPlace
        }
        self.globalKey = globalKey
        self.restaurantId = restaurantId
        self.placeIdentities = placeIdentities
        self.name = name
        self.address = address
        self.city = city
        self.latitude = latitude
        self.longitude = longitude
        self.markerPhotoId = markerPhotoId
        self.merchantImageUrl = merchantImageUrl
        self.markerEmoji = markerEmoji
    }
}

struct RestaurantListSyncContractV1: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let id: String
    let userId: String
    let title: String
    let description: String
    let visibility: RestaurantListVisibility
    let isRanked: Bool
    let coverMode: RestaurantListCoverMode
    let customCoverPhotoId: String?
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, userId, title, description, visibility, isRanked, coverMode
        case customCoverPhotoId, createdAt, updatedAt, deletedAt
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(id, forKey: .id)
        try values.encode(userId, forKey: .userId)
        try values.encode(title, forKey: .title)
        try values.encode(description, forKey: .description)
        try values.encode(visibility, forKey: .visibility)
        try values.encode(isRanked, forKey: .isRanked)
        try values.encode(coverMode, forKey: .coverMode)
        try values.encode(customCoverPhotoId, forKey: .customCoverPhotoId)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encode(updatedAt, forKey: .updatedAt)
        try values.encode(deletedAt, forKey: .deletedAt)
    }

    init(
        schemaVersion: Int = SyncV1Contract.schemaVersion,
        id: String,
        userId: String,
        title: String,
        description: String,
        visibility: RestaurantListVisibility,
        isRanked: Bool,
        coverMode: RestaurantListCoverMode,
        customCoverPhotoId: String?,
        createdAt: String,
        updatedAt: String,
        deletedAt: String?
    ) throws {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty, normalizedTitle.count <= 60 else {
            throw RestaurantListContractError.invalidTitle
        }
        guard normalizedDescription.count <= 240 else {
            throw RestaurantListContractError.invalidDescription
        }
        self.schemaVersion = schemaVersion
        self.id = id
        self.userId = userId
        self.title = normalizedTitle
        self.description = normalizedDescription
        self.visibility = visibility
        self.isRanked = isRanked
        self.coverMode = coverMode
        self.customCoverPhotoId = customCoverPhotoId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

struct RestaurantListItemSyncContractV1: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let id: String
    let userId: String
    let listId: String
    let restaurantId: String
    let restaurantGlobalKey: String
    let position: Int
    let note: String
    let restaurant: RestaurantListPlaceContractV1
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, userId, listId, restaurantId, restaurantGlobalKey, position, note
        case restaurant, createdAt, updatedAt, deletedAt
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(id, forKey: .id)
        try values.encode(userId, forKey: .userId)
        try values.encode(listId, forKey: .listId)
        try values.encode(restaurantId, forKey: .restaurantId)
        try values.encode(restaurantGlobalKey, forKey: .restaurantGlobalKey)
        try values.encode(position, forKey: .position)
        try values.encode(note, forKey: .note)
        try values.encode(restaurant, forKey: .restaurant)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encode(updatedAt, forKey: .updatedAt)
        try values.encode(deletedAt, forKey: .deletedAt)
    }

    init(
        schemaVersion: Int = SyncV1Contract.schemaVersion,
        id: String,
        userId: String,
        listId: String,
        restaurantId: String,
        restaurantGlobalKey: String,
        position: Int,
        note: String,
        restaurant: RestaurantListPlaceContractV1,
        createdAt: String,
        updatedAt: String,
        deletedAt: String?
    ) throws {
        let normalizedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard position >= 0, normalizedNote.count <= 160 else {
            throw RestaurantListContractError.invalidNote
        }
        guard restaurant.globalKey == restaurantGlobalKey,
              restaurant.restaurantId == restaurantId else {
            throw RestaurantListContractError.invalidPlace
        }
        self.schemaVersion = schemaVersion
        self.id = id
        self.userId = userId
        self.listId = listId
        self.restaurantId = restaurantId
        self.restaurantGlobalKey = restaurantGlobalKey
        self.position = position
        self.note = normalizedNote
        self.restaurant = restaurant
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

struct PublicListOwnerDTO: Codable, Equatable, Identifiable, Sendable {
    let userId: String
    let displayName: String
    let avatarPhotoId: String?
    let avatarPresetId: ProfileAvatarPreset
    var id: String { userId }
}

struct PublicListPreviewRestaurantDTO: Codable, Equatable, Identifiable, Sendable {
    let globalKey: String
    let name: String
    let photoId: String?
    let merchantImageUrl: String?
    let markerEmoji: String
    var id: String { globalKey }
}

struct PublicListSummaryDTO: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let description: String
    let visibility: RestaurantListVisibility
    let isRanked: Bool
    let coverMode: RestaurantListCoverMode
    let customCoverPhotoId: String?
    let restaurantCount: Int
    let previewRestaurants: [PublicListPreviewRestaurantDTO]
    let owner: PublicListOwnerDTO
    let updatedAt: String
}

struct PublicListItemDTO: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let position: Int
    let note: String
    let restaurant: RestaurantListPlaceContractV1
}

struct PublicListSummaryPageDTO: Codable, Equatable, Sendable {
    let apiVersion: Int
    let items: [PublicListSummaryDTO]
    let nextCursor: String?
    let generatedAt: String
}

struct PublicListDetailDTO: Codable, Equatable, Sendable {
    let apiVersion: Int
    let list: PublicListSummaryDTO
    let items: [PublicListItemDTO]
    let nextCursor: String?
    let generatedAt: String
}

extension RestaurantListPlaceContractV1 {
    var discoveryProjection: DiscoveryRestaurantProjectionV1 {
        DiscoveryRestaurantProjectionV1(
            globalKey: globalKey,
            placeIdentities: placeIdentities.map {
                DiscoveryPlaceIdentityV1(provider: $0.provider, externalId: $0.externalId, isPrimary: $0.isPrimary)
            },
            name: name,
            address: address,
            city: city,
            latitude: latitude,
            longitude: longitude,
            tags: [],
            pricePerPerson: nil,
            merchantImageUrl: merchantImageUrl,
            markerEmoji: markerEmoji,
            photo: markerPhotoId.map { DiscoveryPhotoProjectionV1(photoId: $0, variant: .thumbnail) }
        )
    }
}
