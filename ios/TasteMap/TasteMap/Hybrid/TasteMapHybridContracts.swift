import Foundation

public enum TasteMapHybridCapability: String, Codable, CaseIterable, Sendable {
    case appleSignIn, logout, profileRead, restaurantRead, visitContract, sync
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
}

public struct TasteMapHybridRestaurantListRequest: Codable, Sendable {
    public let ids: [String]?
    public let status: String?
    public let limit: Int?
}

public struct TasteMapHybridRestaurantGetRequest: Codable, Sendable {
    public let id: String
}

public enum TasteMapHybridBridgeMethod: String, Codable, Sendable {
    case runtimeInfo = "runtime.info"
    case authSessionStatus = "auth.sessionStatus"
    case authSignInWithApple = "auth.signInWithApple"
    case authLogout = "auth.logout"
    case profileGetCurrent = "profile.getCurrent"
    case restaurantGet = "restaurant.get"
    case restaurantList = "restaurant.list"
    case visitContract = "visit.contract"
    case syncStatus = "sync.status"
    case syncRun = "sync.run"
    case hapticsSelection = "haptics.selection"
    case shareOpen = "share.open"
    case locationCurrent = "location.current"
    case photoPick = "photo.pick"
    case premiumStatus = "premium.status"
    case navigationOpenNative = "navigation.openNative"
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
