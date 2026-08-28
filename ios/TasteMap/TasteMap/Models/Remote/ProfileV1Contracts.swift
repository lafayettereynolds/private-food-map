import Foundation

struct OwnProfileSyncContractV1: Codable, Equatable {
    let schemaVersion: Int
    let userId: String
    let displayName: String
    let bio: String
    let city: String
    let avatarPhotoId: String?
    let avatarPresetId: ProfileAvatarPreset
    let visibility: ProfileVisibility
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?
}

struct PublicProfileStatisticsV1: Codable, Equatable {
    let publicRestaurantCount: Int
    let publicVisitCount: Int
}

struct PublicUserProfileV1: Codable, Equatable {
    let apiVersion: Int
    let userId: String
    let displayName: String
    let bio: String?
    let city: String?
    let avatarPhotoId: String?
    let avatarPresetId: ProfileAvatarPreset
    let joinedAt: String
    let statistics: PublicProfileStatisticsV1
}

private struct ProfileContractCodingKey: CodingKey, Hashable {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private enum ProfileContractDecodingError: Error {
    case unexpectedShape
}

extension OwnProfileSyncContractV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, userId, displayName, bio, city, avatarPhotoId
        case avatarPresetId, visibility, createdAt, updatedAt, deletedAt
    }

    init(from decoder: Decoder) throws {
        let allValues = try decoder.container(keyedBy: ProfileContractCodingKey.self)
        let expected = Set(CodingKeys.allCases.map(\.rawValue))
        guard Set(allValues.allKeys.map(\.stringValue)) == expected else {
            throw ProfileContractDecodingError.unexpectedShape
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        userId = try values.decode(String.self, forKey: .userId)
        displayName = try values.decode(String.self, forKey: .displayName)
        bio = try values.decode(String.self, forKey: .bio)
        city = try values.decode(String.self, forKey: .city)
        avatarPhotoId = try values.decode(String?.self, forKey: .avatarPhotoId)
        avatarPresetId = try values.decode(ProfileAvatarPreset.self, forKey: .avatarPresetId)
        visibility = try values.decode(ProfileVisibility.self, forKey: .visibility)
        createdAt = try values.decode(String.self, forKey: .createdAt)
        updatedAt = try values.decode(String.self, forKey: .updatedAt)
        deletedAt = try values.decode(String?.self, forKey: .deletedAt)
        guard schemaVersion == SyncV1Contract.schemaVersion,
              !userId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              avatarPhotoId?.isEmpty != true,
              SyncRecordMapper.date(createdAt) != nil,
              SyncRecordMapper.date(updatedAt) != nil,
              deletedAt == nil else {
            throw ProfileContractDecodingError.unexpectedShape
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(userId, forKey: .userId)
        try values.encode(displayName, forKey: .displayName)
        try values.encode(bio, forKey: .bio)
        try values.encode(city, forKey: .city)
        try values.encode(avatarPhotoId, forKey: .avatarPhotoId)
        try values.encode(avatarPresetId, forKey: .avatarPresetId)
        try values.encode(visibility, forKey: .visibility)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encode(updatedAt, forKey: .updatedAt)
        try values.encode(deletedAt, forKey: .deletedAt)
    }
}

extension PublicUserProfileV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case apiVersion, userId, displayName, bio, city, avatarPhotoId
        case avatarPresetId, joinedAt, statistics
    }

    init(from decoder: Decoder) throws {
        let allValues = try decoder.container(keyedBy: ProfileContractCodingKey.self)
        let expected = Set(CodingKeys.allCases.map(\.rawValue))
        guard Set(allValues.allKeys.map(\.stringValue)) == expected else {
            throw ProfileContractDecodingError.unexpectedShape
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        apiVersion = try values.decode(Int.self, forKey: .apiVersion)
        userId = try values.decode(String.self, forKey: .userId)
        displayName = try values.decode(String.self, forKey: .displayName)
        bio = try values.decode(String?.self, forKey: .bio)
        city = try values.decode(String?.self, forKey: .city)
        avatarPhotoId = try values.decode(String?.self, forKey: .avatarPhotoId)
        avatarPresetId = try values.decode(ProfileAvatarPreset.self, forKey: .avatarPresetId)
        joinedAt = try values.decode(String.self, forKey: .joinedAt)
        statistics = try values.decode(PublicProfileStatisticsV1.self, forKey: .statistics)
        guard apiVersion == 1,
              !userId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              avatarPhotoId?.isEmpty != true,
              SyncRecordMapper.date(joinedAt) != nil,
              statistics.publicRestaurantCount >= 0,
              statistics.publicVisitCount >= 0 else {
            throw ProfileContractDecodingError.unexpectedShape
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(apiVersion, forKey: .apiVersion)
        try values.encode(userId, forKey: .userId)
        try values.encode(displayName, forKey: .displayName)
        try values.encode(bio, forKey: .bio)
        try values.encode(city, forKey: .city)
        try values.encode(avatarPhotoId, forKey: .avatarPhotoId)
        try values.encode(avatarPresetId, forKey: .avatarPresetId)
        try values.encode(joinedAt, forKey: .joinedAt)
        try values.encode(statistics, forKey: .statistics)
    }
}
