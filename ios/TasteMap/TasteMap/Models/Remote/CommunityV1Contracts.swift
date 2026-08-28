import Foundation

enum CommunityFeedScopeV1: String, Codable, CaseIterable, Sendable {
    case following
    case latest

    var title: String { self == .following ? "关注" : "最新" }
}

enum PublicContentSectionV1: String, Codable, Sendable {
    case visits
    case wantToGo = "want_to_go"
}

enum PublicContentKindV1: String, Codable, Sendable {
    case visit
    case wantToGo = "want_to_go"
}

enum PublicContentCacheScopeV1: String, Codable, Sendable {
    case `public`, friends
}

struct PublicContentPlaceIdentityV1: Codable, Equatable, Sendable {
    let provider: RestaurantPlaceProvider
    let externalId: String
    let isPrimary: Bool
}

struct PublicContentPhotoV1: Codable, Equatable, Identifiable, Sendable {
    let photoId: String
    let variant: PhotoBinaryVariant
    var id: String { photoId }
}

struct PublicContentUserV1: Codable, Equatable, Identifiable, Sendable {
    let userId: String
    let displayName: String
    let bio: String?
    let city: String?
    let avatarPhotoId: String?
    let avatarPresetId: ProfileAvatarPreset
    let friendshipId: String?
    let friendshipState: FriendshipPerspectiveState
    let isFollowing: Bool
    var id: String { userId }

    var socialResult: SocialUserResultV1 {
        .init(
            profile: .init(
                userId: userId, displayName: displayName, bio: bio, city: city,
                avatarPhotoId: avatarPhotoId, avatarPresetId: avatarPresetId
            ),
            friendshipId: friendshipId,
            friendshipState: friendshipState,
            isFollowing: isFollowing
        )
    }
}

struct PublicContentRestaurantV1: Codable, Equatable, Sendable {
    let globalKey: String
    let placeIdentities: [PublicContentPlaceIdentityV1]
    let name: String
    let address: String
    let city: String
    let latitude: Double
    let longitude: Double
    let tags: [String]
    let pricePerPerson: Double?
    let merchantImageUrl: String?
    let markerEmoji: String
    let photo: PublicContentPhotoV1?

    var discoveryProjection: DiscoveryRestaurantProjectionV1 {
        .init(
            globalKey: globalKey,
            placeIdentities: placeIdentities.map {
                .init(provider: $0.provider, externalId: $0.externalId, isPrimary: $0.isPrimary)
            },
            name: name, address: address, city: city,
            latitude: latitude, longitude: longitude, tags: tags,
            pricePerPerson: pricePerPerson, merchantImageUrl: merchantImageUrl,
            markerEmoji: markerEmoji,
            photo: photo.map { .init(photoId: $0.photoId, variant: $0.variant) }
        )
    }
}

struct PublicVisitV1: Codable, Equatable, Sendable {
    let id: String
    let ownerUserId: String
    let restaurantGlobalKey: String
    let visitedAt: String
    let rating: Double?
    let note: String?
    let visibility: ProfileVisibility
    let photos: [PublicContentPhotoV1]
    let updatedAt: String
}

struct PublicContentItemV1: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let kind: PublicContentKindV1
    let eventAt: String
    let updatedAt: String
    let user: PublicContentUserV1
    let restaurant: PublicContentRestaurantV1
    let visit: PublicVisitV1?
    var viewerState: DiscoveryViewerRestaurantStateV1
    let cacheScope: PublicContentCacheScopeV1
}

struct PublicContentStatisticsV1: Codable, Equatable, Sendable {
    let visibleRestaurantCount: Int
    let visibleVisitCount: Int
    let visibleWantToGoCount: Int
}

struct PublicProfileContentPageV1: Codable, Equatable, Sendable {
    let apiVersion: Int
    let targetUserId: String
    let section: PublicContentSectionV1
    let generatedAt: String
    let statistics: PublicContentStatisticsV1
    let items: [PublicContentItemV1]
    let nextCursor: String?
}

struct CommunityFeedPageV1: Codable, Equatable, Sendable {
    let apiVersion: Int
    let scope: CommunityFeedScopeV1
    let generatedAt: String
    let items: [PublicContentItemV1]
    let nextCursor: String?
}
