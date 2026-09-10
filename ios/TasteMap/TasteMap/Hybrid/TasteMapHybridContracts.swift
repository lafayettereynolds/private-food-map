import Foundation

public enum TasteMapHybridCapability: String, Codable, CaseIterable, Sendable {
    case appleSignIn, logout, profileRead, restaurantRead, restaurantAcquisition, mapBrowse, visitContract, sync
    case contentRead
    case listsRead, listShare
    case discoveryPage
    case discoveryCityPage
    case recommendationPreferences
    case communityInteraction, restaurantViewerState
    case haptics, share, location, photoPicker, premium, permissions, nativeNavigation, backup, accountDelete, referrals
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
    case hybridPrimary = "HYBRID_PRIMARY"
#if DEBUG || TASTEMAP_PRIVATE_PREVIEW
    case hybridDevelopment = "HYBRID_DEVELOPMENT"
#endif
}

public enum TasteMapHybridRouteSurface: String, Codable, CaseIterable, Sendable {
    case map, discovery, add, profile, restaurant, visit, visitEdit, lists, publicList, activity
    case roulette, analytics, premium, settings
    case acquisitionNative, listManage, premiumStore, settingsNative, socialNative
    case accountSettings, dataBackup, dataClear, privacySettings, permissions, storage
    case helpSettings, aboutSettings, accountDelete
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

/// Additive command metadata; it is not part of a route's identity/equality.
public struct TasteMapHybridNavigationOpenOptions: Decodable, Sendable {
    public let replaceCurrent: Bool?
}

public enum TasteMapHybridRouteError: Error, Equatable, Sendable {
    case missingIdentifier, invalidIdentifier, malformedURL, unsupportedRoute
}

public struct TasteMapHybridNavigationStateDTO: Codable, Equatable, Sendable {
    public let route: TasteMapHybridRouteDTO
    public let owner: TasteMapHybridRouteOwner
    public let canGoBack: Bool
    public let sourceRequestID: String?
    public let completedAction: TasteMapHybridRouteSurface?

    public init(route: TasteMapHybridRouteDTO, canGoBack: Bool, sourceRequestID: String? = nil, completedAction: TasteMapHybridRouteSurface? = nil) {
        self.route = route
        self.owner = route.owner
        self.canGoBack = canGoBack
        self.sourceRequestID = sourceRequestID
        self.completedAction = completedAction
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
    case mapRestaurantGroupSelected = "map.restaurant.groupSelected"
    case dataChanged = "data.changed"
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
    public let deletedRestaurantID: String?

    public init(
        restaurantID: String,
        visitID: String,
        updatedAt: String,
        photoWarning: String? = nil,
        deletedRestaurantID: String? = nil
    ) {
        self.restaurantID = restaurantID
        self.visitID = visitID
        self.updatedAt = updatedAt
        self.photoWarning = photoWarning
        self.deletedRestaurantID = deletedRestaurantID
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
    /// Exact owner-selected Restaurant Emoji. It rides on the fallback visual
    /// descriptor because it is not an image resource and must not be cached as
    /// Provider artwork.
    public let preferredEmoji: String?
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
        preferredEmoji: String? = nil,
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
        self.preferredEmoji = preferredEmoji
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
    public var websiteUrl: String? = nil
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
    public let markerType: String?
    public let markerEmoji: String?
    /// Actual dining imagery, independent from the owner's custom avatar.
    public var contentImage: TasteMapHybridImageDescriptor? = nil
    public var contentImageResolution: TasteMapHybridImageResolutionDTO? = nil
}

public struct TasteMapHybridProfileDTO: Codable, Sendable {
    public let user: TasteMapHybridUserDTO
    public let restaurants: [TasteMapHybridRestaurantDTO]
    public let followerCount: Int
    public let followingCount: Int
    public var analyticsIdentity: TasteMapHybridAnalyticsIdentityDTO? = nil
}

public struct TasteMapHybridAnalyticsDirectoryEntryDTO: Codable, Sendable {
    public let id: String
    public let ownerUserID: String
    public let displayName: String
    public let identifiers: [String]
    public let updatedAt: String
    public let deletedAt: String?
    public var sourceType: String? = nil
}

public struct TasteMapHybridAnalyticsVisitSourceLinkDTO: Codable, Sendable {
    public let visitID: String
    public let sourceID: String?
}

public struct TasteMapHybridAnalyticsIdentityDTO: Codable, Sendable {
    public let ownerUserID: String
    public let recordOwnerID: String
    public let companions: [TasteMapHybridAnalyticsDirectoryEntryDTO]?
    public let sources: [TasteMapHybridAnalyticsDirectoryEntryDTO]?
    public let visitSourceLinks: [TasteMapHybridAnalyticsVisitSourceLinkDTO]?
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
    public var deletablePhotoIDs: [String]? = nil
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
    public let scoreBands: [Int]?
    public let maximumSpend: Double?
    public let priceRange: String?
    public let minimumVisitCount: Int?
    public let diningMode: String?
    public let queueDuration: String?
    public let diningOccasions: [String]?
    public let visitPeriod: String?
    public let distanceKilometers: Int?
    public let companion: String?
    public let cuisine: String?
    public let recommendationSourceType: String?
    public let recommendationSource: String?

    public init(
        city: String? = nil,
        minimumScoreOutOfTen: Double? = nil,
        scoreBands: [Int]? = nil,
        maximumSpend: Double? = nil,
        priceRange: String? = nil,
        minimumVisitCount: Int? = nil,
        diningMode: String? = nil,
        queueDuration: String? = nil,
        diningOccasions: [String]? = nil,
        visitPeriod: String? = nil,
        distanceKilometers: Int? = nil,
        companion: String? = nil,
        cuisine: String? = nil,
        recommendationSourceType: String? = nil,
        recommendationSource: String? = nil
    ) {
        self.city = city
        self.minimumScoreOutOfTen = minimumScoreOutOfTen
        self.scoreBands = scoreBands
        self.maximumSpend = maximumSpend
        self.priceRange = priceRange
        self.minimumVisitCount = minimumVisitCount
        self.diningMode = diningMode
        self.queueDuration = queueDuration
        self.diningOccasions = diningOccasions
        self.visitPeriod = visitPeriod
        self.distanceKilometers = distanceKilometers
        self.companion = companion
        self.cuisine = cuisine
        self.recommendationSourceType = recommendationSourceType
        self.recommendationSource = recommendationSource
    }
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
    public let recommendationRank: Int?
    public let visitCount: Int
    public let averageRating: Double?
    public let fallbackEmoji: String
    public let image: TasteMapHybridImageDescriptor
}

public struct TasteMapHybridTasteDataProgressDTO: Codable, Equatable, Sendable {
    public let displayCount: Int
    public let target: Int
    public let message: String
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
    public let tasteDataProgress: TasteMapHybridTasteDataProgressDTO?
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

/// Native presentation gate, independent of the persistent MapKit model.
/// Revisions are allocated at bridge receipt, before any asynchronous work.
struct TasteMapHybridMapPresentationState {
    private(set) var latestRevision: UInt64 = 0
    var routeAllowsMap = false
    private(set) var requestedVisible = false
    var isVisible: Bool { routeAllowsMap && requestedVisible }

    mutating func receiveUpdate() -> UInt64 {
        latestRevision += 1
        return latestRevision
    }

    func isCurrent(_ revision: UInt64) -> Bool { revision == latestRevision }

    @discardableResult
    mutating func apply(visible: Bool, revision: UInt64) -> Bool {
        guard isCurrent(revision) else { return false }
        requestedVisible = visible
        return true
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

public struct TasteMapHybridMapGroupSelectionEventDTO: Codable, Equatable, Sendable {
    public let restaurantIDs: [String]
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
    public var contentImage: TasteMapHybridImageDescriptor? = nil
    public var contentImageResolution: TasteMapHybridImageResolutionDTO? = nil

    public init(id: String, name: String, address: String, city: String,
                latitude: Double, longitude: Double, tags: [String], referencePrice: Double?,
                image: TasteMapHybridImageDescriptor,
                contentImage: TasteMapHybridImageDescriptor? = nil,
                contentImageResolution: TasteMapHybridImageResolutionDTO? = nil) {
        self.id = id; self.name = name; self.address = address; self.city = city
        self.latitude = latitude; self.longitude = longitude; self.tags = tags
        self.referencePrice = referencePrice; self.image = image
        // Content producers already apply the Native actual-photo gate. Keep
        // this attested channel distinct from legacy Restaurant avatar fields.
        self.contentImage = contentImage ?? image
        self.contentImageResolution = contentImageResolution
    }
}

public struct TasteMapHybridRatingSummaryDTO: Codable, Sendable {
    public let valueOutOfFive: Double?
    public let sampleCount: Int
}

/// Authorized recommendation explanation evidence, on the product ten-point scale.
/// Additive within bridge v1; absence must not be synthesized from display text.
public struct TasteMapHybridDiscoveryReasonEvidenceDTO: Codable, Equatable, Sendable {
    public let sampleCount: Int
    public var referenceRestaurantID: String? = nil
    public var dimensions: [String]? = nil
    public var meanOutOfTen: Double? = nil
    public var windowDays: Int? = nil
    public var source: String? = nil
    public var participants: [TasteMapHybridRecommendationReasonParticipantDTO]? = nil
    public var participantCount: Int? = nil
    public var participantsTruncated: Bool? = nil
    public var missingFields: [String]? = nil
}

/// Already-authorized owner evidence from the response. Never expanded by looking
/// up another account's local restaurants or by parsing explanation text.
public struct TasteMapHybridRecommendationReasonParticipantDTO: Codable, Equatable, Sendable {
    public let restaurantID: String
    public let restaurantName: String?
    public let restaurantRecordIDs: [String]
    public let visitIDs: [String]
    public let fields: Fields

    public struct Fields: Codable, Equatable, Sendable {
        public let tags: [String]
        public let ratingCount: Int
        public let meanOutOfTen: Double?
        public let referenceRatingOutOfTen: Double?
        public let visitCount: Int
        public let firstVisitedAt: String?
        public let lastVisitedAt: String?
        public let recordedPricePerPerson: Double?
        public let priceCurrency: String?
    }
}

public struct TasteMapHybridDiscoveryReasonDTO: Codable, Sendable {
    public let code: String
    public let text: String
    public var evidence: TasteMapHybridDiscoveryReasonEvidenceDTO? = nil
}

/// Optional evaluated-model output. No current producer fabricates this from match scores.
public struct TasteMapCalibratedLikeProbabilityDTO: Codable, Equatable, Sendable {
    public let value: Double
    public let modelVersion: String
    public let calibrationVersion: String
    public let calibrationStatus: String
    public let evidenceStatus: String
    public let positiveFeedbackDefinition: String
    public let definitionVersion: String
    public let definitionStatus: String
    public let validationSampleCount: Int
    public let validUntil: String

    public func isDisplayable(now: Date = Date()) -> Bool {
        let formatter = ISO8601DateFormatter()
        let standardDate = formatter.date(from: validUntil)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = standardDate ?? formatter.date(from: validUntil)
        let nonempty = [modelVersion, calibrationVersion, positiveFeedbackDefinition, definitionVersion]
            .allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return value.isFinite && (0...1).contains(value) && nonempty
            && calibrationStatus == "validated" && evidenceStatus == "sufficient"
            && definitionStatus == "approved" && validationSampleCount > 0
            && date.map { $0 > now } == true
    }
}

public struct TasteMapDiscoveryEvidenceAvailabilityDTO: Codable, Equatable, Sendable {
    public let personalRatedRestaurantCount: Int
    public let personalScoreStandardDeviationOutOfTen: Double
    public let personalEvidence: String
    public let localDirectRestaurantCount: Int

    /// Missing or contradictory evidence stays unknown; membership is a separate gate.
    public var similarTasteEmptyMessage: String {
        guard personalRatedRestaurantCount >= 0, localDirectRestaurantCount >= 0,
              personalScoreStandardDeviationOutOfTen.isFinite,
              personalScoreStandardDeviationOutOfTen >= 0 else { return Self.unknownMessage }
        if personalEvidence == "insufficient" {
            if personalRatedRestaurantCount < 5 {
                return "目前有 \(personalRatedRestaurantCount) 家不同餐厅的有效评分，还需至少 \(5 - personalRatedRestaurantCount) 家，才能开始寻找共同评分的同味用户。请补充真实到访和评分；达到数量也不保证已有合格同味用户。"
            }
            guard personalScoreStandardDeviationOutOfTen < 0.1 else { return Self.unknownMessage }
            return "你已评过 \(personalRatedRestaurantCount) 家不同餐厅，但代表评分几乎没有变化，暂时无法计算可靠同味度。可以继续补充真实体验，不需要为了匹配而刻意改分。"
        }
        if personalEvidence == "eligible", personalRatedRestaurantCount >= 5,
           personalScoreStandardDeviationOutOfTen >= 0.1, localDirectRestaurantCount == 0 {
            return "你的个人评分已达到初始样本要求，但当前城市尚无可推荐的直接同味到访记录。可以主动切换城市；你的长期口味仍可用于“为你推荐”。"
        }
        return Self.unknownMessage
    }
    public static let unknownMessage = "当前结果尚不能确认是个人记录不足，还是当地同味覆盖不足。可重试核对、切换城市，或先查看“为你推荐”；不会用普通热门餐厅冒充同味推荐。"

    public var recoveryAction: String {
        guard similarTasteEmptyMessage != Self.unknownMessage else { return "retry" }
        return personalEvidence == "insufficient" ? "record" : "city"
    }
    public var emptyTitle: String {
        switch recoveryAction {
        case "record": return personalRatedRestaurantCount < 5 ? "还需要更多餐厅评分" : "现有评分还不能区分口味偏好"
        case "city": return "当前城市尚无足够的直接同味记录"
        default: return "暂未找到可展示的同味推荐"
        }
    }
}

public struct TasteMapDiscoveryTasteEvidenceDTO: Codable, Equatable, Sendable {
    public struct User: Codable, Equatable, Sendable {
        public let userId: String
        public let displayName: String
        public let bio: String?
        public let city: String?
        public let avatarPhotoId: String?
        public let avatarPresetId: String
        public let friendshipId: String?
        public let friendshipState: String
        public let isFollowing: Bool
    }
    public struct Record: Codable, Equatable, Sendable {
        public let user: User
        public let visitId: String
        public let visitedAt: String
        public let rating: Double?
    }
    public let evidenceState: String
    public let sharedRestaurantCount: Int
    public let supporterCount: Int
    public let aggregation: String
    public let latestVisibleVisitAt: String
    public let records: [Record]
}

public struct TasteMapPredictedLikingDTO: Codable, Equatable, Sendable {
    public let scoreOutOfTen: Double?
    public let ratedRestaurantCount: Int
    public let ratedVisitCount: Int
    public let matchedRestaurantCount: Int
    public let method: String
}

public struct TasteMapHybridDiscoveryItemDTO: Codable, Sendable {
    public let id: String
    public let mode: String
    public let restaurant: TasteMapHybridContentRestaurantDTO
    public var activityImages: [TasteMapHybridImageDescriptor]? = nil
    public let viewerState: String
    public let sourceUser: TasteMapHybridPersonDTO?
    public let activityRating: Double?
    public let activityVisitedAt: String?
    public let interaction: TasteMapHybridActivityInteractionDTO?
    public let likedByViewer: Bool
    public let likeCount: Int
    public let commentCount: Int
    public let communityRating: TasteMapHybridRatingSummaryDTO
    public let personalTastePercent: Int?
    public var predictedLiking: TasteMapPredictedLikingDTO? = nil
    public var calibratedLikeProbability: TasteMapCalibratedLikeProbabilityDTO? = nil
    public let reasons: [TasteMapHybridDiscoveryReasonDTO]
    public let reason: String
    public let similarityPercent: Int?
    public let sharedRestaurantCount: Int?
    public let trendWindowDays: Int?
    public let uniqueVisitorCount: Int?
    public let wantToGoCount: Int?
    public let rank: Int
    public var tasteEvidence: TasteMapDiscoveryTasteEvidenceDTO? = nil
}

public struct TasteMapHybridActivityItemDTO: Codable, Sendable {
    public let id: String
    public let kind: String
    public let eventAt: String
    public let user: TasteMapHybridPersonDTO
    public let restaurant: TasteMapHybridContentRestaurantDTO
    public var activityImages: [TasteMapHybridImageDescriptor]? = nil
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

public struct TasteMapHybridUGCTarget: Codable, Sendable {
    public let type: String
    public let id: String
}
public struct TasteMapHybridUGCRequest: Codable, Sendable {
    public let target: TasteMapHybridUGCTarget
    public let reason: String?
    public let details: String?
    public let requestID: String?
}
public struct TasteMapHybridUGCSafetyCapabilities: Codable, Sendable {
    public let ownerID: String
    public let canReport: Bool
    public let canBlock: Bool
    public let canDelete: Bool
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

public struct TasteMapHybridRestaurantAvatarRequest: Codable, Sendable {
    public let restaurantID: String
    public let kind: String
    public let photoID: String?
    public let emoji: String?
}

public struct TasteMapHybridRestaurantAvatarMutationDTO: Codable, Sendable {
    public let restaurantID: String
    public let markerType: String
    public let markerEmoji: String
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
    public var coordinate: TasteMapHybridMapCoordinate? = nil
    public var rating: TasteMapHybridListRatingDTO? = nil
}

public struct TasteMapHybridListRatingDTO: Codable, Sendable {
    public enum Source: String, Codable, Sendable { case viewer, `public` }
    public let valueOutOfTen: Double
    public let source: Source
    public let sampleCount: Int

    public init?(valueOutOfTen: Double?, source: Source, sampleCount: Int) {
        guard let valueOutOfTen, valueOutOfTen.isFinite, valueOutOfTen > 0,
              valueOutOfTen <= 10, sampleCount > 0 else { return nil }
        self.valueOutOfTen = valueOutOfTen
        self.source = source
        self.sampleCount = sampleCount
    }
}

public struct TasteMapHybridListGetRequest: Codable, Sendable {
    public let id: String
    public var cursor: String? = nil
}

public struct TasteMapHybridListPageDTO: Codable, Sendable {
    public let list: TasteMapHybridListDTO
    public let nextCursor: String?
    public let generatedAt: String
}

public struct TasteMapHybridListShareLinkDTO: Codable, Sendable {
    public let url: String
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

public struct TasteMapHybridContentSnapshotRequest: Codable, Sendable {
    public var forceRefresh: Bool? = nil
}

public enum TasteMapHybridDiscoveryMode: String, Codable, Sendable {
    case forYou = "for_you", similarTaste = "similar_taste", trending
}

public struct TasteMapHybridDiscoveryPageRequest: Codable, Sendable {
    public let mode: TasteMapHybridDiscoveryMode
    public let city: String
    public let windowDays: Int
    public var cursor: String? = nil
    public var snapshotID: String? = nil
    public var forceRefresh: Bool? = nil
    public var filters: TasteMapDiscoveryFilters? = nil
    public var sort: String? = nil
    public var preferences: TasteMapDiscoverySessionPreferences? = nil

    public init(mode: TasteMapHybridDiscoveryMode, city: String, windowDays: Int,
                cursor: String? = nil, snapshotID: String? = nil, forceRefresh: Bool? = nil,
                filters: TasteMapDiscoveryFilters? = nil, sort: String? = nil, preferences: TasteMapDiscoverySessionPreferences? = nil) {
        self.mode = mode; self.city = city; self.windowDays = windowDays
        self.cursor = cursor; self.snapshotID = snapshotID; self.forceRefresh = forceRefresh
        self.filters = filters; self.sort = sort; self.preferences = preferences
    }
}

public enum TasteMapHybridDiscoveryPagination: String, Codable, Sendable {
    case more, complete, unknown
}

public struct TasteMapHybridDiscoveryCityPageRequest: Codable, Sendable {
    public let mode: String
    public let city: String
    public var windowDays: Int? = nil
    public var cursor: String? = nil
    public var snapshotID: String? = nil
    public var forceRefresh: Bool? = nil
    public var filters: TasteMapDiscoveryFilters? = nil
    public var sort: String? = nil
    public var preferences: TasteMapDiscoverySessionPreferences? = nil
}

public struct TasteMapHybridDiscoveryCityPageDTO: Codable, Sendable {
    public var dataSource: String? = nil
    public let version: Int
    public let mode: String
    public let requestedCity: String
    public let resolvedCity: String
    public let windowDays: Int
    public let snapshotID: String?
    public let generatedAt: String?
    public let discoveryItems: [TasteMapHybridDiscoveryItemDTO]
    public let activityItems: [TasteMapHybridActivityItemDTO]
    public let nextCursor: String?
    public let pagination: TasteMapHybridDiscoveryPagination
    public let refreshStatus: TasteMapHybridDiscoveryRefreshStatusDTO
    public let engagementState: String
    public let interactionsAvailable: Bool
    public var evidenceAvailability: TasteMapDiscoveryEvidenceAvailabilityDTO? = nil
    public var appliedQuery: TasteMapDiscoveryAppliedQuery? = nil
    public var filterCapabilities: TasteMapDiscoveryFilterCapabilities? = nil
    public var filterTaxonomy: TasteMapDiscoveryFilterTaxonomy? = nil
}

/// Additive v1 page channel, independent of content.snapshot. Items are the
/// accumulated accepted pages of this snapshot, never a complete-city count.
public struct TasteMapHybridDiscoveryPageDTO: Codable, Sendable {
    public let version: Int
    public let mode: TasteMapHybridDiscoveryMode
    public let requestedCity: String
    public let resolvedCity: String
    public let windowDays: Int
    public let snapshotID: String?
    public let generatedAt: String?
    public let items: [TasteMapHybridDiscoveryItemDTO]
    public let nextCursor: String?
    public let pagination: TasteMapHybridDiscoveryPagination
    public let refreshStatus: TasteMapHybridDiscoveryRefreshStatusDTO
    /// The upstream page does not contain engagement counts. Its old item
    /// zero defaults must not be presented as authoritative by future consumers.
    public let engagementState: String
    public let interactionsAvailable: Bool
    public var evidenceAvailability: TasteMapDiscoveryEvidenceAvailabilityDTO? = nil
    public var appliedQuery: TasteMapDiscoveryAppliedQuery? = nil
    public var filterCapabilities: TasteMapDiscoveryFilterCapabilities? = nil
    public var filterTaxonomy: TasteMapDiscoveryFilterTaxonomy? = nil
}

public enum TasteMapHybridDiscoveryFreshness: String, Codable, Sendable {
    case fresh, cached, unavailable, restricted
}

public struct TasteMapHybridDiscoveryRefreshStatusDTO: Codable, Sendable {
    public let state: TasteMapHybridDiscoveryFreshness
    public let city: String
    public let windowDays: Int
    public let sourceGeneratedAt: String?
    public let attemptedAt: String
    public let issue: TasteMapHybridBridgeErrorDTO?

    public init(state: TasteMapHybridDiscoveryFreshness, city: String, windowDays: Int,
                sourceGeneratedAt: String?, attemptedAt: String, issue: TasteMapHybridBridgeErrorDTO?) {
        self.state = state
        self.city = city
        self.windowDays = windowDays
        self.sourceGeneratedAt = sourceGeneratedAt
        self.attemptedAt = attemptedAt
        self.issue = issue
    }
}

public struct TasteMapHybridDiscoverySnapshotDTO: Codable, Sendable {
    public let forYou: [TasteMapHybridDiscoveryItemDTO]
    public let similarTaste: [TasteMapHybridDiscoveryItemDTO]
    public let trending: [TasteMapHybridDiscoveryItemDTO]
    /// Optional within bridge v1; missing means legacy/unknown, never proven fresh.
    public var refreshStatus: [String: TasteMapHybridDiscoveryRefreshStatusDTO]? = nil
    public var evidenceAvailability: [String: TasteMapDiscoveryEvidenceAvailabilityDTO]? = nil
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
    public var detectedCity: String? = nil
}

public struct TasteMapHybridAcquisitionSearchRequest: Codable, Sendable {
    public let query: String
    public let city: String
    public var cursor: String? = nil
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
    public var websiteUrl: String? = nil
    public let openingHours: String?
    public let categoryHints: [String]
    /// V1 compatibility descriptor for older Hybrid bundles. New bundles use
    /// `imageResolution`, whose ordering is owned by the canonical Native policy.
    public let image: TasteMapHybridImageDescriptor
    public let imageResolution: TasteMapHybridImageResolutionDTO
    public let duplicateKind: String
    public let existingRestaurantID: String?
}

public struct TasteMapHybridAcquisitionResultsDTO: Codable, Sendable {
    /// Nearby carries the complete accepted 3 km snapshot; batching is UI-only.
    public let candidates: [TasteMapHybridAcquisitionCandidateDTO]
    public let location: TasteMapHybridLocationDTO?
    public let detectedCity: String?
    public let message: String?
    public let sharedImportFingerprint: String?
    public let nextCursor: String?

    public init(
        candidates: [TasteMapHybridAcquisitionCandidateDTO],
        location: TasteMapHybridLocationDTO?,
        detectedCity: String? = nil,
        message: String?,
        sharedImportFingerprint: String?,
        nextCursor: String? = nil
    ) {
        self.candidates = candidates
        self.location = location
        self.detectedCity = detectedCity
        self.message = message
        self.sharedImportFingerprint = sharedImportFingerprint
        self.nextCursor = nextCursor
    }
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
    case discoveryPage = "discovery.page"
    case discoveryCityPage = "discovery.cityPage"
    case recommendationsPreference = "recommendations.preference"
    case listsGet = "lists.get"
    case listsCreateShareLink = "lists.createShareLink"
    case communitySetLike = "community.setLike"
    case communityComments = "community.comments"
    case communityAddComment = "community.addComment"
    case communitySafety = "community.safety"
    case communityReport = "community.report"
    case communityBlock = "community.block"
    case communityDeleteComment = "community.deleteComment"
    case restaurantSetWantToGo = "restaurant.setWantToGo"
    case restaurantSetAvatar = "restaurant.setAvatar"
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
    case premiumTrialEligibility = "premium.trialEligibility"
    case premiumClaimTrial = "premium.claimTrial"
    case premiumStatus = "premium.status"
    case premiumProducts = "premium.products"
    case premiumPurchase = "premium.purchase"
    case premiumRestore = "premium.restore"
    case premiumManage = "premium.manage"
    case referralsDashboard = "referrals.dashboard"
    case directoryDashboard = "directory.dashboard"
    case directoryMutate = "directory.mutate"
    case directoryRespond = "directory.respond"
    case directorySearchUsers = "directory.searchUsers"
    case referralsPrepareRegistration = "referrals.prepareRegistration"
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
