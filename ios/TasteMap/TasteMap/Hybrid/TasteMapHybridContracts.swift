import Foundation

public enum TasteMapHybridCapability: String, Codable, CaseIterable, Sendable {
    case appleSignIn, logout, profileRead, restaurantRead, restaurantAcquisition, mapBrowse, visitContract, sync
    case contentRead
    case communityInteraction, restaurantViewerState
    case haptics, share, location, photoPicker, premium, permissions, nativeNavigation, backup, accountDelete
}

public struct TasteMapHybridRuntimeDTO: Codable, Sendable {
    public let bridgeVersion: Int
    public let platform: String
    public let appVersion: String
    public let build: String
    public let dataSource: String
    public let localBundle: Bool
    public let offlineCapable: Bool
    public let supportedCapabilities: [String: Bool]
}

public struct TasteMapHybridAuthStateDTO: Codable, Sendable {
    public let state: String
    public let userID: String?
    public let displayName: String?

    public init(state: String, userID: String?, displayName: String?) {
        self.state = state
        self.userID = userID
        self.displayName = displayName
    }
}

public struct TasteMapHybridAuthResultDTO: Codable, Sendable {
    public let state: String
    public let session: TasteMapHybridAuthStateDTO

    public init(state: String, session: TasteMapHybridAuthStateDTO) {
        self.state = state
        self.session = session
    }
}

public enum TasteMapHybridRuntimeMode: String, Codable, Sendable {
    case nativePrimary = "NATIVE_PRIMARY"
#if DEBUG
    case hybridDevelopment = "HYBRID_DEVELOPMENT"
#endif
}

public enum TasteMapHybridRouteSurface: String, Codable, CaseIterable, Sendable {
    case map, discovery, add, profile, restaurant, visit, visitEdit, lists, publicList, activity
    case roulette, analytics, premium, settings
    case acquisitionNative, listManage, premiumStore, settingsNative, socialNative
    case dataBackup, permissions, storage, accountDelete
    case profileEdit, restaurantEdit, restaurantDelete, restaurantAddToList, restaurantWantToGo
}

public enum TasteMapHybridRouteOwner: String, Codable, Sendable { case hybrid, native }

public struct TasteMapHybridRouteDTO: Codable, Equatable, Identifiable, Sendable {
    public let surface: TasteMapHybridRouteSurface
    public let identifier: String?

    public init(surface: TasteMapHybridRouteSurface, identifier: String? = nil) throws {
        let normalized = identifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        if [.restaurant, .visit, .visitEdit, .restaurantEdit, .restaurantDelete,
            .restaurantAddToList, .restaurantWantToGo].contains(surface), normalized?.isEmpty != false {
            throw TasteMapHybridRouteError.missingIdentifier
        }
        if let normalized, normalized.count > 256 { throw TasteMapHybridRouteError.invalidIdentifier }
        self.surface = surface
        self.identifier = normalized?.isEmpty == false ? normalized : nil
    }

    private enum CodingKeys: String, CodingKey { case surface, identifier }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            surface: values.decode(TasteMapHybridRouteSurface.self, forKey: .surface),
            identifier: values.decodeIfPresent(String.self, forKey: .identifier)
        )
    }

    public var owner: TasteMapHybridRouteOwner {
        switch surface {
        case .map, .restaurant, .discovery, .add, .visit, .visitEdit, .lists,
                .publicList, .activity, .roulette, .analytics, .premium, .settings: .hybrid
        case .profile where identifier == nil: .hybrid
        default: .native
        }
    }

    public var id: String { "\(surface.rawValue):\(identifier ?? "_")" }
}

public struct TasteMapHybridNativeRouteRequest: Codable, Equatable, Sendable {
    public let route: TasteMapHybridRouteSurface
    public let identifier: String?
}

public enum TasteMapHybridRouteError: Error, Equatable, Sendable {
    case missingIdentifier, invalidIdentifier, malformedURL, unsupportedRoute
}

public struct TasteMapHybridNavigationStateDTO: Codable, Equatable, Sendable {
    public let route: TasteMapHybridRouteDTO
    public let owner: TasteMapHybridRouteOwner
    public let canGoBack: Bool

    public init(route: TasteMapHybridRouteDTO, canGoBack: Bool) {
        self.route = route
        self.owner = route.owner
        self.canGoBack = canGoBack
    }
}

public enum TasteMapHybridEventName: String, Codable, Sendable {
    case authChanged = "auth.changed"
    case navigationRoute = "navigation.route"
    case deepLinkReceived = "deepLink.received"
    case shareExtensionReceived = "shareExtension.received"
    case appLifecycle = "app.lifecycle"
    case locationChanged = "location.changed"
    case mapViewportChanged = "map.viewport.changed"
    case mapRestaurantSelected = "map.restaurant.selected"
}

public struct TasteMapHybridEventEnvelope: Codable, Sendable {
    public let version: Int
    public let sequence: Int
    public let name: TasteMapHybridEventName
    public let payload: TasteMapHybridJSONValue

    public init(sequence: Int, name: TasteMapHybridEventName, payload: TasteMapHybridJSONValue) {
        self.version = TasteMapHybridBridgeContract.version
        self.sequence = sequence
        self.name = name
        self.payload = payload
    }
}

public enum TasteMapHybridLifecycleState: String, Codable, Sendable {
    case foreground, background, resume, memoryWarning
}

public struct TasteMapHybridNormalizedSharePayload: Codable, Equatable, Sendable {
    public let fingerprint: String
    public let text: String
    public let url: String?

    public init(fingerprint: String, text: String, url: String?) {
        self.fingerprint = fingerprint
        self.text = text
        self.url = url
    }
}

public struct TasteMapHybridUserDTO: Codable, Sendable {
    public let id: String
    public let nickname: String
    public let bio: String
    public let city: String
    public let avatarPhotoId: String?
    public let avatarPresetId: String
    public let membershipTier: String
    public let mapSharingEnabled: Bool
    public let mapVisibility: String
    public let createdAt: String
    public let updatedAt: String
}

public struct TasteMapHybridVisitDTO: Codable, Sendable {
    public let id: String
    public let restaurantId: String
    public let visitedAt: String
    public let rating: Double?
    public let valueRating: Double?
    public let environmentRating: Double?
    public let serviceRating: Double?
    public let myActualSpend: Double?
    public let totalPrice: Double?
    public let pricePerPerson: Double?
    public let diningMode: String
    public let visibility: String
    public let paymentMode: String?
    public let queueDuration: String?
    public let diningOccasions: [String]
    public let diningOccasionText: String
    public let valueTags: [String]
    public let environmentTags: [String]
    public let serviceTags: [String]
    public let noiseLevel: String?
    public let diningDuration: String?
    public let portionLevel: String?
    public let transportConvenience: String?
    public let specialNotes: String
    public let companions: [String]
    public let companionIds: [String]
    public let recommendationSourceType: String?
    public let recommendationSourceUserId: String?
    public let recommendationSourceText: String
    public let sharedMealId: String?
    public let partySize: Int?
    public let note: String
    public let dishes: [TasteMapHybridVisitDishDTO]
    public let photos: [TasteMapHybridImageDescriptor]
    public let createdAt: String
    public let updatedAt: String
}

public struct TasteMapHybridVisitDishDTO: Codable, Sendable {
    public let id: String
    public let name: String
    public let taste: String
    public let rating: Double?
    public let price: Double?
    public let photoID: String?
}

public struct TasteMapHybridVisitWriteDraftDTO: Codable, Sendable {
    public let visitedAt: String
    public let rating: Double?
    public let visibility: String
    public let diningMode: String
    public let totalPrice: Double?
    public let myActualSpend: Double?
    public let paymentMode: String?
    public let partySize: Int
    public let queueDuration: String?
    public let diningOccasions: [String]
    public let diningOccasionText: String
    public let valueRating: Double?
    public let environmentRating: Double?
    public let serviceRating: Double?
    public let valueTags: [String]
    public let environmentTags: [String]
    public let serviceTags: [String]
    public let noiseLevel: String?
    public let diningDuration: String?
    public let portionLevel: String?
    public let transportConvenience: String?
    public let specialNotes: String
    public let recommendationSourceType: String?
    public let recommendationSourceUserID: String?
    public let recommendationSourceText: String
    public let sharedParticipantUserIDs: [String]
    public let companions: [String]
    public let dishes: [TasteMapHybridVisitWriteDishDTO]
    public let pendingPhotos: [TasteMapHybridPendingPhotoAttachmentDTO]?
    public let note: String
}

public struct TasteMapHybridPendingPhotoAttachmentDTO: Codable, Sendable {
    public let photoID: String
    public let dishDraftID: String?
}

public struct TasteMapHybridVisitWriteDishDTO: Codable, Sendable {
    public let id: String
    public let name: String
    public let taste: String
    public let rating: Double?
    public let price: Double?
    public let photoID: String?
}

public struct TasteMapHybridVisitWriteRequest: Codable, Sendable {
    public let restaurantID: String
    public let visitID: String?
    public let draft: TasteMapHybridVisitWriteDraftDTO
}

public struct TasteMapHybridVisitDeleteRequest: Codable, Sendable {
    public let visitID: String
}

public struct TasteMapHybridVisitMutationResultDTO: Codable, Sendable {
    public let restaurantID: String
    public let visitID: String
    public let updatedAt: String
    public let photoWarning: String?

    public init(
        restaurantID: String,
        visitID: String,
        updatedAt: String,
        photoWarning: String? = nil
    ) {
        self.restaurantID = restaurantID
        self.visitID = visitID
        self.updatedAt = updatedAt
        self.photoWarning = photoWarning
    }
}

public struct TasteMapHybridPhotoPickRequest: Codable, Sendable {
    public let selectionLimit: Int
}

public struct TasteMapHybridPhotoPickItemDTO: Codable, Sendable {
    public let photoID: String
    public let preview: TasteMapHybridImageDescriptor
}

public struct TasteMapHybridPhotoPickResultDTO: Codable, Sendable {
    public let photos: [TasteMapHybridPhotoPickItemDTO]
}

public struct TasteMapHybridPhotoIDRequest: Codable, Sendable {
    public let photoID: String
}

public enum TasteMapHybridImageKind: String, Codable, Sendable {
    case ownerPhoto, activityPhoto, publicUGC, foodCategoryVisual
    case nativeResource, publicOrCached, providerMerchant, foodDiningFallback
}

public struct TasteMapHybridImageDescriptor: Codable, Sendable {
    public let kind: TasteMapHybridImageKind
    public let resourceURL: String?
    public let photoID: String?
    public let stableSeed: String?
    public let categoryVisualID: String?
    public let restaurantID: String?
    public let visitID: String?
    public let sourceOwnerID: String?
    public let visibility: String?
    public let exportAllowed: Bool?
    public let attributionRequired: Bool?
    public let accessibilityLabel: String

    public init(
        kind: TasteMapHybridImageKind,
        resourceURL: String? = nil,
        photoID: String? = nil,
        stableSeed: String? = nil,
        categoryVisualID: String? = nil,
        restaurantID: String? = nil,
        visitID: String? = nil,
        sourceOwnerID: String? = nil,
        visibility: String? = nil,
        exportAllowed: Bool? = nil,
        attributionRequired: Bool? = nil,
        accessibilityLabel: String
    ) {
        self.kind = kind
        self.resourceURL = resourceURL
        self.photoID = photoID
        self.stableSeed = stableSeed
        self.categoryVisualID = categoryVisualID
        self.restaurantID = restaurantID
        self.visitID = visitID
        self.sourceOwnerID = sourceOwnerID
        self.visibility = visibility
        self.exportAllowed = exportAllowed
        self.attributionRequired = attributionRequired
        self.accessibilityLabel = accessibilityLabel
    }
}

/// An ordered, Native-owned image loading plan. React may advance through the
/// supplied sources after a load failure, but it must not reorder or infer the
/// user/public/provider priority itself.
public struct TasteMapHybridImageResolutionDTO: Codable, Sendable {
    public let sources: [TasteMapHybridImageDescriptor]
    public let fallback: TasteMapHybridImageDescriptor

    public init(
        sources: [TasteMapHybridImageDescriptor],
        fallback: TasteMapHybridImageDescriptor
    ) {
        self.sources = sources
        self.fallback = fallback
    }
}

public struct TasteMapHybridRestaurantDTO: Codable, Sendable {
    public let id: String
    public let name: String
    public let address: String
    public let city: String
    public let latitude: Double
    public let longitude: Double
    public let status: String
    public let tags: [String]
    public let phone: String?
    public let openingHours: String?
    public let referencePrice: Double?
    public let visitCount: Int
    public let averageRating: Double?
    public let scoreOutOfTen: Double?
    public let latestVisitDate: String?
    public let createdAt: String
    public let updatedAt: String
    public let visits: [TasteMapHybridVisitDTO]
    public let image: TasteMapHybridImageDescriptor
}

public struct TasteMapHybridProfileDTO: Codable, Sendable {
    public let user: TasteMapHybridUserDTO
    public let restaurants: [TasteMapHybridRestaurantDTO]
    public let followerCount: Int
    public let followingCount: Int
}

public struct TasteMapHybridRestaurantDetailDTO: Codable, Sendable {
    public let restaurant: TasteMapHybridRestaurantDTO
    /// Owner-scoped aggregate ratings for the exact Restaurant identity.
    /// Values use the public 10-point presentation scale.
    public let socialStats: TasteMapHybridRestaurantSocialStatsDTO?
    /// Native/Browser-owned viewer state. React must not infer this from a
    /// restaurant ID, user ID, or the existence of a public activity.
    public let viewerState: String
    public let editableVisitIDs: [String]
    public let capabilities: TasteMapHybridRestaurantCapabilitiesDTO
}

public struct TasteMapHybridRestaurantSocialStatsDTO: Codable, Equatable, Sendable {
    public let overallUserRating: Double?
    public let overallUserCount: Int
    public let friendAverageRating: Double?
    public let friendUserCount: Int
    public let similarTasteAverageRating: Double?
    public let similarTasteUserCount: Int
    public let repeatVisitRate: Double?
    public let repeatVisitorCount: Int
    public let uniqueVisitorCount: Int
}

public struct TasteMapHybridRestaurantCapabilitiesDTO: Codable, Equatable, Sendable {
    public let canEditRestaurant: Bool
    public let canDeleteRestaurant: Bool
    public let canRecordVisit: Bool
    public let canAddToWantToGo: Bool
    public let canAddToList: Bool
    public let canAddToRoulette: Bool
    public let canShare: Bool

    public static let owned = TasteMapHybridRestaurantCapabilitiesDTO(
        canEditRestaurant: true,
        canDeleteRestaurant: true,
        canRecordVisit: true,
        canAddToWantToGo: true,
        canAddToList: true,
        canAddToRoulette: true,
        canShare: true
    )

    public static let publicReadable = TasteMapHybridRestaurantCapabilitiesDTO(
        canEditRestaurant: false,
        canDeleteRestaurant: false,
        canRecordVisit: true,
        canAddToWantToGo: true,
        canAddToList: true,
        canAddToRoulette: true,
        canShare: true
    )
}

public struct TasteMapHybridRestaurantListRequest: Codable, Sendable {
    public let ids: [String]?
    public let status: String?
    public let limit: Int?
}

public struct TasteMapHybridRestaurantGetRequest: Codable, Sendable {
    public let id: String
}

public enum TasteMapHybridMapScope: String, Codable, Sendable {
    case visited, wantToGo, recommended
}

public enum TasteMapHybridMapSort: String, Codable, Sendable {
    case recent, rating, visits, distance
}

public struct TasteMapHybridMapBounds: Codable, Equatable, Sendable {
    public let north: Double
    public let south: Double
    public let east: Double
    public let west: Double
}

public struct TasteMapHybridMapFilters: Codable, Sendable {
    public let city: String?
    public let minimumScoreOutOfTen: Double?
    public let maximumSpend: Double?
    public let minimumVisitCount: Int?
    public let companion: String?
    public let cuisine: String?
    public let recommendationSource: String?
}

public struct TasteMapHybridMapCoordinate: Codable, Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
}

public struct TasteMapHybridMapBrowseRequest: Codable, Sendable {
    public let requestID: String
    public let scope: TasteMapHybridMapScope
    public let bounds: TasteMapHybridMapBounds?
    public let filters: TasteMapHybridMapFilters
    public let sort: TasteMapHybridMapSort
    public let search: String
    public let limit: Int?
    public let currentLocation: TasteMapHybridMapCoordinate?
}

public struct TasteMapHybridMapBrowseOptions: Codable, Sendable {
    public let cities: [String]
    public let companions: [String]
    public let cuisines: [String]
    public let recommendationSources: [String]
}

public struct TasteMapHybridMapScopeCounts: Codable, Equatable, Sendable {
    public let visited: Int
    public let wantToGo: Int
    public let recommended: Int
}

public struct TasteMapHybridMapBrowseResponse: Codable, Sendable {
    public let requestID: String
    public let items: [TasteMapHybridRestaurantDTO]
    public let totalCount: Int
    public let scopeCounts: TasteMapHybridMapScopeCounts
    public let options: TasteMapHybridMapBrowseOptions
}

/// WebView viewport geometry in CSS points. The Native host converts this into
/// the persistent CAPBridgeViewController coordinate space before positioning
/// the reused MapKit surface.
public struct TasteMapHybridMapSurfaceRect: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
}

public struct TasteMapHybridMapSurfaceMarkerDTO: Codable, Sendable {
    public let id: String
    public let name: String
    public let latitude: Double
    public let longitude: Double
    public let status: TasteMapHybridMapScope
    public let visitCount: Int
    public let averageRating: Double?
    public let fallbackEmoji: String
    public let image: TasteMapHybridImageDescriptor
}

public struct TasteMapHybridMapSurfaceUpdateRequest: Codable, Sendable {
    public let requestID: String
    public let visible: Bool
    public let viewportWidth: Double
    public let viewportHeight: Double
    public let frame: TasteMapHybridMapSurfaceRect
    public let reactControlExclusions: [TasteMapHybridMapSurfaceRect]
    public let scope: TasteMapHybridMapScope
    public let filters: TasteMapHybridMapFilters
    public let sort: TasteMapHybridMapSort
    public let search: String
    public let cameraFitKey: String
    public let selectedRestaurantID: String?
    public let userAvatarPresetID: String
    public let userAvatarPhotoID: String?
    public let markers: [TasteMapHybridMapSurfaceMarkerDTO]
}

public struct TasteMapHybridMapSurfaceUpdateResponse: Codable, Sendable {
    public let requestID: String
    public let surface: String
    public let persistent: Bool

    public init(requestID: String) {
        self.requestID = requestID
        surface = "mapkit"
        persistent = true
    }
}

public struct TasteMapHybridMapViewportDTO: Codable, Equatable, Sendable {
    public let bounds: TasteMapHybridMapBounds
    public let center: TasteMapHybridMapCoordinate
    public let zoom: Double
}

public struct TasteMapHybridMapSelectionEventDTO: Codable, Equatable, Sendable {
    public let restaurantID: String?
}

public struct TasteMapHybridPersonDTO: Codable, Sendable {
    public let id: String
    public let name: String
    public let city: String?
    public let avatarPhotoID: String?
    public let avatarPresetID: String
    public let isFollowing: Bool
}

public struct TasteMapHybridContentRestaurantDTO: Codable, Sendable {
    public let id: String
    public let name: String
    public let address: String
    public let city: String
    public let latitude: Double
    public let longitude: Double
    public let tags: [String]
    public let referencePrice: Double?
    public let image: TasteMapHybridImageDescriptor
}

public struct TasteMapHybridRatingSummaryDTO: Codable, Sendable {
    public let valueOutOfFive: Double?
    public let sampleCount: Int
}

public struct TasteMapHybridDiscoveryItemDTO: Codable, Sendable {
    public let id: String
    public let mode: String
    public let restaurant: TasteMapHybridContentRestaurantDTO
    public let viewerState: String
    public let sourceUser: TasteMapHybridPersonDTO?
    public let activityRating: Double?
    public let activityVisitedAt: String?
    public let interaction: TasteMapHybridActivityInteractionDTO?
    public let likedByViewer: Bool
    public let likeCount: Int
    public let commentCount: Int
    public let communityRating: TasteMapHybridRatingSummaryDTO
    public let reason: String
    public let similarityPercent: Int?
    public let sharedRestaurantCount: Int?
    public let uniqueVisitorCount: Int?
    public let wantToGoCount: Int?
    public let rank: Int
}

public struct TasteMapHybridActivityItemDTO: Codable, Sendable {
    public let id: String
    public let kind: String
    public let eventAt: String
    public let user: TasteMapHybridPersonDTO
    public let restaurant: TasteMapHybridContentRestaurantDTO
    public let visitID: String?
    public let interaction: TasteMapHybridActivityInteractionDTO?
    public let visitRating: Double?
    public let note: String?
    public let viewerState: String
    public let likedByViewer: Bool
    public let likeCount: Int
    public let commentCount: Int
}

public struct TasteMapHybridActivityInteractionDTO: Codable, Sendable {
    public let activityID: String?
    public let visitID: String
    public let authorID: String
    public let restaurantID: String
}

public struct TasteMapHybridInteractionRequest: Codable, Sendable {
    public let target: TasteMapHybridActivityInteractionDTO
}

public struct TasteMapHybridLikeRequest: Codable, Sendable {
    public let target: TasteMapHybridActivityInteractionDTO
    public let liked: Bool
}

public struct TasteMapHybridCommunityEngagementDTO: Codable, Sendable {
    public let likedByViewer: Bool
    public let likeCount: Int
    public let commentCount: Int
}

public struct TasteMapHybridCommunityCommentDTO: Codable, Sendable {
    public let id: String
    public let visitID: String
    public let body: String
    public let author: TasteMapHybridPersonDTO
    public let createdAt: String
}

public struct TasteMapHybridCommunityCommentPageDTO: Codable, Sendable {
    public let items: [TasteMapHybridCommunityCommentDTO]
    public let nextCursor: String?
}

public struct TasteMapHybridAddCommentRequest: Codable, Sendable {
    public let target: TasteMapHybridActivityInteractionDTO
    public let body: String
}

public struct TasteMapHybridCommunityCommentMutationDTO: Codable, Sendable {
    public let likedByViewer: Bool
    public let likeCount: Int
    public let commentCount: Int
    public let comment: TasteMapHybridCommunityCommentDTO
}

public struct TasteMapHybridRestaurantViewerStateRequest: Codable, Sendable {
    public let restaurantID: String
    public let wanted: Bool
}

public struct TasteMapHybridRestaurantViewerStateMutationDTO: Codable, Sendable {
    public let restaurantID: String
    public let viewerState: String
    public let updatedAt: String
}

public struct TasteMapHybridListRestaurantDTO: Codable, Sendable {
    public let id: String
    public let name: String
    public let address: String
    public let city: String
    public let position: Int
    public let note: String
    public let image: TasteMapHybridImageDescriptor
}

public struct TasteMapHybridListDTO: Codable, Sendable {
    public let id: String
    public let title: String
    public let description: String
    public let visibility: String
    public let isRanked: Bool
    public let isOwnedByViewer: Bool
    public let ownerName: String
    public let restaurantCount: Int
    public let restaurants: [TasteMapHybridListRestaurantDTO]
    public let updatedAt: String
}

public struct TasteMapHybridDiscoverySnapshotDTO: Codable, Sendable {
    public let forYou: [TasteMapHybridDiscoveryItemDTO]
    public let similarTaste: [TasteMapHybridDiscoveryItemDTO]
    public let trending: [TasteMapHybridDiscoveryItemDTO]
}

public struct TasteMapHybridCommunitySnapshotDTO: Codable, Sendable {
    public let following: [TasteMapHybridActivityItemDTO]
    public let latest: [TasteMapHybridActivityItemDTO]
}

public struct TasteMapHybridContentSnapshotDTO: Codable, Sendable {
    public let generatedAt: String
    public let discovery: TasteMapHybridDiscoverySnapshotDTO
    public let community: TasteMapHybridCommunitySnapshotDTO
    public let lists: [TasteMapHybridListDTO]
}

public struct TasteMapHybridLocationDTO: Codable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let timestamp: String
    public let horizontalAccuracy: Double
    public let accuracyMode: String
    public let authorizationStatus: String
}

public struct TasteMapHybridAcquisitionSearchRequest: Codable, Sendable {
    public let query: String
    public let city: String
}

public struct TasteMapHybridAcquisitionCandidateDTO: Codable, Sendable {
    public let id: String
    public let name: String
    public let address: String
    public let city: String
    public let district: String
    public let latitude: Double
    public let longitude: Double
    public let distanceMeters: Double?
    public let phone: String?
    public let openingHours: String?
    /// V1 compatibility descriptor for older Hybrid bundles. New bundles use
    /// `imageResolution`, whose ordering is owned by the canonical Native policy.
    public let image: TasteMapHybridImageDescriptor
    public let imageResolution: TasteMapHybridImageResolutionDTO
    public let duplicateKind: String
    public let existingRestaurantID: String?
}

public struct TasteMapHybridAcquisitionResultsDTO: Codable, Sendable {
    public let candidates: [TasteMapHybridAcquisitionCandidateDTO]
    public let location: TasteMapHybridLocationDTO?
    public let message: String?
    public let sharedImportFingerprint: String?
}

public struct TasteMapHybridManualRestaurantDraftDTO: Codable, Sendable {
    public let name: String
    public let city: String
    public let address: String
    public let latitude: Double?
    public let longitude: Double?
}

public struct TasteMapHybridAcquisitionSelectionRequest: Codable, Sendable {
    public let candidateID: String
    public let confirmProbableMatch: Bool
}

public struct TasteMapHybridAcquisitionSelectionDTO: Codable, Sendable {
    public let restaurantID: String
    public let duplicateKind: String
    public let existingRestaurantID: String?
}

public struct TasteMapHybridPremiumProductDTO: Codable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let valueDescription: String
    public let displayPrice: String
    public let period: String
    public let billingPeriodDescription: String
}

public struct TasteMapHybridPremiumActionResultDTO: Codable, Sendable {
    public let outcome: String
    public let status: TasteMapHybridJSONValue
}

public struct TasteMapHybridPermissionsStatusDTO: Codable, Equatable, Sendable {
    public let location: String
    public let camera: String
    public let photoAddOnly: String
    public let canOpenSystemSettings: Bool
}

public enum TasteMapHybridBridgeMethod: String, Codable, Sendable {
    case runtimeInfo = "runtime.info"
    case authSessionStatus = "auth.sessionStatus"
    case authSignInWithApple = "auth.signInWithApple"
    case authLogout = "auth.logout"
    case profileGetCurrent = "profile.getCurrent"
    case restaurantGet = "restaurant.get"
    case restaurantList = "restaurant.list"
    case acquisitionSearch = "acquisition.search"
    case acquisitionNearby = "acquisition.nearby"
    case acquisitionShared = "acquisition.shared"
    case acquisitionManual = "acquisition.manual"
    case acquisitionSelect = "acquisition.select"
    case mapViewport = "map.viewport"
    case mapSurfaceUpdate = "map.surface.update"
    case contentSnapshot = "content.snapshot"
    case communitySetLike = "community.setLike"
    case communityComments = "community.comments"
    case communityAddComment = "community.addComment"
    case restaurantSetWantToGo = "restaurant.setWantToGo"
    case visitContract = "visit.contract"
    case visitSave = "visit.save"
    case visitDelete = "visit.delete"
    case syncStatus = "sync.status"
    case syncRun = "sync.run"
    case hapticsSelection = "haptics.selection"
    case shareOpen = "share.open"
    case locationCurrent = "location.current"
    case photoPick = "photo.pick"
    case photoCapture = "photo.capture"
    case photoDiscard = "photo.discard"
    case photoRetry = "photo.retry"
    case premiumStatus = "premium.status"
    case premiumProducts = "premium.products"
    case premiumPurchase = "premium.purchase"
    case premiumRestore = "premium.restore"
    case premiumManage = "premium.manage"
    case permissionsStatus = "permissions.status"
    case permissionsOpenSettings = "permissions.openSettings"
    case backupOpenExport = "backup.openExport"
    case backupOpenImport = "backup.openImport"
    case accountOpenDelete = "account.openDelete"
    case navigationOpenNative = "navigation.openNative"
    case navigationOpenHybrid = "navigation.openHybrid"
    case navigationBack = "navigation.back"
    case navigationCurrent = "navigation.current"
}

public enum TasteMapHybridJSONValue: Codable, Sendable {
    case string(String), number(Double), bool(Bool), object([String: TasteMapHybridJSONValue])
    case array([TasteMapHybridJSONValue]), null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: Self].self) { self = .object(value) }
        else if let value = try? container.decode([Self].self) { self = .array(value) }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported bridge JSON value.") }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

public struct TasteMapHybridBridgeRequest: Codable, Sendable {
    public let version: Int
    public let requestId: String
    public let method: TasteMapHybridBridgeMethod
    public let payload: TasteMapHybridJSONValue
}

public struct TasteMapHybridBridgeErrorDTO: Codable, Sendable, Error {
    public let code: String
    public let message: String
    public let recoverable: Bool
    public let details: [String: TasteMapHybridJSONValue]?

    public init(
        code: String,
        message: String,
        recoverable: Bool,
        details: [String: TasteMapHybridJSONValue]?
    ) {
        self.code = code
        self.message = message
        self.recoverable = recoverable
        self.details = details
    }
}

public struct TasteMapHybridBridgeResponse: Codable, Sendable {
    public let version: Int
    public let requestId: String
    public let result: TasteMapHybridJSONValue?
    public let error: TasteMapHybridBridgeErrorDTO?
}

public enum TasteMapHybridBridgeContract {
    public static let version = 1
}
