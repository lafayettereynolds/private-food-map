import Foundation
import SwiftData

nonisolated struct ProfileSocialStatistics: Equatable, Sendable {
    let friendCount: Int
    let followingCount: Int
    let followerCount: Int

    static let zero = ProfileSocialStatistics(
        friendCount: 0,
        followingCount: 0,
        followerCount: 0
    )
}

@MainActor
enum ProfileSocialStatisticsLoader {
    static func cached(context: ModelContext, currentUserID: String) -> ProfileSocialStatistics {
        let store = LocalSocialStore(context: context)
        let friendships = (try? store.cachedFriendships(currentUserID: currentUserID)) ?? []
        let follows = (try? store.cachedFollows(currentUserID: currentUserID)) ?? []
        return ProfileSocialStatistics(
            friendCount: Set(friendships.filter {
                $0.deletedAt == nil && $0.perspectiveState == .friends
            }.map(\.otherUserID)).count,
            followingCount: Set(follows.filter {
                $0.deletedAt == nil && $0.followerUserID == currentUserID
            }.map(\.followedUserID)).count,
            followerCount: Set(follows.filter {
                $0.deletedAt == nil && $0.followedUserID == currentUserID
            }.map(\.followerUserID)).count
        )
    }

    static func load(
        api: any SocialAPI,
        context: ModelContext,
        currentUserID: String
    ) async -> ProfileSocialStatistics {
        let fallback = cached(context: context, currentUserID: currentUserID)
        do {
            let friends = try await countAll { cursor in
                try await api.friendships(scope: .friends, cursor: cursor, limit: 100)
            }
            let following = try await countAll { cursor in
                try await api.follows(scope: .following, cursor: cursor, limit: 100)
            }
            let followers = try await countAll { cursor in
                try await api.follows(scope: .followers, cursor: cursor, limit: 100)
            }
            return ProfileSocialStatistics(
                friendCount: friends,
                followingCount: following,
                followerCount: followers
            )
        } catch {
            return fallback
        }
    }

    private static func countAll(
        fetch: (String?) async throws -> SocialPageV1<SocialUserResultV1>
    ) async throws -> Int {
        var cursor: String?
        var seenCursors = Set<String>()
        var seenUsers = Set<String>()
        for _ in 0..<100 {
            let page = try await fetch(cursor)
            page.items.forEach { seenUsers.insert($0.profile.userId) }
            guard let next = page.nextCursor else { return seenUsers.count }
            guard seenCursors.insert(next).inserted else { throw ProfileSocialStatisticsError.repeatedCursor }
            cursor = next
        }
        throw ProfileSocialStatisticsError.pageLimitExceeded
    }
}

private enum ProfileSocialStatisticsError: Error {
    case repeatedCursor
    case pageLimitExceeded
}
