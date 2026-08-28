import Foundation

#if DEBUG
nonisolated enum MonthlyRecapPreviewFixtures {
    static let calendar: Calendar = {
        var value = Calendar(identifier: .gregorian)
        value.locale = Locale(identifier: "zh_Hans_CN")
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }()
    static let now = date(year: 2026, month: 8, day: 28, hour: 20)
    static let currentPeriod = MonthlyPeriod(year: 2026, month: 8, calendar: calendar)
    static let previousPeriod = currentPeriod.previous

    static let rich = MonthlyRecapAnalyzer.analyze(input(), period: currentPeriod, now: now)
    static let withAssetImages = replacePhotos(in: rich)
    static let sparse = MonthlyRecapAnalyzer.analyze(
        input(currentLimit: 2, previousLimit: 1), period: currentPeriod, now: now
    )
    static let empty = MonthlyRecapAnalyzer.analyze(
        input(currentLimit: 0, previousLimit: 5), period: currentPeriod, now: now
    )
    static let past = MonthlyRecapAnalyzer.analyze(input(), period: previousPeriod, now: now)
    static let noNew = MonthlyRecapAnalyzer.analyze(
        input(addPriorVisitsForEveryRestaurant: true), period: currentPeriod, now: now
    )
    static let highRepeat = MonthlyRecapAnalyzer.analyze(
        input(highRepeatOnly: true), period: currentPeriod, now: now
    )
    static let noCompanion = MonthlyRecapAnalyzer.analyze(
        input(includeCompanions: false), period: currentPeriod, now: now
    )
    static let noSource = MonthlyRecapAnalyzer.analyze(
        input(includeSources: false), period: currentPeriod, now: now
    )
    static let lowSpendCoverage = MonthlyRecapAnalyzer.analyze(
        input(spendMode: .lowCoverage), period: currentPeriod, now: now
    )
    static let noSpend = MonthlyRecapAnalyzer.analyze(
        input(spendMode: .none), period: currentPeriod, now: now
    )
    static let noComparison = MonthlyRecapAnalyzer.analyze(
        input(previousLimit: 0), period: currentPeriod, now: now
    )
    static let noPhoto = MonthlyRecapAnalyzer.analyze(
        input(includePhotos: false), period: currentPeriod, now: now
    )
    static let longNames = MonthlyRecapAnalyzer.analyze(
        input(longNames: true), period: currentPeriod, now: now
    )

    enum SpendMode { case full, lowCoverage, none }

    static func input(
        currentLimit: Int = 12,
        previousLimit: Int = 6,
        includeCompanions: Bool = true,
        includeSources: Bool = true,
        includePhotos: Bool = true,
        spendMode: SpendMode = .full,
        addPriorVisitsForEveryRestaurant: Bool = false,
        highRepeatOnly: Bool = false,
        longNames: Bool = false
    ) -> MonthlyRecapInput {
        let companionA = MonthlyRecapInput.CompanionRecord(
            id: uuid(8_001), identifiers: [uuid(8_001).uuidString.lowercased(), "preview-companion-a"],
            displayName: "小林", updatedAt: now, deletedAt: nil
        )
        let companionB = MonthlyRecapInput.CompanionRecord(
            id: uuid(8_002), identifiers: [uuid(8_002).uuidString.lowercased(), "preview-companion-b"],
            displayName: "妈妈", updatedAt: now, deletedAt: nil
        )
        let sourceA = MonthlyRecapInput.SourceRecord(
            id: uuid(8_011), identifiers: [uuid(8_011).uuidString.lowercased(), "preview-source-a"],
            displayName: "小林的私藏清单", sourceType: .friend, updatedAt: now, deletedAt: nil
        )
        let sourceB = MonthlyRecapInput.SourceRecord(
            id: uuid(8_012), identifiers: [uuid(8_012).uuidString.lowercased(), "preview-source-b"],
            displayName: "城市胃口研究所", sourceType: .blogger, updatedAt: now, deletedAt: nil
        )
        let names = [
            "山葵小料理", "红炉火锅", "树影咖啡", "河岸牛排馆", "云朵寿喜烧", "巷口炉端烧",
        ]
        let tags = [
            ["日料", "烧鸟"], ["火锅", "川菜"], ["咖啡", "甜点"],
            ["西餐", "牛排"], ["日料", "寿喜烧"], ["日料", "烧烤"],
        ]
        let restaurants = names.enumerated().map { index, name in
            MonthlyRecapInput.RestaurantRecord(
                id: uuid(8_100 + index),
                name: longNames && index == 0 ? "一间名字特别特别长但每个月还是会想回去很多次的山葵小料理店" : name,
                city: index == 3 ? "上海" : "杭州", status: .visited, tags: tags[index],
                createdAt: date(year: 2026, month: index < 2 ? 7 : 8, day: 1 + index),
                updatedAt: now, deletedAt: nil
            )
        }

        let currentPlan = highRepeatOnly
            ? Array(repeating: 0, count: 10)
            : [0, 0, 1, 4, 0, 2, 5, 1, 4, 3, 0, 5]
        let currentRatings: [Double?] = [4.5, 5, 4, 4.5, 4.5, 4, nil, 4.5, 5, 4, 4.5, 4]
        let currentSpends: [Decimal] = [188, 236, 168, 128, 198, 68, 258, 176, 132, 398, 186, 210]
        let currentVisits = currentPlan.prefix(currentLimit).enumerated().map { index, restaurantIndex in
            let source = index.isMultiple(of: 3) ? sourceB : sourceA
            let companionIDs = includeCompanions
                ? ([companionA.identifiers.last!] + (index.isMultiple(of: 4) ? [companionB.identifiers.last!] : [])) : []
            let companionNames = includeCompanions
                ? ([companionA.displayName] + (index.isMultiple(of: 4) ? [companionB.displayName] : [])) : []
            let spend: Decimal?
            switch spendMode {
            case .full: spend = currentSpends[index]
            case .lowCoverage: spend = index == 0 ? currentSpends[index] : nil
            case .none: spend = nil
            }
            return visit(
                id: 8_200 + index, restaurantID: restaurants[restaurantIndex].id,
                year: 2026, month: 8, day: 2 + index * 2,
                rating: currentRatings[index], spend: spend,
                companionIDs: companionIDs, companionNames: companionNames,
                source: includeSources ? source : nil,
                occasions: index.isMultiple(of: 3) ? ["朋友聚餐"] : ["日常吃饭"]
            )
        }

        let previousPlan = [0, 1, 1, 2, 3, 1]
        var previousVisits = previousPlan.prefix(previousLimit).enumerated().map { index, restaurantIndex in
            visit(
                id: 8_300 + index, restaurantID: restaurants[restaurantIndex].id,
                year: 2026, month: 7, day: 3 + index * 4,
                rating: [4.0, 4.0, 4.5, 3.5, 4.0, 4.0][index],
                spend: Decimal(120 + index * 18),
                companionIDs: includeCompanions ? [companionB.identifiers.last!] : [],
                companionNames: includeCompanions ? [companionB.displayName] : [],
                source: includeSources ? sourceB : nil,
                occasions: ["朋友聚餐"]
            )
        }
        if addPriorVisitsForEveryRestaurant {
            previousVisits += restaurants.enumerated().map { index, restaurant in
                visit(
                    id: 8_350 + index, restaurantID: restaurant.id,
                    year: 2026, month: 6, day: 2 + index,
                    rating: 4, spend: nil, companionIDs: [], companionNames: [], source: nil,
                    occasions: []
                )
            }
        }
        if highRepeatOnly {
            previousVisits = [visit(
                id: 8_399, restaurantID: restaurants[0].id, year: 2026, month: 7, day: 5,
                rating: 4.5, spend: 180, companionIDs: [], companionNames: [], source: nil,
                occasions: []
            )]
        }

        let allVisits = previousVisits + currentVisits
        let dishes = currentVisits.prefix(5).enumerated().map { index, visit in
            MonthlyRecapInput.DishRecord(
                id: uuid(8_500 + index), restaurantID: visit.restaurantID,
                originVisitID: visit.id,
                name: ["炭烤鸡腿葱串", "蓝鳍金枪鱼手卷", "麻辣牛肉", "抹茶布丁", "寿喜烧"][index],
                taste: ["咸鲜炭香", "清爽", "麻辣", "奶香", "浓郁"][index],
                rating: [4.5, 5, 4, 4.5, 5][index], updatedAt: now, deletedAt: nil
            )
        }
        let associations = dishes.map {
            MonthlyRecapInput.VisitDishRecord(visitID: $0.originVisitID, dishID: $0.id, deletedAt: nil)
        }
        let photos = includePhotos ? dishes.enumerated().map { index, dish in
            MonthlyRecapInput.PhotoRecord(
                id: uuid(8_600 + index), restaurantID: dish.restaurantID,
                visitID: dish.originVisitID, dishID: dish.id, kind: .dish,
                sortOrder: index, updatedAt: now, deletedAt: nil
            )
        } : []
        return MonthlyRecapInput(
            userDisplayName: "Lafayette",
            restaurants: restaurants, visits: allVisits, dishes: dishes,
            visitDishes: associations, photos: photos,
            companions: includeCompanions ? [companionA, companionB] : [],
            recommendationSources: includeSources ? [sourceA, sourceB] : []
        )
    }

    private static func visit(
        id: Int,
        restaurantID: UUID,
        year: Int,
        month: Int,
        day: Int,
        rating: Double?,
        spend: Decimal?,
        companionIDs: [String],
        companionNames: [String],
        source: MonthlyRecapInput.SourceRecord?,
        occasions: [String]
    ) -> MonthlyRecapInput.VisitRecord {
        let time = date(year: year, month: month, day: day, hour: 19)
        return MonthlyRecapInput.VisitRecord(
            id: uuid(id), restaurantID: restaurantID, visitedAt: time,
            rating: rating, valueRating: rating.map { max(0.5, $0 - 0.5) },
            environmentRating: rating, serviceRating: rating,
            myActualSpend: spend, note: id.isMultiple(of: 3) ? "这一餐很值得记住" : nil,
            diningOccasionLabels: occasions,
            companionIDs: companionIDs, companionNames: companionNames,
            recommendationSourceID: source?.identifiers.last,
            recommendationSourceType: source?.sourceType,
            recommendationSourceText: source?.displayName,
            updatedAt: time, deletedAt: nil
        )
    }

    private static func replacePhotos(in report: MonthlyRecapAnalysis) -> MonthlyRecapAnalysis {
        let assets = [FoodHeroTheme.japanese.assetName, FoodHeroTheme.hotpotGrill.assetName, FoodHeroTheme.cafe.assetName, FoodHeroTheme.western.assetName]
        let mapped = report.representativeRestaurants.enumerated().map { index, story in
            replace(story, image: .asset(assets[index % assets.count]))
        }
        let map = Dictionary(uniqueKeysWithValues: mapped.map { ($0.id, $0) })
        return MonthlyRecapAnalysis(
            id: report.id + ":assets", kind: report.kind, userDisplayName: report.userDisplayName,
            period: report.period, comparisonPeriod: report.comparisonPeriod,
            isCurrentPeriod: report.isCurrentPeriod, periodLabel: report.periodLabel,
            visitCount: report.visitCount, restaurantCount: report.restaurantCount,
            newRestaurantCount: report.newRestaurantCount, repeatRestaurantCount: report.repeatRestaurantCount,
            spend: report.spend,
            favoriteRestaurant: report.favoriteRestaurant.flatMap { map[$0.id] ?? replace($0, image: .asset(assets[0])) },
            mostVisitedRestaurant: report.mostVisitedRestaurant.flatMap { map[$0.id] ?? replace($0, image: .asset(assets[1])) },
            newRestaurants: report.newRestaurants.map { map[$0.id] ?? replace($0, image: .asset(assets[2])) },
            topCompanion: report.topCompanion, recommendationStory: report.recommendationStory,
            tasteChange: report.tasteChange, keywords: report.keywords,
            highlight: report.highlight.flatMap { map[$0.id] ?? replace($0, image: .asset(assets[3])) },
            representativeRestaurants: mapped, sufficiency: report.sufficiency,
            tasteChangeSufficiency: report.tasteChangeSufficiency, dataNote: report.dataNote,
            generatedAt: report.generatedAt
        )
    }

    private static func replace(
        _ story: MonthlyRestaurantStory,
        image: AnalysisImageReference
    ) -> MonthlyRestaurantStory {
        MonthlyRestaurantStory(
            id: story.id, name: story.name, city: story.city, role: story.role,
            detail: story.detail, visitCount: story.visitCount,
            averageRating: story.averageRating, latestVisitAt: story.latestVisitAt,
            isNew: story.isNew, imageReference: image
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
