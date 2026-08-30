import Foundation
import SwiftData

/// A local-first association between one restaurant-level Dish and one Visit.
/// `Dish.visitId` remains the immutable P2-A/legacy origin visit; all current
/// membership is expressed by this model.
@Model
final class VisitDish {
    @Attribute(.unique) var id: UUID
    var ownerUserID: String = LocalAccountOwner.legacyQuarantine
    var restaurantId: UUID
    var visitId: UUID
    var dishId: UUID
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
    var remoteID: String?
    var deletedAt: Date?
    var serverVersion: Int64
    var lastSyncedAt: Date?
    var remoteRecordData: Data?
    private var syncStatusValue: String

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusValue) ?? .pending }
        set { syncStatusValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        ownerUserID: String = LocalAccountOwner.guest,
        restaurantId: UUID,
        visitId: UUID,
        dishId: UUID,
        sortOrder: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        remoteID: String? = nil,
        deletedAt: Date? = nil,
        serverVersion: Int64 = 0,
        lastSyncedAt: Date? = nil,
        syncStatus: SyncStatus = .pending,
        remoteRecordData: Data? = nil
    ) {
        self.id = id
        self.ownerUserID = LocalAccountOwner.normalized(ownerUserID)
        self.restaurantId = restaurantId
        self.visitId = visitId
        self.dishId = dishId
        self.sortOrder = max(0, sortOrder)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.remoteID = remoteID
        self.deletedAt = deletedAt
        self.serverVersion = serverVersion
        self.lastSyncedAt = lastSyncedAt
        self.syncStatusValue = syncStatus.rawValue
        self.remoteRecordData = remoteRecordData
    }
}
