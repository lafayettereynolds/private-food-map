import Foundation
import SwiftData

@Model
final class Restaurant {
    @Attribute(.unique) var id: UUID
    var ownerUserID: String = LocalAccountOwner.legacyQuarantine
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var appleMapItemIdentifier: String?
    var city: String = ""
    private var statusValue: String = RestaurantStatus.visited.rawValue
    var createdAt: Date
    var updatedAt: Date
    var remoteID: String?
    var deletedAt: Date?
    var serverVersion: Int64 = 0
    var lastSyncedAt: Date?
    var remoteRecordData: Data?
    private var syncStatusValue: String = SyncStatus.pending.rawValue

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusValue) ?? .pending }
        set { syncStatusValue = newValue.rawValue }
    }

    var status: RestaurantStatus {
        get { RestaurantStatus(rawValue: statusValue) ?? .visited }
        set { statusValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        ownerUserID: String = LocalAccountOwner.guest,
        name: String,
        address: String,
        latitude: Double,
        longitude: Double,
        appleMapItemIdentifier: String? = nil,
        city: String = "",
        status: RestaurantStatus = .visited,
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
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.appleMapItemIdentifier = appleMapItemIdentifier
        self.city = city
        self.statusValue = status.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.remoteID = remoteID ?? id.uuidString
        self.deletedAt = deletedAt
        self.serverVersion = serverVersion
        self.lastSyncedAt = lastSyncedAt
        self.syncStatusValue = syncStatus.rawValue
        self.remoteRecordData = remoteRecordData
    }
}
