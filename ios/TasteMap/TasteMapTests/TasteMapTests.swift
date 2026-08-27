import Foundation
import SwiftData
import Testing
@testable import TasteMap

@Suite(.serialized)
@MainActor
struct TasteMapTests {
    @Test("未操作评分时保存 nil")
    func unratedVisitRemainsNil() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let restaurant = makeRestaurant()
        context.insert(restaurant)

        let visit = try LocalTasteMapStore(context: context).createVisit(
            restaurantId: restaurant.id
        )

        #expect(visit.rating == nil)
        #expect(visit.syncStatus == .pending)
    }

    @Test("同一家餐厅可保存多个独立 Visit")
    func repeatVisitCreatesASeparateRecord() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let restaurant = makeRestaurant()
        context.insert(restaurant)
        let store = LocalTasteMapStore(context: context)

        let first = try store.createVisit(restaurantId: restaurant.id, rating: 4)
        let second = try store.createVisit(restaurantId: restaurant.id, rating: nil)
        let visits = try context.fetch(FetchDescriptor<Visit>())

        #expect(first.id != second.id)
        #expect(visits.count == 2)
        #expect(Set(visits.map(\.restaurantId)) == [restaurant.id])
    }

    @Test("编辑一个 Visit 不影响另一个")
    func editingOneVisitDoesNotChangeAnother() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let restaurant = makeRestaurant()
        context.insert(restaurant)
        let store = LocalTasteMapStore(context: context)
        let first = try store.createVisit(restaurantId: restaurant.id, note: "第一次")
        let second = try store.createVisit(restaurantId: restaurant.id, rating: 3.5, note: "第二次")

        try store.update(
            first,
            visitedAt: first.visitedAt,
            rating: 4.5,
            note: "已修改",
            myActualSpend: 88
        )

        #expect(first.rating == 4.5)
        #expect(first.note == "已修改")
        #expect(second.rating == 3.5)
        #expect(second.note == "第二次")
    }

    @Test("删除一个 Visit 不影响另一个")
    func deletingOneVisitLeavesOtherVisits() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let restaurant = makeRestaurant()
        context.insert(restaurant)
        let store = LocalTasteMapStore(context: context)
        let first = try store.createVisit(restaurantId: restaurant.id)
        let second = try store.createVisit(restaurantId: restaurant.id)

        try store.delete(first)
        let visits = try context.fetch(FetchDescriptor<Visit>())

        #expect(visits.count == 1)
        #expect(visits.first?.id == second.id)
    }

    @Test("Apple 标识相同的餐厅会复用现有 Restaurant")
    func duplicateRestaurantUsesExistingRecord() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let existing = makeRestaurant(appleIdentifier: "apple-place-id")
        context.insert(existing)
        let candidate = RestaurantCandidate(
            name: "同一家餐厅的新名称",
            address: "另一个地址格式",
            latitude: 31.23,
            longitude: 121.47,
            appleMapItemIdentifier: "apple-place-id"
        )

        let resolved = try LocalTasteMapStore(context: context).restaurant(
            for: candidate,
            among: [existing]
        )

        #expect(resolved.id == existing.id)
        #expect(try context.fetch(FetchDescriptor<Restaurant>()).count == 1)
    }

    @Test("加入想吃只创建 Restaurant 并保留 Apple Maps identity")
    func addingWantToGoCreatesRestaurantWithoutVisit() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let candidate = RestaurantCandidate(
            name: "想吃餐厅",
            address: "想吃地址",
            latitude: 30.25,
            longitude: 120.16,
            appleMapItemIdentifier: "apple-want-to-go"
        )

        let restaurant = try LocalTasteMapStore(context: context).addToWantToGo(
            candidate: candidate,
            among: []
        )
        let mutations = try context.fetch(FetchDescriptor<SyncMutation>())
        let payload = try #require(mutations.first?.payload)
        let record = try JSONDecoder().decode(RestaurantJSONContractV1.self, from: payload)

        #expect(restaurant.status == .wantToGo)
        #expect(try context.fetch(FetchDescriptor<Visit>()).isEmpty)
        #expect(mutations.count == 1)
        #expect(record.status == .wantToGo)
        #expect(record.placeIdentities.first?.provider == .appleMaps)
        #expect(record.placeIdentities.first?.externalId == "apple-want-to-go")
    }

    @Test("想吃餐厅新增 Visit 后转为去过且不重复创建 Restaurant")
    func wantToGoTransitionsToVisited() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let store = LocalTasteMapStore(context: context)
        let candidate = RestaurantCandidate(
            name: "状态转换餐厅",
            address: "状态转换地址",
            latitude: 31.23,
            longitude: 121.47,
            appleMapItemIdentifier: "apple-status-transition"
        )
        let restaurant = try store.addToWantToGo(candidate: candidate, among: [])

        _ = try store.createVisit(restaurantId: restaurant.id, rating: nil)

        let restaurants = try context.fetch(FetchDescriptor<Restaurant>())
        let visits = try context.fetch(FetchDescriptor<Visit>())
        let restaurantMutation = try #require(
            context.fetch(FetchDescriptor<SyncMutation>()).first { $0.entityType == .restaurant }
        )
        let payload = try #require(restaurantMutation.payload)
        let record = try JSONDecoder().decode(RestaurantJSONContractV1.self, from: payload)
        #expect(restaurants.count == 1)
        #expect(visits.count == 1)
        #expect(restaurant.status == .visited)
        #expect(record.status == .visited)
    }

    @Test("重复加入想吃会复用同一个 Restaurant")
    func duplicateWantToGoUsesExistingRestaurant() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let store = LocalTasteMapStore(context: context)
        let candidate = RestaurantCandidate(
            name: "不重复餐厅",
            address: "不重复地址",
            latitude: 30.2,
            longitude: 120.2,
            appleMapItemIdentifier: "apple-want-dedup"
        )
        let first = try store.addToWantToGo(candidate: candidate, among: [])
        let second = try store.addToWantToGo(candidate: candidate, among: [first])

        #expect(first.id == second.id)
        #expect(try context.fetch(FetchDescriptor<Restaurant>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<SyncMutation>()).count == 1)
    }

    @Test("不合法或非半星评分不会被保存")
    func ratingValidation() {
        #expect(Visit.validatedRating(nil) == nil)
        #expect(Visit.validatedRating(0) == nil)
        #expect(Visit.validatedRating(4.2) == nil)
        #expect(Visit.validatedRating(0.5) == 0.5)
        #expect(Visit.validatedRating(5) == 5)
    }

    @Test("磁盘容器重开后记录仍存在")
    func recordsPersistAcrossContainerRelaunch() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TasteMapTests-\(UUID().uuidString)")
            .appendingPathExtension("store")
        defer { removeStoreFiles(at: storeURL) }

        try savePersistentVisit(at: storeURL)
        let reopenedContainer = try makePersistentContainer(at: storeURL)
        let restaurants = try reopenedContainer.mainContext.fetch(FetchDescriptor<Restaurant>())
        let visits = try reopenedContainer.mainContext.fetch(FetchDescriptor<Visit>())

        #expect(restaurants.count == 1)
        #expect(visits.count == 1)
        #expect(visits.first?.rating == nil)
    }

    @Test("磁盘容器重开后想吃状态仍存在")
    func wantToGoPersistsAcrossContainerRelaunch() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TasteMapWantTests-\(UUID().uuidString)")
            .appendingPathExtension("store")
        defer { removeStoreFiles(at: storeURL) }

        do {
            let container = try makePersistentContainer(at: storeURL)
            let context = container.mainContext
            _ = try LocalTasteMapStore(context: context).addToWantToGo(
                candidate: RestaurantCandidate(
                    name: "重启后仍想吃",
                    address: "持久化地址",
                    latitude: 30.25,
                    longitude: 120.16,
                    appleMapItemIdentifier: "apple-persistent-want"
                ),
                among: []
            )
        }

        let reopenedContainer = try makePersistentContainer(at: storeURL)
        let restaurant = try #require(
            reopenedContainer.mainContext.fetch(FetchDescriptor<Restaurant>()).first
        )
        #expect(restaurant.status == .wantToGo)
        #expect(restaurant.appleMapItemIdentifier == "apple-persistent-want")
    }

    @Test("搜索失败会结束 Loading 并给出可重试错误")
    func searchFailureDoesNotLoadForever() async {
        let viewModel = RestaurantSearchViewModel(
            searchService: FailingRestaurantSearchService()
        )

        await viewModel.search(query: "餐厅")

        #expect(viewModel.isLoading == false)
        #expect(viewModel.results.isEmpty)
        #expect(viewModel.errorMessage != nil)
    }

    @Test("搜索结果保留 Apple Maps identity 和坐标")
    func searchResultPreservesAppleIdentity() async throws {
        let viewModel = RestaurantSearchViewModel(
            searchService: SuccessfulRestaurantSearchService()
        )

        await viewModel.search(query: "真实餐厅")

        let result = try #require(viewModel.results.first)
        #expect(viewModel.isLoading == false)
        #expect(result.name == "真实餐厅")
        #expect(result.latitude == 30.25)
        #expect(result.longitude == 120.16)
        #expect(result.appleMapItemIdentifier == "apple-real-search-result")
    }

    private func makeRestaurant(appleIdentifier: String? = nil) -> Restaurant {
        Restaurant(
            name: "测试餐厅",
            address: "测试地址",
            latitude: 31.2304,
            longitude: 121.4737,
            appleMapItemIdentifier: appleIdentifier
        )
    }

    private func savePersistentVisit(at url: URL) throws {
        let container = try makePersistentContainer(at: url)
        let context = container.mainContext
        let restaurant = makeRestaurant()
        context.insert(restaurant)
        _ = try LocalTasteMapStore(context: context).createVisit(restaurantId: restaurant.id)
    }

    private func makePersistentContainer(at url: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "TasteMapTests",
            schema: TasteMapPersistence.schema,
            url: url,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: TasteMapPersistence.schema,
            configurations: [configuration]
        )
    }

    private func removeStoreFiles(at url: URL) {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: url)
        try? fileManager.removeItem(atPath: url.path + "-shm")
        try? fileManager.removeItem(atPath: url.path + "-wal")
    }
}

private struct FailingRestaurantSearchService: RestaurantSearching {
    struct ExpectedFailure: Error {}

    func search(query: String) async throws -> [RestaurantCandidate] {
        throw ExpectedFailure()
    }
}

private struct SuccessfulRestaurantSearchService: RestaurantSearching {
    func search(query: String) async throws -> [RestaurantCandidate] {
        [RestaurantCandidate(
            name: query,
            address: "真实地址",
            latitude: 30.25,
            longitude: 120.16,
            appleMapItemIdentifier: "apple-real-search-result"
        )]
    }
}
