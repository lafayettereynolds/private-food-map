import Foundation
import SwiftData
import Testing
@testable import TasteMap

@MainActor
struct P3DCommunityTests {
    @Test func publicContractDecodesNullableVisitAndAppleMapsIdentityWithoutPrivateFields() throws {
        let page = try JSONDecoder().decode(CommunityFeedPageV1.self, from: Data(Self.pageJSON.utf8))
        #expect(page.apiVersion == 1)
        #expect(page.items[0].visit?.rating == nil)
        #expect(page.items[0].restaurant.placeIdentities == [
            PublicContentPlaceIdentityV1(provider: .appleMaps, externalId: "apple-public", isPrimary: true),
        ])
        #expect(page.items[0].visit?.note == "公开备注")
        let encoded = try JSONEncoder().encode(page)
        let text = String(decoding: encoded, as: UTF8.self)
        #expect(!text.contains("myActualSpend"))
        #expect(!text.contains("recommendationSource"))
        #expect(!text.contains("storageKey"))
    }

    @Test func communityCacheIsViewerAndRouteScopedAndPersistsOnlyPublicItems() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let store = LocalCommunityStore(context: container.mainContext)
        try store.replace(
            items: [item(id: "public", scope: .public), item(id: "friend", scope: .friends)],
            currentUserID: "tm_a", routeKey: LocalCommunityStore.feedRoute(.latest), fetchedAt: .now
        )
        try store.replace(
            items: [item(id: "other", scope: .public)], currentUserID: "tm_b",
            routeKey: LocalCommunityStore.feedRoute(.latest), fetchedAt: .now
        )
        let aValue = try store.cached(currentUserID: "tm_a", routeKey: LocalCommunityStore.feedRoute(.latest))
        let a = try #require(aValue)
        #expect(a.items.map(\.id) == ["public"])
        let bValue = try store.cached(currentUserID: "tm_b", routeKey: LocalCommunityStore.feedRoute(.latest))
        let b = try #require(bValue)
        #expect(b.items.map(\.id) == ["other"])
    }

    @Test func firstPageReplacementRemovesTombstonesAndVisibilityRevocations() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let store = LocalCommunityStore(context: container.mainContext)
        let route = LocalCommunityStore.profileRoute(userID: "tm_owner", section: .visits)
        try store.replace(
            items: [item(id: "kept", scope: .public), item(id: "deleted", scope: .public)],
            currentUserID: "tm_viewer", routeKey: route, fetchedAt: .now
        )
        try store.replace(
            items: [item(id: "kept", scope: .public)],
            currentUserID: "tm_viewer", routeKey: route, fetchedAt: .now
        )
        #expect(try store.cached(currentUserID: "tm_viewer", routeKey: route)?.items.map(\.id) == ["kept"])
    }

    @Test func invalidatingRelationshipOwnerPurgesTheirPersistedPublicProjection() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let store = LocalCommunityStore(context: container.mainContext)
        try store.replace(
            items: [item(id: "owner-a", scope: .public, owner: "tm_owner_a"),
                    item(id: "owner-b", scope: .public, owner: "tm_owner_b")],
            currentUserID: "tm_viewer", routeKey: LocalCommunityStore.feedRoute(.following), fetchedAt: .now
        )
        try store.invalidateOwner("tm_owner_a", currentUserID: "tm_viewer")
        #expect(try store.cached(currentUserID: "tm_viewer", routeKey: LocalCommunityStore.feedRoute(.following))?.items.map(\.id) == ["owner-b"])
    }

    @Test func followingFeedAuthorsPopulateProfileCountAndOfflinePeopleList() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let store = LocalCommunityStore(context: context)
        try store.replace(
            items: [item(id: "followed", scope: .public, owner: "tm_followed", isFollowing: true)],
            currentUserID: "tm_viewer",
            routeKey: LocalCommunityStore.feedRoute(.following),
            fetchedAt: .now
        )

        let social = LocalSocialStore(context: context)
        let follows = try social.cachedFollows(currentUserID: "tm_viewer")
        let profiles = try social.cachedProfiles()
        let statistics = ProfileSocialStatisticsLoader.cached(
            context: context,
            currentUserID: "tm_viewer"
        )

        #expect(statistics.followingCount == 1)
        #expect(follows.contains {
            $0.deletedAt == nil && $0.followerUserID == "tm_viewer"
                && $0.followedUserID == "tm_followed"
        })
        #expect(profiles.contains {
            $0.tasteMapUserID == "tm_followed" && $0.displayName == "公开用户"
        })
    }

    @Test func publicRestaurantCanEnterOfflineWantToGoOnlyOnExplicitAction() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let projection = item(id: "restaurant", scope: .public).restaurant.discoveryProjection
        #expect(try context.fetch(FetchDescriptor<Restaurant>()).isEmpty)
        let created = try LocalDiscoveryStore(context: context).addToWantToGo(projection: projection, among: [])
        #expect(created.status == .wantToGo)
        #expect(try context.fetch(FetchDescriptor<Restaurant>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<SyncMutation>()).count == 1)
        let payload = try JSONDecoder().decode(RestaurantJSONContractV1.self, from: #require(created.remoteRecordData))
        #expect(payload.placeIdentities.contains { $0.provider == .appleMaps && $0.externalId == "apple-public" })
    }

    private func item(
        id: String,
        scope: PublicContentCacheScopeV1,
        owner: String = "tm_owner",
        isFollowing: Bool = false
    ) -> PublicContentItemV1 {
        let restaurant = PublicContentRestaurantV1(
            globalKey: "place:\(id)",
            placeIdentities: [.init(provider: .appleMaps, externalId: "apple-public", isPrimary: true)],
            name: "公开餐厅", address: "西湖路 1 号", city: "杭州", latitude: 30.2,
            longitude: 120.1, tags: ["日料"], pricePerPerson: 128,
            merchantImageUrl: nil, markerEmoji: "🍣", photo: nil
        )
        let user = PublicContentUserV1(
            userId: owner, displayName: "公开用户", bio: nil, city: "杭州",
            avatarPhotoId: nil, avatarPresetId: .otter, friendshipId: nil,
            friendshipState: scope == .friends ? .friends : .none, isFollowing: isFollowing
        )
        return PublicContentItemV1(
            id: id, kind: .visit, eventAt: "2026-08-28T12:00:00.000Z",
            updatedAt: "2026-08-28T12:00:00.000Z", user: user, restaurant: restaurant,
            visit: .init(
                id: "visit-\(id)", ownerUserId: owner, restaurantGlobalKey: restaurant.globalKey,
                visitedAt: "2026-08-28T12:00:00.000Z", rating: nil, note: "公开备注",
                visibility: scope == .friends ? .friends : .public, photos: [],
                updatedAt: "2026-08-28T12:00:00.000Z"
            ),
            viewerState: .none, cacheScope: scope
        )
    }

    private static let pageJSON = """
    {"apiVersion":1,"scope":"latest","generatedAt":"2026-08-28T12:00:00.000Z","items":[{"id":"visit:one","kind":"visit","eventAt":"2026-08-28T11:00:00.000Z","updatedAt":"2026-08-28T12:00:00.000Z","user":{"userId":"tm_owner","displayName":"公开用户","bio":null,"city":"杭州","avatarPhotoId":null,"avatarPresetId":"otter","friendshipId":null,"friendshipState":"none","isFollowing":false},"restaurant":{"globalKey":"place:one","placeIdentities":[{"provider":"apple_maps","externalId":"apple-public","isPrimary":true}],"name":"公开餐厅","address":"西湖路 1 号","city":"杭州","latitude":30.2,"longitude":120.1,"tags":[],"pricePerPerson":null,"merchantImageUrl":null,"markerEmoji":"🍣","photo":null},"visit":{"id":"visit-one","ownerUserId":"tm_owner","restaurantGlobalKey":"place:one","visitedAt":"2026-08-28T11:00:00.000Z","rating":null,"note":"公开备注","visibility":"public","photos":[],"updatedAt":"2026-08-28T12:00:00.000Z"},"viewerState":"none","cacheScope":"public"}],"nextCursor":null}
    """
}
