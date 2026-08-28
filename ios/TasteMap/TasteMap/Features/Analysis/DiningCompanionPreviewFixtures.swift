#if DEBUG
import Foundation

nonisolated enum DiningCompanionPreviewFixtures {
    static let now = Date(timeIntervalSince1970: 1_780_000_000)

    static var empty: DiningCompanionOverview {
        DiningCompanionAnalyzer.analyze(input(companionCount: 0, sharedVisitCount: 0), now: now, calendar: calendar)
    }

    static var singleVisit: DiningCompanionOverview {
        DiningCompanionAnalyzer.analyze(input(companionCount: 1, sharedVisitCount: 1), now: now, calendar: calendar)
    }

    static var rich: DiningCompanionOverview {
        DiningCompanionAnalyzer.analyze(input(companionCount: 3, sharedVisitCount: 14), now: now, calendar: calendar)
    }

    static var tenVisits: DiningCompanionOverview {
        DiningCompanionAnalyzer.analyze(input(companionCount: 1, sharedVisitCount: 10), now: now, calendar: calendar)
    }

    static var repeatedRestaurant: DiningCompanionOverview {
        DiningCompanionAnalyzer.analyze(
            input(companionCount: 1, sharedVisitCount: 10, onlyFirstRestaurant: true),
            now: now,
            calendar: calendar
        )
    }

    static var multiCuisine: DiningCompanionOverview { rich }

    static var singleCuisine: DiningCompanionOverview {
        DiningCompanionAnalyzer.analyze(
            input(companionCount: 1, sharedVisitCount: 8, onlyFirstRestaurant: true),
            now: now,
            calendar: calendar
        )
    }

    static var noDishes: DiningCompanionOverview {
        DiningCompanionAnalyzer.analyze(
            input(companionCount: 2, sharedVisitCount: 10, includeDishes: false),
            now: now,
            calendar: calendar
        )
    }

    static var withDishes: DiningCompanionOverview { rich }

    static var noPhotos: DiningCompanionOverview {
        DiningCompanionAnalyzer.analyze(
            input(companionCount: 2, sharedVisitCount: 10, includePhotos: false),
            now: now,
            calendar: calendar
        )
    }

    static var withPhotos: DiningCompanionOverview {
        replacingPhotos(in: rich)
    }

    static var longName: DiningCompanionOverview {
        DiningCompanionAnalyzer.analyze(
            input(
                companionCount: 2,
                sharedVisitCount: 12,
                leadName: "一位每次都愿意认真研究菜单也总能找到好吃小馆的朋友"
            ),
            now: now,
            calendar: calendar
        )
    }

    static var linkedAvatar: DiningCompanionOverview {
        DiningCompanionAnalyzer.analyze(
            input(companionCount: 1, sharedVisitCount: 8, linkedAvatar: .otter),
            now: now,
            calendar: calendar
        )
    }

    static var unlinkedAvatar: DiningCompanionOverview { tenVisits }

    static func input(
        companionCount: Int = 3,
        sharedVisitCount: Int = 14,
        includeDishes: Bool = true,
        includePhotos: Bool = true,
        onlyFirstRestaurant: Bool = false,
        leadName: String = "小林",
        linkedAvatar: ProfileAvatarPreset? = nil
    ) -> DiningCompanionInput {
        let allRestaurants = [
            restaurant(ids.restaurant1, "山葵小料理", "日料", status: .visited, preference: .favorite),
            restaurant(ids.restaurant2, "红炉火锅", "火锅", status: .visited, preference: .like),
            restaurant(ids.restaurant3, "炭火小串", "烧烤", status: .visited, preference: .like),
            restaurant(ids.restaurant4, "河岸牛排馆", "西餐", status: .visited, preference: .normal),
            restaurant(ids.restaurant5, "云朵寿喜烧", "日料", status: .wantToGo, preference: .like),
            restaurant(ids.restaurant6, "巷口炉端烧", "烧烤", status: .wantToGo, preference: .normal),
        ]
        let companionNames = [leadName, "妈妈", "一位名字稍微长一点的大学同学"]
        let companions = (0..<min(companionCount, companionNames.count)).map { index in
            DiningCompanionInput.CompanionRecord(
                id: ids.companions[index],
                identifiers: [ids.companions[index].uuidString.lowercased(), "companion-preview-\(index)"],
                displayName: companionNames[index],
                linkedTasteMapUserID: index == 0 && linkedAvatar != nil ? "tm_linked_friend" : nil,
                permittedLinkedAvatarPreset: index == 0 ? linkedAvatar : nil,
                updatedAt: day(-index),
                deletedAt: nil
            )
        }
        let visitedRestaurantIDs = onlyFirstRestaurant
            ? [ids.restaurant1]
            : [ids.restaurant1, ids.restaurant1, ids.restaurant2, ids.restaurant3, ids.restaurant1, ids.restaurant4]
        let ratings: [Double?] = [4.5, 4, 4.5, nil, 5, 4, 4.5]
        let spends: [Decimal?] = [188, 210, nil, 128, 236, 398, 168]
        let visits = (0..<sharedVisitCount).map { index -> DiningCompanionInput.VisitRecord in
            let restaurantID = visitedRestaurantIDs[index % visitedRestaurantIDs.count]
            var personIndexes = [0]
            if companionCount > 1, index % 3 == 0 { personIndexes.append(1) }
            if companionCount > 2, index % 5 == 0 { personIndexes.append(2) }
            let validIndexes = personIndexes.filter { $0 < companions.count }
            return DiningCompanionInput.VisitRecord(
                id: uuid(100 + index),
                restaurantID: restaurantID,
                visitedAt: day(-index * 15, hour: index % 4 == 0 ? 22 : 19),
                rating: ratings[index % ratings.count],
                valueRating: index.isMultiple(of: 2) ? 4.5 : nil,
                environmentRating: index.isMultiple(of: 3) ? 4 : nil,
                serviceRating: index.isMultiple(of: 4) ? 4.5 : nil,
                myActualSpend: spends[index % spends.count],
                diningMode: .dineIn,
                diningOccasionLabels: [index.isMultiple(of: 3) ? "朋友聚餐" : "日常吃饭"],
                environmentTags: [index.isMultiple(of: 2) ? "舒服" : "热闹"],
                noiseLevelLabel: index.isMultiple(of: 2) ? "适中" : "稍吵",
                companionIDs: validIndexes.map { companions[$0].identifiers[0] },
                companionNames: validIndexes.map { companions[$0].displayName },
                hasPrivateNote: index.isMultiple(of: 4),
                updatedAt: day(-index),
                deletedAt: nil
            )
        }
        let dishes: [DiningCompanionInput.DishRecord] = includeDishes && !visits.isEmpty ? [
            .init(
                id: ids.dish1, restaurantID: ids.restaurant1, originVisitID: visits[0].id,
                name: "炭烤鸡腿葱串", taste: "咸鲜炭香", rating: 4.5, updatedAt: day(-1), deletedAt: nil
            ),
            .init(
                id: ids.dish2, restaurantID: ids.restaurant2,
                originVisitID: visits.first(where: { $0.restaurantID == ids.restaurant2 })?.id ?? visits[0].id,
                name: "鲜切吊龙", taste: "麻辣鲜嫩", rating: 4.5, updatedAt: day(-2), deletedAt: nil
            ),
            .init(
                id: ids.dish3, restaurantID: ids.restaurant3,
                originVisitID: visits.first(where: { $0.restaurantID == ids.restaurant3 })?.id ?? visits[0].id,
                name: "盐烤鸡软骨", taste: "焦香", rating: 4, updatedAt: day(-3), deletedAt: nil
            ),
        ] : []
        let links = visits.enumerated().compactMap { index, visit -> DiningCompanionInput.VisitDishRecord? in
            guard includeDishes else { return nil }
            let dishID: UUID?
            switch visit.restaurantID {
            case ids.restaurant1: dishID = ids.dish1
            case ids.restaurant2: dishID = ids.dish2
            case ids.restaurant3: dishID = ids.dish3
            default: dishID = nil
            }
            return dishID.map { .init(visitID: visit.id, dishID: $0, deletedAt: nil) }
        }
        let photos: [DiningCompanionInput.PhotoRecord] = includePhotos && !visits.isEmpty ? [
            .init(
                id: ids.photo1, restaurantID: ids.restaurant1, visitID: visits[0].id,
                dishID: includeDishes ? ids.dish1 : nil, kind: includeDishes ? .dish : .visit,
                visibility: .private, sortOrder: 0, updatedAt: day(-1), deletedAt: nil
            ),
            .init(
                id: ids.photo2, restaurantID: ids.restaurant2,
                visitID: visits.first(where: { $0.restaurantID == ids.restaurant2 })?.id,
                dishID: includeDishes ? ids.dish2 : nil, kind: includeDishes ? .dish : .restaurantMarker,
                visibility: .private, sortOrder: 0, updatedAt: day(-2), deletedAt: nil
            ),
        ] : []
        return DiningCompanionInput(
            userDisplayName: "Lafayette",
            userCity: "上海",
            companions: companions,
            restaurants: allRestaurants,
            visits: visits,
            dishes: dishes,
            visitDishes: links,
            photos: photos
        )
    }

    private static func restaurant(
        _ id: UUID,
        _ name: String,
        _ cuisine: String,
        status: RestaurantStatus,
        preference: RestaurantJSONContractV1.RestaurantPreferenceContract
    ) -> DiningCompanionInput.RestaurantRecord {
        .init(
            id: id, name: name, address: "上海市徐汇区安福路 18 号", city: "上海",
            status: status, preference: preference, tags: [cuisine, "朋友聚餐"],
            updatedAt: day(-2), deletedAt: nil, isAccessible: true
        )
    }

    private static func replacingPhotos(in overview: DiningCompanionOverview) -> DiningCompanionOverview {
        let analyses = overview.analyses.map { report in
            let assetNames = ["FoodHeroJapanese", "FoodHeroHotpotGrill", "FoodHeroWestern"]
            let hero = FoodHeroPresentation(
                theme: report.hero.theme, primaryTheme: report.hero.primaryTheme,
                secondaryThemes: report.hero.secondaryThemes, labels: report.hero.labels,
                imageReferences: assetNames.map(AnalysisImageReference.asset),
                fallbackAssetName: report.hero.fallbackAssetName, tone: report.hero.tone
            )
            let representatives = report.representativeRestaurants.enumerated().map { index, item in
                RepresentativeRestaurant(
                    id: item.id, name: item.name, role: item.role, detail: item.detail,
                    averageRating: item.averageRating, visitCount: item.visitCount,
                    imageReference: .asset(assetNames[index % assetNames.count])
                )
            }
            return DiningCompanionAnalysis(
                id: report.id + ":assets", kind: report.kind, companionID: report.companionID,
                userDisplayName: report.userDisplayName, companionDisplayName: report.companionDisplayName,
                avatar: report.avatar, sufficiency: report.sufficiency,
                sharedVisitCount: report.sharedVisitCount, restaurantCount: report.restaurantCount,
                firstVisit: report.firstVisit, latestVisit: report.latestVisit, topFoods: report.topFoods,
                topRestaurants: report.topRestaurants, diningContexts: report.diningContexts,
                rating: report.rating, spend: report.spend, repeatRestaurantRate: report.repeatRestaurantRate,
                weekendShare: report.weekendShare, lateMealShare: report.lateMealShare,
                keywords: report.keywords, behavioralPortrait: report.behavioralPortrait,
                summary: report.summary, hero: hero, callouts: report.callouts,
                representativeRestaurants: representatives, recommendations: report.recommendations,
                geographicScope: report.geographicScope, dataNote: report.dataNote, generatedAt: report.generatedAt
            )
        }
        return DiningCompanionOverview(
            id: overview.id + ":assets", userDisplayName: overview.userDisplayName,
            companionCount: overview.companionCount,
            companionsWithVisitsCount: overview.companionsWithVisitsCount,
            summaries: analyses.map {
                .init(
                    id: $0.companionID, displayName: $0.companionDisplayName, avatar: $0.avatar,
                    sharedVisitCount: $0.sharedVisitCount, restaurantCount: $0.restaurantCount,
                    latestVisit: $0.latestVisit, topFood: $0.topFoods.first?.label,
                    summary: $0.summary, sufficiency: $0.sufficiency
                )
            },
            analyses: analyses,
            generatedAt: overview.generatedAt
        )
    }

    private static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }

    private static func day(_ offset: Int, hour: Int = 19) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        let start = calendar.date(from: components) ?? now
        return calendar.date(byAdding: .day, value: offset, to: start) ?? start
    }

    private nonisolated static func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "10000000-0000-0000-0000-%012d", value))!
    }

    private enum ids {
        static let restaurant1 = uuid(1)
        static let restaurant2 = uuid(2)
        static let restaurant3 = uuid(3)
        static let restaurant4 = uuid(4)
        static let restaurant5 = uuid(5)
        static let restaurant6 = uuid(6)
        static let dish1 = uuid(21)
        static let dish2 = uuid(22)
        static let dish3 = uuid(23)
        static let photo1 = uuid(31)
        static let photo2 = uuid(32)
        static let companions = [uuid(41), uuid(42), uuid(43)]
    }
}
#endif
