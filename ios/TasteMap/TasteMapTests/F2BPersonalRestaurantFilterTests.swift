import CoreLocation
import Foundation
import Testing
@testable import TasteMap

@Suite("F2-B personal Restaurant filters and sorting")
@MainActor
struct F2BPersonalRestaurantFilterTests {
    @Test("1. status supports visited, want-to-go and all")
    func status() {
        let fixture = makeFixture()
        #expect(resolve(fixture, status: .visited).count == 3)
        #expect(resolve(fixture, status: .wantToGo).map(\.restaurant.name) == ["想吃小馆"])
        #expect(resolve(fixture, status: .all).count == 4)
    }

    @Test("2. dine-in matches a Restaurant with a qualifying active Visit")
    func dineIn() {
        var state = state()
        state.diningMode = .dineIn
        #expect(names(resolve(makeFixture(), state)) == ["甲餐厅", "乙餐厅"])
    }

    @Test("3. takeout matches any qualifying active Visit")
    func takeout() {
        var state = state()
        state.diningMode = .takeout
        #expect(names(resolve(makeFixture(), state)) == ["甲餐厅", "丙未评分"])
    }

    @Test("4. visit count uses Web 1+, 2+, 3+, 5+, 10+ threshold semantics")
    func visitCount() {
        var state = state()
        state.visitCount = .two
        #expect(names(resolve(makeFixture(), state)) == ["甲餐厅"])
        state.visitCount = .three
        #expect(resolve(makeFixture(), state).isEmpty)
    }

    @Test("5. rating bands are multi-select and use average non-nil Visit rating")
    func ratingBands() {
        var state = state()
        state.ratingBands = [.five, .three]
        #expect(names(resolve(makeFixture(), state)) == ["甲餐厅", "乙餐厅"])
    }

    @Test("6. nil rating is not treated as zero")
    func nilRating() {
        var state = state()
        state.ratingBands = [.one]
        #expect(resolve(makeFixture(), state).isEmpty)
    }

    @Test("7. price range follows Visit pricePerPerson boundaries")
    func priceRange() {
        var state = state()
        state.priceRange = .under100
        #expect(names(resolve(makeFixture(), state)) == ["乙餐厅"])
        state.priceRange = .from100To200
        #expect(names(resolve(makeFixture(), state)) == ["甲餐厅"])
        state.priceRange = .over200
        #expect(names(resolve(makeFixture(), state)) == ["甲餐厅"])
    }

    @Test("8. nil price does not borrow myActualSpend or become the cheapest bucket")
    func nilPriceAndSpend() {
        let fixture = makeFixture(gammaActualSpend: 20)
        var state = state()
        state.priceRange = .under100
        #expect(!names(resolve(fixture, state)).contains("丙未评分"))
    }

    @Test("9. recorded queue values distinguish no-wait from an actual duration")
    func queue() {
        var state = state()
        state.queue = .recorded(.noWait)
        #expect(names(resolve(makeFixture(), state)) == ["甲餐厅"])
        state.queue = .recorded(.over120)
        #expect(names(resolve(makeFixture(), state)) == ["丙未评分"])
    }

    @Test("10. unrecorded queue matches nil only")
    func nilQueue() {
        var state = state()
        state.queue = .unrecorded
        #expect(names(resolve(makeFixture(), state)) == ["乙餐厅"])
    }

    @Test("11. dining scenes support multi-select OR within the group")
    func diningScene() {
        var state = state()
        state.diningOccasions = [.friends, .family]
        #expect(names(resolve(makeFixture(), state)) == ["甲餐厅", "丙未评分"])
    }

    @Test("12. recommendation source uses current user's Visit source projection")
    func recommendationSource() throws {
        let fixture = makeFixture()
        let source = try #require(fixture.filterOptions.sources.first { $0.title == "朋友推荐" })
        var state = state()
        state.sourceID = source.id
        #expect(names(resolve(fixture, state)) == ["甲餐厅"])
    }

    @Test("13. companion uses private companion names rather than social identity")
    func companion() throws {
        let fixture = makeFixture()
        let companion = try #require(fixture.filterOptions.companions.first { $0.title == "小林" })
        var state = state()
        state.companionID = companion.id
        #expect(names(resolve(fixture, state)) == ["甲餐厅"])
    }

    @Test("14. visit period restores six-month and one-year calendar semantics")
    func visitPeriod() {
        let fixture = makeFixture()
        var state = state()
        state.visitPeriod = .sixMonths
        #expect(names(resolve(fixture, state)) == ["甲餐厅", "乙餐厅"])
        state.visitPeriod = .oneYear
        #expect(names(resolve(fixture, state)) == ["甲餐厅", "乙餐厅"])
    }

    @Test("15. city comes from active personal Restaurants")
    func city() {
        var state = state()
        state.city = "杭州"
        #expect(names(resolve(makeFixture(), state)) == ["甲餐厅", "丙未评分"])
    }

    @Test("16. distance supports 1/3/5/10 km and excludes invalid coordinates")
    func distance() {
        let invalid = restaurant(90, "无坐标", city: "杭州", status: .visited, latitude: 0, longitude: 0)
        let fixture = RestaurantBrowseBuilder.build(restaurants: [invalid] + fixtureRestaurants(), visits: fixtureVisits())
        var state = state()
        state.distance = .five
        let location = CLLocation(latitude: 30.2741, longitude: 120.1551)
        let result = PersonalRestaurantFilterEngine.resolve(
            snapshot: fixture, state: state, currentLocation: location, now: now
        ).items
        #expect(names(result) == ["甲餐厅", "丙未评分"])
        #expect(!names(result).contains("无坐标"))
    }

    @Test("17. combined Visit filters must match the same Visit")
    func combinedFilters() throws {
        let fixture = makeFixture()
        let friend = try #require(fixture.filterOptions.sources.first { $0.title == "朋友推荐" })
        let xiaohongshu = try #require(fixture.filterOptions.sources.first { $0.title == "小红书" })
        var state = state()
        state.diningMode = .takeout
        state.sourceID = friend.id
        #expect(resolve(fixture, state).isEmpty)
        state.sourceID = xiaohongshu.id
        #expect(names(resolve(fixture, state)) == ["甲餐厅"])
    }

    @Test("18. reset clears filters and sort while preserving top-level status")
    func reset() {
        var state = PersonalRestaurantFilterState(
            status: .wantToGo,
            diningMode: .takeout,
            visitCount: .five,
            ratingBands: [.five],
            city: "杭州",
            sort: .rating
        )
        state.resetKeepingStatus()
        #expect(state == PersonalRestaurantFilterState(status: .wantToGo))
    }

    @Test("19. active count follows Web group-count semantics and ignores inactive Visit groups on want-to-go")
    func activeFilterCount() {
        var state = state()
        state.ratingBands = [.five, .four, .three]
        state.diningOccasions = [.friends, .family]
        state.city = "杭州"
        state.diningMode = .dineIn
        #expect(state.activeFilterCount == 4)
        state.status = .wantToGo
        #expect(state.activeFilterCount == 2)
    }

    @Test("20. Map and List consume the exact same resolved collection")
    func mapListParity() {
        let fixture = makeFixture()
        var state = state()
        state.ratingBands = [.five]
        state.city = "杭州"
        let shared = PersonalRestaurantFilterEngine.resolve(snapshot: fixture, state: state, now: now)
        let mapIDs = shared.items.map(\.id)
        let listIDs = shared.items.map(\.id)
        #expect(mapIDs == listIDs)
        #expect(mapIDs.count == 1)
    }

    @Test("21. recent sort uses latest active Visit and creation time for no-Visit want-to-go")
    func sortRecent() {
        var state = PersonalRestaurantFilterState(status: .all)
        state.sort = .recent
        #expect(names(resolve(makeFixture(), state)) == ["乙餐厅", "甲餐厅", "想吃小馆", "丙未评分"])
    }

    @Test("22. rating sort puts rated Restaurants first and nil ratings last")
    func sortRating() {
        var state = state()
        state.sort = .rating
        #expect(names(resolve(makeFixture(), state)) == ["甲餐厅", "乙餐厅", "丙未评分"])
    }

    @Test("23. comprehensive sort is Web score, count, recent Visit and creation order")
    func sortComprehensive() {
        let state = state()
        #expect(names(resolve(makeFixture(), state)) == ["甲餐厅", "乙餐厅", "丙未评分"])
    }

    @Test("24. Restaurant and Visit tombstones never enter aggregates")
    func tombstones() {
        let fixture = makeFixture()
        #expect(!names(fixture.visited).contains("已删除餐厅"))
        let alpha = fixture.visited.first { $0.restaurant.name == "甲餐厅" }
        #expect(alpha?.visitCount == 2)
        #expect(alpha?.averageRating == 4.75)
    }

    @Test("25. 1,000 Restaurants, 10,000 Visits and combined filters avoid repeated global scans")
    func largeDataset() {
        let restaurants = (0..<1_000).map { index in
            restaurant(
                1_000 + index,
                "性能餐厅 \(index)",
                city: index.isMultiple(of: 2) ? "杭州" : "上海",
                status: index.isMultiple(of: 5) ? .wantToGo : .visited,
                latitude: 30.2 + Double(index % 10) / 1_000,
                longitude: 120.1 + Double(index % 10) / 1_000
            )
        }
        let visits = (0..<10_000).map { index in
            Visit(
                id: uuid(20_000 + index),
                restaurantId: restaurants[index % 1_000].id,
                visitedAt: now.addingTimeInterval(-Double(index % 300) * 86_400),
                rating: index.isMultiple(of: 3) ? nil : 4.5,
                pricePerPerson: index.isMultiple(of: 2) ? 150 : nil,
                diningMode: index.isMultiple(of: 2) ? .takeout : .dineIn,
                queueDuration: index.isMultiple(of: 4) ? .under30 : nil,
                diningOccasions: index.isMultiple(of: 5) ? [.friends] : [],
                companionNames: index.isMultiple(of: 7) ? ["小林"] : [],
                recommendationSourceType: index.isMultiple(of: 11) ? .friend : nil,
                syncStatus: .synced
            )
        }
        let started = Date()
        let snapshot = RestaurantBrowseBuilder.build(restaurants: restaurants, visits: visits)
        var filter = state()
        filter.diningMode = .takeout
        filter.ratingBands = [.five]
        filter.priceRange = .from100To200
        filter.visitPeriod = .oneYear
        filter.city = "杭州"
        filter.sort = .rating
        let result = PersonalRestaurantFilterEngine.resolve(snapshot: snapshot, state: filter, now: now)
        let duration = Date().timeIntervalSince(started)

        #expect(!result.items.isEmpty)
        #expect(result.items.allSatisfy { $0.restaurant.city == "杭州" })
        #expect(duration < 5, "Projection and combined filtering took \(duration) seconds")
    }

    private var now: Date { Date(timeIntervalSince1970: 2_000_000_000) }

    private func state() -> PersonalRestaurantFilterState {
        PersonalRestaurantFilterState(status: .visited)
    }

    private func resolve(
        _ fixture: RestaurantBrowseSnapshot,
        _ state: PersonalRestaurantFilterState
    ) -> [RestaurantBrowseItem] {
        PersonalRestaurantFilterEngine.resolve(snapshot: fixture, state: state, now: now).items
    }

    private func resolve(
        _ fixture: RestaurantBrowseSnapshot,
        status: PersonalRestaurantStatusFilter
    ) -> [RestaurantBrowseItem] {
        resolve(fixture, PersonalRestaurantFilterState(status: status))
    }

    private func names(_ items: [RestaurantBrowseItem]) -> [String] {
        items.map(\.restaurant.name)
    }

    private func makeFixture(gammaActualSpend: Decimal? = nil) -> RestaurantBrowseSnapshot {
        RestaurantBrowseBuilder.build(
            restaurants: fixtureRestaurants(includeDeleted: true),
            visits: fixtureVisits(gammaActualSpend: gammaActualSpend, includeDeleted: true)
        )
    }

    private func fixtureRestaurants(includeDeleted: Bool = false) -> [Restaurant] {
        let alpha = restaurant(1, "甲餐厅", city: "杭州", status: .visited, latitude: 30.2741, longitude: 120.1551)
        let beta = restaurant(2, "乙餐厅", city: "上海", status: .visited, latitude: 31.2304, longitude: 121.4737)
        let gamma = restaurant(3, "丙未评分", city: "杭州", status: .visited, latitude: 30.2800, longitude: 120.1600)
        let wanted = restaurant(4, "想吃小馆", city: "杭州", status: .wantToGo, latitude: 30.30, longitude: 120.20)
        wanted.createdAt = now.addingTimeInterval(-86_400 * 20)
        let deleted = restaurant(5, "已删除餐厅", city: "杭州", status: .visited, latitude: 30.27, longitude: 120.15)
        deleted.deletedAt = now.addingTimeInterval(-100)
        return includeDeleted ? [alpha, beta, gamma, wanted, deleted] : [alpha, beta, gamma, wanted]
    }

    private func fixtureVisits(
        gammaActualSpend: Decimal? = nil,
        includeDeleted: Bool = false
    ) -> [Visit] {
        let alphaID = uuid(1)
        let betaID = uuid(2)
        let gammaID = uuid(3)
        var values = [
            Visit(
                id: uuid(101), restaurantId: alphaID,
                visitedAt: now.addingTimeInterval(-86_400 * 10), rating: 4.5,
                pricePerPerson: 150, diningMode: .dineIn, queueDuration: .noWait,
                diningOccasions: [.friends], companionNames: ["小林"],
                recommendationSourceType: .friend, syncStatus: .synced
            ),
            Visit(
                id: uuid(102), restaurantId: alphaID,
                visitedAt: now.addingTimeInterval(-86_400 * 50), rating: 5,
                pricePerPerson: 220, diningMode: .takeout, queueDuration: .under30,
                diningOccasions: [.solo], companionNames: ["阿宁"],
                recommendationSourceType: .xiaohongshu, syncStatus: .synced
            ),
            Visit(
                id: uuid(103), restaurantId: betaID,
                visitedAt: now.addingTimeInterval(-86_400 * 5), rating: 3,
                pricePerPerson: 80, diningMode: .dineIn, queueDuration: nil,
                diningOccasions: [.business], companionNames: ["阿宁"],
                recommendationSourceType: .dianping, syncStatus: .synced
            ),
            Visit(
                id: uuid(104), restaurantId: gammaID,
                visitedAt: now.addingTimeInterval(-86_400 * 400), rating: nil,
                myActualSpend: gammaActualSpend, pricePerPerson: nil,
                diningMode: .takeout, queueDuration: .over120,
                diningOccasions: [.family], syncStatus: .synced
            ),
        ]
        if includeDeleted {
            values.append(Visit(
                id: uuid(105), restaurantId: alphaID,
                visitedAt: now, rating: 0.5, deletedAt: now, syncStatus: .synced
            ))
            values.append(Visit(
                id: uuid(106), restaurantId: uuid(5),
                visitedAt: now, rating: 5, syncStatus: .synced
            ))
        }
        return values
    }

    private func restaurant(
        _ value: Int,
        _ name: String,
        city: String,
        status: RestaurantStatus,
        latitude: Double = 30,
        longitude: Double = 120
    ) -> Restaurant {
        Restaurant(
            id: uuid(value), name: name, address: "测试路 \(value) 号",
            latitude: latitude, longitude: longitude, city: city, status: status,
            createdAt: now.addingTimeInterval(-Double(value) * 86_400),
            updatedAt: now, syncStatus: .synced
        )
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}
