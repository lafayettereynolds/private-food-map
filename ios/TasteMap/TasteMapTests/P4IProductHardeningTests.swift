import Foundation
import Testing
import UIKit
@testable import TasteMap

@Suite("P4-I Product Hardening")
struct P4IProductHardeningTests {
    private let calendar: Calendar = {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        value.locale = Locale(identifier: "zh_Hans_CN")
        return value
    }()

    @Test("Global Restaurant identity connects Taste Map and provider identities without reviving tombstones")
    func globalRestaurantIdentityProjection() throws {
        let apple = try identity(.appleMaps, "APPLE-SHARED")
        let amap = try identity(.amap, "AMAP-SHARED")
        let a = descriptor(1, updatedAt: 1, tasteMapID: "tm_restaurant_shared", identities: [apple])
        let b = descriptor(2, updatedAt: 3, tasteMapID: "tm_restaurant_shared", identities: [amap])
        let c = descriptor(3, updatedAt: 2, identities: [amap])
        let unrelated = descriptor(4, updatedAt: 4, identities: [try identity(.manual, "manual-other")])
        let tombstone = descriptor(5, updatedAt: 9, deletedAt: Date(timeIntervalSince1970: 10), identities: [apple])
        let caseDistinctProviderID = descriptor(
            6, updatedAt: 5, identities: [try identity(.appleMaps, "apple-shared")]
        )

        let projection = AnalysisRestaurantIdentity.projection([
            a, b, c, unrelated, tombstone, caseDistinctProviderID,
        ])
        #expect(projection.canonicalID(for: a.localID) == b.localID)
        #expect(projection.canonicalID(for: c.localID) == b.localID)
        #expect(projection.canonicalID(for: unrelated.localID) == unrelated.localID)
        #expect(projection.canonicalID(for: tombstone.localID) == tombstone.localID)
        #expect(projection.canonicalID(for: caseDistinctProviderID.localID) == caseDistinctProviderID.localID)
        #expect(projection.representativeIDs == [b.localID, unrelated.localID, caseDistinctProviderID.localID])
    }

    @MainActor
    @Test("Every P4 analysis capture uses the same global Restaurant identity projection")
    func analysisCapturesShareGlobalIdentity() {
        let firstID = uuid(10)
        let secondID = uuid(11)
        let first = Restaurant(
            id: firstID, name: "同一家店（搜索）", address: "湖滨路 1 号",
            latitude: 30.25, longitude: 120.16,
            appleMapItemIdentifier: "apple-global-place", city: "杭州",
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let second = Restaurant(
            id: secondID, name: "同一家店（社区）", address: "湖滨路 1 号",
            latitude: 30.25, longitude: 120.16,
            appleMapItemIdentifier: "apple-global-place", city: "杭州",
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let visits = [
            Visit(id: uuid(20), restaurantId: firstID, visitedAt: date(2026, 8, 2), rating: 4, myActualSpend: 100),
            Visit(id: uuid(21), restaurantId: secondID, visitedAt: date(2026, 8, 8), rating: nil, myActualSpend: nil),
        ]
        let restaurants = [first, second]

        let taste = TasteProfileInput.capture(
            restaurants: restaurants, visits: visits, dishes: [], visitDishes: [], photos: [],
            companions: [], recommendationSources: [], profile: nil
        )
        let companion = DiningCompanionInput.capture(
            restaurants: restaurants, visits: visits, dishes: [], visitDishes: [], photos: [],
            companions: [], profiles: [], socialProfiles: [], friendships: []
        )
        let source = RecommendationSourceInput.capture(
            sources: [], restaurants: restaurants, visits: visits, photos: [], profile: nil
        )
        let recap = MonthlyRecapInput.capture(
            restaurants: restaurants, visits: visits, dishes: [], visitDishes: [], photos: [],
            companions: [], recommendationSources: [], profile: nil
        )

        for count in [taste.restaurants.count, companion.restaurants.count, source.restaurants.count, recap.restaurants.count] {
            #expect(count == 1)
        }
        #expect(Set(taste.visits.map(\.restaurantID)).count == 1)
        #expect(Set(companion.visits.map(\.restaurantID)).count == 1)
        #expect(Set(source.visits.map(\.restaurantID)).count == 1)
        #expect(Set(recap.visits.map(\.restaurantID)).count == 1)

        let tasteReport = TasteProfileAnalyzer.analyze(taste, now: date(2026, 8, 29), calendar: calendar)
        let monthlyReport = MonthlyRecapAnalyzer.analyze(
            recap,
            period: MonthlyPeriod(year: 2026, month: 8, calendar: calendar),
            now: date(2026, 8, 29)
        )
        let annualReport = AnnualRecapAnalyzer.analyze(
            recap,
            period: AnnualPeriod(year: 2026, calendar: calendar),
            now: date(2026, 8, 29)
        )
        #expect(tasteReport.repeatAnalysis.visitedRestaurantCount == 1)
        #expect(monthlyReport.restaurantCount == 1)
        #expect(annualReport.restaurantCount == 1)
    }

    @Test("Twelve monthly reports reconcile exactly with the annual report")
    func monthlyAnnualReconciliation() {
        let restaurants = (1...12).map { month in
            MonthlyRecapInput.RestaurantRecord(
                id: uuid(1_000 + month), name: "第 \(month) 月餐厅", city: "杭州",
                status: .visited, tags: [month.isMultiple(of: 2) ? "日料" : "火锅"],
                createdAt: date(2026, month, 1), updatedAt: date(2026, month, 20), deletedAt: nil
            )
        }
        let visits = restaurants.enumerated().map { index, restaurant in
            MonthlyRecapInput.VisitRecord(
                id: uuid(2_000 + index), restaurantID: restaurant.id,
                visitedAt: date(2026, index + 1, 15), rating: index.isMultiple(of: 3) ? nil : 4.5,
                valueRating: nil, environmentRating: nil, serviceRating: nil,
                myActualSpend: Decimal((index + 1) * 10), note: nil,
                diningOccasionLabels: [], companionIDs: [], companionNames: [],
                recommendationSourceID: nil, recommendationSourceType: nil,
                recommendationSourceText: nil, updatedAt: date(2026, index + 1, 15), deletedAt: nil
            )
        }
        let input = MonthlyRecapInput(
            userDisplayName: "对账用户", restaurants: restaurants, visits: visits,
            dishes: [], visitDishes: [], photos: [], companions: [], recommendationSources: []
        )
        let months = (1...12).map { month in
            MonthlyRecapAnalyzer.analyze(
                input,
                period: MonthlyPeriod(year: 2026, month: month, calendar: calendar),
                now: date(2027, 1, 2)
            )
        }
        let annual = AnnualRecapAnalyzer.analyze(
            input,
            period: AnnualPeriod(year: 2026, calendar: calendar),
            now: date(2027, 1, 2)
        )

        #expect(months.reduce(0) { $0 + $1.visitCount } == annual.visitCount)
        #expect(months.reduce(0) { $0 + $1.newRestaurantCount } == annual.newRestaurantCount)
        #expect(months.compactMap(\.spend.recordedTotal).reduce(0, +) == annual.spend.recordedTotal)
        #expect(annual.restaurantCount == 12)
        #expect(annual.monthlySnapshots.map(\.visitCount) == Array(repeating: 1, count: 12))
    }

    @Test("P4 statistics preserve nil rating and nil spend semantics")
    func sharedNullableDefinitions() {
        struct Sample {
            let rating: Double?
            let spend: Decimal?
        }
        let values = [
            Sample(rating: nil, spend: nil),
            Sample(rating: 4.5, spend: 120),
            Sample(rating: 3.5, spend: 80),
        ]
        let ratings = AnalysisStatisticsDefinitions.overallRatings(in: values, rating: \.rating)
        let spend = AnalysisStatisticsDefinitions.recordedSpendValues(in: values, spend: \.spend)
        #expect(ratings == [4.5, 3.5])
        #expect(AnalysisStatisticsDefinitions.mean(ratings) == 4)
        #expect(spend == [120, 80])
        #expect(AnalysisStatisticsDefinitions.median(spend) == 100)
        #expect(AnalysisStatisticsDefinitions.coverage(recordedCount: spend.count, totalCount: values.count) == 2.0 / 3.0)
    }

    @MainActor
    @Test("All poster families keep one 9:16 canvas and abandoned temp exports stay bounded")
    func posterCanvasAndTemporaryCleanup() throws {
        let sizes = [
            AnalysisPosterView.canvasSize,
            DiningCompanionPosterView.canvasSize,
            RecommendationSourcePosterView.canvasSize,
            MonthlyRecapPosterView.canvasSize,
            AnnualRecapPosterView.canvasSize,
        ]
        #expect(Set(sizes.map { "\(Int($0.width))x\(Int($0.height))" }) == ["1080x1920"])

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = AnalysisPosterTemporaryFileStore(rootURL: root, maximumRetainedFileCount: 8)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.systemBlue.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let outsideSentinel = root.appendingPathComponent("outside-share.png")
        try image.pngData()?.write(to: outsideSentinel)
        for index in 0..<50 { _ = try store.write(image, id: "p4-i-\(index)") }
        var files = try FileManager.default.contentsOfDirectory(
            at: store.rootURL,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "png" }
        #expect(files.count == 8)

        let nonPoster = store.rootURL.appendingPathComponent("keep-me.txt")
        try Data("not a poster".utf8).write(to: nonPoster)
        let agedPoster = store.rootURL.appendingPathComponent("aged.png")
        try image.pngData()?.write(to: agedPoster)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -(25 * 60 * 60))],
            ofItemAtPath: agedPoster.path
        )
        store.cleanup()
        files = try FileManager.default.contentsOfDirectory(
            at: store.rootURL,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "png" }
        #expect(files.count == 8)
        #expect(!FileManager.default.fileExists(atPath: agedPoster.path))
        #expect(FileManager.default.fileExists(atPath: nonPoster.path))
        #expect(FileManager.default.fileExists(atPath: outsideSentinel.path))
    }

    private func identity(
        _ provider: RestaurantPlaceProvider,
        _ externalID: String
    ) throws -> RestaurantPlaceIdentityContract {
        try RestaurantPlaceIdentityContract(
            provider: provider,
            externalId: externalID,
            isPrimary: true,
            createdAt: "2026-08-29T00:00:00.000Z",
            updatedAt: "2026-08-29T00:00:00.000Z"
        )
    }

    private func descriptor(
        _ id: Int,
        updatedAt: TimeInterval,
        deletedAt: Date? = nil,
        tasteMapID: String? = nil,
        identities: [RestaurantPlaceIdentityContract]
    ) -> AnalysisRestaurantIdentity.Descriptor {
        AnalysisRestaurantIdentity.Descriptor(
            localID: uuid(id), updatedAt: Date(timeIntervalSince1970: updatedAt),
            deletedAt: deletedAt, tasteMapID: tasteMapID,
            remoteID: nil, appleMapItemIdentifier: nil, placeIdentities: identities
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "90000000-0000-0000-0000-%012d", value))!
    }
}
