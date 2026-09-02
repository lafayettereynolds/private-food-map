import Foundation

public enum TasteMapHybridCapability: String, Codable, CaseIterable, Sendable {
    case appleSignIn, logout, profileRead, restaurantRead, mapBrowse, visitContract, sync
    case contentRead
    case haptics, share, location, photoPicker, premium, nativeNavigation, backup, accountDelete
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
        case .map, .restaurant, .discovery, .add, .lists, .publicList, .activity,
                .roulette, .analytics, .premium, .settings: .hybrid
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
    public let companions: [String]
    public let companionIds: [String]
    public let recommendationSourceText: String
    public let partySize: Int?
    public let note: String
    public let createdAt: String
    public let updatedAt: String
}

public enum TasteMapHybridImageKind: String, Codable, Sendable {
    case nativeResource, publicOrCached, providerMerchant, foodDiningFallback
}

public struct TasteMapHybridImageDescriptor: Codable, Sendable {
    public let kind: TasteMapHybridImageKind
    public let resourceURL: String?
    public let photoID: String?
    public let stableSeed: String?
    public let accessibilityLabel: String

    public init(
        kind: TasteMapHybridImageKind,
        resourceURL: String? = nil,
        photoID: String? = nil,
        stableSeed: String? = nil,
        accessibilityLabel: String
    ) {
        self.kind = kind
        self.resourceURL = resourceURL
        self.photoID = photoID
        self.stableSeed = stableSeed
        self.accessibilityLabel = accessibilityLabel
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
    /// Native/Browser-owned viewer state. React must not infer this from a
    /// restaurant ID, user ID, or the existence of a public activity.
    public let viewerState: String
    public let editableVisitIDs: [String]
    public let capabilities: TasteMapHybridRestaurantCapabilitiesDTO
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

public struct TasteMapHybridMapBounds: Codable, Sendable {
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

public struct TasteMapHybridMapCoordinate: Codable, Sendable {
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

public struct TasteMapHybridMapBrowseResponse: Codable, Sendable {
    public let requestID: String
    public let items: [TasteMapHybridRestaurantDTO]
    public let totalCount: Int
    public let options: TasteMapHybridMapBrowseOptions
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

public struct TasteMapHybridDiscoveryItemDTO: Codable, Sendable {
    public let id: String
    public let mode: String
    public let restaurant: TasteMapHybridContentRestaurantDTO
    public let viewerState: String
    public let sourceUser: TasteMapHybridPersonDTO?
    public let activityRating: Double?
    public let activityVisitedAt: String?
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
    public let visitRating: Double?
    public let note: String?
    public let viewerState: String
    public let likedByViewer: Bool
    public let likeCount: Int
    public let commentCount: Int
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

public enum TasteMapHybridBridgeMethod: String, Codable, Sendable {
    case runtimeInfo = "runtime.info"
    case authSessionStatus = "auth.sessionStatus"
    case authSignInWithApple = "auth.signInWithApple"
    case authLogout = "auth.logout"
    case profileGetCurrent = "profile.getCurrent"
    case restaurantGet = "restaurant.get"
    case restaurantList = "restaurant.list"
    case mapViewport = "map.viewport"
    case contentSnapshot = "content.snapshot"
    case visitContract = "visit.contract"
    case syncStatus = "sync.status"
    case syncRun = "sync.run"
    case hapticsSelection = "haptics.selection"
    case shareOpen = "share.open"
    case locationCurrent = "location.current"
    case photoPick = "photo.pick"
    case premiumStatus = "premium.status"
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
