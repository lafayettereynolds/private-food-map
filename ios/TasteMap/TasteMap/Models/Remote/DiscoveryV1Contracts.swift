import Foundation

enum DiscoveryEvidencePolicy {
    /// Product language and UI use ten points. Remote Visit.rating remains on
    /// the legacy five-point scale only for storage/API compatibility.
    static let minimumQualifiedScoreOutOfTen = 7.5
    static let minimumQualifiedRatingOutOfFive = minimumQualifiedScoreOutOfTen / 2

    static func isQualified(ratingOutOfFive rating: Double?) -> Bool {
        guard let rating else { return false }
        return rating >= minimumQualifiedRatingOutOfFive
    }
}

enum DiscoveryModeV1: String, Codable, CaseIterable, Identifiable, Sendable {
    case forYou = "for_you"
    case similarTaste = "similar_taste"
    case trending

    var id: Self { self }
    var title: String {
        switch self {
        case .forYou: "为你推荐"
        case .similarTaste: "同味之选"
        case .trending: "趋势"
        }
    }
}

enum DiscoveryViewerRestaurantStateV1: String, Codable, Sendable {
    case none
    case wantToGo = "want_to_go"
    case visited
}

enum DiscoveryCacheScopeV1: String, Codable, Sendable { case `public`, friends }
enum DiscoveryConfidenceV1: String, Codable, Sendable { case insufficient, low, medium, high }

struct DiscoveryPlaceIdentityV1: Codable, Equatable, Sendable {
    let provider: RestaurantPlaceProvider
    let externalId: String
    let isPrimary: Bool
}

struct DiscoveryPhotoProjectionV1: Codable, Equatable, Sendable {
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

    var isActualDiningPhoto: Bool {
        if let photoKind { return ["visit", "dish"].contains(photoKind) }
        return visitId?.isEmpty == false
    }

    /// Nested legacy photos may lack provenance fields, but contradictory
    /// metadata must never turn another Visit/author's photo into this album.
    static func activityAlbum(_ photos: [Self]?, visitID: String, authorID: String) -> [Self]? {
        guard let photos else { return nil }
        var seen = Set<String>()
        return photos.filter {
            !$0.photoId.isEmpty && ($0.photoKind == nil || $0.isActualDiningPhoto)
                && ($0.visitId == nil || $0.visitId == visitID)
                && ($0.ownerUserId == nil || $0.ownerUserId == authorID)
                && seen.insert($0.photoId.lowercased()).inserted
        }
    }
}

struct DiscoveryRestaurantProjectionV1: Codable, Equatable, Identifiable, Sendable {
    let globalKey: String
    let placeIdentities: [DiscoveryPlaceIdentityV1]
    let name: String
    let address: String
    let city: String
    let latitude: Double
    let longitude: Double
    let tags: [String]
    let pricePerPerson: Double?
    let merchantImageUrl: String?
    let markerEmoji: String
    let photo: DiscoveryPhotoProjectionV1?
    var phone: String? = nil
    var websiteUrl: String? = nil
    var openingHours: String? = nil

    var id: String { globalKey }
}

struct DiscoveryPublicUserProjectionV1: Codable, Equatable, Identifiable, Sendable {
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
        SocialUserResultV1(
            profile: SocialUserSummaryV1(
                userId: userId, displayName: displayName, bio: bio, city: city,
                avatarPhotoId: avatarPhotoId, avatarPresetId: avatarPresetId
            ),
            friendshipId: friendshipId,
            friendshipState: friendshipState,
            isFollowing: isFollowing
        )
    }
}

/// One concrete, authorization-filtered activity behind a Discovery card.
/// Restaurant aggregate ratings remain a separate detail-level projection.
struct DiscoveryActivityProjectionV1: Codable, Equatable, Sendable {
    let visitId: String
    let visitedAt: String
    let rating: Double?
    var photos: [DiscoveryPhotoProjectionV1]? = nil
}

struct DiscoveryRatingProjectionV1: Codable, Equatable, Sendable {
    let value: Double?
    let sampleCount: Int
}

struct DiscoveryRatingsV1: Codable, Equatable, Sendable {
    let mine: DiscoveryRatingProjectionV1
    let community: DiscoveryRatingProjectionV1
    let friends: DiscoveryRatingProjectionV1
    let similarTaste: DiscoveryRatingProjectionV1
}

struct DiscoveryReasonV1: Codable, Equatable, Identifiable, Sendable {
    let code: String
    let text: String
    var evidence: TasteMapHybridDiscoveryReasonEvidenceDTO? = nil
    var id: String { "\(code):\(text)" }
}

struct DiscoveryTrendContextV1: Codable, Equatable, Sendable {
    let windowDays: Int
    let uniqueVisitorCount: Int
    let wantToGoCount: Int
}

struct DiscoverySimilarityContextV1: Codable, Equatable, Sendable {
    let percent: Int
    let sharedRestaurantCount: Int
}

struct DiscoveryCardV1: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let mode: DiscoveryModeV1
    let restaurant: DiscoveryRestaurantProjectionV1
    var viewerState: DiscoveryViewerRestaurantStateV1
    let ratings: DiscoveryRatingsV1
    let reasons: [DiscoveryReasonV1]
    let sourceUser: DiscoveryPublicUserProjectionV1?
    let activity: DiscoveryActivityProjectionV1?
    let similarity: DiscoverySimilarityContextV1?
    let trend: DiscoveryTrendContextV1?
    let cacheScope: DiscoveryCacheScopeV1
    let rank: Int
    let score: Double
    let personalTastePercent: Int?
    let calibratedLikeProbability: TasteMapCalibratedLikeProbabilityDTO?
    let tasteEvidence: TasteMapDiscoveryTasteEvidenceDTO?

    init(
        id: String,
        mode: DiscoveryModeV1,
        restaurant: DiscoveryRestaurantProjectionV1,
        viewerState: DiscoveryViewerRestaurantStateV1,
        ratings: DiscoveryRatingsV1,
        reasons: [DiscoveryReasonV1],
        sourceUser: DiscoveryPublicUserProjectionV1?,
        activity: DiscoveryActivityProjectionV1? = nil,
        similarity: DiscoverySimilarityContextV1?,
        trend: DiscoveryTrendContextV1?,
        cacheScope: DiscoveryCacheScopeV1,
        rank: Int,
        score: Double,
        personalTastePercent: Int? = nil,
        calibratedLikeProbability: TasteMapCalibratedLikeProbabilityDTO? = nil,
        tasteEvidence: TasteMapDiscoveryTasteEvidenceDTO? = nil
    ) {
        self.id = id
        self.mode = mode
        self.restaurant = restaurant
        self.viewerState = viewerState
        self.ratings = ratings
        self.reasons = reasons
        self.sourceUser = sourceUser
        self.activity = activity
        self.similarity = similarity
        self.trend = trend
        self.cacheScope = cacheScope
        self.rank = rank
        self.score = score
        self.personalTastePercent = personalTastePercent
        self.calibratedLikeProbability = calibratedLikeProbability
        self.tasteEvidence = tasteEvidence
    }
}

extension DiscoveryCardV1 {
    /// Trend cards are restaurant-level count aggregates and may include
    /// Visits below 7.5/10 in their visitor totals. Rating-driven placements
    /// require a qualified concrete Visit whenever such an activity is attached.
    var isEligibleForDiscoveryPresentation: Bool {
        switch mode {
        case .trending:
            true
        case .similarTaste:
            DiscoveryEvidencePolicy.isQualified(ratingOutOfFive: activity?.rating)
        case .forYou:
            activity == nil || DiscoveryEvidencePolicy.isQualified(ratingOutOfFive: activity?.rating)
        }
    }
}

struct DiscoveryPageV1: Codable, Equatable, Sendable {
    let apiVersion: Int
    let mode: DiscoveryModeV1
    let city: String
    let personalizationConfidence: DiscoveryConfidenceV1
    let generatedAt: String
    let items: [DiscoveryCardV1]
    let nextCursor: String?
    var evidenceAvailability: TasteMapDiscoveryEvidenceAvailabilityDTO? = nil
    var appliedQuery: TasteMapDiscoveryAppliedQuery? = nil
    var filterCapabilities: TasteMapDiscoveryFilterCapabilities? = nil
    var filterTaxonomy: TasteMapDiscoveryFilterTaxonomy? = nil
}

struct DiscoveryCachedCardContext: Codable, Equatable, Sendable {
    let id: String
    let mode: DiscoveryModeV1
    let viewerState: DiscoveryViewerRestaurantStateV1
    let ratings: DiscoveryRatingsV1
    let reasons: [DiscoveryReasonV1]
    let sourceUser: DiscoveryPublicUserProjectionV1?
    let activity: DiscoveryActivityProjectionV1?
    let similarity: DiscoverySimilarityContextV1?
    let trend: DiscoveryTrendContextV1?
    let cacheScope: DiscoveryCacheScopeV1
    let rank: Int
    let score: Double
    let personalTastePercent: Int?
    let calibratedLikeProbability: TasteMapCalibratedLikeProbabilityDTO?
    var tasteEvidence: TasteMapDiscoveryTasteEvidenceDTO? = nil

    init(card: DiscoveryCardV1) {
        id = card.id; mode = card.mode; viewerState = card.viewerState
        ratings = card.ratings; reasons = card.reasons; sourceUser = card.sourceUser
        activity = card.activity
        similarity = card.similarity; trend = card.trend; cacheScope = card.cacheScope
        rank = card.rank; score = card.score
        personalTastePercent = card.personalTastePercent
        calibratedLikeProbability = card.calibratedLikeProbability
        tasteEvidence = card.tasteEvidence
    }

    func card(restaurant: DiscoveryRestaurantProjectionV1) -> DiscoveryCardV1 {
        .init(id: id, mode: mode, restaurant: restaurant, viewerState: viewerState,
              ratings: ratings, reasons: reasons, sourceUser: sourceUser, activity: activity,
              similarity: similarity, trend: trend, cacheScope: cacheScope,
              rank: rank, score: score, personalTastePercent: personalTastePercent,
              calibratedLikeProbability: calibratedLikeProbability, tasteEvidence: tasteEvidence)
    }
}
