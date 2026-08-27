import Foundation
import SwiftData

@Model
final class SyncCheckpoint {
    @Attribute(.unique) var scope: String
    var cursor: String
    var lastSyncedAt: Date?

    init(scope: String = "sync-v1", cursor: String = "0", lastSyncedAt: Date? = nil) {
        self.scope = scope
        self.cursor = cursor
        self.lastSyncedAt = lastSyncedAt
    }
}
