import Foundation
import SwiftData

enum SyncEntityType: String, Codable, Sendable {
    case restaurant
    case visit
}

enum SyncMutationOperation: String, Codable, Sendable {
    case upsert
    case delete
}

enum SyncMutationState: String, Codable, Sendable {
    case queued
    case uploading
    case conflicted
    case failed
}

@Model
final class SyncMutation {
    @Attribute(.unique) var mutationID: UUID
    private var entityTypeValue: String
    var entityID: String
    private var operationValue: String
    var timestamp: Date
    var retryCount: Int
    var payload: Data?
    var baseVersion: Int64
    private var stateValue: String
    var nextRetryAt: Date?
    var lastError: String?

    var entityType: SyncEntityType {
        get { SyncEntityType(rawValue: entityTypeValue) ?? .restaurant }
        set { entityTypeValue = newValue.rawValue }
    }

    var operation: SyncMutationOperation {
        get { SyncMutationOperation(rawValue: operationValue) ?? .upsert }
        set { operationValue = newValue.rawValue }
    }

    var state: SyncMutationState {
        get { SyncMutationState(rawValue: stateValue) ?? .queued }
        set { stateValue = newValue.rawValue }
    }

    init(
        mutationID: UUID = UUID(),
        entityType: SyncEntityType,
        entityID: String,
        operation: SyncMutationOperation,
        timestamp: Date = .now,
        retryCount: Int = 0,
        payload: Data?,
        baseVersion: Int64,
        state: SyncMutationState = .queued,
        nextRetryAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.mutationID = mutationID
        self.entityTypeValue = entityType.rawValue
        self.entityID = entityID
        self.operationValue = operation.rawValue
        self.timestamp = timestamp
        self.retryCount = retryCount
        self.payload = payload
        self.baseVersion = baseVersion
        self.stateValue = state.rawValue
        self.nextRetryAt = nextRetryAt
        self.lastError = lastError
    }
}
