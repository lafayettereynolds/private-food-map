import Foundation
import SwiftData
import Testing
@testable import TasteMap

@MainActor
@Suite("Hybrid List reads and safe links", .serialized)
struct HybridListReadShareTests {
    @Test("Owned List preserves coordinates and viewer-only nullable ratings")
    func ownListTruth() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let store = LocalRestaurantListStore(context: context)
        let list = try store.create(ownerUserID: "tm_a", title: "自己的食单")
        let restaurant = Restaurant(ownerUserID: "tm_a", name: "公开地点测试", address: "公开测试地址",
            latitude: 30.12345678, longitude: 120.87654321, appleMapItemIdentifier: "list-place")
        context.insert(restaurant)
        context.insert(Visit(ownerUserID: "tm_a", restaurantId: restaurant.id, rating: 4.5))
        context.insert(Visit(ownerUserID: "tm_other", restaurantId: restaurant.id, rating: 1))
        try context.save()
        _ = try store.add(restaurant: restaurant, to: list, actorUserID: "tm_a")
        let projection = try TasteMapHybridBridgeService(container: container, ownerUserID: "tm_a")
        let ownedList = try projection.ownedList(identifier: list.remoteID!)
        let result = try #require(ownedList)
        let row = try #require(result.restaurants.first)
        #expect(row.coordinate?.latitude == restaurant.latitude)
        #expect(row.coordinate?.longitude == restaurant.longitude)
        #expect(row.rating?.source == .viewer)
        #expect(row.rating?.valueOutOfTen == 9)
        #expect(row.rating?.sampleCount == 1)
        let otherProjection = try TasteMapHybridBridgeService(container: container, ownerUserID: "tm_other")
        let otherOwnedList = try otherProjection.ownedList(identifier: list.remoteID!)
        #expect(otherOwnedList == nil)
    }

    @Test("List-only public places keep real coordinates without author-private scores")
    func publicListTruth() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let service = try TasteMapHybridBridgeService(container: container, ownerUserID: "tm_a")
        let result = try service.publicListProjection(page(start: 0, count: 1))
        #expect(result.restaurants[0].coordinate?.latitude == 30.25)
        #expect(result.restaurants[0].rating == nil)
        #expect(!result.isOwnedByViewer)
        let persistedRestaurants = try container.mainContext.fetch(FetchDescriptor<Restaurant>())
        #expect(persistedRestaurants.isEmpty)
        #expect(TasteMapHybridListRatingDTO(valueOutOfTen: 0, source: .public, sampleCount: 1) == nil)
        #expect(TasteMapHybridListRatingDTO(valueOutOfTen: 9, source: .public, sampleCount: 0) == nil)
    }

    @Test("All 52 public members are reachable through opaque owner-scoped pages")
    func publicPagination() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let api = ListReadSpy(pages: [try page(start: 0, count: 50, next: "server-next"), try page(start: 50, count: 2)])
        let service = makeService(container, api: api)
        let first = try await service.get(.init(id: "public-list"))
        let token = try #require(first.nextCursor)
        #expect(token != "server-next")
        let second = try await service.get(.init(id: "public-list", cursor: token))
        #expect(first.list.restaurants.count + second.list.restaurants.count == 52)
        #expect(second.nextCursor == nil)
        #expect(api.cursors == [nil, "server-next"])
        let cached = try LocalRestaurantListStore(context: container.mainContext).cachedDetail(listID: "public-list", viewerUserID: "tm_a")
        #expect(cached?.items.count == 52)
        let otherCached = try LocalRestaurantListStore(context: container.mainContext).cachedDetail(listID: "public-list", viewerUserID: "tm_b")
        #expect(otherCached == nil)
    }

    @Test("Refresh invalidates old cursors and a changed List revision cannot append")
    func invalidContinuation() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let api = ListReadSpy(pages: [try page(next: "one"), try page(next: "two"), try page(version: "v2")])
        let service = makeService(container, api: api)
        let first = try await service.get(.init(id: "public-list"))
        let refreshed = try await service.get(.init(id: "public-list"))
        await #expect(throws: TasteMapHybridBridgeErrorDTO.self) {
            _ = try await service.get(.init(id: "public-list", cursor: first.nextCursor))
        }
        await #expect(throws: TasteMapHybridBridgeErrorDTO.self) {
            _ = try await service.get(.init(id: "public-list", cursor: refreshed.nextCursor))
        }
        #expect(api.cursors.count == 3)
    }

    @Test("Permission loss purges viewer cache, not another viewer's cache")
    func permissionRevocation() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let store = LocalRestaurantListStore(context: container.mainContext)
        try store.cache(detail: page(), viewerUserID: "tm_a", replace: true)
        try store.cache(detail: page(), viewerUserID: "tm_b", replace: true)
        let api = ListReadSpy(pages: [])
        api.failure = .server(status: 403, message: "not visible")
        await #expect(throws: TasteMapHybridBridgeErrorDTO.self) {
            _ = try await makeService(container, api: api).get(.init(id: "public-list"))
        }
        let fresh = LocalRestaurantListStore(context: ModelContext(container))
        let revokedCached = try fresh.cachedDetail(listID: "public-list", viewerUserID: "tm_a")
        let otherViewerCached = try fresh.cachedDetail(listID: "public-list", viewerUserID: "tm_b")
        #expect(revokedCached == nil)
        #expect(otherViewerCached != nil)
    }

    @Test("Owner invalidation discards an in-flight public page before cache write")
    func lateOwnerReply() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let api = ListReadSpy(pages: [try page()])
        api.delay = true
        let service = makeService(container, api: api)
        let task = Task { try await service.get(.init(id: "public-list")) }
        for _ in 0..<1_000 where api.cursors.isEmpty { await Task.yield() }
        #expect(!api.cursors.isEmpty)
        service.invalidate()
        await #expect(throws: TasteMapHybridBridgeErrorDTO.self) { _ = try await task.value }
        let cachedLists = try container.mainContext.fetch(FetchDescriptor<CachedPublicRestaurantList>())
        #expect(cachedLists.isEmpty)
    }

    @Test("Safe sharing checks owner/public state and returns only the actual API URL")
    func shareTruth() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let store = LocalRestaurantListStore(context: container.mainContext)
        let list = try store.create(ownerUserID: "tm_a", title: "链接测试")
        let sharing = ListShareSpy()
        let service = makeService(container, api: ListReadSpy(pages: []), sharing: sharing)
        await #expect(throws: TasteMapHybridBridgeErrorDTO.self) { _ = try await service.createShareLink(id: list.remoteID!) }
        #expect(sharing.calls.isEmpty)
        try store.update(list, actorUserID: "tm_a", title: list.title, description: "", visibility: .public, isRanked: false)
        let result = try await service.createShareLink(id: list.remoteID!)
        #expect(result.url == sharing.url.absoluteString)
        #expect(sharing.calls == [list.remoteID!])
        service.invalidate()
        await #expect(throws: TasteMapHybridBridgeErrorDTO.self) { _ = try await service.createShareLink(id: list.remoteID!) }
    }

    private func makeService(_ container: ModelContainer, api: ListReadSpy, sharing: ListShareSpy? = nil) -> TasteMapHybridListService {
        .init(container: container, ownerUserID: "tm_a", api: api, sharing: sharing ?? ListShareSpy(), currentOwner: { "tm_a" })
    }

    private func page(start: Int = 0, count: Int = 1, next: String? = nil, version: String = "v1") throws -> PublicListDetailDTO {
        .init(apiVersion: 1, list: .init(id: "public-list", title: "公开食单", description: "说明", visibility: .public,
            isRanked: true, coverMode: .automatic, customCoverPhotoId: nil, restaurantCount: 52, previewRestaurants: [],
            owner: .init(userId: "tm_other", displayName: "公开作者", avatarPhotoId: nil, avatarPresetId: .otter), updatedAt: version),
            items: try (start..<(start + count)).map { index in
                .init(id: "item-\(index)", position: index, note: "", restaurant: try .init(
                    globalKey: "apple_maps:place-\(index)", restaurantId: "restaurant-\(index)",
                    placeIdentities: [.init(provider: .appleMaps, externalId: "place-\(index)", isPrimary: true)],
                    name: "测试餐厅 \(index)", address: "公开地点", city: "杭州", latitude: 30.25, longitude: 120.15,
                    markerPhotoId: nil, merchantImageUrl: nil, markerEmoji: ""))
            }, nextCursor: next, generatedAt: "2026-09-06T00:00:00Z")
    }
}

@MainActor
private final class ListReadSpy: RestaurantListAPI {
    var pages: [PublicListDetailDTO]
    var cursors: [String?] = []
    var failure: SyncAPIError?
    var delay = false
    init(pages: [PublicListDetailDTO]) { self.pages = pages }
    func detail(listID: String, cursor: String?, limit: Int) async throws -> PublicListDetailDTO {
        cursors.append(cursor)
        #expect(limit == 50)
        if delay { try await Task.sleep(for: .milliseconds(30)) }
        if let failure { throw failure }
        return pages.removeFirst()
    }
    func profileLists(userID: String, cursor: String?, limit: Int) async throws -> PublicListSummaryPageDTO {
        throw SyncAPIError.invalidResponse
    }
}

@MainActor
private final class ListShareSpy: PublicSharingAPI {
    let shareID = String(repeating: "a", count: 32)
    var calls: [String] = []
    var url: URL { URL(string: "https://example.test/share/\(shareID)")! }
    func create(entityType: PublicShareEntityTypeV1, entityID: String) async throws -> CreatePublicShareResponseV1 {
        #expect(entityType == .list)
        calls.append(entityID)
        return .init(apiVersion: 1, shareId: shareID, entityType: .list, url: url)
    }
    func read(shareID: String) async throws -> PublicShareResponseV1 { throw PublicSharingAPIError.invalidResponse }
}
