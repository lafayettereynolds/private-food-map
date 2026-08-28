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
