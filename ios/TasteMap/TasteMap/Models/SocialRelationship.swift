import Foundation
import SwiftData

enum FriendshipPerspectiveState: String, Codable, CaseIterable, Sendable {
    case none
    case outgoingRequest = "outgoing_request"
    case incomingRequest = "incoming_request"
    case friends
    case rejected
    case removed

    var title: String {
        switch self {
        case .none: "添加好友"
        case .outgoingRequest: "已发送"
        case .incomingRequest: "待你处理"
        case .friends: "已是好友"
        case .rejected, .removed: "添加好友"
        }
    }
}

enum SocialMutationKind: String, Codable, Sendable {
    case friendRequest = "friend_request"
    case follow
    case unfollow
}

@Model
final class CachedSocialProfile {
    @Attribute(.unique) var tasteMapUserID: String
    var displayName: String
    var bio: String?
    var city: String?
    var avatarPhotoID: String?
    private var avatarPresetValue: String
    var fetchedAt: Date

    var avatarPreset: ProfileAvatarPreset {
        get { ProfileAvatarPreset(rawValue: avatarPresetValue) ?? .polarBear }
        set { avatarPresetValue = newValue.rawValue }
    }

    init(
        tasteMapUserID: String,
        displayName: String,
        bio: String? = nil,
        city: String? = nil,
        avatarPhotoID: String? = nil,
        avatarPreset: ProfileAvatarPreset = .polarBear,
        fetchedAt: Date = .now
    ) {
        self.tasteMapUserID = tasteMapUserID
        self.displayName = displayName
        self.bio = bio
        self.city = city
        self.avatarPhotoID = avatarPhotoID
        avatarPresetValue = avatarPreset.rawValue
        self.fetchedAt = fetchedAt
    }
}

@Model
final class CachedFriendship {
    @Attribute(.unique) var cacheID: String
    var relationshipID: String
    var currentUserID: String
    var requesterUserID: String
    var addresseeUserID: String
    private var stateValue: String
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var serverVersion: Int64
    var isOptimistic: Bool

    var state: FriendshipPerspectiveState {
        get { FriendshipPerspectiveState(rawValue: stateValue) ?? .none }
        set { stateValue = newValue.rawValue }
    }

    var otherUserID: String {
        requesterUserID == currentUserID ? addresseeUserID : requesterUserID
    }

    var perspectiveState: FriendshipPerspectiveState {
        guard deletedAt == nil else { return .none }
        switch state {
        case .friends: return .friends
        case .outgoingRequest:
            return requesterUserID == currentUserID ? .outgoingRequest : .incomingRequest
        case .incomingRequest:
            return requesterUserID == currentUserID ? .outgoingRequest : .incomingRequest
        default: return .none
        }
    }

    init(
        relationshipID: String,
        currentUserID: String,
        requesterUserID: String,
        addresseeUserID: String,
        state: FriendshipPerspectiveState,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil,
        serverVersion: Int64 = 0,
        isOptimistic: Bool = false
    ) {
        cacheID = "\(currentUserID)|\(relationshipID)"
        self.relationshipID = relationshipID
        self.currentUserID = currentUserID
        self.requesterUserID = requesterUserID
        self.addresseeUserID = addresseeUserID
        stateValue = state.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.serverVersion = serverVersion
        self.isOptimistic = isOptimistic
    }
}

@Model
final class CachedFollow {
    @Attribute(.unique) var cacheID: String
    var relationshipID: String
    var currentUserID: String
    var followerUserID: String
    var followedUserID: String
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var serverVersion: Int64
    var isOptimistic: Bool

    init(
        relationshipID: String,
        currentUserID: String,
        followerUserID: String,
        followedUserID: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil,
        serverVersion: Int64 = 0,
        isOptimistic: Bool = false
    ) {
        cacheID = "\(currentUserID)|\(relationshipID)"
        self.relationshipID = relationshipID
        self.currentUserID = currentUserID
        self.followerUserID = followerUserID
        self.followedUserID = followedUserID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.serverVersion = serverVersion
        self.isOptimistic = isOptimistic
    }
}

@Model
final class SocialMutation {
    @Attribute(.unique) var mutationID: UUID
    var currentUserID: String
    private var kindValue: String
    var targetUserID: String
    var createdAt: Date
    var retryCount: Int
    var lastError: String?

    var kind: SocialMutationKind {
        get { SocialMutationKind(rawValue: kindValue) ?? .friendRequest }
        set { kindValue = newValue.rawValue }
    }

    init(
        mutationID: UUID = UUID(),
        currentUserID: String,
        kind: SocialMutationKind,
        targetUserID: String,
        createdAt: Date = .now,
        retryCount: Int = 0,
        lastError: String? = nil
    ) {
        self.mutationID = mutationID
        self.currentUserID = currentUserID
        kindValue = kind.rawValue
        self.targetUserID = targetUserID
        self.createdAt = createdAt
        self.retryCount = retryCount
        self.lastError = lastError
    }
}
