import SwiftUI
import XCTest
@testable import TasteMap

final class P4EAnnualRecapTests: XCTestCase {
    private let calendar: Calendar = {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        value.locale = Locale(identifier: "zh_Hans_CN")
        return value
    }()

    func testAnnualPeriodBoundariesCurrentPastAndLabels() {
        let now = date(2026, 8, 28)
        let current = AnnualPeriod(year: 2026, calendar: calendar)
        XCTAssertEqual(current.start, date(2026, 1, 1, hour: 0))
        XCTAssertEqual(current.end, date(2027, 1, 1, hour: 0))
        XCTAssertTrue(current.contains(current.start))
        XCTAssertFalse(current.contains(current.end))
        XCTAssertTrue(current.isCurrent(now: now))
        XCTAssertEqual(current.posterLabel(now: now), "2026 · 截至 8 月 28 日")
        XCTAssertEqual(current.previous.posterLabel(now: now), "2025 年度回顾")
        XCTAssertEqual(current.next.previous, current)
    }

    func testTimezoneBoundaryUsesOneCalendarRule() {
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let instant = ISO8601DateFormatter().date(from: "2025-12-31T16:30:00Z")!
        XCTAssertTrue(AnnualPeriod(year: 2026, calendar: calendar).contains(instant))
        XCTAssertFalse(AnnualPeriod(year: 2026, calendar: losAngeles).contains(instant))
    }

    func testCoreCountsDistinctIdentityTombstoneAndEmptyYear() {
        let base = AnnualRecapPreviewFixtures.input(visitLimit: 5)
        let first = base.visits.first!
        let tombstone = copy(first, id: uuid(51_001), deletedAt: date(2026, 5, 1))
        let duplicateRestaurantVisit = copy(first, id: uuid(51_002), deletedAt: nil)
        let input = replacing(base, visits: base.visits + [tombstone, duplicateRestaurantVisit])
        let report = analyze(input)
        XCTAssertEqual(report.visitCount, 6)
        XCTAssertEqual(report.restaurantCount, Set((base.visits.prefix(5) + [duplicateRestaurantVisit]).map(\.restaurantID)).count)
        XCTAssertEqual(report.kind, .annualReview)
        let empty = analyze(replacing(base, visits: base.visits.filter { $0.visitedAt < AnnualPeriod(year: 2026, calendar: calendar).start }))
        XCTAssertFalse(empty.hasData)
        XCTAssertEqual(empty.restaurantCount, 0)
    }

    func testNewRestaurantsFirstEverMultipleVisitsTombstoneAndExplorationRate() {
        let newInput = AnnualRecapPreviewFixtures.input(addPriorVisits: false)
        let newReport = analyze(newInput)
        XCTAssertEqual(newReport.newRestaurantCount, newReport.restaurantCount)
        XCTAssertEqual(newReport.explorationRate, 1, accuracy: 0.0001)

        let priorInput = AnnualRecapPreviewFixtures.input(addPriorVisits: true)
        let priorReport = analyze(priorInput)
        XCTAssertLessThan(priorReport.newRestaurantCount, priorReport.restaurantCount)
        XCTAssertEqual(priorReport.newRestaurantCount, 8)

        let firstCurrent = priorInput.visits.first { AnnualPeriod(year: 2026, calendar: calendar).contains($0.visitedAt) }!
        let tombstonedPrior = copy(
            firstCurrent, id: uuid(51_100),
            visitedAt: date(2025, 3, 2), deletedAt: date(2025, 3, 3)
        )
        let noActivePriorForRestaurant = replacing(
            priorInput,
            visits: priorInput.visits.filter {
                !($0.restaurantID == firstCurrent.restaurantID && $0.visitedAt < AnnualPeriod(year: 2026, calendar: calendar).start)
            } + [tombstonedPrior]
        )
        XCTAssertTrue(analyze(noActivePriorForRestaurant).representativeRestaurants.contains {
            $0.id == firstCurrent.restaurantID && $0.isNew
        })
    }

    func testSpendTotalNilMedianMonthlyDistributionCoverageAndLowState() {
        let report = analyze(AnnualRecapPreviewFixtures.input(visitLimit: 6))
        XCTAssertEqual(report.spend.recordedVisitCount, 6)
        XCTAssertEqual(report.spend.coverage, 1, accuracy: 0.0001)
        XCTAssertEqual(report.spend.displayState, .complete)
        XCTAssertNotNil(report.spend.recordedTotal)
        XCTAssertNotNil(report.spend.median)
        XCTAssertEqual(report.spend.monthlyDistribution.count, 12)
        XCTAssertEqual(report.spend.monthlyDistribution.reduce(0) { $0 + $1.recordedVisitCount }, 6)

        let low = analyze(AnnualRecapPreviewFixtures.input(visitLimit: 10, spendMode: .lowCoverage))
        XCTAssertEqual(low.spend.recordedVisitCount, 3)
        XCTAssertEqual(low.spend.coverage, 0.3, accuracy: 0.0001)
        XCTAssertEqual(low.spend.displayState, .lowCoverage)
        XCTAssertEqual(low.spend.displayState.label, "全年已记录消费")
    }

    func testFavoriteUsesRatingRepeatAndSampleWhileMostVisitedIsStable() {
        let report = analyze(AnnualRecapPreviewFixtures.input())
        XCTAssertEqual(report.favoriteRestaurant?.id, uuid(9_100))
        XCTAssertEqual(report.mostVisitedRestaurant?.id, uuid(9_100))
        XCTAssertGreaterThan(report.favoriteRestaurant?.visitCount ?? 0, 1)
        XCTAssertEqual(report.favoriteRestaurant, analyze(AnnualRecapPreviewFixtures.input()).favoriteRestaurant)
    }

    func testFavoriteCanPreferRepeatedFourPointFiveOverSingleFive() {
        let restaurants = [restaurant(52_001, "稳定喜欢"), restaurant(52_002, "单次满分")]
        let repeated = (0..<6).map { index in visit(52_100 + index, restaurantID: restaurants[0].id, month: 1 + index, rating: 4.5) }
        let single = visit(52_200, restaurantID: restaurants[1].id, month: 8, rating: 5)
        let report = analyze(input(restaurants: restaurants, visits: repeated + [single]))
        XCTAssertEqual(report.favoriteRestaurant?.id, restaurants[0].id)
        XCTAssertEqual(report.mostVisitedRestaurant?.id, restaurants[0].id)
    }

    func testFavoriteAndMostVisitedIgnoreTombstonesAndUseStableTieBreak() {
        let restaurants = [restaurant(52_301, "A"), restaurant(52_302, "B")]
        let commonDate = date(2026, 6, 6)
        let visits = [
            visit(52_401, restaurantID: restaurants[0].id, at: commonDate, rating: 4),
            visit(52_402, restaurantID: restaurants[1].id, at: commonDate, rating: 4),
            copy(visit(52_403, restaurantID: restaurants[1].id, at: commonDate, rating: 5), deletedAt: commonDate),
        ]
        let report = analyze(input(restaurants: restaurants, visits: visits))
        XCTAssertEqual(report.mostVisitedRestaurant?.id, restaurants[0].id)
        XCTAssertEqual(report.favoriteRestaurant?.id, restaurants[0].id)
    }

    func testAnnualCompanionCountRestaurantsMultiCompanionNoCompanionAndDisplayName() {
        let rich = analyze(AnnualRecapPreviewFixtures.input(includeCompanions: true))
        XCTAssertEqual(rich.topCompanion?.displayName, "小林")
        XCTAssertGreaterThan(rich.topCompanion?.sharedVisitCount ?? 0, rich.topCompanion?.restaurantCount ?? 0)
        XCTAssertNotNil(rich.topCompanion?.representativeRestaurant)
        let none = analyze(AnnualRecapPreviewFixtures.input(includeCompanions: false))
        XCTAssertNil(none.topCompanion)
    }

    func testAnnualSourceUsageBestWorstThresholdDistinctRestaurantAndRenameStability() {
        let sourceInput = AnnualRecapPreviewFixtures.input()
        let report = analyze(sourceInput)
        XCTAssertEqual(report.recommendationSummary.usedSourceCount, 2)
        XCTAssertEqual(report.recommendationSummary.attributedRestaurantCount, 12)
        XCTAssertEqual(report.recommendationSummary.best?.displayName, "小林的年度私藏")
        XCTAssertEqual(report.recommendationSummary.worst?.title, "年度最坑推荐来源")
        XCTAssertEqual(report.recommendationSummary.worst?.displayName, "深夜踩坑收藏夹")
        XCTAssertEqual(report.recommendationSummary.rankingSufficiency, .established)

        let renamedSources = sourceInput.recommendationSources.map { source in
            MonthlyRecapInput.SourceRecord(
                id: source.id, identifiers: source.identifiers,
                displayName: source.id == uuid(9_011) ? "小林新版清单" : source.displayName,
                sourceType: source.sourceType, updatedAt: source.updatedAt.addingTimeInterval(10), deletedAt: nil
            )
        }
        XCTAssertEqual(analyze(replacing(sourceInput, sources: renamedSources)).recommendationSummary.best?.displayName, "小林新版清单")
    }

    func testAnnualSourceInsufficientDataDoesNotInventBestOrWorst() {
        let report = analyze(AnnualRecapPreviewFixtures.input(sourceRestaurantLimit: 4))
        XCTAssertNotNil(report.recommendationSummary.mostUsed)
        XCTAssertNil(report.recommendationSummary.best)
        XCTAssertNil(report.recommendationSummary.worst)
        XCTAssertNotEqual(report.recommendationSummary.rankingSufficiency, .established)
    }

    func testTasteJourneyUsesMonthlyGroupingAndDeterministicMilestonesWithGaps() {
        let report = analyze(AnnualRecapPreviewFixtures.input())
        XCTAssertEqual(report.tasteJourney.granularity, .monthly)
        XCTAssertGreaterThanOrEqual(report.tasteJourney.milestones.count, 3)
        XCTAssertLessThanOrEqual(report.tasteJourney.milestones.count, 5)
        XCTAssertEqual(report.monthlySnapshots.count, 12)
        XCTAssertEqual(report.monthlySnapshots.suffix(4).map(\.visitCount), [0, 0, 0, 0])
        XCTAssertEqual(report.tasteJourney, analyze(AnnualRecapPreviewFixtures.input()).tasteJourney)
    }

    func testTasteJourneyFallsBackToQuarterlyAndSuppressesInsufficientYear() {
        let quarterly = analyze(AnnualRecapPreviewFixtures.input(visitLimit: 8))
        XCTAssertEqual(quarterly.tasteJourney.granularity, .quarterly)
        XCTAssertFalse(quarterly.tasteJourney.milestones.isEmpty)
        let sparse = analyze(AnnualRecapPreviewFixtures.input(visitLimit: 3))
        XCTAssertEqual(sparse.tasteJourney.granularity, .insufficient)
        XCTAssertTrue(sparse.tasteJourney.milestones.isEmpty)
        XCTAssertTrue(sparse.tasteJourney.changeSummaries.isEmpty)
    }

    func testTasteJourneyFindsCuisineExplorationRepeatAndContextChangesOnlyWithEvidence() {
        let report = analyze(AnnualRecapPreviewFixtures.input())
        XCTAssertTrue(report.tasteJourney.milestones.contains { $0.title.contains("日料") || $0.title.contains("火锅") || $0.visitCount > 0 })
        XCTAssertTrue(report.tasteJourney.changeSummaries.count <= 3)
        XCTAssertFalse(report.tasteJourney.changeSummaries.contains { $0.contains("转型") })
        XCTAssertTrue(report.tasteJourney.changeSummaries.allSatisfy { !$0.isEmpty })
    }

    func testAnnualKeywordsCoverFactsAndSemanticDedupe() {
        let report = analyze(AnnualRecapPreviewFixtures.input())
        XCTAssertGreaterThanOrEqual(report.keywords.count, 3)
        XCTAssertLessThanOrEqual(report.keywords.count, 6)
        let normalized = report.keywords.map { $0.lowercased().replacingOccurrences(of: " ", with: "") }
        XCTAssertEqual(Set(normalized).count, normalized.count)
        XCTAssertTrue(report.keywords.contains("日料") || report.keywords.contains("朋友聚餐") || report.keywords.contains("探新店"))
        XCTAssertTrue(analyze(AnnualRecapPreviewFixtures.input(includeCompanions: true)).keywords.contains { $0.contains("小林") })
        XCTAssertTrue(analyze(AnnualRecapPreviewFixtures.input(visitLimit: 0)).keywords.isEmpty)
    }

    func testMonthlyHighlightsUseOnlyFactualDistinctMonths() {
        let report = analyze(AnnualRecapPreviewFixtures.input())
        XCTAssertLessThanOrEqual(report.monthlyHighlights.count, 3)
        XCTAssertEqual(Set(report.monthlyHighlights.map(\.month)).count, report.monthlyHighlights.count)
        XCTAssertTrue(report.monthlyHighlights.contains { $0.kind == .busiest })
    }

    func testRepresentativeRestaurantsIncludeRolesDedupeSparseAndPhotoPriority() {
        let input = AnnualRecapPreviewFixtures.input()
        let report = analyze(input)
        XCTAssertGreaterThanOrEqual(report.representativeRestaurants.count, 3)
        XCTAssertLessThanOrEqual(report.representativeRestaurants.count, 6)
        XCTAssertEqual(Set(report.representativeRestaurants.map(\.id)).count, report.representativeRestaurants.count)
        XCTAssertTrue(report.representativeRestaurants.contains { $0.role == "年度最喜欢" })
        XCTAssertTrue(report.representativeRestaurants.contains { $0.role.contains("年度新店") || $0.role.contains("味觉节点") })
        XCTAssertTrue(report.representativeRestaurants.contains { if case .photo = $0.imageReference { true } else { false } })
        let sparse = analyze(AnnualRecapPreviewFixtures.input(visitLimit: 1, includePhotos: false))
        XCTAssertEqual(sparse.representativeRestaurants.count, 1)
        XCTAssertEqual(sparse.representativeRestaurants.first?.imageReference, AnalysisImageReference.none)
    }

    @MainActor
    func testPosterCurrentPastContentFixedSizeLightThemeAndP4RendererReuse() throws {
        let current = AnnualRecapPreviewFixtures.withAssetImages
        XCTAssertEqual(current.periodLabel, "2026 · 截至 8 月 28 日")
        XCTAssertEqual(AnnualRecapPreviewFixtures.past.periodLabel, "2025 年度回顾")
        XCTAssertGreaterThan(current.visitCount, 0)
        XCTAssertGreaterThan(current.restaurantCount, 0)
        XCTAssertGreaterThan(current.newRestaurantCount, 0)
        XCTAssertNotNil(current.favoriteRestaurant)
        XCTAssertNotNil(current.topCompanion)
        XCTAssertNotNil(current.recommendationSummary.mostUsed)
        XCTAssertFalse(current.keywords.isEmpty)
        XCTAssertFalse(current.representativeRestaurants.isEmpty)

        let light = try AnalysisPosterRenderer.render(
            content: AnnualRecapPosterView(report: current, resolvedImages: [:]),
            canvasSize: AnnualRecapPosterView.canvasSize
        )
        let darkHost = try AnalysisPosterRenderer.render(
            content: AnnualRecapPosterView(report: current, resolvedImages: [:]).environment(\.colorScheme, .dark),
            canvasSize: AnnualRecapPosterView.canvasSize
        )
        XCTAssertEqual(light.size, AnnualRecapPosterView.canvasSize)
        XCTAssertEqual(darkHost.size, AnnualRecapPosterView.canvasSize)
        XCTAssertEqual(light.pngData(), darkHost.pngData())
        XCTAssertNotNil(light.pngData())
    }

    @MainActor
    func testPosterSparseSpendInsufficientNoPhotoLongNamesAndNoClippingContracts() throws {
        let sparse = AnnualRecapPreviewFixtures.sparse
        XCTAssertEqual(sparse.tasteJourney.granularity, .insufficient)
        XCTAssertNil(sparse.recommendationSummary.worst)
        let lowSpend = AnnualRecapPreviewFixtures.lowSpendCoverage
        XCTAssertEqual(lowSpend.spend.displayState, .lowCoverage)
        let noPhoto = AnnualRecapPreviewFixtures.noPhoto
        XCTAssertTrue(noPhoto.photoReferences.allSatisfy { $0 == .none })
        XCTAssertTrue(AnnualRecapPreviewFixtures.longNames.representativeRestaurants.contains { $0.name.count > 20 })
        let image = try AnalysisPosterRenderer.render(
            content: AnnualRecapPosterView(report: AnnualRecapPreviewFixtures.longNames, resolvedImages: [:]),
            canvasSize: AnnualRecapPosterView.canvasSize
        )
        XCTAssertEqual(image.size.width, 1_080)
        XCTAssertEqual(image.size.height, 1_920)
    }

    func testPerformanceForOneThousandRestaurantsTenThousandVisitsFiveThousandDishes() {
        let input = performanceInput()
        let started = ContinuousClock.now
        let report = analyze(input)
        let elapsed = ContinuousClock.now - started
        XCTAssertEqual(report.visitCount, 10_000)
        XCTAssertEqual(report.restaurantCount, 1_000)
        XCTAssertEqual(input.dishes.count, 5_000)
        XCTAssertLessThan(elapsed, .seconds(2))
    }

    private func analyze(_ input: MonthlyRecapInput) -> AnnualRecapAnalysis {
        AnnualRecapAnalyzer.analyze(input, period: AnnualPeriod(year: 2026, calendar: calendar), now: date(2026, 8, 28))
    }

    private func input(
        restaurants: [MonthlyRecapInput.RestaurantRecord],
        visits: [MonthlyRecapInput.VisitRecord]
    ) -> MonthlyRecapInput {
        MonthlyRecapInput(userDisplayName: "Tester", restaurants: restaurants, visits: visits,
                          dishes: [], visitDishes: [], photos: [], companions: [], recommendationSources: [])
    }

    private func replacing(
        _ input: MonthlyRecapInput,
        visits: [MonthlyRecapInput.VisitRecord]? = nil,
        sources: [MonthlyRecapInput.SourceRecord]? = nil
    ) -> MonthlyRecapInput {
        MonthlyRecapInput(
            userDisplayName: input.userDisplayName, restaurants: input.restaurants,
            visits: visits ?? input.visits, dishes: input.dishes,
            visitDishes: input.visitDishes, photos: input.photos,
            companions: input.companions, recommendationSources: sources ?? input.recommendationSources
        )
    }

    private func restaurant(_ id: Int, _ name: String) -> MonthlyRecapInput.RestaurantRecord {
        MonthlyRecapInput.RestaurantRecord(
            id: uuid(id), name: name, city: "杭州", status: .visited, tags: ["日料"],
            createdAt: date(2026, 1, 1), updatedAt: date(2026, 8, 28), deletedAt: nil
        )
    }

    private func visit(
        _ id: Int, restaurantID: UUID, month: Int = 1,
        rating: Double? = 4, deletedAt: Date? = nil
    ) -> MonthlyRecapInput.VisitRecord {
        visit(id, restaurantID: restaurantID, at: date(2026, month, 8), rating: rating, deletedAt: deletedAt)
    }

    private func visit(
        _ id: Int, restaurantID: UUID, at: Date,
        rating: Double? = 4, deletedAt: Date? = nil
    ) -> MonthlyRecapInput.VisitRecord {
        MonthlyRecapInput.VisitRecord(
            id: uuid(id), restaurantID: restaurantID, visitedAt: at,
            rating: rating, valueRating: nil, environmentRating: nil, serviceRating: nil,
            myActualSpend: nil, note: nil, diningOccasionLabels: [],
            companionIDs: [], companionNames: [], recommendationSourceID: nil,
            recommendationSourceType: nil, recommendationSourceText: nil,
            updatedAt: at, deletedAt: deletedAt
        )
    }

    private func copy(
        _ value: MonthlyRecapInput.VisitRecord,
        id: UUID? = nil, visitedAt: Date? = nil, deletedAt: Date?
    ) -> MonthlyRecapInput.VisitRecord {
        MonthlyRecapInput.VisitRecord(
            id: id ?? value.id, restaurantID: value.restaurantID,
            visitedAt: visitedAt ?? value.visitedAt, rating: value.rating,
            valueRating: value.valueRating, environmentRating: value.environmentRating,
            serviceRating: value.serviceRating, myActualSpend: value.myActualSpend,
            note: value.note, diningOccasionLabels: value.diningOccasionLabels,
            companionIDs: value.companionIDs, companionNames: value.companionNames,
            recommendationSourceID: value.recommendationSourceID,
            recommendationSourceType: value.recommendationSourceType,
            recommendationSourceText: value.recommendationSourceText,
            updatedAt: visitedAt ?? value.updatedAt, deletedAt: deletedAt
        )
    }

    private func performanceInput() -> MonthlyRecapInput {
        let restaurants = (0..<1_000).map { index in
            MonthlyRecapInput.RestaurantRecord(
                id: uuid(100_000 + index), name: "性能餐厅 \(index)", city: "杭州",
                status: .visited, tags: ["菜系 \(index % 12)"],
                createdAt: date(2026, 1, 1), updatedAt: date(2026, 8, 28), deletedAt: nil
            )
        }
        let visits = (0..<10_000).map { index -> MonthlyRecapInput.VisitRecord in
            let restaurant = restaurants[index % restaurants.count]
            return visit(200_000 + index, restaurantID: restaurant.id, month: 1 + index % 12, rating: 3.5 + Double(index % 4) * 0.5)
        }
        let dishes = (0..<5_000).map { index -> MonthlyRecapInput.DishRecord in
            let visit = visits[index]
            return MonthlyRecapInput.DishRecord(
                id: uuid(300_000 + index), restaurantID: visit.restaurantID,
                originVisitID: visit.id, name: "性能菜品 \(index)", taste: "真实口味",
                rating: 4, updatedAt: visit.updatedAt, deletedAt: nil
            )
        }
        return MonthlyRecapInput(
            userDisplayName: "Performance", restaurants: restaurants, visits: visits,
            dishes: dishes, visitDishes: [], photos: [], companions: [], recommendationSources: []
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}
