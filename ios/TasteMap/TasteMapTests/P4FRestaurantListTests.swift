import Foundation
import SwiftData
import Testing
@testable import TasteMap

@Suite("P4-F Restaurant Lists", .serialized)
@MainActor
struct P4FRestaurantListTests {
    @Test("Create, rename, description, visibility, duplicate title and owner isolation")
    func listDomain() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let store = LocalRestaurantListStore(context: context)
        let first = try store.create(
            ownerUserID: "tm_a", title: "  🍲 我的火锅  ", description: "  周末会再去  ",
            visibility: .private, isRanked: true
        )
        let second = try store.create(ownerUserID: "tm_a", title: "🍲 我的火锅")

        #expect(first.title == "🍲 我的火锅")
        #expect(first.listDescription == "周末会再去")
        #expect(first.id != second.id)
        try store.update(
            first, actorUserID: "tm_a", title: "约会餐厅", description: "光线舒服",
            visibility: .friends, isRanked: false
        )
        #expect(first.title == "约会餐厅")
        #expect(first.visibility == .friends)
        #expect(throws: RestaurantListStoreError.notOwner) {
            try store.update(
                first, actorUserID: "tm_b", title: "伪造修改", description: "",
                visibility: .public, isRanked: false
            )
        }
        #expect(throws: RestaurantListStoreError.invalidTitle) {
            _ = try store.create(ownerUserID: "tm_a", title: "   ")
        }
        #expect(throws: RestaurantListStoreError.descriptionTooLong) {
            _ = try store.create(ownerUserID: "tm_a", title: "有效", description: String(repeating: "味", count: 241))
        }
    }

    @Test("Add prevents duplicate, permits same place across lists and never changes WantToGo")
    func listItemIdentity() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let listStore = LocalRestaurantListStore(context: context)
        let localStore = LocalTasteMapStore(context: context)
        let restaurant = try localStore.restaurant(for: appleCandidate(), among: [])
        let first = try listStore.create(ownerUserID: "tm_a", title: "第一份")
        let second = try listStore.create(ownerUserID: "tm_a", title: "第二份")

        let item = try listStore.add(restaurant: restaurant, to: first, actorUserID: "tm_a")
        #expect(item.restaurantGlobalKey == "apple_maps:apple-p4f-place")
        #expect(restaurant.status == .visited)
        #expect(throws: RestaurantListStoreError.duplicateRestaurant) {
            _ = try listStore.add(restaurant: restaurant, to: first, actorUserID: "tm_a")
        }
        _ = try listStore.add(restaurant: restaurant, to: second, actorUserID: "tm_a")
        #expect(try listStore.items(listID: first.id).count == 1)
        #expect(try listStore.items(listID: second.id).count == 1)
        #expect(try context.fetch(FetchDescriptor<Visit>()).isEmpty)
    }

    @Test("Search/shared place can be list-only and does not create Restaurant user state")
    func sharedPlaceReference() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let store = LocalRestaurantListStore(context: context)
        let list = try store.create(ownerUserID: "tm_a", title: "社区看到的店")
        let projection = try sharedProjection()

        let item = try store.add(
            projection: projection, to: list, actorUserID: "tm_a", localRestaurants: []
        )

        #expect(item.localRestaurantID == nil)
        #expect(item.restaurantGlobalKey == projection.globalKey)
        #expect(try context.fetch(FetchDescriptor<Restaurant>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Visit>()).isEmpty)
    }

    @Test("Remove and delete use tombstones without deleting Restaurant")
    func removalAndTombstone() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let store = LocalRestaurantListStore(context: context)
        let restaurant = try LocalTasteMapStore(context: context).restaurant(for: appleCandidate(), among: [])
        let list = try store.create(ownerUserID: "tm_a", title: "待删榜单")
        let first = try store.add(restaurant: restaurant, to: list, actorUserID: "tm_a")
        let second = try store.add(candidate: manualCandidate(), to: list, actorUserID: "tm_a")

        try store.remove(first, actorUserID: "tm_a")
        #expect(first.deletedAt != nil)
        #expect(second.deletedAt == nil)
        #expect(restaurant.deletedAt == nil)
        #expect(list.activeItemCount == 1)

        try store.delete(list, actorUserID: "tm_a")
        #expect(list.deletedAt != nil)
        #expect(second.deletedAt != nil)
        #expect(restaurant.deletedAt == nil)
        #expect(try context.fetch(FetchDescriptor<Restaurant>()).count == 1)
    }

    @Test("Reorder deterministically renumbers and queues one mutation per changed item")
    func reorder() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let store = LocalRestaurantListStore(context: context)
        let list = try store.create(ownerUserID: "tm_a", title: "排名", isRanked: true)
        var items: [RestaurantListItem] = []
        for index in 0..<5 {
            items.append(try store.add(
                candidate: candidate(index), to: list, actorUserID: "tm_a"
            ))
        }
        for mutation in try context.fetch(FetchDescriptor<SyncMutation>()) { context.delete(mutation) }
        try context.save()

        try store.reorder(list: list, orderedItemIDs: items.reversed().map(\.id), actorUserID: "tm_a")

        #expect(try store.items(listID: list.id).map(\.position) == [0, 1, 2, 3, 4])
        #expect(try store.items(listID: list.id).map(\.id) == items.reversed().map(\.id))
        #expect(try context.fetch(FetchDescriptor<SyncMutation>()).count == 4)
    }

    @Test("Persistent store restart retains list membership and order")
    func restartPersistence() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TasteMapP4F-\(UUID().uuidString).store")
        defer { removeStoreFiles(at: url) }
        let listID: UUID
        do {
            let container = try persistentContainer(at: url)
            let context = container.mainContext
            let store = LocalRestaurantListStore(context: context)
            let list = try store.create(ownerUserID: "tm_a", title: "重启后还在")
            listID = list.id
            let first = try store.add(candidate: candidate(1), to: list, actorUserID: "tm_a")
            let second = try store.add(candidate: candidate(2), to: list, actorUserID: "tm_a")
            try store.reorder(list: list, orderedItemIDs: [second.id, first.id], actorUserID: "tm_a")
        }

        let reopenedContainer = try persistentContainer(at: url)
        let reopenedContext = reopenedContainer.mainContext
        let store = LocalRestaurantListStore(context: reopenedContext)
        #expect(try store.lists(ownerUserID: "tm_a").first?.id == listID)
        #expect(try store.items(listID: listID).map(\.restaurantSnapshot?.name) == ["候选餐厅 2", "候选餐厅 1"])
    }

    @Test("Queue sends parent before child on upsert and child before parent on delete")
    func dependencyOrdering() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let queue = SwiftDataSyncQueue(context: context)
        _ = try queue.enqueueUpsert(entityType: .restaurantListItem, entityID: "item", baseVersion: 0, payload: Data())
        _ = try queue.enqueueUpsert(entityType: .restaurantList, entityID: "list", baseVersion: 0, payload: Data())
        #expect(try queue.nextReadyMutation()?.entityType == .restaurantList)
        try queue.removeMutations(entityType: .restaurantList, entityID: "list")
        try queue.removeMutations(entityType: .restaurantListItem, entityID: "item")
        _ = try queue.enqueueDelete(entityType: .restaurantList, entityID: "list", baseVersion: 1)
        _ = try queue.enqueueDelete(entityType: .restaurantListItem, entityID: "item", baseVersion: 1)
        #expect(try queue.nextReadyMutation()?.entityType == .restaurantListItem)
    }

    @Test("Sync round-trip hydrates a fresh client without creating Restaurant state")
    func syncRoundTrip() async throws {
        let sourceContainer = try TasteMapPersistence.makeContainer(inMemory: true)
        let source = sourceContainer.mainContext
        let store = LocalRestaurantListStore(context: source)
        let list = try store.create(ownerUserID: "tm_a", title: "跨设备榜单", visibility: .public)
        _ = try store.add(
            projection: try sharedProjection(), to: list, actorUserID: "tm_a", localRestaurants: []
        )
        let api = P4FMemorySyncAPI()
        try await SyncEngine(context: source, api: api, ownerUserID: "tm_a").synchronize()

        let freshContainer = try TasteMapPersistence.makeContainer(inMemory: true)
        let fresh = freshContainer.mainContext
        try await SyncEngine(context: fresh, api: api, ownerUserID: "tm_a").synchronize()
        let pulledList = try #require(fresh.fetch(FetchDescriptor<RestaurantList>()).first)
        let pulledItem = try #require(fresh.fetch(FetchDescriptor<RestaurantListItem>()).first)

        #expect(pulledList.title == "跨设备榜单")
        #expect(pulledList.serverVersion == 1)
        #expect(pulledItem.listID == pulledList.id)
        #expect(pulledItem.restaurantGlobalKey == "apple_maps:shared-p4f")
        #expect(try fresh.fetch(FetchDescriptor<Restaurant>()).isEmpty)
    }

    @Test("Public cache is scoped by viewer and invalidates on permission change/logout")
    func publicCacheIsolation() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let store = LocalRestaurantListStore(context: context)
        let summary = publicSummary(id: "public-list", owner: "tm_a", visibility: .friends)
        try store.cache(summaries: [summary], viewerUserID: "tm_b", ownerUserID: "tm_a", replace: true)
        try store.cache(summaries: [summary], viewerUserID: "tm_c", ownerUserID: "tm_a", replace: true)
        #expect(try store.cachedSummaries(viewerUserID: "tm_b", ownerUserID: "tm_a").count == 1)
        #expect(try store.cachedSummaries(viewerUserID: "tm_c", ownerUserID: "tm_a").count == 1)

        let stale = publicSummary(id: "stale-list", owner: "tm_a", visibility: .public)
        try store.cache(
            summaries: [stale], viewerUserID: "tm_b", ownerUserID: "tm_a", replace: false
        )
        #expect(try store.cachedSummaries(viewerUserID: "tm_b", ownerUserID: "tm_a").count == 2)
        try store.cache(
            summaries: [summary], viewerUserID: "tm_b", ownerUserID: "tm_a", replace: true
        )
        #expect(try store.cachedSummaries(viewerUserID: "tm_b", ownerUserID: "tm_a").map(\.id) == ["public-list"])

        store.invalidate(ownerUserID: "tm_a", viewerUserID: "tm_b")
        #expect(try store.cachedSummaries(viewerUserID: "tm_b", ownerUserID: "tm_a").isEmpty)
        #expect(try store.cachedSummaries(viewerUserID: "tm_c", ownerUserID: "tm_a").count == 1)
        try store.purgePublicCache(viewerUserID: "tm_c")
        #expect(try store.cachedSummaries(viewerUserID: "tm_c", ownerUserID: "tm_a").isEmpty)
    }

    @Test("Overview summary stays independent from 5,000 detail rows")
    func summaryPerformanceShape() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        for index in 0..<100 {
            context.insert(RestaurantList(
                ownerUserID: "tm_a", title: "List \(index)", activeItemCount: 50,
                previewRestaurantIDs: ["apple_maps:\(index)"]
            ))
        }
        try context.save()
        let summaries = try LocalRestaurantListStore(context: context).lists(ownerUserID: "tm_a")
        #expect(summaries.count == 100)
        #expect(summaries.allSatisfy { $0.activeItemCount == 50 })
        #expect(try context.fetch(FetchDescriptor<RestaurantListItem>()).isEmpty)
    }

    private func appleCandidate() -> RestaurantCandidate {
        RestaurantCandidate(
            name: "Apple 餐厅", address: "中山路 1 号", latitude: 30.25,
            longitude: 120.16, appleMapItemIdentifier: "apple-p4f-place"
        )
    }

    private func manualCandidate() -> RestaurantCandidate {
        RestaurantCandidate(name: "手工餐厅", address: "无外部 ID", latitude: 31, longitude: 121)
    }

    private func candidate(_ index: Int) -> RestaurantCandidate {
        RestaurantCandidate(
            name: "候选餐厅 \(index)", address: "地址 \(index)",
            latitude: 30 + Double(index) / 100, longitude: 120,
            appleMapItemIdentifier: "candidate-\(index)"
        )
    }

    private func sharedProjection() throws -> DiscoveryRestaurantProjectionV1 {
        DiscoveryRestaurantProjectionV1(
            globalKey: "apple_maps:shared-p4f",
            placeIdentities: [.init(provider: .appleMaps, externalId: "shared-p4f", isPrimary: true)],
            name: "共享餐厅", address: "公开地址", city: "杭州",
            latitude: 30.25, longitude: 120.16, tags: [], pricePerPerson: nil,
            merchantImageUrl: nil, markerEmoji: "🍜", photo: nil
        )
    }

    private func publicSummary(
        id: String, owner: String, visibility: RestaurantListVisibility
    ) -> PublicListSummaryDTO {
        PublicListSummaryDTO(
            id: id, title: "公开榜单", description: "说明", visibility: visibility,
            isRanked: true, coverMode: .automatic, customCoverPhotoId: nil,
            restaurantCount: 1,
            previewRestaurants: [.init(
                globalKey: "apple_maps:shared-p4f", name: "共享餐厅", photoId: nil,
                merchantImageUrl: nil, markerEmoji: "🍜"
            )],
            owner: .init(userId: owner, displayName: "Alpha", avatarPhotoId: nil, avatarPresetId: .otter),
            updatedAt: "2026-08-28T20:00:00.000Z"
        )
    }

    private func persistentContainer(at url: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "TasteMapP4FTests", schema: TasteMapPersistence.schema, url: url,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: TasteMapPersistence.schema, configurations: [configuration])
    }

    private func removeStoreFiles(at url: URL) {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(atPath: url.path + "-shm")
        try? FileManager.default.removeItem(atPath: url.path + "-wal")
    }
}

@MainActor
private final class P4FMemorySyncAPI: SyncAPI {
    private var lists: [String: (Int64, RestaurantListSyncContractV1)] = [:]
    private var items: [String: (Int64, RestaurantListItemSyncContractV1)] = [:]
    private var tombstones: [SyncTombstoneV1] = []
    private var revision: Int64 = 0

    func push(_ request: SyncPushRequestV1) async throws -> SyncPushResponseV1 {
        let acknowledgements = request.mutations.map { mutation in
            revision += 1
            let version = mutation.baseVersion + 1
            switch mutation.payload {
            case .restaurantList(let record): lists[mutation.entityId] = (version, record)
            case .restaurantListItem(let record): items[mutation.entityId] = (version, record)
            default: break
            }
            if mutation.operation == .delete {
                lists.removeValue(forKey: mutation.entityId)
                items.removeValue(forKey: mutation.entityId)
                tombstones.append(.init(
                    entityType: mutation.entityType, entityId: mutation.entityId,
                    serverVersion: version, deletedAt: "2026-08-28T20:00:00.000Z"
                ))
            }
            return SyncMutationAcknowledgementV1(
                mutationId: mutation.mutationId, entityType: mutation.entityType,
                entityId: mutation.entityId, status: .applied, duplicate: false,
                serverVersion: version, revision: revision, conflictReason: nil
            )
        }
        return SyncPushResponseV1(
            apiVersion: 1, acknowledgements: acknowledgements,
            serverTime: "2026-08-28T20:00:00.000Z"
        )
    }

    func pull(cursor: String, limit: Int) async throws -> SyncPullResponseV1 {
        SyncPullResponseV1(
            apiVersion: 1, schemaVersion: 1, restaurants: [], visits: [],
            restaurantLists: lists.values.map {
                RestaurantListSyncRecordEnvelopeV1(serverVersion: $0.0, record: $0.1)
            },
            restaurantListItems: items.values.map {
                RestaurantListItemSyncRecordEnvelopeV1(serverVersion: $0.0, record: $0.1)
            },
            tombstones: tombstones, nextCursor: String(revision), hasMore: false,
            serverTime: "2026-08-28T20:00:00.000Z"
        )
    }
}
