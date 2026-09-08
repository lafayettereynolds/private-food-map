import Foundation
import Testing
@testable import TasteMap

@Suite("City filter source and canonical identity")
@MainActor
struct CityFilterSourceTests {
    @Test("Native rollback uses unfiltered per-scope cities and matches display aliases")
    func scopeAndAliases() {
        let shanghai = restaurant("上海市", .visited)
        let alias = restaurant("上海", .visited)
        let hangzhou = restaurant("杭州", .visited)
        let wanted = restaurant("东京", .wantToGo)
        let deleted = restaurant("北京", .visited)
        deleted.deletedAt = .now
        let source = [shanghai, alias, hangzhou, wanted, deleted]
        let snapshot = RestaurantBrowseBuilder.build(restaurants: source, visits: [])
        #expect(Set(snapshot.filterOptions(for: .visited).cities) == Set(["上海", "杭州"]))
        #expect(snapshot.filterOptions(for: .wantToGo).cities == ["东京"])
        #expect(snapshot.filterOptions(for: .forYou).cities.isEmpty)
        var state = PersonalRestaurantFilterState(status: .visited)
        state.city = "上海"
        let result = PersonalRestaurantFilterEngine.resolve(snapshot: snapshot, state: state)
        #expect(Set(result.items.map(\.id)) == Set([shanghai.id, alias.id]))
        #expect(Set(snapshot.filterOptions(for: .visited).cities) == Set(["上海", "杭州"]))
        #expect(shanghai.city == "上海市")
    }

    @Test("Native rollback rebuild reflects same-timestamp city, status, add and delete changes")
    func changedSnapshot() {
        let edited = restaurant("上海市", .visited)
        let moved = restaurant("杭州", .visited)
        let removed = restaurant("北京", .visited)
        let before = RestaurantBrowseBuilder.build(restaurants: [edited, moved, removed], visits: [])
        #expect(before.filterOptions(for: .visited).cities.count == 3)
        edited.city = "温州市"
        moved.status = .wantToGo
        removed.deletedAt = .now
        let added = restaurant("New York", .visited)
        let after = RestaurantBrowseBuilder.build(restaurants: [edited, moved, removed, added], visits: [])
        #expect(Set(after.filterOptions(for: .visited).cities) == Set(["温州", "New York"]))
        #expect(after.filterOptions(for: .wantToGo).cities == ["杭州"])
        #expect(edited.city == "温州市")
    }

    private func restaurant(_ city: String, _ status: RestaurantStatus) -> Restaurant {
        Restaurant(name: "\(city)真实餐厅", address: "测试路", latitude: 30, longitude: 120, city: city, status: status)
    }
}
