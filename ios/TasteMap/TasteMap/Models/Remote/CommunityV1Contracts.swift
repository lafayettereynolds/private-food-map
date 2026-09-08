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
    var sourceType: String? = nil
    var restaurantId: String? = nil
    var visitId: String? = nil
    var ownerUserId: String? = nil
    var visibility: String? = nil
    var createdAt: String? = nil
    var exportAllowed: Bool? = nil
    var photoKind: String? = nil
    var id: String { photoId }

    var discoveryProjection: DiscoveryPhotoProjectionV1 {
        .init(photoId: photoId, variant: variant, sourceType: sourceType,
              restaurantId: restaurantId, visitId: visitId, ownerUserId: ownerUserId,
              visibility: visibility, createdAt: createdAt, exportAllowed: exportAllowed, photoKind: photoKind)
    }
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
            photo: photo.map {
                .init(
                    photoId: $0.photoId,
                    variant: $0.variant,
                    sourceType: $0.sourceType,
                    restaurantId: $0.restaurantId,
                    visitId: $0.visitId,
                    ownerUserId: $0.ownerUserId,
                    visibility: $0.visibility,
                    createdAt: $0.createdAt,
                    exportAllowed: $0.exportAllowed
                )
            }
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
    var engagement: CommunityEngagementSummaryV1 = .zero

    private enum CodingKeys: String, CodingKey {
        case id, kind, eventAt, updatedAt, user, restaurant, visit, viewerState, cacheScope, engagement
    }

    init(
        id: String,
        kind: PublicContentKindV1,
        eventAt: String,
        updatedAt: String,
        user: PublicContentUserV1,
        restaurant: PublicContentRestaurantV1,
        visit: PublicVisitV1?,
        viewerState: DiscoveryViewerRestaurantStateV1,
        cacheScope: PublicContentCacheScopeV1,
        engagement: CommunityEngagementSummaryV1 = .zero
    ) {
        self.id = id
        self.kind = kind
        self.eventAt = eventAt
        self.updatedAt = updatedAt
        self.user = user
        self.restaurant = restaurant
        self.visit = visit
        self.viewerState = viewerState
        self.cacheScope = cacheScope
        self.engagement = engagement
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        kind = try values.decode(PublicContentKindV1.self, forKey: .kind)
        eventAt = try values.decode(String.self, forKey: .eventAt)
        updatedAt = try values.decode(String.self, forKey: .updatedAt)
        user = try values.decode(PublicContentUserV1.self, forKey: .user)
        restaurant = try values.decode(PublicContentRestaurantV1.self, forKey: .restaurant)
        visit = try values.decodeIfPresent(PublicVisitV1.self, forKey: .visit)
        viewerState = try values.decode(DiscoveryViewerRestaurantStateV1.self, forKey: .viewerState)
        cacheScope = try values.decode(PublicContentCacheScopeV1.self, forKey: .cacheScope)
        engagement = try values.decodeIfPresent(CommunityEngagementSummaryV1.self, forKey: .engagement) ?? .zero
    }
}

extension PublicContentItemV1 {
    /// Discovery is an evidence surface. A Visit below 7.5/10 remains valid on
    /// the author's Profile/history, but it is not qualified public evidence.
    var isEligibleForDiscoveryFeed: Bool {
        kind != .visit || DiscoveryEvidencePolicy.isQualified(ratingOutOfFive: visit?.rating)
    }
}

struct CommunityEngagementSummaryV1: Codable, Equatable, Sendable {
    var likedByViewer: Bool
    var likeCount: Int
    var commentCount: Int

    static let zero = Self(likedByViewer: false, likeCount: 0, commentCount: 0)
}

struct CommunityCommentV1: Codable, Equatable, Identifiable, Sendable {
    let apiVersion: Int
    let id: String
    let contentType: String
    let contentId: String
    let body: String
    let author: PublicContentUserV1
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?
    let serverVersion: Int
}

struct CommunityCommentPageV1: Codable, Equatable, Sendable {
    let apiVersion: Int
    let items: [CommunityCommentV1]
    let nextCursor: String?
}

struct CommunityLikeMutationV1: Codable, Equatable, Sendable {
    let apiVersion: Int
    let likedByViewer: Bool
    let likeCount: Int
    let commentCount: Int
    let duplicate: Bool
}

struct CommunityCommentMutationV1: Codable, Equatable, Sendable {
    let apiVersion: Int
    let comment: CommunityCommentV1
    let likeCount: Int
    let commentCount: Int
}

struct PublicProfileTasteSummaryV1: Codable, Equatable, Sendable {
    let topTags: [String]
    let averageRating: Double?
    let ratedVisitCount: Int
    let summary: String?
}

struct PublicProfileFootprintV1: Codable, Equatable, Identifiable, Sendable {
    let city: String
    let restaurantCount: Int
    let visitCount: Int
    var id: String { city }
}

struct PublicProfileOverviewV1: Codable, Equatable, Sendable {
    let apiVersion: Int
    let targetUserId: String
    let friendCount: Int
    let followingCount: Int
    let followerCount: Int
    let commonWantToGoCount: Int
    let commonWantToGo: [PublicContentRestaurantV1]
    let representativeRestaurants: [PublicContentRestaurantV1]
    let footprints: [PublicProfileFootprintV1]
    let tasteSummary: PublicProfileTasteSummaryV1
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
    /// Nil on older servers; a nonempty requested city requires an explicit echo.
    var city: String? = nil
    let apiVersion: Int
    let scope: CommunityFeedScopeV1
    let generatedAt: String
    let items: [PublicContentItemV1]
    let nextCursor: String?
    var appliedQuery: TasteMapDiscoveryAppliedQuery? = nil
    var filterCapabilities: TasteMapDiscoveryFilterCapabilities? = nil
    var filterTaxonomy: TasteMapDiscoveryFilterTaxonomy? = nil
}
