import Foundation
import SwiftData

enum RecommendationSourceType: String, Codable, CaseIterable, Identifiable, Sendable {
    case friend
    case xiaohongshu
    case douyin
    case dianping
    case blogger
    case `self`
    case other

    var id: Self { self }

    var title: String {
        switch self {
        case .friend: "朋友推荐"
        case .xiaohongshu: "小红书"
        case .douyin: "抖音"
        case .dianping: "大众点评"
        case .blogger: "博主 / 公众号"
        case .self: "自己发现"
        case .other: "其他来源"
        }
    }
}

enum PrivateDirectoryName {
    nonisolated static func normalized(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
    }
}

@Model
final class DiningCompanion {
    @Attribute(.unique) var id: UUID
    var ownerUserId: String
    var displayName: String
    var linkedTasteMapUserId: String?
    var createdAt: Date
    var updatedAt: Date
    @Attribute(.unique) var remoteID: String?
    var deletedAt: Date?
    var serverVersion: Int64
    var lastSyncedAt: Date?
    private var syncStatusValue: String
    var remoteRecordData: Data?

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusValue) ?? .pending }
        set { syncStatusValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        ownerUserId: String = "local",
        displayName: String,
        linkedTasteMapUserId: String? = nil,
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
        self.ownerUserId = ownerUserId
        self.displayName = PrivateDirectoryName.normalized(displayName)
        self.linkedTasteMapUserId = linkedTasteMapUserId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.remoteID = remoteID ?? id.uuidString.lowercased()
        self.deletedAt = deletedAt
        self.serverVersion = serverVersion
        self.lastSyncedAt = lastSyncedAt
        syncStatusValue = syncStatus.rawValue
        self.remoteRecordData = remoteRecordData
    }
}

@Model
final class RecommendationSource {
    @Attribute(.unique) var id: UUID
    var ownerUserId: String
    var displayName: String
    private var sourceTypeValue: String
    var linkedTasteMapUserId: String?
    var createdAt: Date
    var updatedAt: Date
    @Attribute(.unique) var remoteID: String?
    var deletedAt: Date?
    var serverVersion: Int64
    var lastSyncedAt: Date?
    private var syncStatusValue: String
    var remoteRecordData: Data?

    var sourceType: RecommendationSourceType {
        get { RecommendationSourceType(rawValue: sourceTypeValue) ?? .other }
        set { sourceTypeValue = newValue.rawValue }
    }

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusValue) ?? .pending }
        set { syncStatusValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        ownerUserId: String = "local",
        displayName: String,
        sourceType: RecommendationSourceType = .other,
        linkedTasteMapUserId: String? = nil,
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
        self.ownerUserId = ownerUserId
        self.displayName = PrivateDirectoryName.normalized(displayName)
        sourceTypeValue = sourceType.rawValue
        self.linkedTasteMapUserId = linkedTasteMapUserId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.remoteID = remoteID ?? id.uuidString.lowercased()
        self.deletedAt = deletedAt
        self.serverVersion = serverVersion
        self.lastSyncedAt = lastSyncedAt
        syncStatusValue = syncStatus.rawValue
        self.remoteRecordData = remoteRecordData
    }
}
