import Foundation

#if DEBUG
nonisolated enum AnnualRecapPreviewFixtures {
    static let calendar: Calendar = {
        var value = Calendar(identifier: .gregorian)
        value.locale = Locale(identifier: "zh_Hans_CN")
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }()
    static let now = date(year: 2026, month: 8, day: 28, hour: 20)
    static let currentPeriod = AnnualPeriod(year: 2026, calendar: calendar)
    static let previousPeriod = currentPeriod.previous

    static let rich = AnnualRecapAnalyzer.analyze(input(), period: currentPeriod, now: now)
    static let withAssetImages = replaceImages(in: rich)
    static let partial = AnnualRecapAnalyzer.analyze(input(visitLimit: 10), period: currentPeriod, now: now)
    static let past = AnnualRecapAnalyzer.analyze(input(year: 2025), period: previousPeriod, now: now)
    static let sparse = AnnualRecapAnalyzer.analyze(input(visitLimit: 3), period: currentPeriod, now: now)
    static let empty = AnnualRecapAnalyzer.analyze(input(visitLimit: 0), period: currentPeriod, now: now)
    static let highExploration = AnnualRecapAnalyzer.analyze(input(addPriorVisits: false), period: currentPeriod, now: now)
    static let highRepeat = AnnualRecapAnalyzer.analyze(input(highRepeat: true), period: currentPeriod, now: now)
    static let multiCuisine = rich
    static let singleCuisine = AnnualRecapAnalyzer.analyze(input(singleCuisine: true), period: currentPeriod, now: now)
    static let noCompanion = AnnualRecapAnalyzer.analyze(input(includeCompanions: false), period: currentPeriod, now: now)
    static let noSource = AnnualRecapAnalyzer.analyze(input(includeSources: false), period: currentPeriod, now: now)
    static let insufficientSources = AnnualRecapAnalyzer.analyze(input(sourceRestaurantLimit: 4), period: currentPeriod, now: now)
    static let lowSpendCoverage = AnnualRecapAnalyzer.analyze(input(spendMode: .lowCoverage), period: currentPeriod, now: now)
    static let noPhoto = AnnualRecapAnalyzer.analyze(input(includePhotos: false), period: currentPeriod, now: now)
    static let longNames = AnnualRecapAnalyzer.analyze(input(longNames: true), period: currentPeriod, now: now)

    enum SpendMode { case highCoverage, lowCoverage }

    static func input(
        year: Int = 2026,
        visitLimit: Int = 30,
        includeCompanions: Bool = true,
        includeSources: Bool = true,
        includePhotos: Bool = true,
        spendMode: SpendMode = .highCoverage,
        addPriorVisits: Bool = true,
        highRepeat: Bool = false,
        singleCuisine: Bool = false,
        longNames: Bool = false,
        sourceRestaurantLimit: Int = 12
    ) -> MonthlyRecapInput {
        let companionA = MonthlyRecapInput.CompanionRecord(
            id: uuid(9_001), identifiers: [uuid(9_001).uuidString.lowercased(), "annual-companion-a"],
            displayName: "小林", updatedAt: now, deletedAt: nil
        )
        let companionB = MonthlyRecapInput.CompanionRecord(
            id: uuid(9_002), identifiers: [uuid(9_002).uuidString.lowercased(), "annual-companion-b"],
            displayName: "妈妈", updatedAt: now, deletedAt: nil
        )
        let sourceA = MonthlyRecapInput.SourceRecord(
            id: uuid(9_011), identifiers: [uuid(9_011).uuidString.lowercased(), "annual-source-a"],
            displayName: "小林的年度私藏", sourceType: .friend, updatedAt: now, deletedAt: nil
        )
        let sourceB = MonthlyRecapInput.SourceRecord(
            id: uuid(9_012), identifiers: [uuid(9_012).uuidString.lowercased(), "annual-source-b"],
            displayName: "深夜踩坑收藏夹", sourceType: .other, updatedAt: now, deletedAt: nil
        )
        let names = ["山葵小料理", "红炉火锅", "树影咖啡", "河岸牛排馆", "云朵寿喜烧", "巷口炉端烧",
                     "青梅小馆", "野火烧鸟", "白露面包房", "小满食堂", "雨巷面馆", "南山烤肉"]
        let tags = [
            ["日料", "寿司"], ["火锅", "川菜"], ["咖啡", "甜点"], ["西餐", "牛排"],
            ["日料", "寿喜烧"], ["烧烤", "日料"], ["江浙菜", "朋友聚餐"], ["烧鸟", "日料"],
            ["咖啡", "烘焙"], ["家常菜", "日常吃饭"], ["面食", "川菜"], ["烧烤", "朋友聚餐"],
        ]
        let restaurants = names.enumerated().map { index, name in
            MonthlyRecapInput.RestaurantRecord(
                id: uuid(9_100 + index),
                name: longNames && index == 0 ? "这一年反复回去而且名字特别特别长的山葵小料理与四季炭火料理店" : name,
                city: index.isMultiple(of: 4) ? "上海" : "杭州", status: .visited,
                tags: singleCuisine ? ["日料"] : tags[index],
                createdAt: date(year: year, month: 1 + index % 8, day: 2),
                updatedAt: now, deletedAt: nil
            )
        }
        let normalPlan = [0, 0, 1, 2, 3, 0, 4, 5, 6, 0, 1, 7, 8, 2, 9, 0, 10, 11, 4, 5, 6, 0, 7, 8, 9, 1, 10, 11, 0, 4]
        let plan = highRepeat ? Array(repeating: 0, count: 24) : normalPlan
        let ratingsA: [Double?] = [4.5, 5, 4.5, 4, 4.5, 5]
        let ratingsB: [Double?] = [2, 2.5, 2, 3, 2.5, 2]
        let visits = plan.prefix(visitLimit).enumerated().map { index, restaurantIndex -> MonthlyRecapInput.VisitRecord in
            let month = 1 + (index % 8)
            let source: MonthlyRecapInput.SourceRecord? = includeSources && restaurantIndex < sourceRestaurantLimit
                ? (restaurantIndex < 6 ? sourceA : sourceB) : nil
            let rating: Double? = restaurantIndex < 6 ? ratingsA[restaurantIndex % 6] : ratingsB[restaurantIndex % 6]
            let spend: Decimal? = spendMode == .highCoverage || index.isMultiple(of: 4)
                ? Decimal(88 + (index % 9) * 34) : nil
            return visit(
                id: 9_300 + index, restaurantID: restaurants[restaurantIndex].id,
                year: year, month: month, day: 2 + (index % 3) * 8,
                rating: rating, spend: spend,
                companionIDs: includeCompanions
                    ? [companionA.identifiers.last!] + (index.isMultiple(of: 5) ? [companionB.identifiers.last!] : []) : [],
                companionNames: includeCompanions
                    ? [companionA.displayName] + (index.isMultiple(of: 5) ? [companionB.displayName] : []) : [],
                source: source,
                occasions: index.isMultiple(of: 3) ? ["朋友聚餐"] : ["日常吃饭"]
            )
        }
        var allVisits = visits
        if addPriorVisits {
            allVisits += restaurants.prefix(4).enumerated().map { index, restaurant in
                visit(
                    id: 9_700 + index, restaurantID: restaurant.id,
                    year: year - 1, month: 10 + index % 3, day: 3 + index,
                    rating: 4, spend: nil, companionIDs: [], companionNames: [],
                    source: nil, occasions: []
                )
            }
        }
        let dishes = visits.prefix(12).enumerated().map { index, visit in
            MonthlyRecapInput.DishRecord(
                id: uuid(9_500 + index), restaurantID: visit.restaurantID, originVisitID: visit.id,
                name: ["炭烤鸡腿串", "蓝鳍金枪鱼手卷", "麻辣牛肉", "抹茶布丁"][index % 4],
                taste: ["咸鲜", "清爽", "麻辣", "奶香"][index % 4],
                rating: [4.5, 5, 4, 4.5][index % 4], updatedAt: now, deletedAt: nil
            )
        }
        let associations = dishes.map { MonthlyRecapInput.VisitDishRecord(visitID: $0.originVisitID, dishID: $0.id, deletedAt: nil) }
        let photos = includePhotos ? dishes.enumerated().map { index, dish in
            MonthlyRecapInput.PhotoRecord(
                id: uuid(9_600 + index), restaurantID: dish.restaurantID,
                visitID: dish.originVisitID, dishID: dish.id, kind: .dish,
                sortOrder: index, updatedAt: now, deletedAt: nil
            )
        } : []
        return MonthlyRecapInput(
            userDisplayName: "Lafayette", restaurants: restaurants, visits: allVisits,
            dishes: dishes, visitDishes: associations, photos: photos,
            companions: includeCompanions ? [companionA, companionB] : [],
            recommendationSources: includeSources ? [sourceA, sourceB] : []
        )
    }

    private static func visit(
        id: Int, restaurantID: UUID, year: Int, month: Int, day: Int,
        rating: Double?, spend: Decimal?, companionIDs: [String], companionNames: [String],
        source: MonthlyRecapInput.SourceRecord?, occasions: [String]
    ) -> MonthlyRecapInput.VisitRecord {
        let time = date(year: year, month: month, day: day, hour: 19)
        return MonthlyRecapInput.VisitRecord(
            id: uuid(id), restaurantID: restaurantID, visitedAt: time,
            rating: rating, valueRating: rating.map { max(0.5, $0 - 0.5) },
            environmentRating: rating, serviceRating: rating,
            myActualSpend: spend, note: id.isMultiple(of: 4) ? "这一餐是年度高光" : nil,
            diningOccasionLabels: occasions, companionIDs: companionIDs,
            companionNames: companionNames, recommendationSourceID: source?.identifiers.last,
            recommendationSourceType: source?.sourceType,
            recommendationSourceText: source?.displayName,
            updatedAt: time, deletedAt: nil
        )
    }

    private static func replaceImages(in report: AnnualRecapAnalysis) -> AnnualRecapAnalysis {
        let assets = [FoodHeroTheme.japanese.assetName, FoodHeroTheme.hotpotGrill.assetName,
                      FoodHeroTheme.cafe.assetName, FoodHeroTheme.western.assetName,
                      FoodHeroTheme.chinese.assetName, FoodHeroTheme.mixed.assetName]
        let mapped = report.representativeRestaurants.enumerated().map { index, value in
            replace(value, image: .asset(assets[index % assets.count]))
        }
        let storyMap = Dictionary(uniqueKeysWithValues: mapped.map { ($0.id, $0) })
        let milestones = report.tasteJourney.milestones.enumerated().map { index, value in
            AnnualTasteMilestone(
                id: value.id, periodLabel: value.periodLabel, title: value.title,
                detail: value.detail, month: value.month, visitCount: value.visitCount,
                restaurantID: value.restaurantID,
                imageReference: .asset(assets[index % assets.count])
            )
        }
        return AnnualRecapAnalysis(
            id: report.id + ":assets", kind: report.kind, userDisplayName: report.userDisplayName,
            period: report.period, isCurrentPeriod: report.isCurrentPeriod,
            periodLabel: report.periodLabel, visitCount: report.visitCount,
            restaurantCount: report.restaurantCount, newRestaurantCount: report.newRestaurantCount,
            repeatRestaurantCount: report.repeatRestaurantCount, explorationRate: report.explorationRate,
            spend: report.spend,
            favoriteRestaurant: report.favoriteRestaurant.map { storyMap[$0.id] ?? replace($0, image: .asset(assets[0])) },
            mostVisitedRestaurant: report.mostVisitedRestaurant.map { storyMap[$0.id] ?? replace($0, image: .asset(assets[1])) },
            topRestaurants: report.topRestaurants.map { storyMap[$0.id] ?? $0 },
            topCompanion: report.topCompanion,
            recommendationSummary: report.recommendationSummary,
            tasteJourney: AnnualTasteJourney(
                granularity: report.tasteJourney.granularity, milestones: milestones,
                changeSummaries: report.tasteJourney.changeSummaries,
                sufficiency: report.tasteJourney.sufficiency
            ),
            monthlySnapshots: report.monthlySnapshots, monthlyHighlights: report.monthlyHighlights,
            keywords: report.keywords, representativeRestaurants: mapped,
            sufficiency: report.sufficiency, dataNote: report.dataNote, generatedAt: report.generatedAt
        )
    }

    private static func replace(_ value: AnnualRestaurantStory, image: AnalysisImageReference) -> AnnualRestaurantStory {
        AnnualRestaurantStory(
            id: value.id, name: value.name, city: value.city, role: value.role,
            detail: value.detail, visitCount: value.visitCount,
            averageRating: value.averageRating, latestVisitAt: value.latestVisitAt,
            isNew: value.isNew, imageReference: image
        )
    }
    private static func date(year: Int, month: Int, day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
    private static func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}
#endif
