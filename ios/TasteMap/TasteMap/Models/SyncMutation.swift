import Foundation
import SwiftData

enum SyncEntityType: String, Codable, Sendable {
    case restaurant
    case visit
    case dish
    case visitDish
    case photo
    case companion
    case recommendationSource
    case profile
    case restaurantList
    case restaurantListItem

    var dependencyPriority: Int {
        switch self {
        case .restaurant, .companion, .recommendationSource, .restaurantList: 0
        case .visit, .restaurantListItem: 1
        case .dish: 2
        case .visitDish: 3
        case .photo: 4
        case .profile: 5
        }
    }

    func dependencyPriority(for operation: SyncMutationOperation) -> Int {
        operation == .delete ? 10 - dependencyPriority : dependencyPriority
    }
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
    var ownerUserID: String = LocalAccountOwner.legacyQuarantine
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
        ownerUserID: String = LocalAccountOwner.guest,
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
        self.ownerUserID = LocalAccountOwner.normalized(ownerUserID)
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
