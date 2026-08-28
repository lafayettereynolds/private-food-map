import Foundation
import SwiftData

enum ProfileVisibility: String, Codable, CaseIterable, Sendable {
    case `private`
    case friends
    case `public`

    var title: String {
        switch self {
        case .private: "仅自己"
        case .friends: "好友"
        case .public: "公开"
        }
    }
}

enum ProfileAvatarPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case polarBear = "polar-bear"
    case penguin
    case cat
    case dog
    case parrot
    case dinosaur
    case shiba
    case panda
    case otter
    case hedgehog
    case rabbit
    case koala
    case fox
    case raccoon
    case deer
    case whale

    var id: String { rawValue }

    var title: String {
        switch self {
        case .polarBear: "北极熊"
        case .penguin: "企鹅"
        case .cat: "猫咪"
        case .dog: "小狗"
        case .parrot: "鹦鹉"
        case .dinosaur: "小恐龙"
        case .shiba: "柴犬"
        case .panda: "熊猫"
        case .otter: "水獭"
        case .hedgehog: "刺猬"
        case .rabbit: "兔子"
        case .koala: "考拉"
        case .fox: "狐狸"
        case .raccoon: "浣熊"
        case .deer: "小鹿"
        case .whale: "鲸鱼"
        }
    }

    var gridPosition: (column: Int, row: Int) {
        guard let index = Self.allCases.firstIndex(of: self) else { return (0, 0) }
        return (index % 4, index / 4)
    }
}

@Model
final class UserProfile {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var tasteMapUserID: String
    var displayName: String
    var bio: String
    var city: String
    var avatarPhotoID: String?
    private var avatarPresetIDValue: String
    private var visibilityValue: String
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var serverVersion: Int64
    var lastSyncedAt: Date?
    private var syncStatusValue: String
    var remoteRecordData: Data?

    var avatarPreset: ProfileAvatarPreset {
        get { ProfileAvatarPreset(rawValue: avatarPresetIDValue) ?? .polarBear }
        set { avatarPresetIDValue = newValue.rawValue }
    }

    var visibility: ProfileVisibility {
        get { ProfileVisibility(rawValue: visibilityValue) ?? .private }
        set { visibilityValue = newValue.rawValue }
    }

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusValue) ?? .pending }
        set { syncStatusValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        tasteMapUserID: String,
        displayName: String = "Taste Map 用户",
        bio: String = "",
        city: String = "",
        avatarPhotoID: String? = nil,
        avatarPreset: ProfileAvatarPreset = .polarBear,
        visibility: ProfileVisibility = .private,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil,
        serverVersion: Int64 = 0,
        lastSyncedAt: Date? = nil,
        syncStatus: SyncStatus = .pending,
        remoteRecordData: Data? = nil
    ) {
        self.id = id
        self.tasteMapUserID = tasteMapUserID
        self.displayName = displayName
        self.bio = bio
        self.city = city
        self.avatarPhotoID = avatarPhotoID
        avatarPresetIDValue = avatarPreset.rawValue
        visibilityValue = visibility.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.serverVersion = serverVersion
        self.lastSyncedAt = lastSyncedAt
        syncStatusValue = syncStatus.rawValue
        self.remoteRecordData = remoteRecordData
    }
}
