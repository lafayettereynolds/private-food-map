import Foundation
import SwiftData
import XCTest
@testable import TasteMapHybridBridge

@MainActor
final class CityFilterSourceContractTests: XCTestCase {
    func testCityIdentityKeepsRealNamesAndDoesNotRewriteStoredValues() {
        let source = ["上海市", " 上海 ", "杭州市", "杭州", "温州市", "温州", "广州市", "", "  "]
        XCTAssertEqual(Set(RestaurantCityFilterIdentity.options(source)), Set(["上海", "杭州", "温州", "广州"]))
        XCTAssertEqual(source[0], "上海市")
        XCTAssertTrue(RestaurantCityFilterIdentity.matches("上海市", "上海"))
        XCTAssertTrue(RestaurantCityFilterIdentity.matches("杭州市", "杭州"))
        XCTAssertFalse(RestaurantCityFilterIdentity.matches("杭州", "杭"))
        XCTAssertFalse(RestaurantCityFilterIdentity.matches("东京", "东京都"))
        XCTAssertTrue(RestaurantCityFilterIdentity.matches("Ｋａｎｓａｓ　Ｃｉｔｙ", "Kansas City"))
        XCTAssertFalse(RestaurantCityFilterIdentity.matches("Kansas City", "Kansas"))
    }

    func testBridgeCityOptionsUseOwnerAndScopeBeforeOtherFiltersAndRefreshWithNewSnapshot() throws {
        let owner = "tm_city_source_owner"
        let schema = Schema([Restaurant.self, Visit.self, UserProfile.self, CachedFollow.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(
            "CitySource", schema: schema, isStoredInMemoryOnly: true, groupContainer: .none, cloudKitDatabase: .none
        )])
        let context = ModelContext(container)
        context.insert(UserProfile(tasteMapUserID: owner, displayName: "City owner"))
        let shanghai = Restaurant(ownerUserID: owner, name: "上海店", address: "路1号", latitude: 31, longitude: 121, city: "上海市")
        let alias = Restaurant(ownerUserID: owner, name: "上海别名店", address: "路2号", latitude: 31, longitude: 121, city: "上海")
        let hangzhou = Restaurant(ownerUserID: owner, name: "杭州店", address: "路3号", latitude: 30, longitude: 120, city: "杭州")
        let wanted = Restaurant(ownerUserID: owner, name: "东京想吃店", address: "路4号", latitude: 35, longitude: 139, city: "东京", status: .wantToGo)
        let foreign = Restaurant(ownerUserID: "tm_other_owner", name: "他人的广州店", address: "路5号", latitude: 23, longitude: 113, city: "广州")
        let deleted = Restaurant(ownerUserID: owner, name: "已删除北京店", address: "路6号", latitude: 39, longitude: 116, city: "北京")
        deleted.deletedAt = .now
        [shanghai, alias, hangzhou, wanted, foreign, deleted].forEach { context.insert($0) }
        try context.save()
        var service = try TasteMapHybridBridgeService(container: container, ownerUserID: owner)
        let visited = try service.mapViewport(request: request(.visited))
        XCTAssertEqual(Set(visited.options.cities), Set(["上海", "杭州"]))
        XCTAssertEqual(visited.totalCount, 3)
        XCTAssertEqual(try service.mapViewport(request: request(.wantToGo)).options.cities, ["东京"])
        XCTAssertEqual(try service.mapViewport(request: request(.recommended)).options.cities, [])
        let selected = try service.mapViewport(request: request(.visited, city: " 上海 "))
        XCTAssertEqual(Set(selected.items.map(\.city)), Set(["上海", "上海市"]))
        XCTAssertEqual(selected.options.cities, visited.options.cities)
        let filtered = try service.mapViewport(request: request(.visited, city: "上海市", emptyBounds: true, search: "不存在"))
        XCTAssertEqual(filtered.totalCount, 0)
        XCTAssertEqual(filtered.options.cities, visited.options.cities)
        XCTAssertEqual(shanghai.city, "上海市")

        // Mirrors Native localDataDidChange invalidating its read facade. City
        // and status edits must be reflected even if updatedAt is unchanged.
        shanghai.city = "温州市"
        alias.deletedAt = .now
        hangzhou.status = .wantToGo
        let added = Restaurant(ownerUserID: owner, name: "新增纽约", address: "路7号", latitude: 40, longitude: -74, city: "New York")
        context.insert(added)
        try context.save()
        service = try TasteMapHybridBridgeService(container: container, ownerUserID: owner)
        XCTAssertEqual(Set(try service.mapViewport(request: request(.visited)).options.cities), Set(["温州", "New York"]))
        XCTAssertEqual(Set(try service.mapViewport(request: request(.wantToGo)).options.cities), Set(["东京", "杭州"]))
    }

    private func request(_ scope: TasteMapHybridMapScope, city: String? = nil, emptyBounds: Bool = false, search: String = "") -> TasteMapHybridMapBrowseRequest {
        TasteMapHybridMapBrowseRequest(
            requestID: "city-scope-test", scope: scope,
            bounds: emptyBounds ? TasteMapHybridMapBounds(north: 1, south: 0, east: 1, west: 0) : nil,
            filters: TasteMapHybridMapFilters(city: city), sort: .recent, search: search, limit: 300, currentLocation: nil
        )
    }
}
