import Foundation
import SwiftData
import Testing
@testable import TasteMap

@Suite("P3-E social hardening", .serialized)
@MainActor
struct P3ESocialHardeningTests {
    @Test("A complete relationship refresh removes stale multi-device friendship state")
    func completeRelationshipRefreshRevokesStaleFriendship() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let store = LocalSocialStore(context: container.mainContext)
        try store.cache(result(state: .friends), currentUserID: "tm_a")
        try store.upsertFriendship(
            .init(
                apiVersion: 1, id: "friendship:tm_a:tm_b",
                requesterUserId: "tm_a", addresseeUserId: "tm_b", state: .friends,
                createdAt: instant, updatedAt: instant, deletedAt: nil, serverVersion: 2
            ),
            currentUserID: "tm_a"
        )

        try store.reconcileCompleteFriendshipPage(
            .init(apiVersion: 1, items: [], nextCursor: nil),
            scope: .friends,
            currentUserID: "tm_a"
        )

        let cached = try #require(store.cachedFriendships(currentUserID: "tm_a").first)
        #expect(cached.perspectiveState == .none)
        #expect(cached.deletedAt != nil)
        #expect(!cached.isOptimistic)
        #expect(try store.cachedProfiles().allSatisfy { $0.tasteMapUserID != "tm_b" })
    }

    @Test("A partial relationship page never deletes an unseen pagination tail")
    func partialPagePreservesUnseenTail() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let store = LocalSocialStore(context: container.mainContext)
        try store.upsertFriendship(
            .init(
                apiVersion: 1, id: "friendship:tm_a:tm_tail",
                requesterUserId: "tm_a", addresseeUserId: "tm_tail", state: .friends,
                createdAt: instant, updatedAt: instant, deletedAt: nil, serverVersion: 1
            ),
            currentUserID: "tm_a"
        )
        try store.reconcileCompleteFriendshipPage(
            .init(apiVersion: 1, items: [], nextCursor: "opaque-tail"),
            scope: .friends,
            currentUserID: "tm_a"
        )
        #expect(try store.cachedFriendships(currentUserID: "tm_a").first?.perspectiveState == .friends)
    }

    @Test("Authoritative none relationship revokes a stale direct-profile cache entry")
    func authoritativeNoneRevokesCachedRelationship() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let store = LocalSocialStore(context: container.mainContext)
        try store.upsertFriendship(
            .init(
                apiVersion: 1, id: "friendship:tm_a:tm_b",
                requesterUserId: "tm_a", addresseeUserId: "tm_b", state: .friends,
                createdAt: instant, updatedAt: instant, deletedAt: nil, serverVersion: 2
            ),
            currentUserID: "tm_a"
        )
        try store.cache(result(state: .none), currentUserID: "tm_a")
        let cached = try #require(store.cachedFriendships(currentUserID: "tm_a").first)
        #expect(cached.perspectiveState == .none)
        #expect(cached.deletedAt != nil)
    }

    @Test("A complete paginated Follow refresh revokes stale tails but a partial page does not")
    func followPaginationReconciliation() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let store = LocalSocialStore(context: container.mainContext)
        try store.upsertFollow(
            .init(
                apiVersion: 1, id: "follow:tm_a:tm_b",
                followerUserId: "tm_a", followedUserId: "tm_b",
                createdAt: instant, updatedAt: instant, deletedAt: nil,
                serverVersion: 2
            ),
            currentUserID: "tm_a"
        )

        let partial = SocialPageV1(
            apiVersion: 1,
            items: [result(userID: "tm_c", state: .none)],
            nextCursor: "opaque-tail"
        )
        try store.cacheFollowPage(partial, scope: .following, currentUserID: "tm_a")
        #expect(try store.cachedFollows(currentUserID: "tm_a")
            .first { $0.followedUserID == "tm_b" }?.deletedAt == nil)

        try store.reconcileFollowResults(
            partial.items, scope: .following, currentUserID: "tm_a"
        )
        let follows = try store.cachedFollows(currentUserID: "tm_a")
        #expect(follows.first { $0.followedUserID == "tm_b" }?.deletedAt != nil)
        #expect(follows.first { $0.followedUserID == "tm_c" }?.deletedAt == nil)
    }

    @Test("Logout purges social-derived caches without deleting personal Restaurant data")
    func logoutCacheIsolation() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let store = LocalSocialStore(context: context)
        try store.cache(result(state: .friends), currentUserID: "tm_a")
        try store.enqueueOptimisticFollow(currentUserID: "tm_a", targetUserID: "tm_b", following: true)

        let community = TasteMapUITestFixtures.communityPage(scope: .latest)
        try LocalCommunityStore(context: context).replace(
            items: community.items.filter { $0.cacheScope == .public },
            currentUserID: "tm_a", routeKey: LocalCommunityStore.feedRoute(.latest),
            fetchedAt: .now
        )
        try LocalDiscoveryStore(context: context).replaceCache(
            page: TasteMapUITestFixtures.discoveryPage(mode: .forYou, window: 7),
            currentUserID: "tm_a", trendWindowDays: 7
        )
        context.insert(Restaurant(
            name: "用户自己的餐厅", address: "杭州", latitude: 30.2, longitude: 120.1
        ))
        try context.save()

        try store.purgeAllSocialDerivedCaches()

        #expect(try context.fetch(FetchDescriptor<CachedSocialProfile>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<CachedFriendship>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<CachedFollow>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<SocialMutation>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<CachedCommunityContent>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<CachedDiscoveryPlacement>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<CachedDiscoveryRestaurant>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Restaurant>()).count == 1)
    }

    private let instant = "2026-08-28T16:00:00.000Z"

    private func result(
        userID: String = "tm_b",
        state: FriendshipPerspectiveState
    ) -> SocialUserResultV1 {
        .init(
            profile: .init(
                userId: userID, displayName: "安全测试用户", bio: "仅用于缓存隔离测试",
                city: "杭州", avatarPhotoId: nil, avatarPresetId: .otter
            ),
            friendshipId: state == .none ? nil : "friendship:tm_a:tm_b",
            friendshipState: state,
            isFollowing: false
        )
    }
}
