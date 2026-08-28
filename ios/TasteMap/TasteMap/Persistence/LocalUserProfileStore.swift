import Foundation
import SwiftData

enum UserProfileValidationError: LocalizedError, Equatable {
    case emptyDisplayName
    case displayNameTooLong
    case bioTooLong
    case cityTooLong

    var errorDescription: String? {
        switch self {
        case .emptyDisplayName: "显示名称不能为空。"
        case .displayNameTooLong: "显示名称最多 30 个字符。"
        case .bioTooLong: "个人简介最多 160 个字符。"
        case .cityTooLong: "城市最多 30 个字符。"
        }
    }
}

struct ValidatedUserProfileInput: Equatable {
    let displayName: String
    let bio: String
    let city: String

    init(
        displayName: String,
        bio: String,
        city: String,
        unchangedLegacyDisplayName: String? = nil
    ) throws {
        let normalizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { throw UserProfileValidationError.emptyDisplayName }
        guard normalizedName.unicodeScalars.count <= 30 ||
                normalizedName == unchangedLegacyDisplayName else {
            throw UserProfileValidationError.displayNameTooLong
        }
        guard normalizedBio.unicodeScalars.count <= 160 else {
            throw UserProfileValidationError.bioTooLong
        }
        guard normalizedCity.unicodeScalars.count <= 30 else {
            throw UserProfileValidationError.cityTooLong
        }
        self.displayName = normalizedName
        self.bio = normalizedBio
        self.city = normalizedCity
    }
}

@MainActor
struct LocalUserProfileStore {
    let context: ModelContext

    @discardableResult
    func ensureProfile(
        tasteMapUserID: String,
        suggestedDisplayName: String? = nil
    ) throws -> UserProfile {
        if let existing = try profiles().first(where: { $0.tasteMapUserID == tasteMapUserID }) {
            return existing
        }
        let suggestion = suggestedDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = suggestion.flatMap { try? ValidatedUserProfileInput(
            displayName: $0, bio: "", city: ""
        ).displayName } ?? "Taste Map 用户"
        let profile = UserProfile(tasteMapUserID: tasteMapUserID, displayName: displayName)
        context.insert(profile)
        try enqueueIfReady(profile)
        try context.save()
        return profile
    }

    func update(
        _ profile: UserProfile,
        displayName: String,
        bio: String,
        city: String,
        avatarPhotoID: String?,
        avatarPreset: ProfileAvatarPreset,
        visibility: ProfileVisibility
    ) throws {
        let input = try ValidatedUserProfileInput(
            displayName: displayName,
            bio: bio,
            city: city,
            unchangedLegacyDisplayName: profile.displayName
        )
        profile.displayName = input.displayName
        profile.bio = input.bio
        profile.city = input.city
        profile.avatarPhotoID = avatarPhotoID
        profile.avatarPreset = avatarPreset
        profile.visibility = visibility
        profile.updatedAt = .now
        profile.syncStatus = .pending
        try enqueueIfReady(profile)
        try context.save()
    }

    func enqueueIfReady(_ profile: UserProfile) throws {
        if let avatarPhotoID = profile.avatarPhotoID {
            guard let avatar = try photos().first(where: {
                ($0.remoteID ?? $0.id.uuidString.lowercased()) == avatarPhotoID &&
                    $0.deletedAt == nil && $0.kind == .avatar
            }), avatar.uploadState == .uploaded else { return }
        }
        try SwiftDataSyncQueue(context: context).enqueueUpsert(
            entityType: .profile,
            entityID: profile.tasteMapUserID,
            baseVersion: profile.serverVersion,
            payload: SyncRecordMapper.profilePayload(profile),
            timestamp: profile.updatedAt
        )
    }

    private func profiles() throws -> [UserProfile] {
        try context.fetch(FetchDescriptor<UserProfile>())
    }

    private func photos() throws -> [PhotoAsset] {
        try context.fetch(FetchDescriptor<PhotoAsset>())
    }
}
