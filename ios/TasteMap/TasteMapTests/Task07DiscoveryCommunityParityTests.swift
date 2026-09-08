import Foundation
import SwiftData
import Testing
@testable import TasteMap

@MainActor
struct Task07DiscoveryCommunityParityTests {
    @Test func recommendationSortAndFiltersUseVisibleRealProjections() {
        let cards = [
            card(key: "far-high", rank: 2, rating: 4.8, latitude: 30.30),
            card(key: "near-low", rank: 1, rating: 3.8, latitude: 30.251),
            card(key: "near-high", rank: 3, rating: 4.6, latitude: 30.252),
        ]
        let anchor = DiscoveryBrowseCoordinate(latitude: 30.25, longitude: 120.16)

        let recommended = DiscoveryBrowseResolver.resolve(
            cards: cards, filters: DiscoveryBrowseFilters(), anchor: nil
        )
        #expect(recommended.cards.map(\.restaurant.globalKey) == ["near-low", "far-high", "near-high"])

        var highest = DiscoveryBrowseFilters()
        highest.sort = .highestRated
        highest.minimumRating = 4.5
        let rated = DiscoveryBrowseResolver.resolve(cards: cards, filters: highest, anchor: nil)
        #expect(rated.cards.map(\.restaurant.globalKey) == ["far-high", "near-high"])

        var nearest = DiscoveryBrowseFilters()
        nearest.sort = .nearest
        nearest.maximumDistanceKilometers = 1
        let nearby = DiscoveryBrowseResolver.resolve(cards: cards, filters: nearest, anchor: anchor)
        #expect(nearby.cards.map(\.restaurant.globalKey) == ["near-low", "near-high"])
    }

    @Test func distanceFilterNeverPretendsToHaveLocation() {
        var filters = DiscoveryBrowseFilters()
        filters.maximumDistanceKilometers = 3
        let resolution = DiscoveryBrowseResolver.resolve(
            cards: [card(key: "one", rank: 1, rating: 4.5, latitude: 30.25)],
            filters: filters,
            anchor: nil
        )
        #expect(resolution.cards.isEmpty)
        #expect(resolution.emptyReason == .locationUnavailable)
    }

    @Test func providerNeutralCandidatePreservesEveryIdentityButNoAuthorData() {
        let projection = DiscoveryRestaurantProjectionV1(
            globalKey: "place:multi",
            placeIdentities: [
                .init(provider: .appleMaps, externalId: "apple-multi", isPrimary: true),
                .init(provider: .amap, externalId: "amap-multi", isPrimary: false),
            ],
            name: "公开餐厅", address: "公开地址", city: "杭州",
            latitude: 30.25, longitude: 120.16, tags: ["日料"],
            pricePerPerson: 128, merchantImageUrl: "https://example.com/merchant.jpg",
            markerEmoji: "🍣", photo: .init(photoId: UUID().uuidString, variant: .thumbnail)
        )
        let candidate = projection.restaurantCandidate
        #expect(candidate.placeIdentities.map(\.externalID) == ["apple-multi", "amap-multi"])
        #expect(candidate.placeIdentities.first?.isPrimary == true)
        #expect(candidate.appleMapItemIdentifier == "apple-multi")
        #expect(candidate.photoURL?.absoluteString == "https://example.com/merchant.jpg")
    }

    @Test func sparseSimilarityNeverDisplaysPrecisePercent() {
        let sparse = DiscoveryCardV1(
            id: "sparse", mode: .similarTaste,
            restaurant: projection(key: "sparse", latitude: 30.25), viewerState: .none,
            ratings: ratings(4.5), reasons: [], sourceUser: nil,
            similarity: .init(percent: 97, sharedRestaurantCount: 2), trend: nil,
            cacheScope: .public, rank: 1, score: 1
        )
        let supported = DiscoveryCardV1(
            id: "supported", mode: .similarTaste,
            restaurant: projection(key: "supported", latitude: 30.25), viewerState: .none,
            ratings: ratings(4.5), reasons: [], sourceUser: nil,
            similarity: .init(percent: 82, sharedRestaurantCount: 3), trend: nil,
            cacheScope: .public, rank: 1, score: 1
        )
        #expect(sparse.displayableSimilarity == nil)
        #expect(supported.displayableSimilarity?.percent == 82)
    }

    @Test func discoveryEvidenceRequiresSevenPointFiveButKeepsTrendCounts() {
        let unratedCommunity = communityItem(
            id: "unrated", globalKey: "place:unrated", rating: nil
        )
        let lowCommunity = communityItem(
            id: "low", globalKey: "place:low", rating: 3.5
        )
        let boundaryCommunity = communityItem(
            id: "boundary", globalKey: "place:boundary", rating: 3.75
        )
        let ratedCommunity = communityItem(
            id: "rated", globalKey: "place:rated", rating: 4.5
        )
        #expect(!unratedCommunity.isEligibleForDiscoveryFeed)
        #expect(!lowCommunity.isEligibleForDiscoveryFeed)
        #expect(boundaryCommunity.isEligibleForDiscoveryFeed)
        #expect(ratedCommunity.isEligibleForDiscoveryFeed)

        let unratedActivity = DiscoveryActivityProjectionV1(
            visitId: "visit:unrated", visitedAt: "2026-09-04T00:00:00.000Z", rating: nil
        )
        let lowActivity = DiscoveryActivityProjectionV1(
            visitId: "visit:low", visitedAt: "2026-09-04T00:00:00.000Z", rating: 3.5
        )
        let boundaryActivity = DiscoveryActivityProjectionV1(
            visitId: "visit:boundary", visitedAt: "2026-09-04T00:00:00.000Z", rating: 3.75
        )
        let systemForYou = discoveryPolicyCard(mode: .forYou, activity: nil)
        let activityForYou = discoveryPolicyCard(mode: .forYou, activity: unratedActivity)
        let similar = discoveryPolicyCard(mode: .similarTaste, activity: unratedActivity)
        let lowSimilar = discoveryPolicyCard(mode: .similarTaste, activity: lowActivity)
        let boundarySimilar = discoveryPolicyCard(mode: .similarTaste, activity: boundaryActivity)
        let trending = discoveryPolicyCard(mode: .trending, activity: unratedActivity)

        #expect(systemForYou.isEligibleForDiscoveryPresentation)
        #expect(!activityForYou.isEligibleForDiscoveryPresentation)
        #expect(!similar.isEligibleForDiscoveryPresentation)
        #expect(!lowSimilar.isEligibleForDiscoveryPresentation)
        #expect(boundarySimilar.isEligibleForDiscoveryPresentation)
        #expect(trending.isEligibleForDiscoveryPresentation)
        #expect(trending.trend?.uniqueVisitorCount == 1)
    }

    @Test func communityViewerActionUpdatesAllOwnCachesAndNoOtherViewer() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let store = LocalCommunityStore(context: container.mainContext)
        let feedItem = communityItem(id: "visit-one", globalKey: "place:shared")
        try store.replace(
            items: [feedItem], currentUserID: "tm_viewer_a",
            routeKey: LocalCommunityStore.feedRoute(.latest), fetchedAt: .now
        )
        try store.replace(
            items: [feedItem], currentUserID: "tm_viewer_a",
            routeKey: LocalCommunityStore.feedRoute(.following), fetchedAt: .now
        )
        try store.replace(
            items: [feedItem], currentUserID: "tm_viewer_b",
            routeKey: LocalCommunityStore.feedRoute(.latest), fetchedAt: .now
        )

        try store.updateViewerState(
            globalKey: "place:shared", currentUserID: "tm_viewer_a", state: .wantToGo
        )
        #expect(try store.cached(
            currentUserID: "tm_viewer_a", routeKey: LocalCommunityStore.feedRoute(.latest)
        )?.items.first?.viewerState == .wantToGo)
        #expect(try store.cached(
            currentUserID: "tm_viewer_a", routeKey: LocalCommunityStore.feedRoute(.following)
        )?.items.first?.viewerState == .wantToGo)
        #expect(try store.cached(
            currentUserID: "tm_viewer_b", routeKey: LocalCommunityStore.feedRoute(.latest)
        )?.items.first?.viewerState == DiscoveryViewerRestaurantStateV1.none)
    }

    @Test func emptyRefreshRemovesTombstonedOrNewlyPrivateContent() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let store = LocalCommunityStore(context: container.mainContext)
        let route = LocalCommunityStore.feedRoute(.latest)
        try store.replace(
            items: [communityItem(id: "removed", globalKey: "place:removed")],
            currentUserID: "tm_viewer", routeKey: route, fetchedAt: .now
        )
        try store.replace(items: [], currentUserID: "tm_viewer", routeKey: route, fetchedAt: .now)
        #expect(try store.cached(currentUserID: "tm_viewer", routeKey: route) == nil)
    }

    @Test func explicitCommunityActionCreatesOnlyViewerRestaurantAndMutation() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let item = communityItem(id: "public-visit", globalKey: "place:public")
        _ = try LocalDiscoveryStore(context: context).addToWantToGo(
            projection: item.restaurant.discoveryProjection,
            among: []
        )
        #expect(try context.fetch(FetchDescriptor<Restaurant>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<Visit>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<PhotoAsset>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<SyncMutation>()).count == 1)
    }

    private func card(key: String, rank: Int, rating: Double, latitude: Double) -> DiscoveryCardV1 {
        .init(
            id: key, mode: .forYou, restaurant: projection(key: key, latitude: latitude),
            viewerState: .none, ratings: ratings(rating),
            reasons: [.init(code: "REAL", text: "真实推荐依据")], sourceUser: nil,
            similarity: nil, trend: nil, cacheScope: .public, rank: rank, score: Double(100 - rank)
        )
    }

    private func projection(key: String, latitude: Double) -> DiscoveryRestaurantProjectionV1 {
        .init(
            globalKey: key,
            placeIdentities: [.init(provider: .appleMaps, externalId: "apple-\(key)", isPrimary: true)],
            name: key, address: "地址", city: "杭州", latitude: latitude, longitude: 120.16,
            tags: [], pricePerPerson: nil, merchantImageUrl: nil, markerEmoji: "🍜", photo: nil
        )
    }

    private func ratings(_ value: Double) -> DiscoveryRatingsV1 {
        .init(
            mine: .init(value: nil, sampleCount: 0),
            community: .init(value: value, sampleCount: 8),
            friends: .init(value: nil, sampleCount: 0),
            similarTaste: .init(value: nil, sampleCount: 0)
        )
    }

    private func discoveryPolicyCard(
        mode: DiscoveryModeV1,
        activity: DiscoveryActivityProjectionV1?
    ) -> DiscoveryCardV1 {
        .init(
            id: "policy-\(mode.rawValue)", mode: mode,
            restaurant: projection(key: "policy-\(mode.rawValue)", latitude: 30.25),
            viewerState: .none, ratings: ratings(4.5), reasons: [], sourceUser: nil,
            activity: activity, similarity: nil,
            trend: mode == .trending
                ? .init(windowDays: 7, uniqueVisitorCount: 1, wantToGoCount: 0)
                : nil,
            cacheScope: .public, rank: 1, score: 1
        )
    }

    private func communityItem(
        id: String,
        globalKey: String,
        rating: Double? = 4.5
    ) -> PublicContentItemV1 {
        let user = PublicContentUserV1(
            userId: "tm_author", displayName: "作者", bio: nil, city: "杭州",
            avatarPhotoId: nil, avatarPresetId: .otter, friendshipId: nil,
            friendshipState: .none, isFollowing: true
        )
        let restaurant = PublicContentRestaurantV1(
            globalKey: globalKey,
            placeIdentities: [.init(provider: .appleMaps, externalId: "apple-public", isPrimary: true)],
            name: "公开餐厅", address: "公开地址", city: "杭州", latitude: 30.25,
            longitude: 120.16, tags: ["日料"], pricePerPerson: 128,
            merchantImageUrl: nil, markerEmoji: "🍣", photo: nil
        )
        return PublicContentItemV1(
            id: id, kind: .visit, eventAt: "2026-08-30T00:00:00.000Z",
            updatedAt: "2026-08-30T00:00:00.000Z", user: user, restaurant: restaurant,
            visit: .init(
                id: id, ownerUserId: user.userId, restaurantGlobalKey: globalKey,
                visitedAt: "2026-08-30T00:00:00.000Z", rating: rating,
                note: "作者公开备注", visibility: .public,
                photos: [.init(photoId: UUID().uuidString, variant: .thumbnail)],
                updatedAt: "2026-08-30T00:00:00.000Z"
            ),
            viewerState: .none, cacheScope: .public
        )
    }
}
