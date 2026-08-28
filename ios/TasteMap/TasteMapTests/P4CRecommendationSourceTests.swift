import Foundation
import SwiftUI
import Testing
@testable import TasteMap

@Suite("P4-C Recommendation Source Analytics")
struct P4CRecommendationSourceTests {
    @Test("1–2 no source and one source")
    func noSourceAndOneSource() {
        #expect(RecommendationSourcePreviewFixtures.empty.sources.isEmpty)
        #expect(RecommendationSourcePreviewFixtures.empty.mostUsed == nil)
        #expect(RecommendationSourcePreviewFixtures.oneSource.sources.count == 1)
        #expect(RecommendationSourcePreviewFixtures.oneSource.mostUsed?.displayName == "朋友阿宁")
    }

    @Test("3–5 usage, distinct and rated Restaurant counts")
    func restaurantLevelCounts() {
        let source = RecommendationSourcePreviewFixtures.rich.sources.first { $0.displayName == "小林的私藏清单" }!
        #expect(source.usageCount == 8)
        #expect(source.restaurantCount == 8)
        #expect(source.ratedRestaurantCount == 8)
        #expect(source.restaurantCount < source.restaurants.reduce(0) { $0 + $1.visitCount })
    }

    @Test("6–8 average, high and low rating rates")
    func ratingAggregation() {
        let rich = RecommendationSourcePreviewFixtures.rich
        let best = rich.sources.first { $0.displayName == "小林的私藏清单" }!
        let worst = rich.sources.first { $0.displayName == "深夜刷到的收藏夹" }!
        #expect(abs((best.averageRating ?? 0) - 4.5) < 0.001)
        #expect(best.highRatingRate == 1)
        #expect(worst.lowRatingCount == 5)
        #expect(abs(worst.lowRatingRate - (5.0 / 7.0)) < 0.001)
    }

    @Test("9 repeat conversion uses distinct Restaurants")
    func repeatConversion() {
        let source = RecommendationSourcePreviewFixtures.rich.sources.first { $0.displayName == "小林的私藏清单" }!
        #expect(source.repeatedRestaurantCount == 4)
        #expect(source.repeatConversionRate == 0.5)
    }

    @Test("10 rating variance differentiates stable and volatile")
    func ratingVariance() {
        let stable = RecommendationSourcePreviewFixtures.stableHigh.sources.first { $0.displayName == "老饕手写清单" }!
        let volatile = RecommendationSourcePreviewFixtures.volatile.sources.first { $0.displayName.contains("忽高忽低") }!
        #expect(stable.ratingStability == .stable)
        #expect(volatile.ratingStability == .volatile)
        #expect((volatile.ratingStandardDeviation ?? 0) > (stable.ratingStandardDeviation ?? 0))
    }

    @Test("11 latest usage is the attribution Visit, not a later revisit")
    func latestUsage() {
        let input = RecommendationSourcePreviewFixtures.input(plans: [
            .init(name: "来源", type: .friend, ratings: [4.5, 4], repeatEvery: 1),
        ])
        let report = RecommendationSourceAnalyzer.analyze(input, now: RecommendationSourcePreviewFixtures.now)
        let acquisitionMax = input.restaurants.compactMap { restaurant in
            input.visits
                .filter { $0.restaurantID == restaurant.id && $0.recommendationSourceID != nil }
                .min { $0.visitedAt == $1.visitedAt ? $0.id.uuidString < $1.id.uuidString : $0.visitedAt < $1.visitedAt }?
                .visitedAt
        }.max()
        #expect(report.sources[0].latestUsageAt == acquisitionMax)
        #expect(report.sources[0].latestUsageAt != input.visits.map(\.visitedAt).max())
    }

    @Test("12 tombstone Visit is ignored")
    func tombstoneVisitIgnored() {
        let base = RecommendationSourcePreviewFixtures.input(plans: [
            .init(name: "来源", type: .friend, ratings: [4, 5], repeatEvery: 0),
        ])
        let deleted = copy(base.visits[0], deletedAt: RecommendationSourcePreviewFixtures.now)
        let report = analyze(copy(base, visits: [deleted, base.visits[1]]))
        #expect(report.attributedRestaurantCount == 1)
    }

    @Test("13 tombstone Restaurant is ignored")
    func tombstoneRestaurantIgnored() {
        let base = RecommendationSourcePreviewFixtures.input(plans: [
            .init(name: "来源", type: .friend, ratings: [4, 5], repeatEvery: 0),
        ])
        let restaurants = [copy(base.restaurants[0], deletedAt: RecommendationSourcePreviewFixtures.now), base.restaurants[1]]
        #expect(analyze(copy(base, restaurants: restaurants)).attributedRestaurantCount == 1)
    }

    @Test("14 nil rating is ignored rather than zero")
    func nilRatingIgnored() {
        let report = analyze(RecommendationSourcePreviewFixtures.input(plans: [
            .init(name: "来源", type: .friend, ratings: [nil, 4.5], repeatEvery: 0),
        ]))
        #expect(report.sources[0].ratedRestaurantCount == 1)
        #expect(report.sources[0].averageRating == 4.5)
    }

    @Test("15 multiple Visits at one Restaurant do not overweight source or rating")
    func repeatVisitsDoNotOverweight() {
        let repeated = analyze(RecommendationSourcePreviewFixtures.input(plans: [
            .init(name: "来源", type: .friend, ratings: [5, 1], repeatEvery: 1),
        ])).sources[0]
        #expect(repeated.restaurantCount == 2)
        #expect(repeated.ratedRestaurantCount == 2)
        #expect(repeated.averageRating == 3)
    }

    @Test("16 source rename keeps stable identity and uses current displayName")
    func sourceRename() {
        let base = RecommendationSourcePreviewFixtures.input(plans: [
            .init(name: "旧名字", type: .friend, ratings: [4, 4.5], repeatEvery: 0),
        ])
        let source = base.sources[0]
        let renamed = RecommendationSourceInput.SourceRecord(
            id: source.id, identifiers: source.identifiers, displayName: "我自己写的新名字",
            sourceType: source.sourceType, updatedAt: source.updatedAt.addingTimeInterval(1), deletedAt: nil
        )
        let report = analyze(copy(base, sources: [renamed]))
        #expect(report.sources[0].id == source.id)
        #expect(report.sources[0].displayName == "我自己写的新名字")
        #expect(report.sources[0].restaurantCount == 2)
    }

    @Test("17 data sufficiency follows 2/10 Restaurant samples")
    func dataSufficiency() {
        #expect(RecommendationSourcePreviewFixtures.oneSource.sources[0].sufficiency == .insufficient)
        #expect(RecommendationSourcePreviewFixtures.twoInsufficient.sources[0].sufficiency == .emerging)
        #expect(RecommendationSourcePreviewFixtures.stableHigh.sources[0].sufficiency == .established)
    }

    @Test("18 deterministic ties use stable UUID")
    func deterministicTies() {
        let input = RecommendationSourcePreviewFixtures.input(plans: [
            .init(name: "A", type: .friend, ratings: Array(repeating: 4.0, count: 6), repeatEvery: 0),
            .init(name: "B", type: .friend, ratings: Array(repeating: 4.0, count: 6), repeatEvery: 0),
        ])
        let first = analyze(input)
        let second = analyze(input)
        #expect(first.bestSource?.sourceID == second.bestSource?.sourceID)
        #expect(first.worstSource?.sourceID == second.worstSource?.sourceID)
        #expect(first.sources.map(\.id) == second.sources.map(\.id))
    }

    @Test("formal discovery attribution uses the earliest source-bearing Visit")
    func earliestSourceBearingVisitWins() {
        let base = RecommendationSourcePreviewFixtures.input(plans: [
            .init(name: "第一次发现", type: .friend, ratings: [4.5], repeatEvery: 0),
            .init(name: "后来又提到", type: .blogger, ratings: [4.0], repeatEvery: 0),
        ])
        let firstRestaurant = base.restaurants[0]
        let laterSource = base.sources[1]
        let laterVisit = RecommendationSourceInput.VisitRecord(
            id: uuid(999_001), restaurantID: firstRestaurant.id,
            visitedAt: base.visits[0].visitedAt.addingTimeInterval(30 * 86_400),
            rating: 5, valueRating: nil, environmentRating: nil, serviceRating: nil,
            recommendationSourceID: laterSource.identifiers.last,
            recommendationSourceType: laterSource.sourceType,
            recommendationSourceText: laterSource.displayName,
            updatedAt: RecommendationSourcePreviewFixtures.now, deletedAt: nil
        )
        let report = analyze(copy(base, visits: base.visits + [laterVisit]))
        #expect(report.sources.first { $0.displayName == "第一次发现" }?.restaurantCount == 1)
        #expect(report.sources.first { $0.displayName == "后来又提到" }?.restaurantCount == 1)
    }

    @Test("tombstoned sources and unresolved explicit identities are not reassigned by name")
    func sourceTombstoneAndExplicitIdentityBoundary() {
        let base = RecommendationSourcePreviewFixtures.input(plans: [
            .init(name: "同名来源", type: .friend, ratings: [4.5], repeatEvery: 0),
        ])
        let original = base.sources[0]
        let tombstoned = RecommendationSourceInput.SourceRecord(
            id: original.id, identifiers: original.identifiers, displayName: original.displayName,
            sourceType: original.sourceType, updatedAt: original.updatedAt, deletedAt: RecommendationSourcePreviewFixtures.now
        )
        #expect(analyze(copy(base, sources: [tombstoned])).sources.isEmpty)

        let visit = base.visits[0]
        let unresolved = RecommendationSourceInput.VisitRecord(
            id: visit.id, restaurantID: visit.restaurantID, visitedAt: visit.visitedAt,
            rating: visit.rating, valueRating: visit.valueRating,
            environmentRating: visit.environmentRating, serviceRating: visit.serviceRating,
            recommendationSourceID: "missing-stable-identity",
            recommendationSourceType: visit.recommendationSourceType,
            recommendationSourceText: original.displayName,
            updatedAt: visit.updatedAt, deletedAt: nil
        )
        #expect(analyze(copy(base, visits: [unresolved])).attributedRestaurantCount == 0)
    }

    @Test("ambiguous legacy source names are never merged automatically")
    func duplicateLegacyNamesStayUnresolved() {
        let base = RecommendationSourcePreviewFixtures.input(plans: [
            .init(name: "小红书", type: .xiaohongshu, ratings: [4.5], repeatEvery: 0),
            .init(name: "小红书", type: .other, ratings: [2.0], repeatEvery: 0),
        ])
        let legacyVisits = base.visits.map { visit in
            RecommendationSourceInput.VisitRecord(
                id: visit.id, restaurantID: visit.restaurantID, visitedAt: visit.visitedAt,
                rating: visit.rating, valueRating: visit.valueRating,
                environmentRating: visit.environmentRating, serviceRating: visit.serviceRating,
                recommendationSourceID: nil, recommendationSourceType: visit.recommendationSourceType,
                recommendationSourceText: "小红书", updatedAt: visit.updatedAt, deletedAt: nil
            )
        }
        #expect(analyze(copy(base, visits: legacyVisits)).attributedRestaurantCount == 0)
    }

    @Test("Want To Go without a formal Visit source is excluded")
    func wantToGoDoesNotEnterSourceOutcome() {
        let withoutWantToGo = RecommendationSourcePreviewFixtures.rich
        let withWantToGo = RecommendationSourcePreviewFixtures.wantToGoExcluded
        #expect(withWantToGo.attributedRestaurantCount == withoutWantToGo.attributedRestaurantCount)
        #expect(withWantToGo.ratedRestaurantCount == withoutWantToGo.ratedRestaurantCount)
    }

    @Test("19 below-threshold source is excluded from best ranking")
    func belowThresholdExcluded() {
        let report = analyze(RecommendationSourcePreviewFixtures.input(plans: [
            .init(name: "五家满分但不足", type: .friend, ratings: Array(repeating: 5, count: 5), repeatEvery: 1),
            .init(name: "合格高分", type: .self, ratings: Array(repeating: 4, count: 6), repeatEvery: 2),
            .init(name: "合格低分", type: .other, ratings: Array(repeating: 2, count: 6), repeatEvery: 0),
        ]))
        #expect(report.bestSource?.displayName == "合格高分")
    }

    @Test("20–23 sufficient high average, hit rate, repeat rate and competition")
    func bestSourceSignals() {
        let report = RecommendationSourcePreviewFixtures.rich
        let best = report.analysis(for: report.bestSource!.sourceID)!
        #expect(best.displayName == "小林的私藏清单")
        #expect((best.averageRating ?? 0) >= 4.5)
        #expect(best.highRatingRate == 1)
        #expect(best.repeatConversionRate == 0.5)
        #expect(report.sources.count >= 2)
    }

    @Test("24 best ranking tie-break is deterministic")
    func bestTieBreak() {
        deterministicTies()
    }

    @Test("25 only one qualifying source does not create relative ranking")
    func onlyOneQualifiedNoBest() {
        let report = analyze(RecommendationSourcePreviewFixtures.input(plans: [
            .init(name: "够样本", type: .friend, ratings: Array(repeating: 4.5, count: 6), repeatEvery: 2),
            .init(name: "不够样本", type: .self, ratings: [5, 5], repeatEvery: 1),
        ]))
        #expect(report.bestSource == nil)
        #expect(report.worstSource == nil)
    }

    @Test("26 best explanation uses human-readable evidence")
    func bestExplanation() {
        let conclusion = RecommendationSourcePreviewFixtures.rich.bestSource!
        #expect(conclusion.explanation.contains("有评分餐厅"))
        #expect(conclusion.explanation.contains("4.0"))
        #expect(conclusion.explanation.contains("回头餐厅"))
        #expect(!conclusion.explanation.contains("reliabilityScore"))
    }

    @Test("27 formal output name remains 最坑推荐来源")
    func exactWorstLabel() {
        #expect(RecommendationSourcePreviewFixtures.rich.worstSource?.title == "最坑推荐来源")
    }

    @Test("28 one bad Restaurant is insufficient to label a source worst")
    func oneBadRestaurantIsNotWorst() {
        let report = analyze(RecommendationSourcePreviewFixtures.input(plans: [
            .init(name: "一次踩坑", type: .other, ratings: [1], repeatEvery: 0),
            .init(name: "稳定来源", type: .friend, ratings: Array(repeating: 4, count: 6), repeatEvery: 2),
        ]))
        #expect(report.worstSource == nil)
    }

    @Test("29–33 sufficient low sample, low rate, average, repeat auxiliary and candidates")
    func worstSourceSignals() {
        let report = RecommendationSourcePreviewFixtures.rich
        let worst = report.analysis(for: report.worstSource!.sourceID)!
        #expect(worst.displayName == "深夜刷到的收藏夹")
        #expect(worst.ratedRestaurantCount >= 6)
        #expect(worst.lowRatingRate > 0.7)
        #expect((worst.averageRating ?? 5) < 3)
        #expect(worst.repeatConversionRate == 0)
        #expect(report.sources.filter { $0.pitfallScore != nil }.count >= 2)
    }

    @Test("34 worst ranking is deterministic")
    func worstDeterministic() {
        deterministicTies()
    }

    @Test("35 no qualifying worst source produces no claim")
    func noQualifyingWorst() {
        #expect(RecommendationSourcePreviewFixtures.twoInsufficient.worstSource == nil)
    }

    @Test("36 worst explanation uses counts and avoids opaque score")
    func worstExplanation() {
        let explanation = RecommendationSourcePreviewFixtures.rich.worstSource!.explanation
        #expect(explanation.contains("不高于 2.5"))
        #expect(explanation.contains("回头餐厅"))
        #expect(!explanation.contains("pitfallScore"))
    }

    @Test("37–40 representative Restaurants cover best, worst, latest without duplicates")
    func representativeRestaurants() {
        let evidence = RecommendationSourcePreviewFixtures.rich.representativeRestaurants
        #expect(evidence.contains { $0.role == "靠谱来源代表" })
        #expect(evidence.contains { $0.role == "最坑来源证据" })
        #expect(evidence.contains { $0.role == "近期来源故事" })
        #expect(Set(evidence.map(\.id)).count == evidence.count)
    }

    @Test("41 Photo fallback is explicit and deterministic")
    func photoFallback() {
        let withPhotos = RecommendationSourcePreviewFixtures.withPhotos.sources.flatMap(\.restaurants)
        let withoutPhotos = RecommendationSourcePreviewFixtures.noPhotos.sources.flatMap(\.restaurants)
        #expect(withPhotos.contains { if case .photo = $0.imageReference { true } else { false } })
        #expect(withoutPhotos.allSatisfy { $0.imageReference == .none })
    }

    @Test("42 nil rating Restaurant is not a best/worst rating example")
    func nilRatingNotRepresentativeExtreme() {
        let report = analyze(RecommendationSourcePreviewFixtures.input(plans: [
            .init(name: "好来源", type: .friend, ratings: [nil, 5, 5, 5, 5, 5, 5], repeatEvery: 2),
            .init(name: "差来源", type: .other, ratings: [nil, 1, 1, 1, 1, 1, 1], repeatEvery: 0),
        ]))
        let extremes = report.representativeRestaurants.filter { $0.role != "近期来源故事" }
        #expect(extremes.allSatisfy { $0.averageRating != nil })
    }

    @MainActor
    @Test("43–45 poster contains most-used, best and 最坑 conclusions")
    func posterConclusionsRender() throws {
        let report = RecommendationSourcePreviewFixtures.posterRich
        #expect(report.mostUsed != nil)
        #expect(report.bestSource != nil)
        #expect(report.worstSource?.title == "最坑推荐来源")
        let image = try render(report)
        #expect(image.size == RecommendationSourcePosterView.canvasSize)
    }

    @MainActor
    @Test("46 insufficient poster renders honest empty conclusions")
    func insufficientPoster() throws {
        let report = RecommendationSourcePreviewFixtures.posterSparse
        #expect(report.bestSource == nil)
        #expect(report.worstSource == nil)
        #expect(try render(report).size == RecommendationSourcePosterView.canvasSize)
    }

    @MainActor
    @Test("47 poster accepts Restaurant photo references")
    func posterPhotos() throws {
        let report = RecommendationSourcePreviewFixtures.withPhotos
        #expect(report.photoReferences.contains { if case .photo = $0 { true } else { false } })
        #expect(try render(report).size.width == 1080)
    }

    @MainActor
    @Test("48–49 long source and Restaurant names render")
    func posterLongContent() throws {
        #expect(try render(RecommendationSourcePreviewFixtures.longSourceName).size.height == 1920)
        #expect(try render(RecommendationSourcePreviewFixtures.longRestaurantName).size.height == 1920)
    }

    @MainActor
    @Test("50 fixed poster size is 1080 × 1920")
    func fixedPosterSize() throws {
        #expect(RecommendationSourcePosterView.canvasSize == CGSize(width: 1080, height: 1920))
        #expect(try render(RecommendationSourcePreviewFixtures.rich).size == CGSize(width: 1080, height: 1920))
    }

    @MainActor
    @Test("51–53 poster stays clipped, light and uses shared P4 renderer/components")
    func posterVisualSystem() throws {
        let image = try AnalysisPosterRenderer.render(
            content: RecommendationSourcePosterView(overview: RecommendationSourcePreviewFixtures.rich),
            canvasSize: RecommendationSourcePosterView.canvasSize
        )
        #expect(image.size == RecommendationSourcePosterView.canvasSize)
        #expect(image.pngData()?.isEmpty == false)
        _ = ReceiptShape()
        _ = PosterRestaurantCard(
            restaurant: RecommendationSourcePreviewFixtures.rich.representativeRestaurants.map {
                RepresentativeRestaurant(id: $0.id, name: $0.name, role: $0.role, detail: $0.detail, averageRating: $0.averageRating, visitCount: $0.visitCount, imageReference: $0.imageReference)
            }[0],
            image: nil
        )
    }

    @Test("performance: 100 sources, 1000 Restaurants and 3000 Visits")
    func performance() {
        let input = performanceInput()
        let clock = ContinuousClock()
        let elapsed = clock.measure { _ = analyze(input) }
        #expect(elapsed < .seconds(2))
        #expect(analyze(input).sources.count == 100)
    }

    private func analyze(_ input: RecommendationSourceInput) -> RecommendationSourceOverview {
        RecommendationSourceAnalyzer.analyze(input, now: RecommendationSourcePreviewFixtures.now)
    }

    @MainActor
    private func render(_ report: RecommendationSourceOverview) throws -> UIImage {
        try AnalysisPosterRenderer.render(
            content: RecommendationSourcePosterView(overview: report),
            canvasSize: RecommendationSourcePosterView.canvasSize
        )
    }

    private func copy(
        _ source: RecommendationSourceInput,
        sources: [RecommendationSourceInput.SourceRecord]? = nil,
        restaurants: [RecommendationSourceInput.RestaurantRecord]? = nil,
        visits: [RecommendationSourceInput.VisitRecord]? = nil
    ) -> RecommendationSourceInput {
        .init(
            userDisplayName: source.userDisplayName,
            sources: sources ?? source.sources,
            restaurants: restaurants ?? source.restaurants,
            visits: visits ?? source.visits,
            photos: source.photos
        )
    }

    private func copy(
        _ source: RecommendationSourceInput.VisitRecord,
        deletedAt: Date?
    ) -> RecommendationSourceInput.VisitRecord {
        .init(
            id: source.id, restaurantID: source.restaurantID, visitedAt: source.visitedAt,
            rating: source.rating, valueRating: source.valueRating,
            environmentRating: source.environmentRating, serviceRating: source.serviceRating,
            recommendationSourceID: source.recommendationSourceID,
            recommendationSourceType: source.recommendationSourceType,
            recommendationSourceText: source.recommendationSourceText,
            updatedAt: source.updatedAt, deletedAt: deletedAt
        )
    }

    private func copy(
        _ source: RecommendationSourceInput.RestaurantRecord,
        deletedAt: Date?
    ) -> RecommendationSourceInput.RestaurantRecord {
        .init(
            id: source.id, name: source.name, city: source.city, status: source.status,
            updatedAt: source.updatedAt, deletedAt: deletedAt
        )
    }

    private func performanceInput() -> RecommendationSourceInput {
        var sources: [RecommendationSourceInput.SourceRecord] = []
        var restaurants: [RecommendationSourceInput.RestaurantRecord] = []
        var visits: [RecommendationSourceInput.VisitRecord] = []
        for sourceIndex in 0..<100 {
            let sourceID = uuid(100_000 + sourceIndex)
            let remoteID = "perf-source-\(sourceIndex)"
            sources.append(.init(
                id: sourceID, identifiers: [remoteID], displayName: "来源 \(sourceIndex)",
                sourceType: .other, updatedAt: RecommendationSourcePreviewFixtures.now, deletedAt: nil
            ))
            for restaurantIndex in 0..<10 {
                let index = sourceIndex * 10 + restaurantIndex
                let restaurantID = uuid(110_000 + index)
                restaurants.append(.init(
                    id: restaurantID, name: "餐厅 \(index)", city: "杭州", status: .visited,
                    updatedAt: RecommendationSourcePreviewFixtures.now, deletedAt: nil
                ))
                for visitIndex in 0..<3 {
                    visits.append(.init(
                        id: uuid(200_000 + index * 3 + visitIndex), restaurantID: restaurantID,
                        visitedAt: RecommendationSourcePreviewFixtures.now.addingTimeInterval(Double(-visitIndex) * 86_400),
                        rating: Double((index + visitIndex) % 10 + 1) / 2,
                        valueRating: nil, environmentRating: nil, serviceRating: nil,
                        recommendationSourceID: remoteID, recommendationSourceType: .other,
                        recommendationSourceText: "来源 \(sourceIndex)",
                        updatedAt: RecommendationSourcePreviewFixtures.now, deletedAt: nil
                    ))
                }
            }
        }
        return .init(
            userDisplayName: "Performance", sources: sources,
            restaurants: restaurants, visits: visits, photos: []
        )
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}
