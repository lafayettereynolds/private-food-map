import Foundation

enum DiningCompanionAnalyzer {
    private nonisolated struct RestaurantAggregate {
        let restaurant: DiningCompanionInput.RestaurantRecord
        let visits: [DiningCompanionInput.VisitRecord]
        let averageRating: Double?
        let latestVisit: Date?
    }

    private nonisolated struct RankedCandidate {
        let recommendation: DiningCompanionRecommendation
        let wantToGo: Bool
    }

    nonisolated static func analyze(
        _ input: DiningCompanionInput,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> DiningCompanionOverview {
        let activeCompanions = deduplicateCompanions(input.companions.filter { $0.deletedAt == nil })
        let activeRestaurants = deduplicateRestaurants(input.restaurants.filter { $0.deletedAt == nil })
        let restaurantByID = Dictionary(uniqueKeysWithValues: activeRestaurants.map { ($0.id, $0) })
        let activeVisits = input.visits.filter {
            $0.deletedAt == nil && restaurantByID[$0.restaurantID] != nil
        }
        let activeDishes = input.dishes.filter {
            $0.deletedAt == nil && restaurantByID[$0.restaurantID] != nil
        }
        let activePhotos = input.photos.filter {
            $0.deletedAt == nil && $0.kind != .avatar
        }
        let activeAssociations = input.visitDishes.filter { $0.deletedAt == nil }
        let baselineRatings = activeVisits.compactMap(\.rating)
        let visitsByRestaurant = Dictionary(grouping: activeVisits, by: \.restaurantID)

        let visitsByCompanion = groupVisitsByCompanion(
            activeVisits,
            companions: activeCompanions
        )
        let analyses = activeCompanions.map { companion in
            analyzeCompanion(
                companion,
                sharedVisits: visitsByCompanion[companion.id] ?? [],
                restaurants: activeRestaurants,
                restaurantByID: restaurantByID,
                allVisitsByRestaurant: visitsByRestaurant,
                dishes: activeDishes,
                associations: activeAssociations,
                photos: activePhotos,
                baselineRatings: baselineRatings,
                input: input,
                now: now,
                calendar: calendar
            )
        }
        .sorted(by: analysisSort)

        let summaries = analyses.map {
            DiningCompanionSummary(
                id: $0.companionID,
                displayName: $0.companionDisplayName,
                avatar: $0.avatar,
                sharedVisitCount: $0.sharedVisitCount,
                restaurantCount: $0.restaurantCount,
                latestVisit: $0.latestVisit,
                topFood: $0.topFoods.first?.label,
                summary: $0.summary,
                sufficiency: $0.sufficiency
            )
        }
        let latest = activeCompanions.map(\.updatedAt).max()?.timeIntervalSince1970 ?? 0
        return DiningCompanionOverview(
            id: "companion-overview:\(activeCompanions.count):\(activeVisits.count):\(Int(latest))",
            userDisplayName: input.userDisplayName,
            companionCount: activeCompanions.count,
            companionsWithVisitsCount: analyses.filter(\.hasSharedVisits).count,
            summaries: summaries,
            analyses: analyses,
            generatedAt: now
        )
    }

    private nonisolated static func analyzeCompanion(
        _ companion: DiningCompanionInput.CompanionRecord,
        sharedVisits: [DiningCompanionInput.VisitRecord],
        restaurants: [DiningCompanionInput.RestaurantRecord],
        restaurantByID: [UUID: DiningCompanionInput.RestaurantRecord],
        allVisitsByRestaurant: [UUID: [DiningCompanionInput.VisitRecord]],
        dishes: [DiningCompanionInput.DishRecord],
        associations: [DiningCompanionInput.VisitDishRecord],
        photos: [DiningCompanionInput.PhotoRecord],
        baselineRatings: [Double],
        input: DiningCompanionInput,
        now: Date,
        calendar: Calendar
    ) -> DiningCompanionAnalysis {
        let visits = sharedVisits.sorted(by: visitSort)
        let sharedVisitIDs = Set(visits.map(\.id))
        let visitsByRestaurant = Dictionary(grouping: visits, by: \.restaurantID)
        let restaurantCount = visitsByRestaurant.count
        let repeatedRestaurantCount = visitsByRestaurant.values.filter { $0.count >= 2 }.count
        let repeatRate = ratio(repeatedRestaurantCount, restaurantCount)
        let sufficiency = AnalysisSufficiencyPolicy.level(
            sampleCount: visits.count,
            emergingAt: AnalysisSufficiencyThresholds.companion.emerging,
            establishedAt: AnalysisSufficiencyThresholds.companion.established
        )
        let avatar = avatarPresentation(for: companion)
        let foodRanks = rankFoods(
            visits: visits,
            sharedVisitIDs: sharedVisitIDs,
            restaurantByID: restaurantByID,
            dishes: dishes,
            associations: associations
        )
        let context = frequency(
            visits.flatMap { visit in
                visit.diningOccasionLabels + visit.environmentTags + [visit.noiseLevelLabel].compactMap { $0 }
            },
            total: visits.count
        )
        let rating = ratingSummary(visits: visits, baselineRatings: baselineRatings)
        let spend = spendSummary(visits)
        let weekendCount = visits.filter { calendar.isDateInWeekend($0.visitedAt) }.count
        let lateMealCount = visits.filter {
            let hour = calendar.component(.hour, from: $0.visitedAt)
            return hour >= 21 || hour < 5
        }.count
        let weekendShare = ratio(weekendCount, visits.count)
        let lateMealShare = ratio(lateMealCount, visits.count)
        let rankedRestaurants = rankRestaurants(
            visitsByRestaurant: visitsByRestaurant,
            restaurantByID: restaurantByID,
            photos: photos,
            sharedVisitIDs: sharedVisitIDs,
            dishes: dishes,
            associations: associations
        )
        let cuisineRanks = rankCuisines(visits: visits, restaurantByID: restaurantByID)
        let keywords = relationKeywords(
            visits: visits,
            restaurantCount: restaurantCount,
            repeatRate: repeatRate,
            topFood: foodRanks.first,
            topCuisine: cuisineRanks.first,
            rating: rating,
            weekendShare: weekendShare,
            lateMealShare: lateMealShare
        )
        let portrait = behavioralPortrait(
            visitCount: visits.count,
            restaurantCount: restaurantCount,
            repeatRate: repeatRate,
            topFood: foodRanks.first,
            weekendShare: weekendShare
        )
        let representatives = representativeRestaurants(
            visitsByRestaurant: visitsByRestaurant,
            restaurantByID: restaurantByID,
            photos: photos,
            sharedVisitIDs: sharedVisitIDs,
            dishes: dishes,
            associations: associations,
            topCuisine: cuisineRanks.first?.label,
            now: now,
            calendar: calendar
        )
        let geographicScope = mostFrequentCity(visits: visits, restaurantByID: restaurantByID)
            ?? input.userCity.trimmed.nilIfEmpty
        let recommendations = recommendRestaurants(
            restaurants: restaurants,
            sharedVisitsByRestaurant: visitsByRestaurant,
            allVisitsByRestaurant: allVisitsByRestaurant,
            photos: photos,
            topCuisineLabels: cuisineRanks.prefix(3).map(\.label),
            geographicScope: geographicScope,
            repeatRate: repeatRate,
            now: now,
            calendar: calendar
        )
        let hero = foodHero(
            foods: foodRanks,
            cuisines: cuisineRanks,
            representatives: representatives,
            photos: photos,
            sharedVisitIDs: sharedVisitIDs,
            dishes: dishes,
            associations: associations
        )
        let summary = summary(
            displayName: companion.displayName,
            visitCount: visits.count,
            restaurantCount: restaurantCount,
            topFood: foodRanks.first,
            repeatRate: repeatRate
        )
        let callouts = callouts(
            visits: visits,
            restaurantCount: restaurantCount,
            topFood: foodRanks.first,
            sufficiency: sufficiency,
            calendar: calendar
        )
        let newestUpdate = visits.map(\.updatedAt).max()?.timeIntervalSince1970 ?? companion.updatedAt.timeIntervalSince1970

        return DiningCompanionAnalysis(
            id: "companion:\(companion.id.uuidString.lowercased()):\(visits.count):\(Int(newestUpdate))",
            kind: .companion,
            companionID: companion.id,
            userDisplayName: input.userDisplayName,
            companionDisplayName: companion.displayName,
            avatar: avatar,
            sufficiency: sufficiency,
            sharedVisitCount: visits.count,
            restaurantCount: restaurantCount,
            firstVisit: visits.first?.visitedAt,
            latestVisit: visits.last?.visitedAt,
            topFoods: foodRanks,
            topRestaurants: rankedRestaurants,
            diningContexts: context,
            rating: rating,
            spend: spend,
            repeatRestaurantRate: repeatRate,
            weekendShare: weekendShare,
            lateMealShare: lateMealShare,
            keywords: keywords,
            behavioralPortrait: portrait,
            summary: summary,
            hero: hero,
            callouts: callouts,
            representativeRestaurants: representatives,
            recommendations: recommendations,
            geographicScope: geographicScope,
            dataNote: "只分析你自己记录、且包含这位饭搭子的有效到访；不会读取 TA 的私人 Taste Map 历史，也不会把私人备注放进分享海报。",
            generatedAt: now
        )
    }

    private nonisolated static func groupVisitsByCompanion(
        _ visits: [DiningCompanionInput.VisitRecord],
        companions: [DiningCompanionInput.CompanionRecord]
    ) -> [UUID: [DiningCompanionInput.VisitRecord]] {
        var identifierOwners: [String: UUID] = [:]
        for companion in companions {
            for identifier in companion.identifiers {
                identifierOwners[identifier.normalized] = companion.id
            }
        }
        let nameGroups = Dictionary(grouping: companions, by: { $0.displayName.normalized })
        let uniqueNameOwners = nameGroups.compactMapValues { values in
            values.count == 1 ? values[0].id : nil
        }

        var result: [UUID: [DiningCompanionInput.VisitRecord]] = [:]
        for visit in visits {
            var resolved = Set<UUID>()
            for identifier in visit.companionIDs {
                if let companionID = identifierOwners[identifier.normalized] {
                    resolved.insert(companionID)
                }
            }
            for name in visit.companionNames {
                if let companionID = uniqueNameOwners[name.normalized] {
                    resolved.insert(companionID)
                }
            }
            for companionID in resolved {
                result[companionID, default: []].append(visit)
            }
        }
        return result
    }

    private nonisolated static func rankFoods(
        visits: [DiningCompanionInput.VisitRecord],
        sharedVisitIDs: Set<UUID>,
        restaurantByID: [UUID: DiningCompanionInput.RestaurantRecord],
        dishes: [DiningCompanionInput.DishRecord],
        associations: [DiningCompanionInput.VisitDishRecord]
    ) -> [DiningCompanionFoodRank] {
        guard visits.count >= 2 else { return [] }
        let visitByID = Dictionary(uniqueKeysWithValues: visits.map { ($0.id, $0) })
        let dishByID = Dictionary(uniqueKeysWithValues: dishes.map { ($0.id, $0) })
        var visitIDsByDish: [UUID: Set<UUID>] = [:]
        for association in associations where sharedVisitIDs.contains(association.visitID) {
            guard let dish = dishByID[association.dishID],
                  visitByID[association.visitID]?.restaurantID == dish.restaurantID else { continue }
            visitIDsByDish[association.dishID, default: []].insert(association.visitID)
        }
        for dish in dishes where sharedVisitIDs.contains(dish.originVisitID) {
            visitIDsByDish[dish.id, default: []].insert(dish.originVisitID)
        }
        let dishRanks = dishes.compactMap { dish -> DiningCompanionFoodRank? in
            let visitIDs = visitIDsByDish[dish.id] ?? []
            guard !visitIDs.isEmpty else { return nil }
            let ratings = [dish.rating].compactMap { $0 } + visitIDs.compactMap { visitByID[$0]?.rating }
            return DiningCompanionFoodRank(
                id: "dish:\(dish.id.uuidString.lowercased())",
                label: dish.name,
                source: .dish,
                sharedVisitCount: visitIDs.count,
                share: ratio(visitIDs.count, visits.count),
                averageRating: average(ratings)
            )
        }
        .sorted(by: foodSort)

        if dishRanks.contains(where: { $0.sharedVisitCount >= 2 }) {
            return Array(dishRanks.prefix(6))
        }
        return Array(rankCuisines(visits: visits, restaurantByID: restaurantByID).prefix(6))
    }

    private nonisolated static func rankCuisines(
        visits: [DiningCompanionInput.VisitRecord],
        restaurantByID: [UUID: DiningCompanionInput.RestaurantRecord]
    ) -> [DiningCompanionFoodRank] {
        var visitIDsByCuisine: [String: Set<UUID>] = [:]
        var ratingsByCuisine: [String: [Double]] = [:]
        for visit in visits {
            guard let restaurant = restaurantByID[visit.restaurantID] else { continue }
            let labels = Set(restaurant.tags.compactMap(cuisineLabel))
            for label in labels {
                visitIDsByCuisine[label, default: []].insert(visit.id)
                if let rating = visit.rating { ratingsByCuisine[label, default: []].append(rating) }
            }
        }
        return visitIDsByCuisine.map { label, visitIDs in
            DiningCompanionFoodRank(
                id: "cuisine:\(label.normalized)",
                label: label,
                source: .cuisine,
                sharedVisitCount: visitIDs.count,
                share: ratio(visitIDs.count, visits.count),
                averageRating: average(ratingsByCuisine[label] ?? [])
            )
        }.sorted(by: foodSort)
    }

    private nonisolated static func rankRestaurants(
        visitsByRestaurant: [UUID: [DiningCompanionInput.VisitRecord]],
        restaurantByID: [UUID: DiningCompanionInput.RestaurantRecord],
        photos: [DiningCompanionInput.PhotoRecord],
        sharedVisitIDs: Set<UUID>,
        dishes: [DiningCompanionInput.DishRecord],
        associations: [DiningCompanionInput.VisitDishRecord]
    ) -> [DiningCompanionRestaurantRank] {
        visitsByRestaurant.compactMap { id, visits in
            guard let restaurant = restaurantByID[id], let latest = visits.map(\.visitedAt).max() else { return nil }
            return DiningCompanionRestaurantRank(
                id: id,
                name: restaurant.name,
                sharedVisitCount: visits.count,
                latestVisit: latest,
                averageRating: average(visits.compactMap(\.rating)),
                imageReference: preferredPhoto(
                    restaurantID: id,
                    photos: photos,
                    sharedVisitIDs: sharedVisitIDs,
                    dishes: dishes,
                    associations: associations
                ).map { .photo($0.id) }
                    ?? restaurant.merchantImageURL.map(AnalysisImageReference.provider)
                    ?? .none
            )
        }.sorted { lhs, rhs in
            if lhs.sharedVisitCount != rhs.sharedVisitCount { return lhs.sharedVisitCount > rhs.sharedVisitCount }
            if (lhs.averageRating ?? -1) != (rhs.averageRating ?? -1) {
                return (lhs.averageRating ?? -1) > (rhs.averageRating ?? -1)
            }
            if lhs.latestVisit != rhs.latestVisit { return lhs.latestVisit > rhs.latestVisit }
            return uuidLess(lhs.id, rhs.id)
        }
    }

    private nonisolated static func ratingSummary(
        visits: [DiningCompanionInput.VisitRecord],
        baselineRatings: [Double]
    ) -> DiningCompanionRatingSummary {
        let ratings = AnalysisStatisticsDefinitions.overallRatings(in: visits, rating: \.rating)
        let sharedAverage = average(ratings)
        let baselineAverage = average(baselineRatings)
        let difference: Double? = if ratings.count >= 2, baselineRatings.count >= 3,
                                     let sharedAverage, let baselineAverage {
            sharedAverage - baselineAverage
        } else { nil }
        let sufficiency = AnalysisSufficiencyPolicy.level(
            sampleCount: ratings.count,
            emergingAt: AnalysisSufficiencyThresholds.companion.emerging,
            establishedAt: AnalysisSufficiencyThresholds.companion.established
        )
        let summary: String
        if ratings.isEmpty {
            summary = "这些共同到访还没有评分；空评分不会当作 0。"
        } else if let difference, abs(difference) >= 0.15 {
            let direction = difference > 0 ? "高" : "低"
            summary = "和 TA 一起吃饭时，你的平均评分比全部记录\(direction) \(oneDecimal(abs(difference)))。"
        } else if let sharedAverage {
            summary = "和 TA 一起吃饭时，你的平均评分是 \(oneDecimal(sharedAverage))。"
        } else {
            summary = "评分样本正在形成。"
        }
        return DiningCompanionRatingSummary(
            sampleCount: ratings.count,
            sharedAverage: sharedAverage,
            overallAverage: baselineAverage,
            differenceFromOverall: difference,
            valueAverage: average(visits.compactMap(\.valueRating)),
            environmentAverage: average(visits.compactMap(\.environmentRating)),
            serviceAverage: average(visits.compactMap(\.serviceRating)),
            summary: summary,
            sufficiency: sufficiency
        )
    }

    private nonisolated static func spendSummary(
        _ visits: [DiningCompanionInput.VisitRecord]
    ) -> DiningCompanionSpendSummary {
        let values = AnalysisStatisticsDefinitions.recordedSpendValues(
            in: visits,
            spend: \.myActualSpend
        ).sorted()
        let median = AnalysisStatisticsDefinitions.median(values)
        let total = values.isEmpty ? nil : values.reduce(0, +)
        let summary = median.map {
            "和 TA 吃饭时，你记录的本人消费中位数是 ¥\(Int($0.rounded()))；共 \(values.count) 条消费样本。"
        } ?? "还没有可用的本人实际消费记录。"
        return DiningCompanionSpendSummary(
            sampleCount: values.count,
            median: median,
            totalRecorded: total,
            summary: summary,
            sufficiency: AnalysisSufficiencyPolicy.level(
                sampleCount: values.count,
                emergingAt: AnalysisSufficiencyThresholds.companionSpend.emerging,
                establishedAt: AnalysisSufficiencyThresholds.companionSpend.established
            )
        )
    }

    private nonisolated static func relationKeywords(
        visits: [DiningCompanionInput.VisitRecord],
        restaurantCount: Int,
        repeatRate: Double,
        topFood: DiningCompanionFoodRank?,
        topCuisine: DiningCompanionFoodRank?,
        rating: DiningCompanionRatingSummary,
        weekendShare: Double,
        lateMealShare: Double
    ) -> [String] {
        guard visits.count >= 3 else { return [] }
        var values: [String] = []
        if visits.count >= 3 {
            if repeatRate >= 0.5 { values.append("常去熟店") }
            else if restaurantCount == visits.count || repeatRate <= 0.2 { values.append("探店型") }
        }
        if let food = topFood ?? topCuisine, food.sharedVisitCount >= 2, food.share >= 0.45 {
            values.append("\(food.label)搭子")
        }
        if visits.count >= 3, weekendShare >= 0.6 { values.append("周末饭友") }
        if visits.count >= 3, lateMealShare >= 0.5 { values.append("深夜饭搭子") }
        if rating.sampleCount >= 3, (rating.sharedAverage ?? 0) >= 4.3 { values.append("高分组合") }
        return Array(stableUnique(values).prefix(4))
    }

    private nonisolated static func behavioralPortrait(
        visitCount: Int,
        restaurantCount: Int,
        repeatRate: Double,
        topFood: DiningCompanionFoodRank?,
        weekendShare: Double
    ) -> String {
        guard visitCount > 0 else { return "还没有有效的共同到访，暂不生成共同吃饭模式。" }
        guard visitCount >= 2 else { return "目前只有一次共同到访，只展示这次真实记录。" }
        var pieces: [String] = []
        if repeatRate >= 0.5 { pieces.append("更常回到熟悉的餐厅") }
        else if restaurantCount == visitCount { pieces.append("每次都在尝试不同餐厅") }
        if let topFood, topFood.sharedVisitCount >= 2 { pieces.append("共同记录更集中在\(topFood.label)") }
        if visitCount >= 3, weekendShare >= 0.6 { pieces.append("周末共同到访更多") }
        return pieces.isEmpty
            ? "共同用餐记录分布较均衡，继续记录后会形成更清晰的行为模式。"
            : pieces.joined(separator: "，") + "。"
    }

    private nonisolated static func representativeRestaurants(
        visitsByRestaurant: [UUID: [DiningCompanionInput.VisitRecord]],
        restaurantByID: [UUID: DiningCompanionInput.RestaurantRecord],
        photos: [DiningCompanionInput.PhotoRecord],
        sharedVisitIDs: Set<UUID>,
        dishes: [DiningCompanionInput.DishRecord],
        associations: [DiningCompanionInput.VisitDishRecord],
        topCuisine: String?,
        now: Date,
        calendar: Calendar
    ) -> [RepresentativeRestaurant] {
        guard !visitsByRestaurant.isEmpty else { return [] }
        let mostFrequent = visitsByRestaurant.keys.sorted(by: uuidLess).max { lhs, rhs in
            let left = visitsByRestaurant[lhs]?.count ?? 0
            let right = visitsByRestaurant[rhs]?.count ?? 0
            return left == right ? uuidLess(lhs, rhs) : left < right
        }
        let memory = visitsByRestaurant.compactMap { id, visits -> (UUID, Double)? in
            guard restaurantByID[id] != nil else { return nil }
            let rating = average(visits.compactMap(\.rating)) ?? 0
            let photo = preferredPhoto(
                restaurantID: id, photos: photos, sharedVisitIDs: sharedVisitIDs,
                dishes: dishes, associations: associations
            ) == nil ? 0.0 : 1.2
            let note = visits.contains(where: \.hasPrivateNote) ? 0.7 : 0
            let specialContext = visits.contains { !$0.diningOccasionLabels.isEmpty } ? 0.4 : 0
            let latest = visits.map(\.visitedAt).max() ?? .distantPast
            let days = calendar.dateComponents([.day], from: latest, to: now).day ?? 999
            let recency = days <= 90 ? 0.8 : days <= 180 ? 0.35 : 0
            return (id, Double(visits.count) * 1.5 + rating + photo + note + specialContext + recency)
        }.sorted { lhs, rhs in
            lhs.1 == rhs.1 ? uuidLess(lhs.0, rhs.0) : lhs.1 > rhs.1
        }.first?.0
        let flavor = visitsByRestaurant.compactMap { id, visits -> (UUID, Double)? in
            guard let restaurant = restaurantByID[id] else { return nil }
            let match = restaurant.tags.compactMap(cuisineLabel).contains(topCuisine ?? "") ? 3.0 : 0
            return (id, match + Double(visits.count) + (average(visits.compactMap(\.rating)) ?? 0))
        }.sorted { lhs, rhs in
            lhs.1 == rhs.1 ? uuidLess(lhs.0, rhs.0) : lhs.1 > rhs.1
        }.first?.0
        let recent = visitsByRestaurant.compactMap { id, visits in
            visits.map(\.visitedAt).max().map { (id, $0) }
        }.sorted { lhs, rhs in
            lhs.1 == rhs.1 ? uuidLess(lhs.0, rhs.0) : lhs.1 > rhs.1
        }.first?.0

        let candidates: [(UUID?, String)] = [
            (mostFrequent, "最常一起去"),
            (memory, "共同回忆餐厅"),
            (flavor, "最代表共同口味"),
            (recent, "最近一次一起吃"),
        ]
        var used = Set<UUID>()
        return candidates.compactMap { optionalID, role -> RepresentativeRestaurant? in
            guard let id = optionalID, used.insert(id).inserted,
                  let restaurant = restaurantByID[id], let visits = visitsByRestaurant[id] else { return nil }
            let latest = visits.map(\.visitedAt).max()
            let rating = average(visits.compactMap(\.rating))
            let detail = [
                "\(visits.count) 次共同到访",
                rating.map { "你的平均评分 \(oneDecimal($0))" },
                latest.map { shortDate($0, calendar: calendar) },
            ].compactMap { $0 }.joined(separator: " · ")
            let photo = preferredPhoto(
                restaurantID: id, photos: photos, sharedVisitIDs: sharedVisitIDs,
                dishes: dishes, associations: associations
            )
            return RepresentativeRestaurant(
                id: id,
                name: restaurant.name,
                role: role,
                detail: detail,
                averageRating: rating,
                visitCount: visits.count,
                imageReference: photo.map { .photo($0.id) }
                    ?? restaurant.merchantImageURL.map(AnalysisImageReference.provider)
                    ?? .none
            )
        }.prefix(3).map { $0 }
    }

    private nonisolated static func recommendRestaurants(
        restaurants: [DiningCompanionInput.RestaurantRecord],
        sharedVisitsByRestaurant: [UUID: [DiningCompanionInput.VisitRecord]],
        allVisitsByRestaurant: [UUID: [DiningCompanionInput.VisitRecord]],
        photos: [DiningCompanionInput.PhotoRecord],
        topCuisineLabels: [String],
        geographicScope: String?,
        repeatRate: Double,
        now: Date,
        calendar: Calendar
    ) -> [DiningCompanionRecommendation] {
        guard let normalizedScope = geographicScope?.normalized.nilIfEmpty else { return [] }
        let familiarPattern = repeatRate >= 0.4
        let topCuisineSet = Set(topCuisineLabels.map(\.normalized))
        let ranked = restaurants.compactMap { restaurant -> RankedCandidate? in
            guard restaurant.deletedAt == nil,
                  restaurant.isAccessible,
                  restaurant.preference != .avoid else { return nil }
            guard restaurant.city.normalized == normalizedScope else { return nil }

            let allVisits = allVisitsByRestaurant[restaurant.id] ?? []
            let sharedVisits = sharedVisitsByRestaurant[restaurant.id] ?? []
            let averageRating = average(allVisits.compactMap(\.rating))
            if let averageRating, averageRating < 3 { return nil }

            let alreadyShared = !sharedVisits.isEmpty
            let wantToGo = restaurant.status == .wantToGo
            let unshared = !alreadyShared
            if alreadyShared && !familiarPattern { return nil }

            if alreadyShared,
               sharedVisits.count >= 2,
               let latest = sharedVisits.map(\.visitedAt).max(),
               let cutoff = calendar.date(byAdding: .day, value: -14, to: now),
               latest >= cutoff,
               !(repeatRate >= 0.6 && (averageRating ?? 0) >= 4.5) {
                return nil
            }

            let cuisineMatches = restaurant.tags.compactMap(cuisineLabel)
                .filter { topCuisineSet.contains($0.normalized) }.count
            var score = 0.0
            if wantToGo { score += 5.0 }
            if unshared { score += 2.2 }
            score += Double(min(2, cuisineMatches)) * 1.8
            if let averageRating { score += max(0, averageRating - 3) * 1.2 }
            score += 0.8
            if alreadyShared && familiarPattern { score += 1.4 }
            if restaurant.preference == .favorite { score += 1.2 }
            else if restaurant.preference == .like { score += 0.6 }

            let reason: String
            if wantToGo, cuisineMatches > 0 {
                reason = "想吃清单里，符合你们常记录的\(cuisineMatches == 1 ? "口味" : "几种口味")。"
            } else if wantToGo {
                reason = "已在你的想吃清单，且位于当前共同用餐城市。"
            } else if unshared, cuisineMatches > 0 {
                reason = "你去过但还没和 TA 一起去，口味与共同记录相符。"
            } else {
                reason = "你们有回熟店的模式，这家店评分和重复选择都较稳定。"
            }
            let photo = photos.filter {
                $0.deletedAt == nil && $0.restaurantID == restaurant.id && $0.kind == .restaurantMarker
            }.sorted(by: photoSort).first
            return RankedCandidate(
                recommendation: DiningCompanionRecommendation(
                    id: restaurant.id.uuidString.lowercased(),
                    localRestaurantID: restaurant.id,
                    name: restaurant.name,
                    city: restaurant.city,
                    reason: reason,
                    score: score,
                    imageReference: photo.map { .photo($0.id) }
                        ?? restaurant.merchantImageURL.map(AnalysisImageReference.provider)
                        ?? .none
                ),
                wantToGo: wantToGo
            )
        }.sorted { lhs, rhs in
            if abs(lhs.recommendation.score - rhs.recommendation.score) > 0.000_001 {
                return lhs.recommendation.score > rhs.recommendation.score
            }
            if lhs.wantToGo != rhs.wantToGo { return lhs.wantToGo }
            let nameOrder = lhs.recommendation.name.localizedStandardCompare(rhs.recommendation.name)
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            return lhs.recommendation.id < rhs.recommendation.id
        }
        return Array(ranked.prefix(3).map(\.recommendation))
    }

    private nonisolated static func foodHero(
        foods: [DiningCompanionFoodRank],
        cuisines: [DiningCompanionFoodRank],
        representatives: [RepresentativeRestaurant],
        photos: [DiningCompanionInput.PhotoRecord],
        sharedVisitIDs: Set<UUID>,
        dishes: [DiningCompanionInput.DishRecord],
        associations: [DiningCompanionInput.VisitDishRecord]
    ) -> FoodHeroPresentation {
        let labels = stableUnique((foods + cuisines).prefix(6).map(\.label))
        let theme = resolveTheme(labels)
        var references = representatives.map(\.imageReference).filter {
            if case .none = $0 { return false }
            return true
        }
        let sharedDishIDs = Set(associations.filter { sharedVisitIDs.contains($0.visitID) }.map(\.dishID))
            .union(dishes.filter { sharedVisitIDs.contains($0.originVisitID) }.map(\.id))
        references.append(contentsOf: photos.filter {
            $0.deletedAt == nil && (
                $0.visitID.map(sharedVisitIDs.contains) == true ||
                $0.dishID.map(sharedDishIDs.contains) == true
            )
        }.sorted(by: photoSort).map { .photo($0.id) })
        references = Array(stableUnique(references).prefix(4))
        if references.isEmpty { references = [.asset(theme.assetName)] }
        return FoodHeroPresentation(
            theme: theme,
            primaryTheme: labels.first ?? "共同口味正在形成",
            secondaryThemes: Array(labels.dropFirst().prefix(3)),
            labels: Array(labels.prefix(4)),
            imageReferences: references,
            fallbackAssetName: theme.assetName,
            tone: tone(for: theme)
        )
    }

    private nonisolated static func callouts(
        visits: [DiningCompanionInput.VisitRecord],
        restaurantCount: Int,
        topFood: DiningCompanionFoodRank?,
        sufficiency: AnalysisDataSufficiency,
        calendar: Calendar
    ) -> [AnalysisCallout] {
        [
            AnalysisCallout(
                id: "visits", icon: "🥢", title: "一起吃过", value: "\(visits.count) 次",
                detail: "一条包含 TA 的有效 Visit 只计算一次。", tone: .brand,
                sufficiency: visits.isEmpty ? .insufficient : sufficiency
            ),
            AnalysisCallout(
                id: "restaurants", icon: "📍", title: "一起去过", value: "\(restaurantCount) 家",
                detail: "按 Taste Map Restaurant ID 去重。", tone: .ingredientRed,
                sufficiency: restaurantCount == 0 ? .insufficient : sufficiency
            ),
            AnalysisCallout(
                id: "food", icon: "🍲", title: "常一起吃", value: topFood?.label ?? "正在形成",
                detail: topFood.map { "出现在 \($0.sharedVisitCount) 次共同到访。" } ?? "至少两次后再判断趋势。",
                tone: .leafGreen, sufficiency: topFood == nil ? .insufficient : sufficiency
            ),
            AnalysisCallout(
                id: "latest", icon: "🗓️", title: "最近一起吃",
                value: visits.last.map { shortDate($0.visitedAt, calendar: calendar) } ?? "暂无",
                detail: visits.last == nil ? "还没有共同到访。" : "来自最近一条有效共同 Visit。",
                tone: .caramel, sufficiency: visits.isEmpty ? .insufficient : sufficiency
            ),
        ]
    }

    private nonisolated static func summary(
        displayName: String,
        visitCount: Int,
        restaurantCount: Int,
        topFood: DiningCompanionFoodRank?,
        repeatRate: Double
    ) -> String {
        guard visitCount > 0 else { return "你已经记录了 \(displayName)，共同吃饭画像会从第一次有效到访开始。" }
        guard visitCount >= 2 else { return "你和 \(displayName) 目前有 1 次共同到访，只展示这次真实事实。" }
        var pieces = ["\(visitCount) 次共同到访、\(restaurantCount) 家餐厅"]
        if let topFood { pieces.append("更常一起记录\(topFood.label)") }
        if repeatRate >= 0.5 { pieces.append("也会回到熟悉的店") }
        return "你和 \(displayName) 有" + pieces.joined(separator: "，") + "。"
    }

    private nonisolated static func mostFrequentCity(
        visits: [DiningCompanionInput.VisitRecord],
        restaurantByID: [UUID: DiningCompanionInput.RestaurantRecord]
    ) -> String? {
        frequency(
            visits.compactMap { restaurantByID[$0.restaurantID]?.city.trimmed.nilIfEmpty },
            total: visits.count
        ).first?.label
    }

    private nonisolated static func preferredPhoto(
        restaurantID: UUID,
        photos: [DiningCompanionInput.PhotoRecord],
        sharedVisitIDs: Set<UUID>,
        dishes: [DiningCompanionInput.DishRecord],
        associations: [DiningCompanionInput.VisitDishRecord]
    ) -> DiningCompanionInput.PhotoRecord? {
        let dishByID = Dictionary(uniqueKeysWithValues: dishes.map { ($0.id, $0) })
        let sharedDishIDs = Set(associations.filter { sharedVisitIDs.contains($0.visitID) }.map(\.dishID))
            .union(dishes.filter { sharedVisitIDs.contains($0.originVisitID) }.map(\.id))
        return photos.filter { photo in
            guard photo.deletedAt == nil else { return false }
            if let dishID = photo.dishID,
               sharedDishIDs.contains(dishID),
               dishByID[dishID]?.restaurantID == restaurantID { return true }
            if let visitID = photo.visitID,
               sharedVisitIDs.contains(visitID),
               photo.restaurantID == restaurantID { return true }
            return photo.restaurantID == restaurantID && photo.kind == .restaurantMarker
        }.sorted(by: photoSort).first
    }

    private nonisolated static func photoSort(
        _ lhs: DiningCompanionInput.PhotoRecord,
        _ rhs: DiningCompanionInput.PhotoRecord
    ) -> Bool {
        func priority(_ kind: PhotoAssetKind) -> Int {
            switch kind {
            case .dish: 0
            case .visit: 1
            case .restaurantMarker: 2
            case .avatar: 3
            }
        }
        let left = priority(lhs.kind)
        let right = priority(rhs.kind)
        if left != right { return left < right }
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return uuidLess(lhs.id, rhs.id)
    }

    private nonisolated static func avatarPresentation(
        for companion: DiningCompanionInput.CompanionRecord
    ) -> DiningCompanionAvatarPresentation {
        if let preset = companion.permittedLinkedAvatarPreset { return .preset(preset) }
        let characters = Array(companion.displayName.trimmed)
        let initial: String
        if characters.isEmpty { initial = "·" }
        else if characters.count >= 2, ["小", "老", "阿"].contains(String(characters[0])) {
            initial = String(characters[1])
        } else {
            initial = String(characters[0]).uppercased()
        }
        let tones: [AnalysisTone] = [.brand, .ingredientRed, .leafGreen, .cream, .caramel]
        let hash = companion.id.uuidString.unicodeScalars.reduce(UInt(0)) {
            ($0 &* 31) &+ UInt($1.value)
        }
        return .initial(initial, tones[Int(hash % UInt(tones.count))])
    }

    private nonisolated static func cuisineLabel(_ raw: String) -> String? {
        let value = raw.trimmed
        guard !value.isEmpty, value.count <= 16 else { return nil }
        let excluded = [
            "约会", "聚餐", "朋友", "家人", "同事", "庆祝", "商务", "一个人", "独处",
            "安静", "热闹", "舒适", "拥挤", "宽敞", "精致", "氛围", "景观", "性价比",
            "偏贵", "划算", "商场", "中心", "广场", "附近", "排队", "交通", "停车", "外卖",
        ]
        guard !excluded.contains(where: value.contains) else { return nil }
        let normalized = value.normalized
        if containsAny(normalized, ["日料", "日本", "寿司", "刺身", "居酒屋", "japanese", "sushi"]) { return "日料" }
        if containsAny(normalized, ["火锅", "涮锅", "hotpot"]) { return "火锅" }
        if containsAny(normalized, ["烧烤", "烤肉", "烤串", "bbq", "grill"]) { return "烧烤" }
        if containsAny(normalized, ["西餐", "牛排", "意面", "法餐", "意大利", "western", "steak", "pasta"]) { return "西餐" }
        if containsAny(normalized, ["咖啡", "甜品", "甜点", "烘焙", "面包", "brunch", "cafe", "dessert"]) { return "咖啡甜点" }
        return value
    }

    private nonisolated static func resolveTheme(_ labels: [String]) -> FoodHeroTheme {
        var scores: [FoodHeroTheme: Int] = [:]
        for label in labels {
            let value = label.normalized
            let theme: FoodHeroTheme?
            if containsAny(value, ["日料", "日本", "寿司", "刺身", "居酒屋", "拉面", "sushi", "japanese"]) { theme = .japanese }
            else if containsAny(value, ["火锅", "烧烤", "烤肉", "串", "hotpot", "bbq", "grill"]) { theme = .hotpotGrill }
            else if containsAny(value, ["咖啡", "甜品", "甜点", "烘焙", "面包", "早午餐", "brunch", "cafe", "dessert"]) { theme = .cafe }
            else if containsAny(value, ["西餐", "牛排", "意面", "法餐", "意大利", "汉堡", "western", "steak", "pasta"]) { theme = .western }
            else if containsAny(value, ["中餐", "川菜", "粤菜", "湘菜", "本帮", "江浙", "面", "饺", "小笼", "家常"]) { theme = .chinese }
            else { theme = nil }
            if let theme { scores[theme, default: 0] += 1 }
        }
        let ranked = scores.sorted { lhs, rhs in
            lhs.value == rhs.value ? lhs.key.rawValue < rhs.key.rawValue : lhs.value > rhs.value
        }
        guard let first = ranked.first else { return .mixed }
        if ranked.count > 1, Double(ranked[1].value) >= Double(first.value) * 0.6 { return .mixed }
        return first.key
    }

    private nonisolated static func tone(for theme: FoodHeroTheme) -> AnalysisTone {
        switch theme {
        case .japanese: .ingredientRed
        case .hotpotGrill: .caramel
        case .chinese: .leafGreen
        case .western: .brand
        case .cafe: .cream
        case .mixed: .brand
        }
    }

    private nonisolated static func frequency(_ labels: [String], total: Int) -> [AnalysisFrequencyItem] {
        var values: [String: (String, Int)] = [:]
        for raw in labels {
            let label = raw.trimmed
            guard !label.isEmpty else { continue }
            let key = label.normalized
            values[key] = (values[key]?.0 ?? label, (values[key]?.1 ?? 0) + 1)
        }
        return values.map { key, value in
            AnalysisFrequencyItem(id: key, label: value.0, count: value.1, share: ratio(value.1, total))
        }.sorted { lhs, rhs in
            lhs.count == rhs.count
                ? lhs.label.localizedStandardCompare(rhs.label) == .orderedAscending
                : lhs.count > rhs.count
        }
    }

    private nonisolated static func foodSort(
        _ lhs: DiningCompanionFoodRank,
        _ rhs: DiningCompanionFoodRank
    ) -> Bool {
        if lhs.sharedVisitCount != rhs.sharedVisitCount { return lhs.sharedVisitCount > rhs.sharedVisitCount }
        if (lhs.averageRating ?? -1) != (rhs.averageRating ?? -1) {
            return (lhs.averageRating ?? -1) > (rhs.averageRating ?? -1)
        }
        return lhs.label.localizedStandardCompare(rhs.label) == .orderedAscending
    }

    private nonisolated static func analysisSort(
        _ lhs: DiningCompanionAnalysis,
        _ rhs: DiningCompanionAnalysis
    ) -> Bool {
        if lhs.sharedVisitCount != rhs.sharedVisitCount { return lhs.sharedVisitCount > rhs.sharedVisitCount }
        if lhs.latestVisit != rhs.latestVisit { return (lhs.latestVisit ?? .distantPast) > (rhs.latestVisit ?? .distantPast) }
        let nameOrder = lhs.companionDisplayName.localizedStandardCompare(rhs.companionDisplayName)
        if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
        return uuidLess(lhs.companionID, rhs.companionID)
    }

    private nonisolated static func visitSort(
        _ lhs: DiningCompanionInput.VisitRecord,
        _ rhs: DiningCompanionInput.VisitRecord
    ) -> Bool {
        lhs.visitedAt == rhs.visitedAt ? uuidLess(lhs.id, rhs.id) : lhs.visitedAt < rhs.visitedAt
    }

    private nonisolated static func deduplicateCompanions(
        _ values: [DiningCompanionInput.CompanionRecord]
    ) -> [DiningCompanionInput.CompanionRecord] {
        var result: [UUID: DiningCompanionInput.CompanionRecord] = [:]
        for value in values.sorted(by: { $0.updatedAt < $1.updatedAt }) { result[value.id] = value }
        return result.values.sorted { uuidLess($0.id, $1.id) }
    }

    private nonisolated static func deduplicateRestaurants(
        _ values: [DiningCompanionInput.RestaurantRecord]
    ) -> [DiningCompanionInput.RestaurantRecord] {
        var result: [UUID: DiningCompanionInput.RestaurantRecord] = [:]
        for value in values.sorted(by: { $0.updatedAt < $1.updatedAt }) { result[value.id] = value }
        return result.values.sorted { uuidLess($0.id, $1.id) }
    }

    private nonisolated static func average(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private nonisolated static func percentile(_ values: [Double], _ percentile: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let position = max(0, min(1, percentile)) * Double(values.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = Int(position.rounded(.up))
        if lower == upper { return values[lower] }
        let fraction = position - Double(lower)
        return values[lower] + (values[upper] - values[lower]) * fraction
    }

    private nonisolated static func ratio(_ count: Int, _ total: Int) -> Double {
        total == 0 ? 0 : Double(count) / Double(total)
    }

    private nonisolated static func stableUnique<T: Hashable>(_ values: [T]) -> [T] {
        var seen = Set<T>()
        return values.filter { seen.insert($0).inserted }
    }

    private nonisolated static func oneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private nonisolated static func shortDate(_ value: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: value)
        return "\(components.year ?? 0).\(components.month ?? 0).\(components.day ?? 0)"
    }

    private nonisolated static func containsAny(_ value: String, _ terms: [String]) -> Bool {
        terms.contains(where: value.contains)
    }

    private nonisolated static func uuidLess(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }
}

private extension String {
    nonisolated var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    nonisolated var normalized: String {
        precomposedStringWithCompatibilityMapping
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }
    nonisolated var nilIfEmpty: String? { isEmpty ? nil : self }
}
