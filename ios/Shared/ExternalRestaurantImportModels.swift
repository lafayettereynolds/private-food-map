import Foundation

public enum ExternalRestaurantImportSource: String, Codable, Sendable {
    case url
    case sharedText
}

public struct PendingExternalRestaurantImport: Codable, Identifiable, Sendable {
    public let id: UUID
    public let source: ExternalRestaurantImportSource
    public let payload: String
    public let normalizedFingerprint: String
    public let ownerSubject: String?
    public let createdAt: Date
    public var attemptCount: Int
    public var lastError: String?

    public init(
        id: UUID = UUID(),
        source: ExternalRestaurantImportSource,
        payload: String,
        normalizedFingerprint: String,
        ownerSubject: String?,
        createdAt: Date = Date(),
        attemptCount: Int = 0,
        lastError: String? = nil
    ) {
        self.id = id
        self.source = source
        self.payload = payload
        self.normalizedFingerprint = normalizedFingerprint
        self.ownerSubject = ownerSubject
        self.createdAt = createdAt
        self.attemptCount = attemptCount
        self.lastError = lastError
    }
}

public struct ExternalRestaurantResolveRequest: Encodable, Sendable {
    public let url: String?
    public let text: String?
    public let currentCity: String?

    public init(pending: PendingExternalRestaurantImport, currentCity: String?) {
        url = pending.source == .url ? pending.payload : nil
        text = pending.source == .sharedText ? pending.payload : nil
        self.currentCity = currentCity
    }
}

public enum ExternalRestaurantMatchConfidence: String, Decodable, Sendable {
    case high = "HIGH"
    case medium = "MEDIUM"
    case low = "LOW"
    case none = "NONE"
}

public struct ExternalRestaurantCandidate: Decodable, Identifiable, Sendable {
    public var id: String { restaurantId ?? amapPoiId }
    public let restaurantId: String?
    public let amapPoiId: String
    public let name: String
    public let address: String
    public let city: String
    public let latitude: Double
    public let longitude: Double
    public let merchantImageUrl: String?
    public let phone: String?
    public let openingHours: String?
}

public struct ExternalRestaurantSearchFallback: Decodable, Sendable {
    public let keyword: String
    public let city: String
    public let addressHint: String
    public let latitude: Double?
    public let longitude: Double?
}

public struct ExternalRestaurantResolveResponse: Decodable, Sendable {
    public let sourceType: String
    public let confidence: ExternalRestaurantMatchConfidence
    public let matchType: String
    public let candidates: [ExternalRestaurantCandidate]
    public let searchFallback: ExternalRestaurantSearchFallback?
    public let sourceSuggestion: String
    public let message: String
}
