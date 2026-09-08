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
        let follows = (try? store.cachedFollows(currentUserID: currentUserID)) ?? []
        let followingUserIDs = Set(follows.filter {
            $0.deletedAt == nil && $0.followerUserID == currentUserID
        }.map(\.followedUserID))
        let followerUserIDs = Set(follows.filter {
            $0.deletedAt == nil && $0.followedUserID == currentUserID
        }.map(\.followerUserID))
        return ProfileSocialStatistics(
            friendCount: followingUserIDs.intersection(followerUserIDs).count,
            followingCount: followingUserIDs.count,
            followerCount: followerUserIDs.count
        )
    }

    static func load(
        api: any SocialAPI,
        context: ModelContext,
        currentUserID: String
    ) async -> ProfileSocialStatistics {
        let fallback = cached(context: context, currentUserID: currentUserID)
        do {
            let following = try await fetchAll { cursor in
                try await api.follows(scope: .following, cursor: cursor, limit: 100)
            }
            let followers = try await fetchAll { cursor in
                try await api.follows(scope: .followers, cursor: cursor, limit: 100)
            }
            return ProfileSocialStatistics(
                friendCount: SocialRelationshipSectionPolicy
                    .mutualFriends(fromFollowers: followers).count,
                followingCount: Set(following.map(\.id)).count,
                followerCount: Set(followers.map(\.id)).count
            )
        } catch {
            return fallback
        }
    }

    private static func fetchAll(
        fetch: (String?) async throws -> SocialPageV1<SocialUserResultV1>
    ) async throws -> [SocialUserResultV1] {
        var cursor: String?
        var seenCursors = Set<String>()
        var usersByID: [String: SocialUserResultV1] = [:]
        for _ in 0..<100 {
            let page = try await fetch(cursor)
            page.items.forEach { usersByID[$0.id] = $0 }
            guard let next = page.nextCursor else { return Array(usersByID.values) }
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
