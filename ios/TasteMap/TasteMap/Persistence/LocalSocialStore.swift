import Foundation
import SwiftData

@MainActor
struct LocalSocialStore {
    let context: ModelContext

    func cache(_ result: SocialUserResultV1, currentUserID: String) throws {
        try cache(result.profile)
        if let friendshipID = result.friendshipId, result.friendshipState != .none {
            let requester = result.friendshipState == .incomingRequest
                ? result.profile.userId : currentUserID
            let addressee = requester == currentUserID ? result.profile.userId : currentUserID
            try upsertFriendship(
                FriendshipContractV1(
                    apiVersion: 1, id: friendshipID,
                    requesterUserId: requester, addresseeUserId: addressee,
                    state: result.friendshipState, createdAt: SyncRecordMapper.dateString(.now),
                    updatedAt: SyncRecordMapper.dateString(.now), deletedAt: nil, serverVersion: 0
                ),
                currentUserID: currentUserID
            )
        } else {
            for friendship in try friendships() where
                friendship.currentUserID == currentUserID &&
                friendship.otherUserID == result.profile.userId &&
                friendship.deletedAt == nil {
                friendship.state = .removed
                friendship.deletedAt = .now
                friendship.updatedAt = .now
                friendship.isOptimistic = false
            }
        }
        try context.save()
    }

    func cache(_ profile: SocialUserSummaryV1) throws {
        if let existing = try profiles().first(where: { $0.tasteMapUserID == profile.userId }) {
            existing.displayName = profile.displayName
            existing.bio = profile.bio
            existing.city = profile.city
            existing.avatarPhotoID = profile.avatarPhotoId
            existing.avatarPreset = profile.avatarPresetId
            existing.fetchedAt = .now
        } else {
            context.insert(CachedSocialProfile(
                tasteMapUserID: profile.userId, displayName: profile.displayName,
                bio: profile.bio, city: profile.city, avatarPhotoID: profile.avatarPhotoId,
                avatarPreset: profile.avatarPresetId
            ))
        }
    }

    func cache(_ page: SocialPageV1<SocialUserResultV1>, currentUserID: String) throws {
        for item in page.items { try cache(item, currentUserID: currentUserID) }
        try context.save()
    }

    /// Reconciles a complete first page with server authority. Partial pages
    /// never delete unseen tail records.
    func reconcileCompleteFriendshipPage(
        _ page: SocialPageV1<SocialUserResultV1>,
        scope: FriendshipListScope,
        currentUserID: String
    ) throws {
        try cache(page, currentUserID: currentUserID)
        guard page.nextCursor == nil else { return }
        try reconcileFriendshipResults(
            page.items, scope: scope, currentUserID: currentUserID
        )
    }

    func reconcileFriendshipResults(
        _ items: [SocialUserResultV1],
        scope: FriendshipListScope,
        currentUserID: String
    ) throws {
        let authoritative = Set(items.compactMap(\.friendshipId))
        var revokedUserIDs = Set<String>()
        for friendship in try friendships() where
            friendship.currentUserID == currentUserID && friendship.deletedAt == nil &&
            Self._belongs(friendship.perspectiveState, to: scope) &&
            !authoritative.contains(friendship.relationshipID) {
            revokedUserIDs.insert(friendship.otherUserID)
            friendship.state = .removed
            friendship.deletedAt = .now
            friendship.updatedAt = .now
            friendship.isOptimistic = false
        }
        for profile in try profiles() where revokedUserIDs.contains(profile.tasteMapUserID) {
            context.delete(profile)
        }
        try context.save()
    }

    func cacheFollowPage(
        _ page: SocialPageV1<SocialUserResultV1>,
        scope: FollowListScope,
        currentUserID: String
    ) throws {
        try cache(page, currentUserID: currentUserID)
        if page.nextCursor == nil {
            try reconcileFollowResults(page.items, scope: scope, currentUserID: currentUserID)
        } else {
            try cacheFollowResults(page.items, scope: scope, currentUserID: currentUserID)
        }
    }

    func reconcileFollowResults(
        _ items: [SocialUserResultV1],
        scope: FollowListScope,
        currentUserID: String
    ) throws {
        try cacheFollowResults(items, scope: scope, currentUserID: currentUserID)
        let authoritative = Set(items.map {
            let pair = Self._followPair($0.profile.userId, scope: scope, currentUserID: currentUserID)
            return "follow:\(pair.follower):\(pair.followed)"
        })
        for follow in try follows() where
            follow.currentUserID == currentUserID && follow.deletedAt == nil &&
            Self._belongs(follow, to: scope, currentUserID: currentUserID) &&
            !authoritative.contains(follow.relationshipID) {
            follow.deletedAt = .now
            follow.updatedAt = .now
            follow.isOptimistic = false
        }
        try context.save()
    }

    /// Logout removes every social-derived cache and pending social mutation.
    /// Restaurant/Visit ownership data and the normal sync queue are untouched.
    func purgeAllSocialDerivedCaches() throws {
        for value in try profiles() { context.delete(value) }
        for value in try friendships() { context.delete(value) }
        for value in try follows() { context.delete(value) }
        for value in try mutations() { context.delete(value) }
        for value in try context.fetch(FetchDescriptor<CachedCommunityContent>()) { context.delete(value) }
        for value in try context.fetch(FetchDescriptor<CachedDiscoveryPlacement>()) { context.delete(value) }
        for value in try context.fetch(FetchDescriptor<CachedDiscoveryRestaurant>()) { context.delete(value) }
        try context.save()
    }

    func invalidateProfile(_ tasteMapUserID: String) throws {
        for value in try profiles() where value.tasteMapUserID == tasteMapUserID {
            context.delete(value)
        }
        try context.save()
    }

    func upsertFriendship(_ contract: FriendshipContractV1, currentUserID: String) throws {
        if let optimistic = try friendships().first(where: {
            $0.currentUserID == currentUserID && $0.otherUserID == otherUser(in: contract, currentUserID: currentUserID) && $0.isOptimistic
        }) { context.delete(optimistic) }
        let item = try friendships().first(where: {
            $0.currentUserID == currentUserID && $0.relationshipID == contract.id
        }) ?? CachedFriendship(
            relationshipID: contract.id, currentUserID: currentUserID,
            requesterUserID: contract.requesterUserId, addresseeUserID: contract.addresseeUserId,
            state: contract.state
        )
        if item.modelContext == nil { context.insert(item) }
        item.currentUserID = currentUserID
        item.requesterUserID = contract.requesterUserId
        item.addresseeUserID = contract.addresseeUserId
        item.state = contract.state
        item.createdAt = SyncRecordMapper.date(contract.createdAt) ?? item.createdAt
        item.updatedAt = SyncRecordMapper.date(contract.updatedAt) ?? .now
        item.deletedAt = contract.deletedAt.flatMap(SyncRecordMapper.date)
        item.serverVersion = max(item.serverVersion, contract.serverVersion)
        item.isOptimistic = false
        try context.save()
    }

    func upsertFollow(_ contract: FollowContractV1, currentUserID: String) throws {
        let item = try follows().first(where: {
            $0.currentUserID == currentUserID && $0.relationshipID == contract.id
        }) ?? CachedFollow(
            relationshipID: contract.id, currentUserID: currentUserID,
            followerUserID: contract.followerUserId, followedUserID: contract.followedUserId
        )
        if item.modelContext == nil { context.insert(item) }
        item.currentUserID = currentUserID
        item.followerUserID = contract.followerUserId
        item.followedUserID = contract.followedUserId
        item.createdAt = SyncRecordMapper.date(contract.createdAt) ?? item.createdAt
        item.updatedAt = SyncRecordMapper.date(contract.updatedAt) ?? .now
        item.deletedAt = contract.deletedAt.flatMap(SyncRecordMapper.date)
        item.serverVersion = max(item.serverVersion, contract.serverVersion)
        item.isOptimistic = false
        try context.save()
    }

    @discardableResult
    func enqueueOptimisticFriendRequest(currentUserID: String, targetUserID: String) throws -> CachedFriendship {
        if let existing = try friendships().first(where: {
            $0.currentUserID == currentUserID && $0.otherUserID == targetUserID && $0.deletedAt == nil
        }) { return existing }
        let relationship = CachedFriendship(
            relationshipID: "local:\(UUID().uuidString.lowercased())",
            currentUserID: currentUserID, requesterUserID: currentUserID,
            addresseeUserID: targetUserID, state: .outgoingRequest, isOptimistic: true
        )
        context.insert(relationship)
        replaceQueuedMutation(currentUserID: currentUserID, targetUserID: targetUserID, kind: .friendRequest)
        try context.save()
        return relationship
    }

    func enqueueOptimisticFollow(currentUserID: String, targetUserID: String, following: Bool) throws {
        let id = "follow:\(currentUserID):\(targetUserID)"
        let item = try follows().first(where: {
            $0.currentUserID == currentUserID && $0.relationshipID == id
        }) ?? CachedFollow(
            relationshipID: id, currentUserID: currentUserID,
            followerUserID: currentUserID, followedUserID: targetUserID,
            isOptimistic: true
        )
        if item.modelContext == nil { context.insert(item) }
        item.deletedAt = following ? nil : .now
        item.updatedAt = .now
        item.isOptimistic = true
        replaceQueuedMutation(
            currentUserID: currentUserID, targetUserID: targetUserID,
            kind: following ? .follow : .unfollow
        )
        try context.save()
    }

    func flushQueue(currentUserID: String, api: any SocialAPI) async {
        let queued = (try? mutations().filter { $0.currentUserID == currentUserID }) ?? []
        for mutation in queued.sorted(by: { $0.createdAt < $1.createdAt }) {
            do {
                switch mutation.kind {
                case .friendRequest:
                    let response = try await api.requestFriend(userID: mutation.targetUserID)
                    try upsertFriendship(response.friendship, currentUserID: currentUserID)
                case .follow, .unfollow:
                    let response = try await api.setFollowing(mutation.kind == .follow, userID: mutation.targetUserID)
                    if let follow = response.follow { try upsertFollow(follow, currentUserID: currentUserID) }
                }
                context.delete(mutation)
                try context.save()
            } catch {
                if let apiError = error as? SyncAPIError, case .server = apiError {
                    rollbackOptimistic(mutation)
                    context.delete(mutation)
                } else {
                    mutation.retryCount += 1
                    mutation.lastError = error.localizedDescription
                }
                try? context.save()
            }
        }
    }

    func cachedProfiles() throws -> [CachedSocialProfile] { try profiles() }
    func cachedFriendships(currentUserID: String) throws -> [CachedFriendship] {
        try friendships().filter { $0.currentUserID == currentUserID }
    }
    func cachedFollows(currentUserID: String) throws -> [CachedFollow] {
        try follows().filter { $0.currentUserID == currentUserID }
    }

    private func replaceQueuedMutation(currentUserID: String, targetUserID: String, kind: SocialMutationKind) {
        if let existing = try? mutations().first(where: {
            $0.currentUserID == currentUserID && $0.targetUserID == targetUserID &&
                (($0.kind == .follow || $0.kind == .unfollow) == (kind == .follow || kind == .unfollow))
        }) { context.delete(existing) }
        context.insert(SocialMutation(currentUserID: currentUserID, kind: kind, targetUserID: targetUserID))
    }

    private func rollbackOptimistic(_ mutation: SocialMutation) {
        switch mutation.kind {
        case .friendRequest:
            if let item = try? friendships().first(where: {
                $0.currentUserID == mutation.currentUserID &&
                    $0.otherUserID == mutation.targetUserID && $0.isOptimistic
            }) { context.delete(item) }
        case .follow:
            if let item = try? follows().first(where: {
                $0.currentUserID == mutation.currentUserID &&
                    $0.followedUserID == mutation.targetUserID && $0.isOptimistic
            }) {
                if item.serverVersion == 0 { context.delete(item) }
                else { item.deletedAt = .now; item.isOptimistic = false }
            }
        case .unfollow:
            if let item = try? follows().first(where: {
                $0.currentUserID == mutation.currentUserID &&
                    $0.followedUserID == mutation.targetUserID && $0.isOptimistic
            }) { item.deletedAt = nil; item.isOptimistic = false }
        }
    }

    private func otherUser(in contract: FriendshipContractV1, currentUserID: String) -> String {
        contract.requesterUserId == currentUserID ? contract.addresseeUserId : contract.requesterUserId
    }

    private static func _belongs(
        _ state: FriendshipPerspectiveState,
        to scope: FriendshipListScope
    ) -> Bool {
        switch scope {
        case .friends: state == .friends
        case .incoming: state == .incomingRequest
        case .outgoing: state == .outgoingRequest
        }
    }

    private func cacheFollowResults(
        _ items: [SocialUserResultV1],
        scope: FollowListScope,
        currentUserID: String
    ) throws {
        for item in items {
            let pair = Self._followPair(item.profile.userId, scope: scope, currentUserID: currentUserID)
            try upsertFollow(
                .init(
                    apiVersion: 1, id: "follow:\(pair.follower):\(pair.followed)",
                    followerUserId: pair.follower, followedUserId: pair.followed,
                    createdAt: SyncRecordMapper.dateString(.now),
                    updatedAt: SyncRecordMapper.dateString(.now), deletedAt: nil,
                    serverVersion: 0
                ),
                currentUserID: currentUserID
            )
        }
    }

    private static func _followPair(
        _ otherUserID: String,
        scope: FollowListScope,
        currentUserID: String
    ) -> (follower: String, followed: String) {
        scope == .following
            ? (currentUserID, otherUserID)
            : (otherUserID, currentUserID)
    }

    private static func _belongs(
        _ follow: CachedFollow,
        to scope: FollowListScope,
        currentUserID: String
    ) -> Bool {
        switch scope {
        case .following: follow.followerUserID == currentUserID
        case .followers: follow.followedUserID == currentUserID
        }
    }

    private func profiles() throws -> [CachedSocialProfile] { try context.fetch(FetchDescriptor<CachedSocialProfile>()) }
    private func friendships() throws -> [CachedFriendship] { try context.fetch(FetchDescriptor<CachedFriendship>()) }
    private func follows() throws -> [CachedFollow] { try context.fetch(FetchDescriptor<CachedFollow>()) }
    private func mutations() throws -> [SocialMutation] { try context.fetch(FetchDescriptor<SocialMutation>()) }
}
