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
    var createdAt: Date
    var updatedAt: Date
    private var syncStatusValue: String

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusValue) ?? .pending }
        set { syncStatusValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        restaurantId: UUID,
        visitedAt: Date = .now,
        rating: Double? = nil,
        note: String? = nil,
        myActualSpend: Decimal? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        syncStatus: SyncStatus = .pending
    ) {
        self.id = id
        self.restaurantId = restaurantId
        self.visitedAt = visitedAt
        self.rating = Self.validatedRating(rating)
        self.note = note?.nilIfBlank
        self.myActualSpend = myActualSpend
        self.createdAt = createdAt
        self.updatedAt = updatedAt
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
