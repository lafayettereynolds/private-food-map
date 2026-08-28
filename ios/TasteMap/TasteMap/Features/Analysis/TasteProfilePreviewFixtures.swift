#if DEBUG
import Foundation

nonisolated enum TasteProfilePreviewFixtures {
    static let now = Date(timeIntervalSince1970: 1_780_000_000)

    static var rich: TasteProfileAnalysis {
        TasteProfileAnalyzer.analyze(input(visitCount: 18), now: now, calendar: shanghaiCalendar)
    }

    static var emerging: TasteProfileAnalysis {
        TasteProfileAnalyzer.analyze(input(visitCount: 3), now: now, calendar: shanghaiCalendar)
    }

    static var medium: TasteProfileAnalysis {
        TasteProfileAnalyzer.analyze(input(visitCount: 8), now: now, calendar: shanghaiCalendar)
    }

    static var sparse: TasteProfileAnalysis {
        TasteProfileAnalyzer.analyze(input(visitCount: 1, includeContext: false), now: now, calendar: shanghaiCalendar)
    }

    static var empty: TasteProfileAnalysis {
        TasteProfileAnalyzer.analyze(input(visitCount: 0), now: now, calendar: shanghaiCalendar)
    }

    static var noPhotos: TasteProfileAnalysis {
        TasteProfileAnalyzer.analyze(input(visitCount: 12, includePhotos: false), now: now, calendar: shanghaiCalendar)
    }

    static var longContent: TasteProfileAnalysis {
        TasteProfileAnalyzer.analyze(
            input(visitCount: 18, longNames: true), now: now, calendar: shanghaiCalendar
        )
    }

    static var singlePreference: TasteProfileAnalysis {
        let source = input(visitCount: 18)
        let restaurantID = ids.restaurant1
        let visits = source.visits.filter { $0.restaurantID == restaurantID }
        let visitIDs = Set(visits.map(\.id))
        let dishes = source.dishes.filter { $0.restaurantID == restaurantID }
        let dishIDs = Set(dishes.map(\.id))
        let selected = TasteProfileInput(
            userDisplayName: source.userDisplayName,
            restaurants: source.restaurants.filter { $0.id == restaurantID },
            visits: visits,
            dishes: dishes,
            visitDishes: source.visitDishes.filter { visitIDs.contains($0.visitID) && dishIDs.contains($0.dishID) },
            photos: source.photos.filter { $0.restaurantID == restaurantID },
            companions: source.companions,
            recommendationSources: source.recommendationSources
        )
        return TasteProfileAnalyzer.analyze(selected, now: now, calendar: shanghaiCalendar)
    }

    static var highRepeat: TasteProfileAnalysis {
        TasteProfileAnalyzer.analyze(input(visitCount: 28), now: now, calendar: shanghaiCalendar)
    }

    static var noPeopleOrSources: TasteProfileAnalysis {
        TasteProfileAnalyzer.analyze(
            input(visitCount: 12, includeContext: false), now: now, calendar: shanghaiCalendar
        )
    }

    static var withAssetImages: TasteProfileAnalysis {
        replacingImages(in: rich)
    }

    static func input(
        visitCount: Int,
        includeContext: Bool = true,
        includePhotos: Bool = true,
        longNames: Bool = false
    ) -> TasteProfileInput {
        let restaurants = [
            TasteProfileInput.RestaurantRecord(
                id: ids.restaurant1,
                name: longNames ? "巷口那家总要提前排队但每次都值得的炭火烧鸟与季节料理" : "山葵小料理",
                address: "上海市徐汇区安福路 18 号", city: "上海", status: "visited",
                tags: ["日料", "居酒屋", "安静"], createdAt: day(-320), updatedAt: day(-3), deletedAt: nil
            ),
            TasteProfileInput.RestaurantRecord(
                id: ids.restaurant2,
                name: longNames ? "朋友们一致决定下次还要再来的重庆老火锅旗舰总店" : "红炉火锅",
                address: "上海市静安区愚园路 90 号", city: "上海", status: "visited",
                tags: ["火锅", "川菜", "朋友聚餐"], createdAt: day(-280), updatedAt: day(-8), deletedAt: nil
            ),
            TasteProfileInput.RestaurantRecord(
                id: ids.restaurant3,
                name: longNames ? "从清晨第一杯手冲咖啡坐到傍晚甜点出炉的小小客厅" : "树影咖啡",
                address: "上海市长宁区新华路 62 号", city: "上海", status: "visited",
                tags: ["咖啡", "甜点", "早午餐"], createdAt: day(-220), updatedAt: day(-15), deletedAt: nil
            ),
            TasteProfileInput.RestaurantRecord(
                id: ids.restaurant4,
                name: "河岸牛排馆", address: "上海市黄浦区中山东一路 6 号", city: "上海", status: "visited",
                tags: ["西餐", "牛排", "约会"], createdAt: day(-180), updatedAt: day(-25), deletedAt: nil
            ),
        ]

        let visits = (0..<visitCount).map { index -> TasteProfileInput.VisitRecord in
            let restaurantIDs = [ids.restaurant1, ids.restaurant1, ids.restaurant2, ids.restaurant1, ids.restaurant3, ids.restaurant2, ids.restaurant4]
            let restaurantID = restaurantIDs[index % restaurantIDs.count]
            let companion = includeContext && index % 3 != 2 ? ["小林"] : []
            let source = includeContext && index % 2 == 0 ? "朋友推荐" : nil
            let spendValues: [Decimal?] = [188, 236, 128, nil, 68, 210, 398]
            let ratings: [Double?] = [4.5, 4, 4.5, nil, 4, 5, 4]
            return TasteProfileInput.VisitRecord(
                id: uuid(100 + index), restaurantID: restaurantID,
                visitedAt: day(-index * 13, hour: index % 4 == 0 ? 13 : 19),
                rating: ratings[index % ratings.count],
                valueRating: index % 2 == 0 ? 4 : nil,
                environmentRating: index % 3 == 0 ? 4.5 : nil,
                serviceRating: index % 4 == 0 ? 4 : nil,
                myActualSpend: spendValues[index % spendValues.count],
                diningMode: "dineIn",
                diningOccasionLabels: includeContext ? [index % 3 == 0 ? "朋友聚餐" : "日常吃饭"] : [],
                diningOccasionText: nil,
                valueTags: includeContext ? ["值得再去"] : [],
                environmentTags: includeContext ? [index % 2 == 0 ? "舒服" : "热闹"] : [],
                serviceTags: includeContext ? ["细心"] : [],
                noiseLevelLabel: includeContext ? "适中" : nil,
                companionIDs: [], companionNames: companion,
                recommendationSourceID: nil,
                recommendationSourceTypeLabel: source,
                recommendationSourceText: nil,
                createdAt: day(-index * 13), updatedAt: day(-index * 13), deletedAt: nil
            )
        }

        let dishes = [
            TasteProfileInput.DishRecord(
                id: ids.dish1, restaurantID: ids.restaurant1,
                originVisitID: visits.first?.id ?? uuid(900), name: "炭烤鸡腿葱串", taste: "咸鲜炭香",
                rating: 4.5, updatedAt: day(-3), deletedAt: nil
            ),
            TasteProfileInput.DishRecord(
                id: ids.dish2, restaurantID: ids.restaurant2,
                originVisitID: visits.dropFirst(2).first?.id ?? uuid(901), name: "鲜切吊龙", taste: "麻辣鲜嫩",
                rating: 4.5, updatedAt: day(-8), deletedAt: nil
            ),
        ]
        let associations = visits.enumerated().compactMap { index, visit -> TasteProfileInput.VisitDishRecord? in
            let dishID: UUID?
            if visit.restaurantID == ids.restaurant1 { dishID = ids.dish1 }
            else if visit.restaurantID == ids.restaurant2 { dishID = ids.dish2 }
            else { dishID = nil }
            return dishID.map {
                TasteProfileInput.VisitDishRecord(visitID: visit.id, dishID: $0, sortOrder: index, deletedAt: nil)
            }
        }
        let photos: [TasteProfileInput.PhotoRecord] = includePhotos ? [
            .init(
                id: ids.photo1, restaurantID: ids.restaurant1, visitID: visits.first?.id,
                dishID: ids.dish1, kind: "dish", sortOrder: 0, updatedAt: day(-3), deletedAt: nil
            ),
            .init(
                id: ids.photo2, restaurantID: ids.restaurant2, visitID: visits.dropFirst(2).first?.id,
                dishID: ids.dish2, kind: "visit", sortOrder: 0, updatedAt: day(-8), deletedAt: nil
            ),
        ] : []

        return TasteProfileInput(
            userDisplayName: longNames ? "一位认真记录每一顿饭也愿意把故事讲得很长的 Taste Map 用户" : "Lafayette",
            restaurants: restaurants,
            visits: visits,
            dishes: dishes,
            visitDishes: associations,
            photos: photos,
            companions: includeContext ? [
                .init(identifiers: ["companion-lin"], displayName: "小林", deletedAt: nil),
            ] : [],
            recommendationSources: includeContext ? [
                .init(identifiers: ["source-friend"], displayName: "朋友推荐", deletedAt: nil),
            ] : []
        )
    }

    private static var shanghaiCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private static func day(_ offset: Int, hour: Int = 19) -> Date {
        var components = shanghaiCalendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        let start = shanghaiCalendar.date(from: components) ?? now
        return shanghaiCalendar.date(byAdding: .day, value: offset, to: start) ?? start
    }

    private static func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }

    private static func replacingImages(in report: TasteProfileAnalysis) -> TasteProfileAnalysis {
        let hero = FoodHeroPresentation(
            theme: report.hero.theme,
            primaryTheme: report.hero.primaryTheme,
            secondaryThemes: report.hero.secondaryThemes,
            labels: report.hero.labels,
            imageReferences: [.asset(report.hero.fallbackAssetName)],
            fallbackAssetName: report.hero.fallbackAssetName,
            tone: report.hero.tone
        )
        let restaurants = report.restaurants.enumerated().map { index, restaurant in
            RepresentativeRestaurant(
                id: restaurant.id, name: restaurant.name, role: restaurant.role,
                detail: restaurant.detail, averageRating: restaurant.averageRating,
                visitCount: restaurant.visitCount,
                imageReference: .asset(["FoodHeroJapanese", "FoodHeroHotpotGrill", "FoodHeroCafe"][index % 3])
            )
        }
        return TasteProfileAnalysis(
            id: report.id + ":asset-images", kind: report.kind,
            userDisplayName: report.userDisplayName, title: report.title,
            eyebrow: report.eyebrow, subtitle: report.subtitle, summary: report.summary,
            generatedAt: report.generatedAt, visitCount: report.visitCount,
            ratedVisitCount: report.ratedVisitCount, sufficiency: report.sufficiency,
            favoriteStatement: report.favoriteStatement, cuisineRanking: report.cuisineRanking,
            spend: report.spend, diningScenes: report.diningScenes,
            recommendationSources: report.recommendationSources, companions: report.companions,
            ratingStyle: report.ratingStyle, repeatAnalysis: report.repeatAnalysis,
            diningTime: report.diningTime, keywords: report.keywords, hero: hero,
            callouts: report.callouts, insights: report.insights, restaurants: restaurants,
            dataNote: report.dataNote, footer: report.footer
        )
    }

    private nonisolated enum ids {
        static let restaurant1 = uuid(1)
        static let restaurant2 = uuid(2)
        static let restaurant3 = uuid(3)
        static let restaurant4 = uuid(4)
        static let dish1 = uuid(10)
        static let dish2 = uuid(11)
        static let photo1 = uuid(20)
        static let photo2 = uuid(21)
    }
}
#endif
