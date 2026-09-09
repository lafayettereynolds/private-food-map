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
        try synchronizeFootprintVisibility(profile)
        try context.save()
    }

    /// Homepage scope is authoritative for the owner's Visits and attached photos.
    /// Legacy per-record fields are synchronized through the ordinary mutation queue.
    @discardableResult
    func synchronizeFootprintVisibility(_ profile: UserProfile) throws -> Int {
        guard profile.deletedAt == nil else { return 0 }
        let owner = profile.tasteMapUserID
        let visibility = VisitVisibility(rawValue: profile.visibility.rawValue) ?? .private
        let restaurants = try context.fetch(FetchDescriptor<Restaurant>()).filter { $0.ownerUserID == owner && $0.deletedAt == nil }
        let restaurantByID = Dictionary(uniqueKeysWithValues: restaurants.map { ($0.id, $0) })
        let visits = try context.fetch(FetchDescriptor<Visit>()).filter { $0.ownerUserID == owner && $0.deletedAt == nil && restaurantByID[$0.restaurantId] != nil }
        let visitByID = Dictionary(uniqueKeysWithValues: visits.map { ($0.id, $0) })
        let dishes = try context.fetch(FetchDescriptor<Dish>()).filter { $0.ownerUserID == owner && $0.deletedAt == nil }
        let dishByID = Dictionary(uniqueKeysWithValues: dishes.map { ($0.id, $0) })
        let queue = SwiftDataSyncQueue(context: context, ownerUserID: owner)
        var changed = 0
        try context.transaction {
            for visit in visits where visit.visibility != visibility {
                guard let restaurant = restaurantByID[visit.restaurantId], let remote = restaurant.remoteID else { continue }
                if restaurant.syncStatus != .synced {
                    try queue.enqueueUpsert(entityType: .restaurant, entityID: remote, baseVersion: restaurant.serverVersion,
                        payload: SyncRecordMapper.restaurantPayload(restaurant), timestamp: restaurant.updatedAt)
                }
                for companion in try context.fetch(FetchDescriptor<DiningCompanion>()) where companion.ownerUserId == owner && companion.deletedAt == nil && companion.syncStatus != .synced && visit.companionIDs.map { $0.lowercased() }.contains((companion.remoteID ?? companion.id.uuidString).lowercased()) {
                    try queue.enqueueUpsert(entityType: .companion, entityID: companion.remoteID ?? companion.id.uuidString.lowercased(), baseVersion: companion.serverVersion,
                        payload: SyncRecordMapper.companionPayload(companion), timestamp: companion.updatedAt)
                }
                visit.visibility = visibility; visit.updatedAt = .now; visit.syncStatus = .pending
                try queue.enqueueUpsert(entityType: .visit, entityID: visit.remoteID ?? visit.id.uuidString,
                    baseVersion: visit.serverVersion, payload: SyncRecordMapper.visitPayload(visit, restaurantRemoteID: remote), timestamp: visit.updatedAt)
                changed += 1
            }
            for photo in try photos() where photo.ownerUserID == owner && photo.deletedAt == nil {
                guard let visitID = photo.visitId, let visit = visitByID[visitID], photo.visibility.rawValue != visibility.rawValue else { continue }
                photo.visibility = PhotoVisibility(rawValue: visibility.rawValue) ?? .private
                photo.updatedAt = .now; photo.syncStatus = .pending
                if photo.uploadState == .uploaded {
                    let restaurant = restaurantByID[visit.restaurantId]
                    try queue.enqueueUpsert(entityType: .photo, entityID: photo.remoteID ?? photo.id.uuidString.lowercased(),
                        baseVersion: photo.serverVersion,
                        payload: SyncRecordMapper.photoPayload(photo, restaurantRemoteID: restaurant?.remoteID,
                            visitRemoteID: visit.remoteID, dishRemoteID: photo.dishId.flatMap { dishByID[$0]?.remoteID }), timestamp: photo.updatedAt)
                }
                changed += 1
            }
            if changed > 0 { try enqueueIfReady(profile) }
        }
        return changed
    }

    func enqueueIfReady(_ profile: UserProfile) throws {
        if let avatarPhotoID = profile.avatarPhotoID {
            guard let avatar = try photos().first(where: {
                ($0.remoteID ?? $0.id.uuidString.lowercased()) == avatarPhotoID &&
                    $0.ownerUserID == profile.tasteMapUserID &&
                    $0.deletedAt == nil && $0.kind == .avatar
            }), avatar.uploadState == .uploaded else { return }
        }
        try SwiftDataSyncQueue(
            context: context,
            ownerUserID: profile.tasteMapUserID
        ).enqueueUpsert(
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
