import Foundation

struct SocialUserSummaryV1: Codable, Equatable, Identifiable {
    let userId: String
    let displayName: String
    let bio: String?
    let city: String?
    let avatarPhotoId: String?
    let avatarPresetId: ProfileAvatarPreset

    var id: String { userId }
}

private struct SocialContractCodingKey: CodingKey, Hashable {
    let stringValue: String
    let intValue: Int? = nil
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private enum SocialContractError: Error { case unexpectedShape }

extension SocialUserSummaryV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case userId, displayName, bio, city, avatarPhotoId, avatarPresetId
    }

    init(from decoder: Decoder) throws {
        let all = try decoder.container(keyedBy: SocialContractCodingKey.self)
        guard Set(all.allKeys.map(\.stringValue)) == Set(CodingKeys.allCases.map(\.rawValue)) else {
            throw SocialContractError.unexpectedShape
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        userId = try values.decode(String.self, forKey: .userId)
        displayName = try values.decode(String.self, forKey: .displayName)
        bio = try values.decode(String?.self, forKey: .bio)
        city = try values.decode(String?.self, forKey: .city)
        avatarPhotoId = try values.decode(String?.self, forKey: .avatarPhotoId)
        avatarPresetId = try values.decode(ProfileAvatarPreset.self, forKey: .avatarPresetId)
        guard !userId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              avatarPhotoId?.isEmpty != true else { throw SocialContractError.unexpectedShape }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(userId, forKey: .userId)
        try values.encode(displayName, forKey: .displayName)
        try values.encode(bio, forKey: .bio)
        try values.encode(city, forKey: .city)
        try values.encode(avatarPhotoId, forKey: .avatarPhotoId)
        try values.encode(avatarPresetId, forKey: .avatarPresetId)
    }
}

struct SocialUserResultV1: Codable, Equatable, Identifiable {
    let profile: SocialUserSummaryV1
    let friendshipId: String?
    let friendshipState: FriendshipPerspectiveState
    let isFollowing: Bool

    var id: String { profile.userId }
}

struct SocialPageV1<Item: Codable & Equatable>: Codable, Equatable {
    let apiVersion: Int
    let items: [Item]
    let nextCursor: String?
}

struct FriendshipContractV1: Codable, Equatable {
    let apiVersion: Int
    let id: String
    let requesterUserId: String
    let addresseeUserId: String
    let state: FriendshipPerspectiveState
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?
    let serverVersion: Int64
}

struct FollowContractV1: Codable, Equatable {
    let apiVersion: Int
    let id: String
    let followerUserId: String
    let followedUserId: String
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?
    let serverVersion: Int64
}

struct FriendshipMutationResponseV1: Codable, Equatable {
    let friendship: FriendshipContractV1
    let duplicate: Bool
    let crossRequestAccepted: Bool?
}

struct FollowMutationResponseV1: Codable, Equatable {
    let follow: FollowContractV1?
    let duplicate: Bool
}

struct SocialRelationshipContextV1: Codable, Equatable {
    let friendshipId: String?
    let friendshipState: FriendshipPerspectiveState
    let isFollowing: Bool
}

struct SocialProfileContextV1: Codable, Equatable {
    let apiVersion: Int
    let profile: PublicUserProfileV1
    let relationship: SocialRelationshipContextV1
}

enum FriendshipListScope: String, Sendable {
    case friends, incoming, outgoing
}

enum FollowListScope: String, Sendable {
    case following, followers
}

enum FriendshipMutationAction: String, Sendable {
    case accept, reject, cancel, remove
}
