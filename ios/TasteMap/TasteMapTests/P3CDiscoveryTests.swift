import Foundation
import SwiftData
import Testing
@testable import TasteMap

@MainActor
struct P3CDiscoveryTests {
    @Test func discoveryContractDecodesNullableRatingsAndAppleIdentity() throws {
        let page = try JSONDecoder().decode(DiscoveryPageV1.self, from: Data(Self.pageJSON.utf8))
        #expect(page.apiVersion == 1)
        #expect(page.mode == .forYou)
        #expect(page.items[0].ratings.mine.value == nil)
        #expect(page.items[0].restaurant.placeIdentities == [
            DiscoveryPlaceIdentityV1(provider: .appleMaps, externalId: "apple-only", isPrimary: true),
        ])
        #expect(page.items[0].sourceUser?.friendshipState == .friends)
    }

    @Test func cacheSharesOneRestaurantAcrossModulesAndSeparatesUsers() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let store = LocalDiscoveryStore(context: container.mainContext)
        try store.replaceCache(page: page(mode: .forYou), currentUserID: "tm_a", trendWindowDays: 7)
        try store.replaceCache(page: page(mode: .trending), currentUserID: "tm_a", trendWindowDays: 7)
        try store.replaceCache(page: page(mode: .forYou), currentUserID: "tm_b", trendWindowDays: 7)
        let restaurants = try container.mainContext.fetch(FetchDescriptor<CachedDiscoveryRestaurant>())
        let placements = try container.mainContext.fetch(FetchDescriptor<CachedDiscoveryPlacement>())
        #expect(restaurants.filter { $0.currentUserID == "tm_a" }.count == 1)
        #expect(restaurants.filter { $0.currentUserID == "tm_b" }.count == 1)
        #expect(placements.filter { $0.currentUserID == "tm_a" }.count == 2)
    }

    @Test func friendsOnlyCardIsNeverPersistedForOfflineAuthorization() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let store = LocalDiscoveryStore(context: container.mainContext)
        var protected = card(mode: .forYou)
        protected = DiscoveryCardV1(
            id: protected.id, mode: protected.mode, restaurant: protected.restaurant,
            viewerState: protected.viewerState, ratings: protected.ratings, reasons: protected.reasons,
            sourceUser: protected.sourceUser, similarity: protected.similarity, trend: protected.trend,
            cacheScope: .friends, rank: protected.rank, score: protected.score
        )
        try store.replaceCache(
            page: DiscoveryPageV1(apiVersion: 1, mode: .forYou, city: "杭州",
                                  personalizationConfidence: .high,
                                  generatedAt: "2026-08-28T12:00:00.000Z", items: [protected], nextCursor: nil),
            currentUserID: "tm_a", trendWindowDays: 7
        )
        #expect(try container.mainContext.fetch(FetchDescriptor<CachedDiscoveryRestaurant>()).isEmpty)
        #expect(try store.cachedPage(mode: .forYou, city: "杭州", currentUserID: "tm_a", trendWindowDays: 7) == nil)
    }

    @Test func cacheSurvivesContainerReopen() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("p3c-cache-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        var container: ModelContainer? = try TasteMapPersistence.makeContainer(storageURL: url)
        try LocalDiscoveryStore(context: container!.mainContext)
            .replaceCache(page: page(mode: .forYou), currentUserID: "tm_a", trendWindowDays: 7)
        container = nil
        let reopened = try TasteMapPersistence.makeContainer(storageURL: url)
        let cached = try LocalDiscoveryStore(context: reopened.mainContext)
            .cachedPage(mode: .forYou, city: "杭州", currentUserID: "tm_a", trendWindowDays: 7)
        #expect(cached?.cards.first?.restaurant.globalKey == "place:shared")
    }

    @Test func discoveryWantToGoIsOfflineFirstIdempotentAndPreservesProviderIdentity() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let store = LocalDiscoveryStore(context: context)
        let projection = restaurant(provider: .amap, externalID: "amap-shared")
        let first = try store.addToWantToGo(projection: projection, among: [])
        let second = try store.addToWantToGo(
            projection: projection,
            among: try context.fetch(FetchDescriptor<Restaurant>())
        )
        #expect(first.id == second.id)
        #expect(first.status == .wantToGo)
        #expect(try context.fetch(FetchDescriptor<Restaurant>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<SyncMutation>()).count == 1)
        let record = try JSONDecoder().decode(RestaurantJSONContractV1.self, from: #require(first.remoteRecordData))
        #expect(record.placeIdentities.first?.provider == .amap)
        #expect(record.placeIdentities.first?.externalId == "amap-shared")
    }

    @Test func discoveryNeverRegressesVisitedRestaurantToWantToGo() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let visited = Restaurant(
            name: "Visited", address: "西湖路 1 号", latitude: 30.2, longitude: 120.1,
            appleMapItemIdentifier: "apple-only", city: "杭州", status: .visited
        )
        context.insert(visited); try context.save()
        let resolved = try LocalDiscoveryStore(context: context)
            .addToWantToGo(projection: restaurant(provider: .appleMaps, externalID: "apple-only"), among: [visited])
        #expect(resolved.id == visited.id)
        #expect(resolved.status == .visited)
        #expect(try context.fetch(FetchDescriptor<Restaurant>()).count == 1)
    }

    @Test func discoveryMergesNewProviderIdentityIntoExistingWantToGoWithoutDuplicating() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let existing = Restaurant(
            name: "Discovery Restaurant", address: "西湖路 1 号", latitude: 30.2, longitude: 120.1,
            status: .wantToGo
        )
        context.insert(existing); try context.save()
        let resolved = try LocalDiscoveryStore(context: context)
            .addToWantToGo(projection: restaurant(provider: .amap, externalID: "amap-new"), among: [existing])
        let record = try JSONDecoder().decode(
            RestaurantJSONContractV1.self, from: #require(resolved.remoteRecordData)
        )
        #expect(resolved.id == existing.id)
        #expect(record.placeIdentities.contains { $0.provider == .amap && $0.externalId == "amap-new" })
        #expect(try context.fetch(FetchDescriptor<Restaurant>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<SyncMutation>()).count == 1)
    }

    @Test func cacheViewerStateUpdatesAcrossAllModules() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let store = LocalDiscoveryStore(context: container.mainContext)
        try store.replaceCache(page: page(mode: .forYou), currentUserID: "tm_a", trendWindowDays: 7)
        try store.replaceCache(page: page(mode: .trending), currentUserID: "tm_a", trendWindowDays: 7)
        try store.updateViewerState(globalKey: "place:shared", currentUserID: "tm_a", state: .wantToGo)
        #expect(try store.cachedPage(mode: .forYou, city: "杭州", currentUserID: "tm_a", trendWindowDays: 7)?.cards[0].viewerState == .wantToGo)
        #expect(try store.cachedPage(mode: .trending, city: "杭州", currentUserID: "tm_a", trendWindowDays: 7)?.cards[0].viewerState == .wantToGo)
    }

    private static let pageJSON = """
    {"apiVersion":1,"mode":"for_you","city":"杭州","personalizationConfidence":"high","generatedAt":"2026-08-28T12:00:00.000Z","items":[{"id":"for_you:place:one","mode":"for_you","restaurant":{"globalKey":"place:one","placeIdentities":[{"provider":"apple_maps","externalId":"apple-only","isPrimary":true}],"name":"餐厅","address":"地址","city":"杭州","latitude":30.2,"longitude":120.1,"tags":[],"pricePerPerson":null,"merchantImageUrl":null,"markerEmoji":"🍜","photo":null},"viewerState":"none","ratings":{"mine":{"value":null,"sampleCount":0},"community":{"value":4.5,"sampleCount":2},"friends":{"value":5,"sampleCount":1},"similarTaste":{"value":4.5,"sampleCount":1}},"reasons":[{"code":"FRIEND_HIGH_RATING","text":"好友最近给过高分"}],"sourceUser":{"userId":"tm_b","displayName":"Bob","bio":null,"city":"杭州","avatarPhotoId":null,"avatarPresetId":"penguin","friendshipId":"friend","friendshipState":"friends","isFollowing":false},"similarity":null,"trend":null,"cacheScope":"public","rank":1,"score":99}],"nextCursor":null}
    """

    private func page(mode: DiscoveryModeV1) -> DiscoveryPageV1 {
        DiscoveryPageV1(apiVersion: 1, mode: mode, city: "杭州", personalizationConfidence: .high,
                        generatedAt: "2026-08-28T12:00:00.000Z", items: [card(mode: mode)], nextCursor: nil)
    }

    private func card(mode: DiscoveryModeV1) -> DiscoveryCardV1 {
        DiscoveryCardV1(
            id: "\(mode.rawValue):place:shared", mode: mode,
            restaurant: restaurant(provider: .appleMaps, externalID: "apple-only"),
            viewerState: .none,
            ratings: .init(mine: .init(value: nil, sampleCount: 0), community: .init(value: 4.5, sampleCount: 3),
                           friends: .init(value: nil, sampleCount: 0), similarTaste: .init(value: nil, sampleCount: 0)),
            reasons: [.init(code: "COMMUNITY_QUALITY", text: "当前城市有稳定的公开高分记录")],
            sourceUser: nil, similarity: nil,
            trend: mode == .trending ? .init(windowDays: 7, uniqueVisitorCount: 3, wantToGoCount: 2) : nil,
            cacheScope: .public, rank: 1, score: 50
        )
    }

    private func restaurant(provider: RestaurantPlaceProvider,
                            externalID: String) -> DiscoveryRestaurantProjectionV1 {
        DiscoveryRestaurantProjectionV1(
            globalKey: "place:shared", placeIdentities: [.init(provider: provider, externalId: externalID, isPrimary: true)],
            name: "Discovery Restaurant", address: "西湖路 1 号", city: "杭州",
            latitude: 30.2, longitude: 120.1, tags: ["日料"], pricePerPerson: 120,
            merchantImageUrl: nil, markerEmoji: "🍣", photo: nil
        )
    }
}
