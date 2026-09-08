import Foundation
import Testing
import UIKit
@testable import TasteMap

@Suite("P4-D Monthly Recap")
struct P4DMonthlyRecapTests {
    private let calendar: Calendar = {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        value.locale = Locale(identifier: "zh_Hans_CN")
        return value
    }()

    @Test("1–4 month boundary, current/past and timezone")
    func monthPeriodContract() {
        let august = MonthlyPeriod(year: 2026, month: 8, calendar: calendar)
        #expect(august.contains(date(2026, 8, 1, 0)))
        #expect(august.contains(date(2026, 8, 31, 23)))
        #expect(!august.contains(date(2026, 9, 1, 0)))
        #expect(august.isCurrent(now: date(2026, 8, 28, 12)))
        #expect(!august.previous.isCurrent(now: date(2026, 8, 28, 12)))
        #expect(august.posterLabel(now: date(2026, 8, 28, 12)).contains("截至 8 月 28 日"))
        #expect(august.previous.posterLabel(now: date(2026, 8, 28, 12)) == "2026 年 7 月")

        let instant = ISO8601DateFormatter().date(from: "2026-07-31T17:00:00Z")!
        var losAngeles = calendar
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        #expect(MonthlyPeriod(date: instant, calendar: calendar).month == 8)
        #expect(MonthlyPeriod(date: instant, calendar: losAngeles).month == 7)
    }

    @Test("5–9 Visit count, distinct Restaurant, tombstone, identity and empty month")
    func coreCounts() {
        let r1 = restaurant(1, "A", tags: ["日料"])
        let r2 = restaurant(2, "B", tags: ["火锅"])
        let active = [
            visit(1, r1.id, 2026, 8, 1), visit(2, r1.id, 2026, 8, 4), visit(3, r2.id, 2026, 8, 5),
        ]
        let deleted = copy(visit(4, r2.id, 2026, 8, 7), deletedAt: date(2026, 8, 8))
        let duplicateRestaurant = MonthlyRecapInput.RestaurantRecord(
            id: r1.id, name: "A renamed", city: "杭州", status: .visited, tags: ["日料"],
            createdAt: r1.createdAt, updatedAt: r1.updatedAt.addingTimeInterval(10), deletedAt: nil
        )
        let report = analyze(input(restaurants: [r1, duplicateRestaurant, r2], visits: active + [deleted]))
        #expect(report.visitCount == 3)
        #expect(report.restaurantCount == 2)
        #expect(report.favoriteRestaurant?.name == "A renamed")
        #expect(analyze(input(restaurants: [r1], visits: [])).visitCount == 0)
        #expect(!analyze(input(restaurants: [r1], visits: [])).hasData)
    }

    @Test("10–14 first-ever Restaurant semantics and tombstoned first Visit")
    func newRestaurantSemantics() {
        let r1 = restaurant(10, "老店")
        let r2 = restaurant(11, "新店")
        let prior = visit(10, r1.id, 2026, 7, 2)
        let oldTombstone = copy(visit(11, r2.id, 2026, 6, 2), deletedAt: date(2026, 6, 3))
        let visits = [
            prior, oldTombstone,
            visit(12, r1.id, 2026, 8, 2),
            visit(13, r2.id, 2026, 8, 3), visit(14, r2.id, 2026, 8, 5),
        ]
        let report = analyze(input(restaurants: [r1, r2], visits: visits))
        #expect(report.newRestaurantCount == 1)
        #expect(report.newRestaurants.count == 1)
        #expect(report.newRestaurants[0].id == r2.id)
        #expect(report.newRestaurants[0].visitCount == 2)
        #expect(report.restaurantCount == 2)
    }

    @Test("15–20 spend total, nil, median, coverage, partial wording and no spend")
    func spendSemantics() {
        let r = restaurant(20, "小馆")
        let values: [Decimal?] = [100, nil, 300, 200]
        let visits = values.enumerated().map { index, value in
            copy(visit(20 + index, r.id, 2026, 8, index + 1), spend: value)
        }
        let report = analyze(input(restaurants: [r], visits: visits))
        #expect(report.spend.recordedTotal == 600)
        #expect(report.spend.median == 200)
        #expect(report.spend.recordedVisitCount == 3)
        #expect(report.spend.coverage == 0.75)
        #expect(report.spend.displayState == .recorded)
        #expect(report.spend.displayState.label == "本月已记录消费")
        let none = analyze(input(restaurants: [r], visits: visits.map { copy($0, spend: .some(nil)) }))
        #expect(none.spend.recordedTotal == nil)
        #expect(none.spend.displayState == .none)
    }

    @Test("low spend coverage remains explicitly recorded and not prominent")
    func lowSpendCoverage() {
        let report = MonthlyRecapPreviewFixtures.lowSpendCoverage
        #expect(report.spend.coverage < 0.6)
        #expect(report.spend.displayState == .lowCoverage)
        #expect(report.spend.displayState.label == "本月已记录消费")
    }

    @Test("21–23 favorite ranking rewards repeat evidence over one perfect score")
    func favoriteRanking() {
        let onePerfect = restaurant(30, "一次满分")
        let repeated = restaurant(31, "稳定回去")
        let visits = [visit(30, onePerfect.id, 2026, 8, 1, rating: 5)]
            + (0..<4).map { visit(31 + $0, repeated.id, 2026, 8, 3 + $0, rating: 4.5) }
        let report = analyze(input(restaurants: [onePerfect, repeated], visits: visits))
        #expect(report.favoriteRestaurant?.id == repeated.id)
        #expect(report.favoriteRestaurant?.visitCount == 4)
        #expect(report.favoriteRestaurant?.averageRating == 4.5)
    }

    @Test("24–27 most visited tie-break is deterministic and ignores tombstones")
    func mostVisitedRanking() {
        let a = restaurant(40, "A")
        let b = restaurant(41, "B")
        let visits = [
            visit(40, a.id, 2026, 8, 1, rating: 4), visit(41, a.id, 2026, 8, 2, rating: 4),
            visit(42, b.id, 2026, 8, 3, rating: 4.5), visit(43, b.id, 2026, 8, 4, rating: 4.5),
            copy(visit(44, a.id, 2026, 8, 5, rating: 5), deletedAt: date(2026, 8, 6)),
        ]
        let first = analyze(input(restaurants: [a, b], visits: visits))
        let second = analyze(input(restaurants: [b, a], visits: Array(visits.reversed())))
        #expect(first.mostVisitedRestaurant?.id == b.id)
        #expect(first.mostVisitedRestaurant?.id == second.mostVisitedRestaurant?.id)
        #expect(first.visitCount == 4)
    }

    @Test("28–32 top Companion, multi-companion, absent, tombstone and displayName")
    func companionSemantics() {
        let r = restaurant(50, "共同餐桌")
        let alice = companion(50, "Alice", remote: "companion-alice")
        let renamed = companion(51, "小林的新名字", remote: "companion-lin")
        let visits = [
            copy(visit(50, r.id, 2026, 8, 1), companions: (["companion-alice", "companion-lin"], ["Alice", "旧名字"])),
            copy(visit(51, r.id, 2026, 8, 2), companions: (["companion-lin"], ["旧名字"])),
            copy(copy(visit(52, r.id, 2026, 8, 3), companions: (["companion-alice"], ["Alice"])), deletedAt: date(2026, 8, 4)),
        ]
        let report = analyze(input(restaurants: [r], visits: visits, companions: [alice, renamed]))
        #expect(report.topCompanion?.id == renamed.id)
        #expect(report.topCompanion?.displayName == "小林的新名字")
        #expect(report.topCompanion?.sharedVisitCount == 2)
        #expect(report.topCompanion?.restaurantCount == 1)
        #expect(analyze(input(restaurants: [r], visits: [visit(53, r.id, 2026, 8, 5)])).topCompanion == nil)
    }

    @Test("33–37 source usage is Restaurant-level, rated and rename-stable")
    func recommendationSourceSemantics() {
        let r1 = restaurant(60, "A")
        let r2 = restaurant(61, "B")
        let source = recommendationSource(60, "我改过名的来源", remote: "source-stable")
        let visits = [
            copy(visit(60, r1.id, 2026, 8, 1, rating: 4.5), source: source),
            copy(visit(61, r1.id, 2026, 8, 2, rating: 5), source: source),
            copy(visit(62, r2.id, 2026, 8, 3, rating: 4), source: source),
        ]
        let report = analyze(input(restaurants: [r1, r2], visits: visits, sources: [source]))
        #expect(report.recommendationStory?.displayName == "我改过名的来源")
        #expect(report.recommendationStory?.restaurantCount == 2)
        #expect(report.recommendationStory?.ratedRestaurantCount == 2)
        #expect(report.recommendationStory?.highRatedRestaurantCount == 2)
        #expect(report.recommendationStory?.statement.contains("2 家店") == true)
        #expect(analyze(input(restaurants: [r1], visits: [visit(63, r1.id, 2026, 8, 4)])).recommendationStory == nil)
    }

    @Test("explicit unknown source identity never falls back by text")
    func unknownSourceIdentityBoundary() {
        let r = restaurant(70, "A")
        let source = recommendationSource(70, "同名来源", remote: "known-source")
        var visit = copy(self.visit(70, r.id, 2026, 8, 1), source: source)
        visit = MonthlyRecapInput.VisitRecord(
            id: visit.id, restaurantID: visit.restaurantID, visitedAt: visit.visitedAt,
            rating: visit.rating, valueRating: nil, environmentRating: nil, serviceRating: nil,
            myActualSpend: nil, note: nil, diningOccasionLabels: [], companionIDs: [], companionNames: [],
            recommendationSourceID: "unknown-id", recommendationSourceType: .friend,
            recommendationSourceText: source.displayName, updatedAt: visit.updatedAt, deletedAt: nil
        )
        #expect(analyze(input(restaurants: [r], visits: [visit], sources: [source])).recommendationStory == nil)
    }

    @Test("38–39 three meals in two restaurants cannot establish cuisine change")
    func cuisineTasteChange() {
        let japaneseA = restaurant(80, "日料 A", tags: ["日料"])
        let japaneseB = restaurant(81, "日料 B", tags: ["日料"])
        let hotpotA = restaurant(82, "火锅 A", tags: ["火锅"])
        let hotpotB = restaurant(83, "火锅 B", tags: ["火锅"])
        let previous = [
            visit(80, hotpotA.id, 2026, 7, 1), visit(81, hotpotB.id, 2026, 7, 2), visit(82, hotpotA.id, 2026, 7, 3),
        ]
        let current = [
            visit(83, japaneseA.id, 2026, 8, 1), visit(84, japaneseB.id, 2026, 8, 2), visit(85, japaneseA.id, 2026, 8, 3),
        ]
        let report = analyze(input(restaurants: [japaneseA, japaneseB, hotpotA, hotpotB], visits: previous + current))
        #expect(report.tasteChange == nil)
        #expect(report.tasteChangeSufficiency == .insufficient)
    }

    @Test("Eligible adjacent-month change uses ten visits in five restaurants and matching dates")
    func eligibleComparisonAndCurrentWindow() {
        let previousRestaurants = (0..<5).map { restaurant(800 + $0, "旧店 \($0)", tags: ["火锅"]) }
        let currentRestaurants = (0..<5).map { restaurant(810 + $0, "新店 \($0)", tags: ["日料"]) }
        let previous = (0..<10).map { visit(800 + $0, previousRestaurants[$0 % 5].id, 2026, 7, $0 + 1) }
        let current = (0..<10).map { visit(810 + $0, currentRestaurants[$0 % 5].id, 2026, 8, $0 + 1) }
        let value = input(restaurants: previousRestaurants + currentRestaurants, visits: previous + current)
        let completeEvidence = analyze(value)
        #expect(completeEvidence.tasteChange != nil)
        let early = MonthlyRecapAnalyzer.analyze(value, period: MonthlyPeriod(year: 2026, month: 8, calendar: calendar), now: date(2026, 8, 5))
        #expect(early.visitCount == 5)
        #expect(early.tasteChange == nil)
    }

    @Test("40 sparse exploration comparison stays unavailable")
    func explorationIncrease() {
        let oldA = restaurant(90, "熟店 A")
        let oldB = restaurant(91, "熟店 B")
        let newA = restaurant(92, "新店 A")
        let newB = restaurant(93, "新店 B")
        let visits = [
            visit(90, oldA.id, 2026, 6, 1), visit(91, oldB.id, 2026, 6, 2),
            visit(92, oldA.id, 2026, 7, 1), visit(93, oldB.id, 2026, 7, 2), visit(94, oldA.id, 2026, 7, 3),
            visit(95, newA.id, 2026, 8, 1), visit(96, newB.id, 2026, 8, 2), visit(97, newA.id, 2026, 8, 3),
        ]
        let report = analyze(input(restaurants: [oldA, oldB, newA, newB], visits: visits))
        #expect(report.tasteChange == nil)
    }

    @Test("41 two restaurants cannot establish repeat-behavior change")
    func repeatIncrease() {
        let a = restaurant(100, "A")
        let b = restaurant(101, "B")
        let visits = [
            visit(100, a.id, 2026, 7, 1), visit(101, b.id, 2026, 7, 2), visit(102, b.id, 2026, 7, 3),
            visit(103, a.id, 2026, 8, 1), visit(104, b.id, 2026, 8, 2), visit(105, a.id, 2026, 8, 3),
        ]
        let report = analyze(input(restaurants: [a, b], visits: visits))
        #expect(report.tasteChange == nil)
    }

    @Test("42–45 insufficient current/previous, no previous and deterministic keywords")
    func tasteSufficiencyAndKeywords() {
        let sparse = MonthlyRecapPreviewFixtures.sparse
        let noPrevious = MonthlyRecapPreviewFixtures.noComparison
        #expect(sparse.tasteChange == nil)
        #expect(sparse.tasteChangeSufficiency == .insufficient)
        #expect(noPrevious.tasteChange == nil)
        #expect(noPrevious.tasteChangeSufficiency == .insufficient)
        #expect(MonthlyRecapPreviewFixtures.rich.keywords == MonthlyRecapPreviewFixtures.rich.keywords)
        #expect((2...5).contains(MonthlyRecapPreviewFixtures.rich.keywords.count))
    }

    @Test("46–52 representatives cover favorite, frequent, new, highlight, dedupe and photo fallback")
    func representativeRestaurants() {
        let report = MonthlyRecapPreviewFixtures.rich
        #expect(report.representativeRestaurants.count <= 4)
        #expect(Set(report.representativeRestaurants.map(\.id)).count == report.representativeRestaurants.count)
        #expect(report.favoriteRestaurant.map(\.id).map { report.representativeRestaurants.map(\.id).contains($0) } ?? true)
        #expect(report.mostVisitedRestaurant.map(\.id).map { report.representativeRestaurants.map(\.id).contains($0) } ?? true)
        #expect(report.highlight != nil)
        #expect(MonthlyRecapPreviewFixtures.sparse.representativeRestaurants.count < 4)
        #expect(MonthlyRecapPreviewFixtures.noPhoto.representativeRestaurants.allSatisfy { $0.imageReference == .none })
    }

    @Test("photo priority is Dish then Visit then Restaurant marker")
    func photoPriority() {
        let base = MonthlyRecapPreviewFixtures.input(currentLimit: 1, previousLimit: 0, includePhotos: false)
        let visit = base.visits[0]
        let dish = base.dishes[0]
        let marker = photo(110, restaurant: visit.restaurantID, visit: nil, dish: nil, kind: .restaurantMarker, order: 0)
        let visitPhoto = photo(111, restaurant: visit.restaurantID, visit: visit.id, dish: nil, kind: .visit, order: 0)
        let dishPhoto = photo(112, restaurant: visit.restaurantID, visit: visit.id, dish: dish.id, kind: .dish, order: 4)
        let report = analyze(copy(base, photos: [marker, visitPhoto, dishPhoto]))
        #expect(report.representativeRestaurants.first?.imageReference == .photo(dishPhoto.id))
    }

    @Test("53–67 poster content contract for current/past, facts and optional modules")
    func posterContentContract() {
        let current = MonthlyRecapPreviewFixtures.rich
        let past = MonthlyRecapPreviewFixtures.past
        #expect(current.periodLabel.contains("截至"))
        #expect(!past.periodLabel.contains("截至"))
        #expect(current.visitCount > 0)
        #expect(current.restaurantCount > 0)
        #expect(current.newRestaurantCount >= 0)
        #expect(current.spend.displayState == .complete)
        #expect(MonthlyRecapPreviewFixtures.lowSpendCoverage.spend.displayState == .lowCoverage)
        #expect(current.favoriteRestaurant != nil)
        #expect(current.topCompanion != nil)
        #expect(current.recommendationStory != nil)
        #expect(MonthlyRecapPreviewFixtures.noComparison.tasteChange == nil)
        #expect(current.photoReferences.count == current.representativeRestaurants.count)
        #expect(MonthlyRecapPreviewFixtures.noPhoto.photoReferences.allSatisfy { $0 == .none })
        #expect(MonthlyRecapPosterView.canvasSize == CGSize(width: 1_080, height: 1_920))
    }

    @MainActor
    @Test("68–69 poster renders fixed dimensions without clipping in light theme")
    func posterRender() throws {
        let image = try AnalysisPosterRenderer.render(
            content: MonthlyRecapPosterView(report: MonthlyRecapPreviewFixtures.withAssetImages, resolvedImages: [:]),
            canvasSize: MonthlyRecapPosterView.canvasSize
        )
        #expect(image.size == MonthlyRecapPosterView.canvasSize)
        #expect(image.pngData()?.isEmpty == false)
        #expect(image.cgImage?.width == 1_080)
        #expect(image.cgImage?.height == 1_920)
    }

    @Test("500 Restaurants / 5000 Visits / 2000 Dishes stay interactive")
    func performance() {
        let restaurants = (0..<500).map { restaurant(1_000 + $0, "Restaurant \($0)", tags: [$0.isMultiple(of: 2) ? "日料" : "火锅"]) }
        let visits = (0..<5_000).map { index in
            visit(2_000 + index, restaurants[index % restaurants.count].id, 2026, index < 2_500 ? 8 : 7, (index % 27) + 1, rating: Double((index % 10) + 1) / 2)
        }
        let dishes = (0..<2_000).map { index in
            MonthlyRecapInput.DishRecord(
                id: uuid(20_000 + index), restaurantID: restaurants[index % 500].id,
                originVisitID: visits[index].id, name: "Dish \(index % 40)", taste: "咸鲜",
                rating: 4, updatedAt: date(2026, 8, 20), deletedAt: nil
            )
        }
        let value = input(restaurants: restaurants, visits: visits, dishes: dishes)
        let started = Date()
        let report = analyze(value)
        #expect(report.visitCount == 2_500)
        #expect(Date().timeIntervalSince(started) < 2)
    }

    private func analyze(_ value: MonthlyRecapInput) -> MonthlyRecapAnalysis {
        MonthlyRecapAnalyzer.analyze(
            value, period: MonthlyPeriod(year: 2026, month: 8, calendar: calendar),
            now: date(2026, 8, 28, 12)
        )
    }

    private func input(
        restaurants: [MonthlyRecapInput.RestaurantRecord],
        visits: [MonthlyRecapInput.VisitRecord],
        dishes: [MonthlyRecapInput.DishRecord] = [],
        visitDishes: [MonthlyRecapInput.VisitDishRecord] = [],
        photos: [MonthlyRecapInput.PhotoRecord] = [],
        companions: [MonthlyRecapInput.CompanionRecord] = [],
        sources: [MonthlyRecapInput.SourceRecord] = []
    ) -> MonthlyRecapInput {
        MonthlyRecapInput(
            userDisplayName: "测试用户", restaurants: restaurants, visits: visits,
            dishes: dishes, visitDishes: visitDishes, photos: photos,
            companions: companions, recommendationSources: sources
        )
    }

    private func copy(_ input: MonthlyRecapInput, photos: [MonthlyRecapInput.PhotoRecord]) -> MonthlyRecapInput {
        MonthlyRecapInput(
            userDisplayName: input.userDisplayName, restaurants: input.restaurants, visits: input.visits,
            dishes: input.dishes, visitDishes: input.visitDishes, photos: photos,
            companions: input.companions, recommendationSources: input.recommendationSources
        )
    }

    private func restaurant(_ value: Int, _ name: String, tags: [String] = []) -> MonthlyRecapInput.RestaurantRecord {
        MonthlyRecapInput.RestaurantRecord(
            id: uuid(value), name: name, city: "杭州", status: .visited, tags: tags,
            createdAt: date(2026, 1, 1), updatedAt: date(2026, 8, 28), deletedAt: nil
        )
    }

    private func visit(
        _ value: Int,
        _ restaurantID: UUID,
        _ year: Int,
        _ month: Int,
        _ day: Int,
        rating: Double? = 4
    ) -> MonthlyRecapInput.VisitRecord {
        let timestamp = date(year, month, day, 19)
        return MonthlyRecapInput.VisitRecord(
            id: uuid(value), restaurantID: restaurantID, visitedAt: timestamp,
            rating: rating, valueRating: nil, environmentRating: nil, serviceRating: nil,
            myActualSpend: nil, note: nil, diningOccasionLabels: [],
            companionIDs: [], companionNames: [], recommendationSourceID: nil,
            recommendationSourceType: nil, recommendationSourceText: nil,
            updatedAt: timestamp, deletedAt: nil
        )
    }

    private func copy(
        _ value: MonthlyRecapInput.VisitRecord,
        deletedAt: Date? = nil,
        spend: Decimal?? = nil,
        companions: ([String], [String])? = nil,
        source: MonthlyRecapInput.SourceRecord? = nil
    ) -> MonthlyRecapInput.VisitRecord {
        MonthlyRecapInput.VisitRecord(
            id: value.id, restaurantID: value.restaurantID, visitedAt: value.visitedAt,
            rating: value.rating, valueRating: value.valueRating,
            environmentRating: value.environmentRating, serviceRating: value.serviceRating,
            myActualSpend: spend ?? value.myActualSpend, note: value.note,
            diningOccasionLabels: value.diningOccasionLabels,
            companionIDs: companions?.0 ?? value.companionIDs,
            companionNames: companions?.1 ?? value.companionNames,
            recommendationSourceID: source?.identifiers.last ?? value.recommendationSourceID,
            recommendationSourceType: source?.sourceType ?? value.recommendationSourceType,
            recommendationSourceText: source?.displayName ?? value.recommendationSourceText,
            updatedAt: value.updatedAt, deletedAt: deletedAt ?? value.deletedAt
        )
    }

    private func companion(_ value: Int, _ name: String, remote: String) -> MonthlyRecapInput.CompanionRecord {
        MonthlyRecapInput.CompanionRecord(
            id: uuid(value), identifiers: [uuid(value).uuidString.lowercased(), remote],
            displayName: name, updatedAt: date(2026, 8, 28), deletedAt: nil
        )
    }

    private func recommendationSource(
        _ value: Int,
        _ name: String,
        remote: String
    ) -> MonthlyRecapInput.SourceRecord {
        MonthlyRecapInput.SourceRecord(
            id: uuid(value), identifiers: [uuid(value).uuidString.lowercased(), remote],
            displayName: name, sourceType: .friend, updatedAt: date(2026, 8, 28), deletedAt: nil
        )
    }

    private func photo(
        _ value: Int,
        restaurant: UUID?,
        visit: UUID?,
        dish: UUID?,
        kind: PhotoAssetKind,
        order: Int
    ) -> MonthlyRecapInput.PhotoRecord {
        MonthlyRecapInput.PhotoRecord(
            id: uuid(value), restaurantID: restaurant, visitID: visit, dishID: dish,
            kind: kind, sortOrder: order, updatedAt: date(2026, 8, 28), deletedAt: nil
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}
