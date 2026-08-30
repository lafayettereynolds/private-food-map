import Foundation
import MapKit
import SwiftData
import Testing
@testable import TasteMap

@Suite("Restaurant Detail", .serialized)
@MainActor
struct RestaurantDetailTests {
    @Test("统计忽略 tombstone、nil 评分和 nil 消费并按日期倒序")
    func statisticsUseOnlyMeaningfulActiveValues() {
        let restaurantID = UUID()
        let oldest = visit(
            restaurantID: restaurantID,
            days: 1,
            rating: 4,
            spend: 100
        )
        let newest = visit(
            restaurantID: restaurantID,
            days: 3,
            rating: nil,
            spend: nil
        )
        let middle = visit(
            restaurantID: restaurantID,
            days: 2,
            rating: 5,
            spend: 200
        )
        let tombstone = visit(
            restaurantID: restaurantID,
            days: 4,
            rating: 1,
            spend: 999,
            deletedAt: Date(timeIntervalSince1970: 10)
        )
        let otherRestaurant = visit(
            restaurantID: UUID(),
            days: 5,
            rating: 0.5,
            spend: 800
        )

        let presentation = RestaurantDetailPresentation(
            restaurantID: restaurantID,
            visits: [oldest, newest, tombstone, otherRestaurant, middle]
        )

        #expect(presentation.activeVisits.map(\.id) == [newest.id, middle.id, oldest.id])
        #expect(presentation.visitCount == 3)
        #expect(presentation.averageRating == 4.5)
        #expect(presentation.latestVisit?.id == newest.id)
        #expect(presentation.totalSpend == Decimal(300))
        #expect(presentation.averageSpend == Decimal(150))
    }

    @Test("没有评分或消费时统计保持为空而不是零")
    func sparseStatisticsStayNil() {
        let restaurantID = UUID()
        let presentation = RestaurantDetailPresentation(
            restaurantID: restaurantID,
            visits: [visit(restaurantID: restaurantID, days: 1, rating: nil, spend: nil)]
        )

        #expect(presentation.visitCount == 1)
        #expect(presentation.averageRating == nil)
        #expect(presentation.totalSpend == nil)
        #expect(presentation.averageSpend == nil)
    }

    @Test("新增、编辑和删除 Visit 后重新计算详情统计")
    func visitMutationsRefreshStatistics() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let restaurant = restaurant()
        context.insert(restaurant)
        let store = LocalTasteMapStore(context: context)
        let first = try store.createVisit(
            restaurantId: restaurant.id,
            visitedAt: Date(timeIntervalSince1970: 100),
            rating: 4,
            myActualSpend: 80
        )
        let second = try store.createVisit(
            restaurantId: restaurant.id,
            visitedAt: Date(timeIntervalSince1970: 200),
            rating: nil,
            myActualSpend: nil
        )

        var presentation = detail(for: restaurant, context: context)
        #expect(presentation.visitCount == 2)
        #expect(presentation.averageRating == 4)
        #expect(presentation.latestVisit?.id == second.id)

        try store.update(
            first,
            visitedAt: Date(timeIntervalSince1970: 300),
            rating: 5,
            note: "更新后",
            myActualSpend: 120
        )
        presentation = detail(for: restaurant, context: context)
        #expect(presentation.averageRating == 5)
        #expect(presentation.totalSpend == Decimal(120))
        #expect(presentation.latestVisit?.id == first.id)

        try store.delete(second)
        presentation = detail(for: restaurant, context: context)
        #expect(presentation.visitCount == 1)
        #expect(presentation.activeVisits.first?.id == first.id)
    }

    @Test("想吃记录到访后变为去过，再次记录会新增独立 Visit")
    func statusTransitionAndRepeatVisit() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let restaurant = restaurant(status: .wantToGo)
        context.insert(restaurant)
        let store = LocalTasteMapStore(context: context)

        _ = try store.createVisit(restaurantId: restaurant.id, rating: nil)
        _ = try store.createVisit(restaurantId: restaurant.id, rating: 4.5)

        #expect(restaurant.status == .visited)
        #expect(detail(for: restaurant, context: context).visitCount == 2)
        #expect(try context.fetch(FetchDescriptor<Restaurant>()).count == 1)
    }

    @Test("Apple Maps-only Restaurant 生成正确原生导航地点")
    func appleMapsNavigationUsesRestaurantLocation() {
        let restaurant = restaurant()
        let mapItem = AppleMapsRestaurantNavigator().mapItem(for: restaurant)
        let coordinate: CLLocationCoordinate2D
        if #available(iOS 26.0, *) {
            coordinate = mapItem.location.coordinate
        } else {
            coordinate = mapItem.placemark.coordinate
        }

        #expect(mapItem.name == restaurant.name)
        #expect(abs(coordinate.latitude - restaurant.latitude) < 0.000_001)
        #expect(abs(coordinate.longitude - restaurant.longitude) < 0.000_001)
        #expect(restaurant.appleMapItemIdentifier == "apple-detail-place")
    }

    @Test("离线编辑名称和城市不会破坏 Restaurant 或 provider identity")
    func offlineRestaurantEditPreservesIdentity() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let restaurant = restaurant(serverVersion: 4)
        let originalID = restaurant.id
        let originalRemoteID = restaurant.remoteID
        let originalAppleID = restaurant.appleMapItemIdentifier
        let originalAddress = restaurant.address
        let originalLatitude = restaurant.latitude
        let originalLongitude = restaurant.longitude
        context.insert(restaurant)
        try context.save()

        try LocalTasteMapStore(context: context).updateBasics(
            restaurant,
            name: "  编辑后的餐厅  ",
            city: " 杭州 "
        )

        let mutations = try context.fetch(FetchDescriptor<SyncMutation>())
        let payload = try #require(mutations.first?.payload)
        let record = try JSONDecoder().decode(RestaurantJSONContractV1.self, from: payload)
        #expect(restaurant.id == originalID)
        #expect(restaurant.remoteID == originalRemoteID)
        #expect(restaurant.appleMapItemIdentifier == originalAppleID)
        #expect(restaurant.address == originalAddress)
        #expect(restaurant.latitude == originalLatitude)
        #expect(restaurant.longitude == originalLongitude)
        #expect(restaurant.name == "编辑后的餐厅")
        #expect(restaurant.city == "杭州")
        #expect(restaurant.syncStatus == .pending)
        #expect(try context.fetch(FetchDescriptor<Restaurant>()).count == 1)
        #expect(mutations.count == 1)
        #expect(record.id == originalRemoteID)
        #expect(record.placeIdentities.first?.provider == .appleMaps)
        #expect(record.placeIdentities.first?.externalId == originalAppleID)
    }

    @Test("App 重启后 Restaurant Detail 数据仍然正确")
    func detailPersistsAcrossRelaunch() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TasteMapDetailTests-\(UUID().uuidString)")
            .appendingPathExtension("store")
        defer { removeStoreFiles(at: storeURL) }

        let restaurantID: UUID
        do {
            let container = try persistentContainer(at: storeURL)
            let context = container.mainContext
            let restaurant = restaurant()
            restaurantID = restaurant.id
            context.insert(restaurant)
            context.insert(visit(restaurantID: restaurant.id, days: 2, rating: 4.5, spend: 128))
            context.insert(visit(restaurantID: restaurant.id, days: 1, rating: nil, spend: nil))
            try context.save()
        }

        let reopened = try persistentContainer(at: storeURL)
        let context = reopened.mainContext
        let restaurant = try #require(
            context.fetch(FetchDescriptor<Restaurant>()).first { $0.id == restaurantID }
        )
        let presentation = detail(for: restaurant, context: context)
        #expect(restaurant.appleMapItemIdentifier == "apple-detail-place")
        #expect(presentation.visitCount == 2)
        #expect(presentation.averageRating == 4.5)
        #expect(presentation.totalSpend == Decimal(128))
    }

    private func detail(
        for restaurant: Restaurant,
        context: ModelContext
    ) -> RestaurantDetailPresentation {
        RestaurantDetailPresentation(
            restaurantID: restaurant.id,
            visits: (try? context.fetch(FetchDescriptor<Visit>())) ?? []
        )
    }

    private func restaurant(
        status: RestaurantStatus = .visited,
        serverVersion: Int64 = 0
    ) -> Restaurant {
        Restaurant(
            name: "Apple 地图餐厅",
            address: "杭州市湖滨路 18 号",
            latitude: 30.259,
            longitude: 120.168,
            appleMapItemIdentifier: "apple-detail-place",
            city: "杭州",
            status: status,
            remoteID: "tm-restaurant-detail",
            serverVersion: serverVersion,
            syncStatus: serverVersion > 0 ? .synced : .pending
        )
    }

    private func visit(
        restaurantID: UUID,
        days: TimeInterval,
        rating: Double?,
        spend: Decimal?,
        deletedAt: Date? = nil
    ) -> Visit {
        Visit(
            restaurantId: restaurantID,
            visitedAt: Date(timeIntervalSince1970: days * 86_400),
            rating: rating,
            myActualSpend: spend,
            createdAt: Date(timeIntervalSince1970: days * 86_400),
            deletedAt: deletedAt,
            syncStatus: .synced
        )
    }

    private func persistentContainer(at url: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "TasteMapDetailTests",
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
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(atPath: url.path + "-shm")
        try? FileManager.default.removeItem(atPath: url.path + "-wal")
    }
}
