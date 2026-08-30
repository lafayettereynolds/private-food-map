import Foundation
import SwiftData

@Model
final class SyncCheckpoint {
    @Attribute(.unique) var scope: String
    var ownerUserID: String = LocalAccountOwner.legacyQuarantine
    var cursor: String
    var lastSyncedAt: Date?

    init(ownerUserID: String = LocalAccountOwner.guest, cursor: String = "0", lastSyncedAt: Date? = nil) {
        let ownerUserID = LocalAccountOwner.normalized(ownerUserID)
        self.scope = "\(ownerUserID)|sync-v1"
        self.ownerUserID = ownerUserID
        self.cursor = cursor
        self.lastSyncedAt = lastSyncedAt
    }
}
