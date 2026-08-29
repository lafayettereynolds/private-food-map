import Foundation
import Testing
@testable import TasteMap

@Suite("F2-A Map, lists and taste footprints")
@MainActor
struct F2AMapListFootprintsTests {
    @Test("Visited and want-to-go collections share active Restaurant semantics")
    func collectionSemantics() throws {
        let visited = restaurant(1, name: "最近去过", city: "杭州", status: .visited)
        let older = restaurant(2, name: "较早去过", city: "上海", status: .visited)
        let wanted = restaurant(3, name: "想吃小馆", city: "成都", status: .wantToGo)
        let deleted = restaurant(4, name: "已删除", city: "杭州", status: .visited)
        deleted.deletedAt = date(900)

        let visits = [
            visit(11, restaurant: visited, at: 800, rating: nil),
            visit(12, restaurant: visited, at: 700, rating: 4.5),
            visit(13, restaurant: older, at: 600, rating: 3.5),
            visit(14, restaurant: visited, at: 950, rating: 1, deletedAt: date(960)),
            visit(15, restaurant: deleted, at: 980, rating: 5),
        ]

        let snapshot = RestaurantBrowseBuilder.build(
            restaurants: [wanted, deleted, older, visited],
            visits: visits
        )

        #expect(snapshot.visited.map(\.id) == [visited.id, older.id])
        #expect(snapshot.wantToGo.map(\.id) == [wanted.id])
        #expect(snapshot.visited[0].visitCount == 2)
        #expect(snapshot.visited[0].averageRating == 4.5)
        #expect(snapshot.visited[0].latestVisitAt == date(800))
        #expect(snapshot.footprints.count == 3)
        #expect(snapshot.footprints.allSatisfy { $0.restaurant.id != deleted.id })
        #expect(snapshot.footprints.allSatisfy { $0.visit.id != uuid(14) })
        #expect(snapshot.footprints.contains { $0.visit.rating == nil })
    }

    @Test("Every active Visit becomes one independently sorted footprint with real metadata")
    func footprintMetadata() throws {
        let restaurant = restaurant(
            21,
            name: "一间名称很长很长但不能丢失的季节料理小馆",
            city: "杭州",
            status: .visited
        )
        let companion = DiningCompanion(
            id: uuid(22), ownerUserId: "tm_current", displayName: "小林", syncStatus: .synced
        )
        let source = RecommendationSource(
            id: uuid(23), ownerUserId: "tm_current", displayName: "朋友阿宁",
            sourceType: .friend, syncStatus: .synced
        )
        let first = Visit(
            id: uuid(24), restaurantId: restaurant.id, visitedAt: date(400),
            rating: 4.5, note: "第一次到访",
            companionIDs: [companion.remoteID!],
            recommendationSourceID: source.remoteID,
            syncStatus: .synced
        )
        let second = Visit(
            id: uuid(25), restaurantId: restaurant.id, visitedAt: date(500),
            rating: nil, note: "第二次到访", syncStatus: .synced
        )
        let dish = Dish(
            id: uuid(26), restaurantId: restaurant.id, visitId: first.id,
            name: "炭烤时蔬", syncStatus: .synced
        )
        let association = VisitDish(
            id: uuid(27), restaurantId: restaurant.id, visitId: first.id,
            dishId: dish.id, syncStatus: .synced
        )
        let photo = PhotoAsset(
            id: uuid(28), restaurantId: restaurant.id, visitId: first.id,
            kind: .visit, mimeType: "image/jpeg", byteSize: 100,
            createdAt: date(410), syncStatus: .synced
        )
        let deletedPhoto = PhotoAsset(
            id: uuid(29), restaurantId: restaurant.id, visitId: second.id,
            kind: .visit, mimeType: "image/jpeg", byteSize: 100,
            createdAt: date(510), deletedAt: date(520), syncStatus: .synced
        )

        let snapshot = RestaurantBrowseBuilder.build(
            restaurants: [restaurant], visits: [first, second],
            photos: [photo, deletedPhoto], dishes: [dish], visitDishes: [association],
            companions: [companion], recommendationSources: [source]
        )

        #expect(snapshot.footprints.map(\.visit.id) == [second.id, first.id])
        #expect(snapshot.footprints[0].photo == nil)
        let firstFootprint = try #require(snapshot.footprints.first { $0.visit.id == first.id })
        #expect(firstFootprint.photo?.id == photo.id)
        #expect(firstFootprint.dishNames == ["炭烤时蔬"])
        #expect(firstFootprint.companionNames == ["小林"])
        #expect(firstFootprint.recommendationSource == "朋友阿宁")
        #expect(firstFootprint.restaurant.name == restaurant.name)
    }

    @Test("Missing photos, empty collections and local search have explicit results")
    func fallbackEmptyAndSearch() {
        let hangzhou = restaurant(31, name: "青岚寿司", city: "杭州", status: .visited)
        hangzhou.address = "湖滨路 1 号"
        let shanghai = restaurant(32, name: "雨巷火锅", city: "上海", status: .wantToGo)
        shanghai.address = "静安路 2 号"
        let snapshot = RestaurantBrowseBuilder.build(
            restaurants: [hangzhou, shanghai], visits: []
        )

        #expect(snapshot.visited[0].photo == nil)
        #expect(snapshot.wantToGo[0].photo == nil)
        #expect(snapshot.footprints.isEmpty)
        #expect(RestaurantBrowseSearch.filter(snapshot.visited, query: "青岚").map(\.id) == [hangzhou.id])
        #expect(RestaurantBrowseSearch.filter(snapshot.visited, query: "杭州").map(\.id) == [hangzhou.id])
        #expect(RestaurantBrowseSearch.filter(snapshot.visited, query: "湖滨路").map(\.id) == [hangzhou.id])
        #expect(RestaurantBrowseSearch.filter(snapshot.visited, query: "不存在").isEmpty)

        let empty = RestaurantBrowseBuilder.build(restaurants: [], visits: [])
        #expect(empty.visited.isEmpty)
        #expect(empty.wantToGo.isEmpty)
        #expect(empty.footprints.isEmpty)
    }

    @Test("Profile statistics use the same tombstone and Restaurant status boundaries")
    func profileCountsMatchLists() {
        let visited = restaurant(41, name: "去过", city: "杭州", status: .visited)
        let wanted = restaurant(42, name: "想吃", city: "杭州", status: .wantToGo)
        let deleted = restaurant(43, name: "删除", city: "杭州", status: .visited)
        deleted.deletedAt = date(100)
        let valid = visit(44, restaurant: visited, at: 90, rating: 4.5)
        let nilRating = visit(45, restaurant: visited, at: 80, rating: nil)
        let invalid = visit(46, restaurant: deleted, at: 70, rating: 5)

        let statistics = ProfileBasicStatistics(
            restaurants: [visited, wanted, deleted], visits: [valid, nilRating, invalid]
        )
        let snapshot = RestaurantBrowseBuilder.build(
            restaurants: [visited, wanted, deleted], visits: [valid, nilRating, invalid]
        )

        #expect(statistics.visitedRestaurantCount == snapshot.visited.count)
        #expect(statistics.wantToGoRestaurantCount == snapshot.wantToGo.count)
        #expect(statistics.visitCount == snapshot.footprints.count)
        #expect(statistics.averageRating == 4.5)
    }

    @Test("One thousand Restaurants and ten thousand Visits build without quadratic row scans")
    func largeFixturePerformance() {
        let restaurants = (0..<1_000).map { index in
            restaurant(
                1_000 + index,
                name: "性能餐厅 \(index)",
                city: index.isMultiple(of: 2) ? "杭州" : "上海",
                status: index.isMultiple(of: 5) ? .wantToGo : .visited
            )
        }
        let visits = (0..<10_000).map { index in
            let restaurant = restaurants[index % restaurants.count]
            return visit(
                20_000 + index,
                restaurant: restaurant,
                at: Double(index),
                rating: index.isMultiple(of: 3) ? nil : Double(index % 10 + 1) / 2
            )
        }

        let started = Date()
        let snapshot = RestaurantBrowseBuilder.build(restaurants: restaurants, visits: visits)
        let duration = Date().timeIntervalSince(started)

        #expect(snapshot.visited.count == 800)
        #expect(snapshot.wantToGo.count == 200)
        #expect(snapshot.footprints.count == 10_000)
        #expect(duration < 5, "Projection took \(duration) seconds")
    }

    private func restaurant(
        _ value: Int,
        name: String,
        city: String,
        status: RestaurantStatus
    ) -> Restaurant {
        Restaurant(
            id: uuid(value), name: name, address: "测试路 \(value) 号",
            latitude: 30, longitude: 120, city: city, status: status,
            createdAt: date(Double(value)), updatedAt: date(Double(value)),
            syncStatus: .synced
        )
    }

    private func visit(
        _ value: Int,
        restaurant: Restaurant,
        at: Double,
        rating: Double?,
        deletedAt: Date? = nil
    ) -> Visit {
        Visit(
            id: uuid(value), restaurantId: restaurant.id, visitedAt: date(at),
            rating: rating, createdAt: date(at), updatedAt: date(at),
            deletedAt: deletedAt, syncStatus: .synced
        )
    }

    private func date(_ value: Double) -> Date {
        Date(timeIntervalSince1970: value)
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}
