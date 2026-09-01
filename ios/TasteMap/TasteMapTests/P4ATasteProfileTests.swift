import Foundation
import Photos
import Testing
import UIKit
@testable import TasteMap

@Suite("P4-A taste profile analytics and share poster", .serialized)
@MainActor
struct P4ATasteProfileTests {
    @Test("Zero and one visit never fabricate mature conclusions")
    func sparseData() {
        let empty = TasteProfilePreviewFixtures.empty
        #expect(empty.visitCount == 0)
        #expect(empty.sufficiency == .insufficient)
        #expect(empty.cuisineRanking.isEmpty)
        #expect(empty.spend.median == nil)
        #expect(empty.ratingStyle.average == nil)
        #expect(empty.restaurants.isEmpty)
        #expect(empty.availableInsights.isEmpty)

        let sparse = TasteProfilePreviewFixtures.sparse
        #expect(sparse.visitCount == 1)
        #expect(sparse.sufficiency == .insufficient)
        #expect(sparse.favoriteStatement == "口味正在形成")
        #expect(sparse.recommendationSources.isEmpty)
        #expect(sparse.companions.isEmpty)
    }

    @Test("Cuisine ranking uses frequency, breadth, repeat, reliable ratings and recency deterministically")
    func cuisineRankingAndDeterminism() {
        let input = TasteProfilePreviewFixtures.input(visitCount: 18)
        let first = TasteProfileAnalyzer.analyze(input, now: TasteProfilePreviewFixtures.now)
        let second = TasteProfileAnalyzer.analyze(input, now: TasteProfilePreviewFixtures.now)
        #expect(first == second)
        #expect(first.cuisineRanking.first?.label == "日料")
        #expect(first.cuisineRanking.first?.visitCount == 9)
        #expect(first.cuisineRanking.first?.repeatVisitCount == 8)
        #expect(first.cuisineRanking.allSatisfy { !$0.label.contains("安静") && !$0.label.contains("聚餐") })
    }

    @Test("Nil rating and spend are excluded rather than converted to zero")
    func nilSemantics() {
        let input = TasteProfilePreviewFixtures.input(visitCount: 7)
        let report = TasteProfileAnalyzer.analyze(input, now: TasteProfilePreviewFixtures.now)
        #expect(report.ratedVisitCount == 6)
        #expect(report.ratingStyle.sampleCount == 6)
        #expect(report.spend.sampleCount == 6)
        #expect(report.ratingStyle.average! > 4)
        #expect(report.spend.median! > 0)
        #expect(report.dataNote.contains("nil 评分与 nil 消费不会当作 0"))
    }

    @Test("Spend median, quartiles and buckets only use myActualSpend")
    func spendDistribution() {
        let report = TasteProfileAnalyzer.analyze(
            TasteProfilePreviewFixtures.input(visitCount: 7),
            now: TasteProfilePreviewFixtures.now
        )
        #expect(report.spend.median == 199)
        #expect(report.spend.lowerQuartile == 143)
        #expect(report.spend.upperQuartile == 229.5)
        #expect(report.spend.typicalBucket == "¥100–200")
        #expect(report.spend.distribution.reduce(0) { $0 + $1.count } == 6)
    }

    @Test("Repeat rate counts repeated restaurants, not repeated visit rows")
    func repeatRate() {
        let report = TasteProfileAnalyzer.analyze(
            TasteProfilePreviewFixtures.input(visitCount: 14),
            now: TasteProfilePreviewFixtures.now
        )
        #expect(report.repeatAnalysis.visitedRestaurantCount == 4)
        #expect(report.repeatAnalysis.repeatedRestaurantCount == 4)
        #expect(report.repeatAnalysis.rate == 1)
    }

    @Test("Tombstoned visits, restaurants, dishes and photos never influence analysis")
    func tombstones() {
        let input = TasteProfilePreviewFixtures.input(visitCount: 7)
        let deletedRestaurantID = input.restaurants[0].id
        let restaurants = input.restaurants.map { restaurant in
            restaurant.id == deletedRestaurantID
                ? .init(
                    id: restaurant.id, name: restaurant.name, address: restaurant.address,
                    city: restaurant.city, status: restaurant.status, tags: restaurant.tags,
                    createdAt: restaurant.createdAt, updatedAt: restaurant.updatedAt,
                    deletedAt: TasteProfilePreviewFixtures.now
                )
                : restaurant
        }
        let report = TasteProfileAnalyzer.analyze(
            copy(input, restaurants: restaurants), now: TasteProfilePreviewFixtures.now
        )
        #expect(report.visitCount == 4)
        #expect(report.restaurants.allSatisfy { $0.id != deletedRestaurantID })
        #expect(!report.hero.imageReferences.contains(.photo(input.photos[0].id)))
    }

    @Test("Dining context, companions and recommendation sources use structured fields")
    func contextDirectories() {
        let report = TasteProfileAnalyzer.analyze(
            TasteProfilePreviewFixtures.input(visitCount: 9),
            now: TasteProfilePreviewFixtures.now
        )
        #expect(report.diningScenes.first?.label == "适中")
        #expect(report.companions.first?.label == "小林")
        #expect(report.recommendationSources.first?.label == "朋友推荐")
        #expect(report.insights.first(where: { $0.id == "source" })?.detail.contains("P4-C") == true)
        #expect(report.insights.first(where: { $0.id == "companion" })?.detail.contains("P4-B") == true)
    }

    @Test("Rating style ignores nil and includes detailed dimension averages")
    func ratingStyle() {
        let report = TasteProfileAnalyzer.analyze(
            TasteProfilePreviewFixtures.input(visitCount: 18),
            now: TasteProfilePreviewFixtures.now
        )
        #expect(report.ratingStyle.sampleCount == 15)
        #expect(report.ratingStyle.dimensionSummary?.contains("性价比") == true)
        #expect(report.ratingStyle.dimensionSummary?.contains("环境") == true)
        #expect(report.ratingStyle.dimensionSummary?.contains("服务") == true)
    }

    @Test("Dining time is evaluated in the provided device calendar and discloses timezone limitation")
    func diningTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let report = TasteProfileAnalyzer.analyze(
            TasteProfilePreviewFixtures.input(visitCount: 12),
            now: TasteProfilePreviewFixtures.now,
            calendar: calendar
        )
        #expect(report.diningTime.label == "晚餐")
        #expect(report.diningTime.timeZoneNotice.contains("设备时区"))
    }

    @Test("Representative restaurants are selected by distinct roles and deduplicated")
    func representativeRestaurants() {
        let report = TasteProfileAnalyzer.analyze(
            TasteProfilePreviewFixtures.input(visitCount: 18),
            now: TasteProfilePreviewFixtures.now
        )
        #expect((1...4).contains(report.restaurants.count))
        #expect(Set(report.restaurants.map(\.id)).count == report.restaurants.count)
        #expect(report.restaurants.first?.role == "你最常去的店")
        #expect(report.restaurants.contains { $0.imageReference != .none })
    }

    @Test("Most visited, favorite, recent and representative roles select distinct real restaurants")
    func representativeRoles() {
        let report = TasteProfileAnalyzer.analyze(
            representativeRoleInput(), now: TasteProfilePreviewFixtures.now
        )
        let roles = Set(report.restaurants.map(\.role))
        #expect(report.restaurants.count == 4)
        #expect(roles.contains("你最常去的店"))
        #expect(roles.contains("你最喜欢的店"))
        #expect(roles.contains("近期常去的店"))
        #expect(roles.contains("最能代表你口味的店"))
        #expect(Set(report.restaurants.map(\.id)).count == 4)

        let oneRestaurant = TasteProfilePreviewFixtures.singlePreference
        #expect(oneRestaurant.restaurants.count == 1)
        #expect(oneRestaurant.restaurants[0].imageReference != .none)
    }

    @Test("Food hero follows cuisine and dish signals, supports mixed preference and fallback")
    func foodHero() {
        #expect(TasteProfileAnalyzer.resolveHeroTheme(labels: ["寿司", "日料"]) == .japanese)
        #expect(TasteProfileAnalyzer.resolveHeroTheme(labels: ["火锅", "烤肉"]) == .hotpotGrill)
        #expect(TasteProfileAnalyzer.resolveHeroTheme(labels: ["咖啡", "甜点"]) == .cafe)
        #expect(TasteProfileAnalyzer.resolveHeroTheme(labels: ["日料", "火锅"]) == .mixed)
        #expect(TasteProfileAnalyzer.resolveHeroTheme(labels: []) == .mixed)

        let noPhotos = TasteProfilePreviewFixtures.noPhotos
        #expect(noPhotos.hero.imageReferences == [.asset(noPhotos.hero.fallbackAssetName)])

        let dishPhoto = TasteProfilePreviewFixtures.rich
        #expect(dishPhoto.hero.imageReferences.contains(.photo(
            TasteProfilePreviewFixtures.input(visitCount: 18).photos[0].id
        )))

        let source = TasteProfilePreviewFixtures.input(visitCount: 12, includePhotos: false)
        let restaurantPhotoID = UUID(uuidString: "00000000-0000-0000-0000-000000009999")!
        let restaurantPhoto = TasteProfileInput.PhotoRecord(
            id: restaurantPhotoID, restaurantID: source.restaurants[2].id,
            visitID: nil, dishID: nil, kind: "restaurant_marker", sortOrder: 0,
            updatedAt: TasteProfilePreviewFixtures.now, deletedAt: nil
        )
        let restaurantPhotoReport = TasteProfileAnalyzer.analyze(
            TasteProfileInput(
                userDisplayName: source.userDisplayName, restaurants: source.restaurants,
                visits: source.visits, dishes: [], visitDishes: [], photos: [restaurantPhoto],
                companions: source.companions, recommendationSources: source.recommendationSources
            ),
            now: TasteProfilePreviewFixtures.now
        )
        #expect(restaurantPhotoReport.hero.imageReferences.contains(.photo(restaurantPhotoID)))
        #expect(TasteProfilePreviewFixtures.empty.hero.imageReferences == [.asset("FoodHeroMixed")])
    }

    @Test("Real local photos outrank provider images and provider images outrank decorative fallback")
    func restaurantImagePriority() {
        let providerURL = URL(string: "https://images.example.com/merchant.jpg")!
        let source = TasteProfilePreviewFixtures.input(visitCount: 12, includePhotos: false)
        let restaurants = source.restaurants.map { restaurant in
            TasteProfileInput.RestaurantRecord(
                id: restaurant.id, name: restaurant.name, address: restaurant.address,
                city: restaurant.city, status: restaurant.status, tags: restaurant.tags,
                merchantImageURL: providerURL,
                createdAt: restaurant.createdAt, updatedAt: restaurant.updatedAt, deletedAt: restaurant.deletedAt
            )
        }
        let providerReport = TasteProfileAnalyzer.analyze(
            TasteProfileInput(
                userDisplayName: source.userDisplayName, restaurants: restaurants,
                visits: source.visits, dishes: source.dishes, visitDishes: source.visitDishes,
                photos: [], companions: source.companions,
                recommendationSources: source.recommendationSources
            ),
            now: TasteProfilePreviewFixtures.now
        )
        #expect(providerReport.restaurants.contains { $0.imageReference == .provider(providerURL) })
        #expect(providerReport.hero.imageReferences.contains(.provider(providerURL)))

        let realPhoto = TasteProfileInput.PhotoRecord(
            id: UUID(), restaurantID: restaurants[0].id, visitID: nil, dishID: nil,
            kind: "restaurant_marker", sortOrder: 0,
            updatedAt: TasteProfilePreviewFixtures.now, deletedAt: nil
        )
        let localReport = TasteProfileAnalyzer.analyze(
            TasteProfileInput(
                userDisplayName: source.userDisplayName, restaurants: restaurants,
                visits: source.visits, dishes: source.dishes, visitDishes: source.visitDishes,
                photos: [realPhoto], companions: source.companions,
                recommendationSources: source.recommendationSources
            ),
            now: TasteProfilePreviewFixtures.now
        )
        let localRepresentative = localReport.restaurants.first { $0.id == restaurants[0].id }
        #expect(localRepresentative?.imageReference == .photo(
            realPhoto.id,
            providerFallback: providerURL
        ))
    }

    @Test("Taste keywords are explainable, bounded and disappear when no evidence exists")
    func tasteKeywords() {
        let report = TasteProfilePreviewFixtures.rich
        #expect(!report.keywords.isEmpty)
        #expect(report.keywords.count <= 7)
        #expect(report.keywords.contains("日料"))
        #expect(TasteProfilePreviewFixtures.empty.keywords.isEmpty)
        #expect(report.sufficiency == .established)
        #expect(TasteProfilePreviewFixtures.emerging.sufficiency == .emerging)
    }

    @Test("Analyzer remains interactive with 200 restaurants, 1000 visits, 500 dishes and photo metadata")
    func performance() {
        let input = performanceInput()
        #expect(input.restaurants.count == 200)
        #expect(input.visits.count == 1_000)
        #expect(input.dishes.count == 500)
        #expect(input.photos.count == 500)
        let start = ContinuousClock.now
        let report = TasteProfileAnalyzer.analyze(input, now: TasteProfilePreviewFixtures.now)
        let elapsed = start.duration(to: .now)
        #expect(report.visitCount == 1_000)
        #expect(elapsed < .seconds(2))
    }

    @Test("ImageRenderer exports exact 9:16 pixels for rich, sparse and long content")
    func posterRendering() throws {
        for report in [
            TasteProfilePreviewFixtures.rich,
            TasteProfilePreviewFixtures.sparse,
            TasteProfilePreviewFixtures.longContent,
            TasteProfilePreviewFixtures.noPhotos,
        ] {
            let image = try AnalysisPosterRenderer.render(report: report)
            #expect(image.size == AnalysisPosterView.canvasSize)
            #expect(image.cgImage?.width == 1_080)
            #expect(image.cgImage?.height == 1_920)
            #expect(image.pngData()?.isEmpty == false)
        }
    }

    @Test("Poster temporary share file is written atomically and cleaned after sharing")
    func temporaryShareFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AnalysisPosterTemporaryFileStore(rootURL: root)
        let image = try AnalysisPosterRenderer.render(report: TasteProfilePreviewFixtures.sparse)
        let url = try store.write(image, id: "preview:unsafe/id")
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(url.pathExtension == "png")
        store.remove(url)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("Add-only photo save reports success, denial and write failure explicitly")
    func photoSaveOutcomes() async throws {
        let image = try AnalysisPosterRenderer.render(report: TasteProfilePreviewFixtures.sparse)
        var saveCount = 0
        let success = AnalysisPosterPhotoSaver(
            authorizationStatus: { .authorized },
            requestAuthorization: { .authorized },
            performSave: { _ in saveCount += 1 }
        )
        try await success.save(image)
        #expect(saveCount == 1)

        let denied = AnalysisPosterPhotoSaver(
            authorizationStatus: { .denied }, requestAuthorization: { .denied }, performSave: { _ in }
        )
        await #expect(throws: AnalysisPosterSaveError.permissionDenied) { try await denied.save(image) }

        struct WriteFailure: Error {}
        let failing = AnalysisPosterPhotoSaver(
            authorizationStatus: { .authorized }, requestAuthorization: { .authorized },
            performSave: { _ in throw WriteFailure() }
        )
        await #expect(throws: AnalysisPosterSaveError.saveFailed) { try await failing.save(image) }
    }

    @Test("Offline image resolution falls back without requiring a transfer coordinator")
    func offlineImageResolution() async {
        let resolved = await AnalysisPosterImageResolver.resolve(
            report: TasteProfilePreviewFixtures.rich, photosByID: [:], coordinator: nil
        )
        #expect(resolved.isEmpty)
    }

    private func copy(
        _ input: TasteProfileInput,
        restaurants: [TasteProfileInput.RestaurantRecord]? = nil,
        visits: [TasteProfileInput.VisitRecord]? = nil
    ) -> TasteProfileInput {
        TasteProfileInput(
            userDisplayName: input.userDisplayName,
            restaurants: restaurants ?? input.restaurants,
            visits: visits ?? input.visits,
            dishes: input.dishes,
            visitDishes: input.visitDishes,
            photos: input.photos,
            companions: input.companions,
            recommendationSources: input.recommendationSources
        )
    }

    private func representativeRoleInput() -> TasteProfileInput {
        let restaurants = (0..<4).map { index in
            TasteProfileInput.RestaurantRecord(
                id: uuid(20_000 + index), name: ["常去小馆", "最高分餐厅", "近期新店", "口味代表店"][index],
                address: "测试路 \(index) 号", city: "杭州", status: "visited",
                tags: index == 0 || index == 3 ? ["日料"] : [index == 1 ? "西餐" : "咖啡"],
                createdAt: day(-400), updatedAt: day(-1), deletedAt: nil
            )
        }
        var visits: [TasteProfileInput.VisitRecord] = []
        func append(_ restaurant: Int, count: Int, rating: Double?, startDay: Int) {
            for offset in 0..<count {
                visits.append(visit(
                    id: 21_000 + visits.count, restaurantID: restaurants[restaurant].id,
                    day: startDay - offset, rating: rating
                ))
            }
        }
        append(0, count: 4, rating: 3, startDay: -150)
        append(1, count: 1, rating: 5, startDay: -120)
        append(2, count: 1, rating: nil, startDay: -1)
        append(3, count: 2, rating: 4.5, startDay: -100)
        return TasteProfileInput(
            userDisplayName: "测试用户", restaurants: restaurants, visits: visits,
            dishes: [], visitDishes: [], photos: [], companions: [], recommendationSources: []
        )
    }

    private func performanceInput() -> TasteProfileInput {
        let cuisineTags = ["日料", "火锅", "川菜", "西餐", "咖啡", "粤菜"]
        let restaurants = (0..<200).map { index in
            TasteProfileInput.RestaurantRecord(
                id: uuid(30_000 + index), name: "性能餐厅 \(index)",
                address: "性能路 \(index) 号", city: "杭州", status: "visited",
                tags: [cuisineTags[index % cuisineTags.count]],
                createdAt: day(-700 + index), updatedAt: day(-index % 90), deletedAt: nil
            )
        }
        let visits = (0..<1_000).map { index in
            visit(
                id: 40_000 + index, restaurantID: restaurants[index % restaurants.count].id,
                day: -(index % 700), rating: index % 6 == 0 ? nil : Double(6 + index % 5) / 2
            )
        }
        let dishes = (0..<500).map { index in
            TasteProfileInput.DishRecord(
                id: uuid(50_000 + index), restaurantID: restaurants[index % 200].id,
                originVisitID: visits[index].id, name: "真实菜品 \(index)", taste: "风味 \(index % 12)",
                rating: index % 5 == 0 ? nil : 4, updatedAt: day(-(index % 300)), deletedAt: nil
            )
        }
        let associations = (0..<500).map { index in
            TasteProfileInput.VisitDishRecord(
                visitID: visits[index].id, dishID: dishes[index].id,
                sortOrder: index % 5, deletedAt: nil
            )
        }
        let photos = (0..<500).map { index in
            TasteProfileInput.PhotoRecord(
                id: uuid(60_000 + index), restaurantID: restaurants[index % 200].id,
                visitID: visits[index].id, dishID: dishes[index].id,
                kind: "dish", sortOrder: index % 4,
                updatedAt: day(-(index % 300)), deletedAt: nil
            )
        }
        return TasteProfileInput(
            userDisplayName: "性能测试", restaurants: restaurants, visits: visits,
            dishes: dishes, visitDishes: associations, photos: photos,
            companions: [], recommendationSources: []
        )
    }

    private func visit(
        id: Int,
        restaurantID: UUID,
        day offset: Int,
        rating: Double?
    ) -> TasteProfileInput.VisitRecord {
        TasteProfileInput.VisitRecord(
            id: uuid(id), restaurantID: restaurantID, visitedAt: day(offset),
            rating: rating, valueRating: rating, environmentRating: nil,
            serviceRating: nil, myActualSpend: id.isMultiple(of: 7) ? nil : Decimal(50 + id % 600),
            diningMode: "dineIn", diningOccasionLabels: [id.isMultiple(of: 2) ? "朋友聚餐" : "日常吃饭"],
            diningOccasionText: nil, valueTags: ["合理"], environmentTags: ["舒适"],
            serviceTags: [], noiseLevelLabel: "正常", companionIDs: [], companionNames: [],
            recommendationSourceID: nil, recommendationSourceTypeLabel: nil,
            recommendationSourceText: nil, createdAt: day(offset), updatedAt: day(offset), deletedAt: nil
        )
    }

    private func day(_ offset: Int) -> Date {
        Calendar(identifier: .gregorian).date(
            byAdding: .day, value: offset, to: TasteProfilePreviewFixtures.now
        ) ?? TasteProfilePreviewFixtures.now
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}
