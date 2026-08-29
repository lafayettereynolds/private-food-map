import Foundation
import Testing
@testable import TasteMap

@Suite("F7-A On This Day")
struct OnThisDayTests {
    private let ownerA = "tm_owner_a"
    private let ownerB = "tm_owner_b"
    private let shanghai: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_Hans_CN")
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }()

    @Test("1 no history remains explicitly empty")
    func noHistory() {
        let report = analyze(input(visits: []))
        #expect(!report.hasMemories)
        #expect(report.groups.isEmpty)
    }

    @Test("2 one prior year is enough to create a memory")
    func onePriorYear() {
        let report = analyze(input(visits: [visit(1, year: 2025)]))
        #expect(report.memories.count == 1)
        #expect(report.memories[0].yearsAgo == 1)
    }

    @Test("3 multiple prior years are grouped newest year first")
    func multiplePriorYears() {
        let report = analyze(input(visits: [
            visit(1, year: 2023), visit(2, year: 2025), visit(3, year: 2024),
        ]))
        #expect(report.groups.map(\.year) == [2025, 2024, 2023])
        #expect(report.memories.count == 3)
    }

    @Test("4 current year is never promoted into a memory")
    func currentYearExcluded() {
        let report = analyze(input(visits: [visit(1, year: 2026), visit(2, year: 2025)]))
        #expect(report.memories.map(\.year) == [2025])
    }

    @Test("5 multiple Visits on the same day remain independent")
    func sameDayMultipleVisits() {
        let report = analyze(input(visits: [
            visit(1, year: 2025, hour: 12), visit(2, year: 2025, hour: 20),
        ]))
        #expect(report.memories.count == 2)
        #expect(Set(report.memories.map(\.id)).count == 2)
        #expect(report.memories.map(\.id) == [uuid(2), uuid(1)])
    }

    @Test("6 deleted Visit is excluded")
    func deletedVisitExcluded() {
        let deleted = visit(1, year: 2025, deletedAt: date(2025, 9, 1))
        #expect(analyze(input(visits: [deleted])).memories.isEmpty)
    }

    @Test("7 deleted Restaurant excludes its Visit")
    func deletedRestaurantExcluded() {
        let deletedRestaurant = restaurant(1, owner: ownerA, deletedAt: date(2026, 1, 1))
        #expect(analyze(input(restaurants: [deletedRestaurant], visits: [visit(1, year: 2025)])).memories.isEmpty)
    }

    @Test("8 nil rating is preserved and not invented")
    func nilRating() {
        let report = analyze(input(visits: [visit(1, year: 2025, rating: nil)]))
        #expect(report.memories[0].rating == nil)
    }

    @Test("9 nil spend is preserved and not treated as zero")
    func nilSpend() {
        let report = analyze(input(visits: [visit(1, year: 2025, spend: nil)]))
        #expect(report.memories[0].spend == nil)
    }

    @Test("10 missing or tombstoned Photo uses the no-photo reference")
    func photoMissing() {
        let photo = OnThisDayInput.PhotoRecord(
            id: uuid(80), restaurantID: uuid(1), visitID: uuid(1), dishID: nil,
            kind: .visit, sortOrder: 0, updatedAt: date(2025, 8, 29),
            binaryDeletedAt: date(2025, 9, 1), deletedAt: nil
        )
        let report = analyze(input(visits: [visit(1, year: 2025)], photos: [photo]))
        #expect(report.memories[0].imageReference == .none)
    }

    @Test("11 Shanghai timezone evaluates local calendar day")
    func shanghaiTimezone() {
        let reference = iso("2026-08-29T00:30:00Z")
        let shanghaiOnly = visit(1, at: iso("2025-08-29T07:00:00Z"))
        let report = OnThisDayAnalyzer.analyze(
            input(visits: [shanghaiOnly]),
            context: OnThisDayContext(referenceDate: reference, calendar: shanghai)
        )
        #expect(report.memories.count == 1)
    }

    @Test("12 Los Angeles timezone evaluates the same instants differently")
    func losAngelesTimezone() {
        var losAngeles = shanghai
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let reference = iso("2026-08-29T00:30:00Z")
        let shanghaiOnly = visit(1, at: iso("2025-08-29T07:00:00Z"))
        let losAngelesMatch = visit(2, at: iso("2025-08-28T07:00:00Z"))
        let report = OnThisDayAnalyzer.analyze(
            input(visits: [shanghaiOnly, losAngelesMatch]),
            context: OnThisDayContext(referenceDate: reference, calendar: losAngeles)
        )
        #expect(report.memories.map(\.id) == [uuid(2)])
    }

    @Test("13 Feb 29 matches only a real historical Feb 29")
    func leapDay() {
        let reference = date(2028, 2, 29, 12)
        let exact = visit(1, at: date(2024, 2, 29, 19))
        let february28 = visit(2, at: date(2025, 2, 28, 19))
        let march1 = visit(3, at: date(2025, 3, 1, 19))
        let report = OnThisDayAnalyzer.analyze(
            input(visits: [february28, exact, march1]),
            context: OnThisDayContext(referenceDate: reference, calendar: shanghai)
        )
        #expect(report.memories.map(\.id) == [uuid(1)])
    }

    @Test("14 ordering is deterministic by year, visitedAt, then stable ID")
    func deterministicOrdering() {
        let first = visit(1, year: 2025, hour: 20)
        let tiedHighID = visit(9, year: 2025, hour: 12)
        let tiedLowID = visit(3, year: 2025, hour: 12)
        let older = visit(2, year: 2024, hour: 22)
        let expected = [uuid(1), uuid(3), uuid(9), uuid(2)]
        #expect(analyze(input(visits: [tiedHighID, older, first, tiedLowID])).memories.map(\.id) == expected)
        #expect(analyze(input(visits: [older, tiedLowID, first, tiedHighID])).memories.map(\.id) == expected)
    }

    @Test("15 10,000 Visit snapshot completes in a bounded time")
    func performance() {
        let visits = (0..<10_000).map { index in
            visit(10_000 + index, year: 2010 + index % 16, hour: index % 24)
        }
        let clock = ContinuousClock()
        let elapsed = clock.measure { _ = analyze(input(visits: visits)) }
        #expect(elapsed < .seconds(2))
        #expect(analyze(input(visits: visits)).memories.count == 10_000)
    }

    @Test("16 current-user isolation rejects another owner's Restaurant and Visit")
    func currentUserIsolation() {
        let restaurantA = restaurant(1, owner: ownerA)
        let restaurantB = restaurant(2, owner: ownerB)
        let own = visit(1, owner: ownerA, restaurantID: restaurantA.id, year: 2025)
        let other = visit(2, owner: ownerB, restaurantID: restaurantB.id, year: 2025)
        let report = analyze(input(restaurants: [restaurantA, restaurantB], visits: [other, own]))
        #expect(report.memories.map(\.id) == [own.id])
    }

    @Test("Global Restaurant identity keeps two Visit memories after canonicalization")
    func globalIdentityKeepsVisitEvents() {
        let descriptors = [1, 2].map { index in
            AnalysisRestaurantIdentity.Descriptor(
                localID: uuid(index), updatedAt: date(2026, 1, index), deletedAt: nil,
                tasteMapID: nil, remoteID: nil,
                appleMapItemIdentifier: "apple-global-same-place", placeIdentities: []
            )
        }
        let projection = AnalysisRestaurantIdentity.projection(descriptors)
        let canonical = projection.canonicalID(for: uuid(1))
        #expect(canonical == projection.canonicalID(for: uuid(2)))
        let record = OnThisDayInput.RestaurantRecord(
            id: canonical, ownerUserID: ownerA, name: "同一家餐厅", city: "杭州",
            updatedAt: date(2026, 1, 2), deletedAt: nil
        )
        let visits = [
            visit(1, restaurantID: canonical, year: 2025),
            visit(2, restaurantID: canonical, year: 2024),
        ]
        #expect(analyze(input(restaurants: [record], visits: visits)).memories.count == 2)
    }

    @Test("Dish, Companion, source and active Photo remain real card evidence")
    func cardEvidence() {
        let dish = OnThisDayInput.DishRecord(
            id: uuid(90), restaurantID: uuid(1), name: "龙井虾仁", sortOrder: 0,
            updatedAt: date(2025, 8, 29), deletedAt: nil
        )
        let link = OnThisDayInput.VisitDishRecord(
            visitID: uuid(1), dishID: dish.id, sortOrder: 0, deletedAt: nil
        )
        let photo = OnThisDayInput.PhotoRecord(
            id: uuid(91), restaurantID: uuid(1), visitID: uuid(1), dishID: nil,
            kind: .visit, sortOrder: 0, updatedAt: date(2025, 8, 29),
            binaryDeletedAt: nil, deletedAt: nil
        )
        let visit = visit(
            1, year: 2025, companions: ["小林"], source: "朋友推荐"
        )
        let report = analyze(input(
            visits: [visit], dishes: [dish], visitDishes: [link], photos: [photo]
        ))
        #expect(report.memories[0].dishNames == ["龙井虾仁"])
        #expect(report.memories[0].companions == ["小林"])
        #expect(report.memories[0].recommendationSource == "朋友推荐")
        #expect(report.memories[0].imageReference == .photo(photo.id))
    }

    private func analyze(_ input: OnThisDayInput) -> OnThisDayReport {
        OnThisDayAnalyzer.analyze(
            input,
            context: OnThisDayContext(referenceDate: date(2026, 8, 29, 12), calendar: shanghai)
        )
    }

    private func input(
        restaurants: [OnThisDayInput.RestaurantRecord]? = nil,
        visits: [OnThisDayInput.VisitRecord],
        dishes: [OnThisDayInput.DishRecord] = [],
        visitDishes: [OnThisDayInput.VisitDishRecord] = [],
        photos: [OnThisDayInput.PhotoRecord] = []
    ) -> OnThisDayInput {
        OnThisDayInput(
            currentUserID: ownerA,
            restaurants: restaurants ?? [restaurant(1, owner: ownerA)],
            visits: visits,
            dishes: dishes,
            visitDishes: visitDishes,
            photos: photos
        )
    }

    private func restaurant(
        _ id: Int,
        owner: String,
        deletedAt: Date? = nil
    ) -> OnThisDayInput.RestaurantRecord {
        OnThisDayInput.RestaurantRecord(
            id: uuid(id), ownerUserID: owner, name: "测试餐厅 \(id)", city: "杭州",
            updatedAt: date(2026, 1, 1), deletedAt: deletedAt
        )
    }

    private func visit(
        _ id: Int,
        owner: String? = nil,
        restaurantID: UUID? = nil,
        year: Int,
        hour: Int = 19,
        rating: Double? = 4.5,
        spend: Decimal? = 188,
        companions: [String] = [],
        source: String? = nil,
        deletedAt: Date? = nil
    ) -> OnThisDayInput.VisitRecord {
        visit(
            id,
            owner: owner,
            restaurantID: restaurantID,
            at: date(year, 8, 29, hour),
            rating: rating,
            spend: spend,
            companions: companions,
            source: source,
            deletedAt: deletedAt
        )
    }

    private func visit(
        _ id: Int,
        owner: String? = nil,
        restaurantID: UUID? = nil,
        at visitedAt: Date,
        rating: Double? = 4.5,
        spend: Decimal? = 188,
        companions: [String] = [],
        source: String? = nil,
        deletedAt: Date? = nil
    ) -> OnThisDayInput.VisitRecord {
        OnThisDayInput.VisitRecord(
            id: uuid(id), ownerUserID: owner ?? ownerA,
            restaurantID: restaurantID ?? uuid(1), visitedAt: visitedAt,
            rating: rating, note: "真实历史备注", myActualSpend: spend,
            companionNames: companions, recommendationSource: source,
            updatedAt: visitedAt, deletedAt: deletedAt
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        shanghai.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour
        ))!
    }

    private func iso(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}
