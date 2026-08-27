import Foundation

enum SyncV1Contract {
    static let apiVersion = 1
    static let schemaVersion = 1
}

struct VisitSyncContractV1: Codable, Equatable {
    let schemaVersion: Int
    let id: String
    let userId: String
    let restaurantId: String
    let visitedAt: String
    let diningMode: DiningMode
    let partySize: Int?
    let rating: Double?
    let note: String?
    let myActualSpend: Double?
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?
}

private extension VisitSyncContractV1 {
    enum CodingKeys: String, CodingKey {
        case schemaVersion, id, userId, restaurantId, visitedAt, diningMode, partySize
        case rating, note, myActualSpend, createdAt, updatedAt, deletedAt
    }
}

extension VisitSyncContractV1 {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        id = try container.decode(String.self, forKey: .id)
        userId = try container.decode(String.self, forKey: .userId)
        restaurantId = try container.decode(String.self, forKey: .restaurantId)
        visitedAt = try container.decode(String.self, forKey: .visitedAt)
        diningMode = try container.decodeIfPresent(DiningMode.self, forKey: .diningMode) ?? .dineIn
        partySize = try container.decodeIfPresent(Int.self, forKey: .partySize)
        if let partySize, partySize < 1 {
            throw DecodingError.dataCorruptedError(
                forKey: .partySize,
                in: container,
                debugDescription: "partySize must be null or a positive integer."
            )
        }
        rating = try container.decode(Double?.self, forKey: .rating)
        note = try container.decode(String?.self, forKey: .note)
        myActualSpend = try container.decode(Double?.self, forKey: .myActualSpend)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        deletedAt = try container.decode(String?.self, forKey: .deletedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encode(restaurantId, forKey: .restaurantId)
        try container.encode(visitedAt, forKey: .visitedAt)
        try container.encode(diningMode, forKey: .diningMode)
        try container.encode(partySize, forKey: .partySize)
        try container.encode(rating, forKey: .rating)
        try container.encode(note, forKey: .note)
        try container.encode(myActualSpend, forKey: .myActualSpend)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(deletedAt, forKey: .deletedAt)
    }
}

enum SyncMutationPayload: Encodable {
    case restaurant(RestaurantJSONContractV1)
    case visit(VisitSyncContractV1)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .restaurant(let restaurant): try container.encode(restaurant)
        case .visit(let visit): try container.encode(visit)
        }
    }
}

struct SyncMutationRequestV1: Encodable {
    let mutationId: String
    let entityType: SyncEntityType
    let entityId: String
    let operation: SyncMutationOperation
    let baseVersion: Int64
    let clientTimestamp: String
    let payload: SyncMutationPayload?
}

struct SyncPushRequestV1: Encodable {
    let apiVersion = SyncV1Contract.apiVersion
    let schemaVersion = SyncV1Contract.schemaVersion
    let mutations: [SyncMutationRequestV1]
}

struct SyncMutationAcknowledgementV1: Codable, Equatable {
    enum Status: String, Codable {
        case applied
        case conflict
    }

    let mutationId: String
    let entityType: SyncEntityType
    let entityId: String
    let status: Status
    let duplicate: Bool
    let serverVersion: Int64
    let revision: Int64?
    let conflictReason: String?
}

struct SyncPushResponseV1: Decodable {
    let apiVersion: Int
    let acknowledgements: [SyncMutationAcknowledgementV1]
    let serverTime: String
}

struct RestaurantSyncRecordEnvelopeV1: Decodable {
    let serverVersion: Int64
    let record: RestaurantJSONContractV1
}

struct VisitSyncRecordEnvelopeV1: Decodable {
    let serverVersion: Int64
    let record: VisitSyncContractV1
}

struct SyncTombstoneV1: Codable, Equatable {
    let entityType: SyncEntityType
    let entityId: String
    let serverVersion: Int64
    let deletedAt: String
}

struct SyncPullResponseV1: Decodable {
    let apiVersion: Int
    let schemaVersion: Int
    let restaurants: [RestaurantSyncRecordEnvelopeV1]
    let visits: [VisitSyncRecordEnvelopeV1]
    let tombstones: [SyncTombstoneV1]
    let nextCursor: String
    let hasMore: Bool
    let serverTime: String
}
