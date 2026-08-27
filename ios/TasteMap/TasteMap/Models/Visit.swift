import Foundation
import SwiftData

@Model
final class Visit {
    @Attribute(.unique) var id: UUID
    var restaurantId: UUID
    var visitedAt: Date
    var rating: Double?
    var note: String?
    var myActualSpend: Decimal?
    private var diningModeValue: String = DiningMode.dineIn.rawValue
    var partySize: Int?
    var createdAt: Date
    var updatedAt: Date
    @Attribute(.unique) var remoteID: String?
    var deletedAt: Date?
    var serverVersion: Int64 = 0
    var lastSyncedAt: Date?
    private var syncStatusValue: String = SyncStatus.pending.rawValue

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusValue) ?? .pending }
        set { syncStatusValue = newValue.rawValue }
    }

    var diningMode: DiningMode {
        get { DiningMode(rawValue: diningModeValue) ?? .dineIn }
        set { diningModeValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        restaurantId: UUID,
        visitedAt: Date = .now,
        rating: Double? = nil,
        note: String? = nil,
        myActualSpend: Decimal? = nil,
        diningMode: DiningMode = .dineIn,
        partySize: Int? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        remoteID: String? = nil,
        deletedAt: Date? = nil,
        serverVersion: Int64 = 0,
        lastSyncedAt: Date? = nil,
        syncStatus: SyncStatus = .pending
    ) {
        self.id = id
        self.restaurantId = restaurantId
        self.visitedAt = visitedAt
        self.rating = Self.validatedRating(rating)
        self.note = note?.nilIfBlank
        self.myActualSpend = myActualSpend
        self.diningModeValue = diningMode.rawValue
        self.partySize = partySize.flatMap { $0 >= 1 ? $0 : nil }
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.remoteID = remoteID ?? id.uuidString
        self.deletedAt = deletedAt
        self.serverVersion = serverVersion
        self.lastSyncedAt = lastSyncedAt
        self.syncStatusValue = syncStatus.rawValue
    }

    static func validatedRating(_ value: Double?) -> Double? {
        guard let value, (0.5...5).contains(value) else { return nil }
        let halfStep = (value * 2).rounded() / 2
        return abs(halfStep - value) < 0.000_001 ? halfStep : nil
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
