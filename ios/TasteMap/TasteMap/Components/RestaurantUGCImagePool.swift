import Foundation

enum RestaurantUGCImageSourceType: String, Codable, Equatable, Sendable {
    case currentOwnerPhoto
    case activityAuthorPhoto
    case publicUGC
    case nonPublic
}

struct RestaurantUGCImageRecord: Equatable, Sendable {
    let photoID: String
    let restaurantID: String
    let visitID: String?
    let ownerUserID: String
    let visibility: String
    /// Nil is valid for a Restaurant-level PhotoAsset without a Visit.
    let visitVisibility: String?
    let profileVisibility: String?
    let moderationEligible: Bool
    let deletedAt: Date?
    let binaryDeletedAt: Date?
    let createdAt: Date
    let markerPreferred: Bool
    let resourceURL: String
}

struct RestaurantUGCImageSelection: Equatable, Sendable {
    let sourceType: RestaurantUGCImageSourceType
    let record: RestaurantUGCImageRecord
    let exportAllowed: Bool
}

enum RestaurantVisualSurface: String, CaseIterable, Sendable {
    case map, search, nearby, detail, following, forYou, similarTaste, latest, trending
}

/// Pure, deterministic eligibility and selection policy. Callers load records
/// in grouped snapshots; the pool never performs per-card persistence reads.
enum RestaurantUGCImagePool {
    /// Returns nil when the product contract requires a Food Category Visual.
    static func resolve(
        surface: RestaurantVisualSurface,
        records: [RestaurantUGCImageRecord],
        currentOwnerID: String,
        restaurantID: String,
        activityVisitID: String? = nil,
        canSeeFriendsActivity: Bool = false
    ) -> RestaurantUGCImageSelection? {
        switch surface {
        case .map:
            currentOwnerPhoto(records: records, currentOwnerID: currentOwnerID, restaurantID: restaurantID)
        case .following, .similarTaste, .latest:
            activityVisitID.flatMap {
                activityPhoto(
                    records: records, visibleVisitID: $0, currentOwnerID: currentOwnerID,
                    canSeeFriends: canSeeFriendsActivity
                )
            } ?? publicUGC(records: records, restaurantID: restaurantID)
        case .search, .nearby, .detail, .forYou, .trending:
            currentOwnerPhoto(records: records, currentOwnerID: currentOwnerID, restaurantID: restaurantID)
                ?? publicUGC(records: records, restaurantID: restaurantID)
        }
    }

    static func currentOwnerPhoto(
        records: [RestaurantUGCImageRecord],
        currentOwnerID: String,
        restaurantID: String
    ) -> RestaurantUGCImageSelection? {
        preferred(records.filter {
            active($0) && $0.ownerUserID == currentOwnerID && $0.restaurantID == restaurantID
        }.map { .init(sourceType: .currentOwnerPhoto, record: $0, exportAllowed: true) })
    }

    static func activityPhoto(
        records: [RestaurantUGCImageRecord],
        visibleVisitID: String,
        currentOwnerID: String,
        canSeeFriends: Bool
    ) -> RestaurantUGCImageSelection? {
        preferred(records.filter {
            active($0) && $0.visitID == visibleVisitID &&
                ($0.ownerUserID == currentOwnerID || isPublic($0) ||
                    (canSeeFriends && isFriendsVisible($0)))
        }.map {
            .init(sourceType: .activityAuthorPhoto, record: $0, exportAllowed: $0.ownerUserID == currentOwnerID)
        })
    }

    static func publicUGC(
        records: [RestaurantUGCImageRecord],
        restaurantID: String
    ) -> RestaurantUGCImageSelection? {
        preferred(records.filter {
            active($0) && $0.restaurantID == restaurantID && isPublic($0)
        }.map { .init(sourceType: .publicUGC, record: $0, exportAllowed: false) })
    }

    private static func active(_ value: RestaurantUGCImageRecord) -> Bool {
        value.moderationEligible && value.deletedAt == nil && value.binaryDeletedAt == nil
    }

    private static func isPublic(_ value: RestaurantUGCImageRecord) -> Bool {
        value.visibility == "public"
            && (value.visitVisibility == nil || value.visitVisibility == "public")
            && value.profileVisibility == "public"
    }

    private static func isFriendsVisible(_ value: RestaurantUGCImageRecord) -> Bool {
        ["public", "friends"].contains(value.visibility)
            && value.visitVisibility.map { ["public", "friends"].contains($0) } == true
            && value.profileVisibility.map { ["public", "friends"].contains($0) } == true
    }

    private static func preferred(_ values: [RestaurantUGCImageSelection]) -> RestaurantUGCImageSelection? {
        values.sorted {
            if $0.record.markerPreferred != $1.record.markerPreferred { return $0.record.markerPreferred }
            if $0.record.createdAt != $1.record.createdAt { return $0.record.createdAt > $1.record.createdAt }
            return $0.record.photoID < $1.record.photoID
        }.first
    }
}
