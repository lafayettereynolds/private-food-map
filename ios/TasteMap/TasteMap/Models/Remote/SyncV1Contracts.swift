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
    let rating: Double?
    let note: String?
    let myActualSpend: Double?
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?
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
