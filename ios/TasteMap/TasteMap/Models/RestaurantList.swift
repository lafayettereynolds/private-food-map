import Foundation
import SwiftData

enum RestaurantListVisibility: String, Codable, CaseIterable, Identifiable, Sendable {
    case `private`
    case friends
    case `public`

    var id: Self { self }
    var title: String {
        switch self {
        case .private: "仅自己"
        case .friends: "好友"
        case .public: "公开"
        }
    }
    var systemImage: String {
        switch self {
        case .private: "lock.fill"
        case .friends: "person.2.fill"
        case .public: "globe.asia.australia.fill"
        }
    }
}

enum RestaurantListCoverMode: String, Codable, CaseIterable, Sendable {
    case automatic
    case custom
}

@Model
final class RestaurantList {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var remoteID: String?
    var ownerUserID: String
    var title: String
    var listDescription: String
    private var visibilityValue: String
    var isRanked: Bool
    private var coverModeValue: String
    var customCoverPhotoID: String?
    /// Derived summary maintained transactionally; the detail's ListItems are
    /// still the source of truth. This keeps 100-list overviews from loading
    /// thousands of full items.
    var activeItemCount: Int
    var previewRestaurantIDsData: Data?
    var previewRestaurantsData: Data?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var serverVersion: Int64
    var lastSyncedAt: Date?
    private var syncStatusValue: String
    var remoteRecordData: Data?

    var visibility: RestaurantListVisibility {
        get { RestaurantListVisibility(rawValue: visibilityValue) ?? .private }
        set { visibilityValue = newValue.rawValue }
    }

    var coverMode: RestaurantListCoverMode {
        get { RestaurantListCoverMode(rawValue: coverModeValue) ?? .automatic }
        set { coverModeValue = newValue.rawValue }
    }

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusValue) ?? .pending }
        set { syncStatusValue = newValue.rawValue }
    }

    var previewRestaurantIDs: [String] {
        get { previewRestaurantIDsData.flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? [] }
        set { previewRestaurantIDsData = try? JSONEncoder().encode(Array(newValue.prefix(4))) }
    }

    @MainActor var previewRestaurants: [RestaurantListPlaceContractV1] {
        get { previewRestaurantsData.flatMap { try? JSONDecoder().decode([RestaurantListPlaceContractV1].self, from: $0) } ?? [] }
        set { previewRestaurantsData = try? JSONEncoder().encode(Array(newValue.prefix(4))) }
    }

    init(
        id: UUID = UUID(),
        remoteID: String? = nil,
        ownerUserID: String,
        title: String,
        listDescription: String = "",
        visibility: RestaurantListVisibility = .private,
        isRanked: Bool = false,
        coverMode: RestaurantListCoverMode = .automatic,
        customCoverPhotoID: String? = nil,
        activeItemCount: Int = 0,
        previewRestaurantIDs: [String] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil,
        serverVersion: Int64 = 0,
        lastSyncedAt: Date? = nil,
        syncStatus: SyncStatus = .pending,
        remoteRecordData: Data? = nil
    ) {
        self.id = id
        self.remoteID = remoteID ?? id.uuidString.lowercased()
        self.ownerUserID = ownerUserID
        self.title = title
        self.listDescription = listDescription
        visibilityValue = visibility.rawValue
        self.isRanked = isRanked
        coverModeValue = coverMode.rawValue
        self.customCoverPhotoID = customCoverPhotoID
        self.activeItemCount = activeItemCount
        previewRestaurantIDsData = try? JSONEncoder().encode(Array(previewRestaurantIDs.prefix(4)))
        previewRestaurantsData = nil
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.serverVersion = serverVersion
        self.lastSyncedAt = lastSyncedAt
        syncStatusValue = syncStatus.rawValue
        self.remoteRecordData = remoteRecordData
    }
}

@Model
final class RestaurantListItem {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var remoteID: String?
    var ownerUserID: String
    var listID: UUID
    var listRemoteID: String
    /// Stable owner-side Restaurant reference. A search-only item may not yet
    /// have a user Restaurant state, so the public-safe snapshot is retained.
    var restaurantReferenceID: String
    var localRestaurantID: UUID?
    var restaurantGlobalKey: String
    var restaurantSnapshotData: Data
    var position: Int
    var note: String
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var serverVersion: Int64
    var lastSyncedAt: Date?
    private var syncStatusValue: String
    var remoteRecordData: Data?

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusValue) ?? .pending }
        set { syncStatusValue = newValue.rawValue }
    }

    @MainActor var restaurantSnapshot: RestaurantListPlaceContractV1? {
        get { try? JSONDecoder().decode(RestaurantListPlaceContractV1.self, from: restaurantSnapshotData) }
        set { if let newValue { restaurantSnapshotData = (try? JSONEncoder().encode(newValue)) ?? restaurantSnapshotData } }
    }

    @MainActor init(
        id: UUID = UUID(),
        remoteID: String? = nil,
        ownerUserID: String,
        listID: UUID,
        listRemoteID: String,
        restaurantReferenceID: String,
        localRestaurantID: UUID?,
        restaurantGlobalKey: String,
        restaurantSnapshot: RestaurantListPlaceContractV1,
        position: Int,
        note: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil,
        serverVersion: Int64 = 0,
        lastSyncedAt: Date? = nil,
        syncStatus: SyncStatus = .pending,
        remoteRecordData: Data? = nil
    ) throws {
        self.id = id
        self.remoteID = remoteID ?? id.uuidString.lowercased()
        self.ownerUserID = ownerUserID
        self.listID = listID
        self.listRemoteID = listRemoteID
        self.restaurantReferenceID = restaurantReferenceID
        self.localRestaurantID = localRestaurantID
        self.restaurantGlobalKey = restaurantGlobalKey
        restaurantSnapshotData = try JSONEncoder().encode(restaurantSnapshot)
        self.position = position
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.serverVersion = serverVersion
        self.lastSyncedAt = lastSyncedAt
        syncStatusValue = syncStatus.rawValue
        self.remoteRecordData = remoteRecordData
    }
}

@Model
final class CachedPublicRestaurantList {
    @Attribute(.unique) var cacheID: String
    var viewerUserID: String
    var listID: String
    var ownerUserID: String
    var summaryData: Data
    var detailValidatedAt: Date?
    var fetchedAt: Date

    @MainActor init(viewerUserID: String, summary: PublicListSummaryDTO, fetchedAt: Date = .now) throws {
        cacheID = "\(viewerUserID)|\(summary.id)"
        self.viewerUserID = viewerUserID
        listID = summary.id
        ownerUserID = summary.owner.userId
        summaryData = try JSONEncoder().encode(summary)
        self.fetchedAt = fetchedAt
    }

    @MainActor var summary: PublicListSummaryDTO? {
        try? JSONDecoder().decode(PublicListSummaryDTO.self, from: summaryData)
    }
}

@Model
final class CachedPublicRestaurantListItem {
    @Attribute(.unique) var cacheID: String
    var viewerUserID: String
    var listID: String
    var itemID: String
    var position: Int
    var itemData: Data
    var fetchedAt: Date

    @MainActor init(viewerUserID: String, listID: String, item: PublicListItemDTO, fetchedAt: Date = .now) throws {
        cacheID = "\(viewerUserID)|\(listID)|\(item.id)"
        self.viewerUserID = viewerUserID
        self.listID = listID
        itemID = item.id
        position = item.position
        itemData = try JSONEncoder().encode(item)
        self.fetchedAt = fetchedAt
    }

    @MainActor var item: PublicListItemDTO? {
        try? JSONDecoder().decode(PublicListItemDTO.self, from: itemData)
    }
}
