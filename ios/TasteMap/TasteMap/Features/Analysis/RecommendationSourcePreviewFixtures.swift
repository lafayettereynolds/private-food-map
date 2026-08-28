import Foundation

nonisolated enum RecommendationSourcePreviewFixtures {
    nonisolated static let now = Date(timeIntervalSince1970: 1_777_590_000)
    nonisolated static var empty: RecommendationSourceOverview {
        RecommendationSourceAnalyzer.analyze(input(plans: []), now: now, calendar: calendar)
    }
    nonisolated static var oneSource: RecommendationSourceOverview {
        RecommendationSourceAnalyzer.analyze(input(plans: [
            .init(name: "朋友阿宁", type: .friend, ratings: [4.5], repeatEvery: 0),
        ]), now: now, calendar: calendar)
    }
    nonisolated static var twoInsufficient: RecommendationSourceOverview {
        RecommendationSourceAnalyzer.analyze(input(plans: [
            .init(name: "朋友阿宁", type: .friend, ratings: [4.5, 4.0], repeatEvery: 0),
            .init(name: "周末散步发现", type: .self, ratings: [3.0, 3.5], repeatEvery: 0),
        ]), now: now, calendar: calendar)
    }
    nonisolated static var rich: RecommendationSourceOverview {
        RecommendationSourceAnalyzer.analyze(input(), now: now, calendar: calendar)
    }
    nonisolated static var clearBestWorst: RecommendationSourceOverview { rich }
    nonisolated static var stableHigh: RecommendationSourceOverview {
        RecommendationSourceAnalyzer.analyze(input(plans: [
            .init(name: "老饕手写清单", type: .friend, ratings: Array(repeating: 4.5, count: 10), repeatEvery: 2),
            .init(name: "随手刷到", type: .other, ratings: Array(repeating: 3.0, count: 10), repeatEvery: 4),
        ]), now: now, calendar: calendar)
    }
    nonisolated static var volatile: RecommendationSourceOverview {
        RecommendationSourceAnalyzer.analyze(input(plans: [
            .init(name: "忽高忽低的朋友清单", type: .friend, ratings: [5, 1, 4.5, 1.5, 5, 2, 4.5, 1], repeatEvery: 3),
            .init(name: "稳定散步发现", type: .self, ratings: Array(repeating: 3.5, count: 8), repeatEvery: 3),
        ]), now: now, calendar: calendar)
    }
    nonisolated static var lowSource: RecommendationSourceOverview {
        RecommendationSourceAnalyzer.analyze(input(plans: [
            .init(name: "深夜刷到的收藏夹", type: .other, ratings: [2, 2.5, 1.5, 2, 2.5, 2], repeatEvery: 0),
            .init(name: "自己走到的店", type: .self, ratings: [4, 4, 4.5, 4, 4.5, 4], repeatEvery: 2),
        ]), now: now, calendar: calendar)
    }
    nonisolated static var wantToGoExcluded: RecommendationSourceOverview {
        RecommendationSourceAnalyzer.analyze(input(includeWantToGo: true), now: now, calendar: calendar)
    }
    nonisolated static var withPhotos: RecommendationSourceOverview {
        RecommendationSourceAnalyzer.analyze(input(includePhotos: true), now: now, calendar: calendar)
    }
    nonisolated static var noPhotos: RecommendationSourceOverview {
        RecommendationSourceAnalyzer.analyze(input(includePhotos: false), now: now, calendar: calendar)
    }
    nonisolated static var longSourceName: RecommendationSourceOverview {
        RecommendationSourceAnalyzer.analyze(input(plans: [
            .init(name: "大学室友毕业以后每个月都会更新一次的杭州私藏餐厅长长长清单", type: .friend, ratings: [4.5, 4, 4.5, 4, 5, 4.5, 4], repeatEvery: 2),
            .init(name: "自己发现", type: .self, ratings: [3, 3.5, 3, 3.5, 3, 3.5], repeatEvery: 0),
        ]), now: now, calendar: calendar)
    }
    nonisolated static var longRestaurantName: RecommendationSourceOverview {
        RecommendationSourceAnalyzer.analyze(
            input(longRestaurantNames: true), now: now, calendar: calendar
        )
    }
    nonisolated static var posterRich: RecommendationSourceOverview { rich }
    nonisolated static var posterSparse: RecommendationSourceOverview { twoInsufficient }

    nonisolated struct Plan: Sendable {
        let name: String
        let type: RecommendationSourceType
        let ratings: [Double?]
        let repeatEvery: Int
    }

    nonisolated static func input(
        plans: [Plan] = [
            .init(name: "小林的私藏清单", type: .friend, ratings: [4.5, 5, 4.5, 4, 4.5, 5, 4, 4.5], repeatEvery: 2),
            .init(name: "城市胃口研究所", type: .blogger, ratings: [4, 3.5, 4, 3.5, 4, 3.5, 4], repeatEvery: 3),
            .init(name: "深夜刷到的收藏夹", type: .other, ratings: [2, 2.5, 3, 2, 2.5, 3, 2], repeatEvery: 0),
        ],
        includePhotos: Bool = true,
        includeWantToGo: Bool = false,
        longRestaurantNames: Bool = false
    ) -> RecommendationSourceInput {
        var sources: [RecommendationSourceInput.SourceRecord] = []
        var restaurants: [RecommendationSourceInput.RestaurantRecord] = []
        var visits: [RecommendationSourceInput.VisitRecord] = []
        var photos: [RecommendationSourceInput.PhotoRecord] = []
        var counter = 0

        for (sourceIndex, plan) in plans.enumerated() {
            let sourceID = uuid(8_000 + sourceIndex)
            let remoteID = "source-preview-\(sourceIndex)"
            sources.append(.init(
                id: sourceID,
                identifiers: [sourceID.uuidString.lowercased(), remoteID],
                displayName: plan.name,
                sourceType: plan.type,
                updatedAt: now.addingTimeInterval(Double(-sourceIndex) * 80),
                deletedAt: nil
            ))
            for (ratingIndex, rating) in plan.ratings.enumerated() {
                counter += 1
                let restaurantID = uuid(8_100 + counter)
                let acquiredAt = now.addingTimeInterval(Double(-(sourceIndex * 45 + ratingIndex * 11 + 4)) * 86_400)
                let name = longRestaurantNames && sourceIndex == 0 && ratingIndex == 0
                    ? "山海之间炭火熟成料理与四季小酒馆杭州湖滨特别长名字店"
                    : ["青梅小馆", "野火烧鸟", "白露面包房", "雨巷火锅", "木心寿司", "南山牛排", "小满食堂", "湖畔咖啡"][counter % 8] + " \(sourceIndex + 1)-\(ratingIndex + 1)"
                restaurants.append(.init(
                    id: restaurantID,
                    name: name,
                    city: "杭州",
                    status: .visited,
                    updatedAt: acquiredAt,
                    deletedAt: nil
                ))
                let visitID = uuid(8_500 + counter * 3)
                visits.append(.init(
                    id: visitID,
                    restaurantID: restaurantID,
                    visitedAt: acquiredAt,
                    rating: rating,
                    valueRating: rating.map { max(0.5, $0 - 0.5) },
                    environmentRating: rating,
                    serviceRating: rating.map { min(5, $0 + 0.5) },
                    recommendationSourceID: remoteID,
                    recommendationSourceType: plan.type,
                    recommendationSourceText: plan.name,
                    updatedAt: acquiredAt,
                    deletedAt: nil
                ))
                if plan.repeatEvery > 0 && ratingIndex.isMultiple(of: plan.repeatEvery) {
                    visits.append(.init(
                        id: uuid(8_501 + counter * 3),
                        restaurantID: restaurantID,
                        visitedAt: acquiredAt.addingTimeInterval(12 * 86_400),
                        rating: rating,
                        valueRating: rating,
                        environmentRating: rating,
                        serviceRating: rating,
                        recommendationSourceID: remoteID,
                        recommendationSourceType: plan.type,
                        recommendationSourceText: plan.name,
                        updatedAt: acquiredAt.addingTimeInterval(12 * 86_400),
                        deletedAt: nil
                    ))
                }
                if includePhotos && ratingIndex < 2 {
                    photos.append(.init(
                        id: uuid(9_500 + counter),
                        restaurantID: restaurantID,
                        visitID: visitID,
                        dishID: nil,
                        kind: ratingIndex == 0 ? .dish : .visit,
                        sortOrder: ratingIndex,
                        updatedAt: acquiredAt,
                        deletedAt: nil
                    ))
                }
            }
        }

        if includeWantToGo {
            restaurants.append(.init(
                id: uuid(9_999), name: "只有想吃状态的来源候选店", city: "杭州",
                status: .wantToGo, updatedAt: now, deletedAt: nil
            ))
        }
        return RecommendationSourceInput(
            userDisplayName: "Lafayette",
            sources: sources,
            restaurants: restaurants,
            visits: visits,
            photos: photos
        )
    }

    private nonisolated static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 8 * 3_600)!
        return value
    }

    private nonisolated static func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}
