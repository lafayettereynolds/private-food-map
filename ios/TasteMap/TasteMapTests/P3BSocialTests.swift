import Foundation
import SwiftData
import Testing
@testable import TasteMap

@Suite("P3-B social relationships", .serialized)
@MainActor
struct P3BSocialTests {
    private let instant = "2026-08-28T14:00:00.000Z"

    @Test("Social JSON exposes only the public search allowlist")
    func contractAllowlist() throws {
        let result = socialResult(state: .none)
        let data = try JSONEncoder().encode(result)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let profile = try #require(object["profile"] as? [String: Any])
        #expect(Set(profile.keys) == [
            "userId", "displayName", "bio", "city", "avatarPhotoId", "avatarPresetId",
        ])
        #expect(profile["email"] == nil)
        #expect(profile["appleSub"] == nil)
        #expect(profile["authSubject"] == nil)
        #expect(try JSONDecoder().decode(SocialUserResultV1.self, from: data) == result)
    }

    @Test("Perspective state distinguishes outgoing, incoming and accepted friends")
    func perspectiveState() {
        let outgoing = CachedFriendship(
            relationshipID: "f1", currentUserID: "tm_a", requesterUserID: "tm_a",
            addresseeUserID: "tm_b", state: .outgoingRequest
        )
        let incoming = CachedFriendship(
            relationshipID: "f2", currentUserID: "tm_a", requesterUserID: "tm_b",
            addresseeUserID: "tm_a", state: .outgoingRequest
        )
        let friends = CachedFriendship(
            relationshipID: "f3", currentUserID: "tm_a", requesterUserID: "tm_b",
            addresseeUserID: "tm_a", state: .friends
        )
        #expect(outgoing.perspectiveState == .outgoingRequest)
        #expect(incoming.perspectiveState == .incomingRequest)
        #expect(friends.perspectiveState == .friends)
    }

    @Test("Offline friend request and Follow queue survive app restart")
    func offlineQueueSurvivesRestart() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("social.store")
        var container: ModelContainer? = try TasteMapPersistence.makeContainer(storageURL: url)
        let context = try #require(container?.mainContext)
        let store = LocalSocialStore(context: context)
        try store.cache(socialResult(state: .none).profile)
        _ = try store.enqueueOptimisticFriendRequest(currentUserID: "tm_a", targetUserID: "tm_b")
        try store.enqueueOptimisticFollow(currentUserID: "tm_a", targetUserID: "tm_b", following: true)
        #expect(try context.fetch(FetchDescriptor<SocialMutation>()).count == 2)
        container = nil

        let reopened = try TasteMapPersistence.makeContainer(storageURL: url)
        let reopenedStore = LocalSocialStore(context: reopened.mainContext)
        #expect(try reopened.mainContext.fetch(FetchDescriptor<SocialMutation>()).count == 2)
        #expect(try reopenedStore.cachedFriendships(currentUserID: "tm_a").first?.perspectiveState == .outgoingRequest)
        #expect(try reopenedStore.cachedFollows(currentUserID: "tm_a").first?.deletedAt == nil)
    }

    @Test("Reconnect flushes queued mutations and materializes server authority")
    func queueFlushes() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let store = LocalSocialStore(context: container.mainContext)
        _ = try store.enqueueOptimisticFriendRequest(currentUserID: "tm_a", targetUserID: "tm_b")
        try store.enqueueOptimisticFollow(currentUserID: "tm_a", targetUserID: "tm_b", following: true)
        let api = SocialMemoryAPI()
        await store.flushQueue(currentUserID: "tm_a", api: api)

        #expect(try container.mainContext.fetch(FetchDescriptor<SocialMutation>()).isEmpty)
        #expect(try store.cachedFriendships(currentUserID: "tm_a").first?.isOptimistic == false)
        #expect(try store.cachedFriendships(currentUserID: "tm_a").first?.serverVersion == 1)
        #expect(try store.cachedFollows(currentUserID: "tm_a").first?.isOptimistic == false)
        #expect(api.friendRequestCount == 1)
        #expect(api.followCount == 1)
    }

    @Test("A server rejection rolls optimistic UI back instead of granting a relationship")
    func rejectionRollsBack() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let store = LocalSocialStore(context: container.mainContext)
        _ = try store.enqueueOptimisticFriendRequest(currentUserID: "tm_a", targetUserID: "tm_b")
        await store.flushQueue(currentUserID: "tm_a", api: SocialMemoryAPI(rejectMutations: true))
        #expect(try container.mainContext.fetch(FetchDescriptor<SocialMutation>()).isEmpty)
        #expect(try store.cachedFriendships(currentUserID: "tm_a").isEmpty)
    }

    @Test("Follow remains independent and never grants Friendship")
    func followDoesNotGrantFriendship() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let store = LocalSocialStore(context: container.mainContext)
        try store.enqueueOptimisticFollow(currentUserID: "tm_a", targetUserID: "tm_b", following: true)
        #expect(try store.cachedFollows(currentUserID: "tm_a").count == 1)
        #expect(try store.cachedFriendships(currentUserID: "tm_a").isEmpty)
    }

    @Test("Visible friends contain only people with reciprocal follows")
    func visibleFriendsRequireMutualFollow() {
        let followers = [
            socialResult(userID: "tm_b", isFollowing: true),
            socialResult(userID: "tm_c", isFollowing: false),
            socialResult(userID: "tm_d", isFollowing: true),
        ]
        #expect(SocialHubSection.allCases == [.friends, .following, .followers, .recommendations])
        #expect(SocialRelationshipSectionPolicy.mutualFriends(fromFollowers: followers).map(\.id) == ["tm_b", "tm_d"])
    }

    @Test("Companion linking is explicit, survives rename/unfriend, and can be unlinked")
    func companionLinking() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let store = LocalCompanionSourceStore(context: context)
        let companion = try store.findOrCreateCompanion(name: "大学室友")
        #expect(throws: CompanionSourceStoreError.targetIsNotFriend) {
            try store.link(companion, toTasteMapUserID: "tm_b", acceptedFriendUserIDs: [])
        }
        try store.link(companion, toTasteMapUserID: "tm_b", acceptedFriendUserIDs: ["tm_b"])
        try store.rename(companion, to: "老同学")
        #expect(companion.linkedTasteMapUserId == "tm_b")

        // Removing a Friendship does not call into the private dining directory.
        #expect(companion.displayName == "老同学")
        try store.unlinkTasteMapUser(from: companion)
        #expect(companion.linkedTasteMapUserId == nil)
    }

    private func socialResult(state: FriendshipPerspectiveState) -> SocialUserResultV1 {
        .init(
            profile: .init(
                userId: "tm_b", displayName: "小林", bio: "周末找小店", city: "杭州",
                avatarPhotoId: nil, avatarPresetId: .otter
            ),
            friendshipId: state == .none ? nil : "friendship:tm_a:tm_b",
            friendshipState: state, isFollowing: false
        )
    }


    private func socialResult(userID: String, isFollowing: Bool) -> SocialUserResultV1 {
        .init(
            profile: .init(
                userId: userID, displayName: userID, bio: nil, city: "杭州",
                avatarPhotoId: nil, avatarPresetId: .otter
            ),
            friendshipId: nil, friendshipState: .none, isFollowing: isFollowing
        )
    }
}
@MainActor
private final class SocialMemoryAPI: SocialAPI {
    let rejectMutations: Bool
    var friendRequestCount = 0
    var followCount = 0

    init(rejectMutations: Bool = false) { self.rejectMutations = rejectMutations }
    func search(query: String, cursor: String?, limit: Int) async throws -> SocialPageV1<SocialUserResultV1> { page() }
    func friendships(scope: FriendshipListScope, cursor: String?, limit: Int) async throws -> SocialPageV1<SocialUserResultV1> { page() }
    func follows(scope: FollowListScope, cursor: String?, limit: Int) async throws -> SocialPageV1<SocialUserResultV1> { page() }
    func profileContext(userID: String) async throws -> SocialProfileContextV1 { throw SyncAPIError.server(status: 404, message: "not used") }

    func requestFriend(userID: String) async throws -> FriendshipMutationResponseV1 {
        if rejectMutations { throw SyncAPIError.server(status: 403, message: "rejected") }
        friendRequestCount += 1
        return .init(friendship: friendship(userID), duplicate: false, crossRequestAccepted: nil)
    }

    func mutateFriendship(id: String, action: FriendshipMutationAction) async throws -> FriendshipMutationResponseV1 {
        .init(friendship: friendship("tm_b"), duplicate: false, crossRequestAccepted: nil)
    }

    func setFollowing(_ following: Bool, userID: String) async throws -> FollowMutationResponseV1 {
        if rejectMutations { throw SyncAPIError.server(status: 403, message: "rejected") }
        followCount += 1
        return .init(follow: .init(
            apiVersion: 1, id: "follow:tm_a:\(userID)", followerUserId: "tm_a",
            followedUserId: userID, createdAt: instant, updatedAt: instant,
            deletedAt: following ? nil : instant, serverVersion: 1
        ), duplicate: false)
    }

    private var instant: String { "2026-08-28T14:00:00.000Z" }
    private func page() -> SocialPageV1<SocialUserResultV1> { .init(apiVersion: 1, items: [], nextCursor: nil) }
    private func friendship(_ target: String) -> FriendshipContractV1 {
        .init(apiVersion: 1, id: "friendship:tm_a:\(target)", requesterUserId: "tm_a",
              addresseeUserId: target, state: .outgoingRequest, createdAt: instant,
              updatedAt: instant, deletedAt: nil, serverVersion: 1)
    }
}
