import Foundation
import SwiftData

@Model
final class Dish {
    @Attribute(.unique) var id: UUID
    var ownerUserID: String = LocalAccountOwner.legacyQuarantine
    var restaurantId: UUID
    var visitId: UUID
    var name: String
    var taste: String
    var rating: Double?
    var price: Decimal?
    var photoRemoteID: String?
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
        name: String,
        taste: String = "",
        rating: Double? = nil,
        price: Decimal? = nil,
        photoRemoteID: String? = nil,
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
        self.name = name
        self.taste = taste
        self.rating = Visit.validatedRating(rating)
        self.price = price.flatMap { $0 >= 0 ? $0 : nil }
        self.photoRemoteID = photoRemoteID
        self.sortOrder = max(0, sortOrder)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.remoteID = remoteID ?? id.uuidString.lowercased()
        self.deletedAt = deletedAt
        self.serverVersion = serverVersion
        self.lastSyncedAt = lastSyncedAt
        self.syncStatusValue = syncStatus.rawValue
        self.remoteRecordData = remoteRecordData
    }
}
