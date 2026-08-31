import Foundation

nonisolated enum AnnualRecapSufficiencyPolicy {
    static let minimumSpendCoverageForProminence = 0.60
    static let minimumVisitsForMonthlyJourney = 12
    static let minimumActiveMonthsForMonthlyJourney = 4
    static let minimumVisitsForQuarterlyJourney = 6
    static let minimumActiveQuartersForQuarterlyJourney = 2
    static let minimumVisitsPerHalfForChange = 4
    static let minimumRestaurantsPerHalfForChange = 2
    static let materialShareDelta = 0.20
    static let minimumRatedRestaurantsForSourceRanking = RecommendationSourceAnalyzer.minimumRatedRestaurantsForRanking
    static let stableRatedRestaurantCount = RecommendationSourceAnalyzer.stableRatedRestaurantCount
}

nonisolated enum AnnualRecapAnalyzer {
    private struct RestaurantAggregate {
        let restaurant: MonthlyRecapInput.RestaurantRecord?
        let restaurantID: UUID
        let visits: [MonthlyRecapInput.VisitRecord]
        let averageRating: Double?
        let dishAverageRating: Double?
        let latestVisitAt: Date
        let isNew: Bool
        let imageReference: AnalysisImageReference
        let hasNote: Bool
    }

    private struct CompanionBucket {
        let record: MonthlyRecapInput.CompanionRecord
        var visitIDs = Set<UUID>()
        var restaurantIDs = Set<UUID>()
        var latestVisitAt = Date.distantPast
    }

    private struct SourceEvidence {
        let source: MonthlyRecapInput.SourceRecord
        let restaurants: [RestaurantAggregate]
        let ratings: [Double]
        let highCount: Int
        let lowCount: Int
        let repeatCount: Int
        let reliability: Double?
        let pitfall: Double?
    }

    private struct JourneyBucket {
        let id: String
        let label: String
        let month: Int
        let visits: [MonthlyRecapInput.VisitRecord]
        let aggregates: [RestaurantAggregate]
        let dominantCuisine: String?
        let explorationRate: Double
        let repeatRate: Double
    }

    static func analyze(
        _ input: MonthlyRecapInput,
        period: AnnualPeriod = .current(),
        now: Date = .now
    ) -> AnnualRecapAnalysis {
        let restaurants = deduplicate(input.restaurants).filter { $0.deletedAt == nil }
        let allVisits = deduplicate(input.visits).filter { $0.deletedAt == nil }
        let dishes = deduplicate(input.dishes).filter { $0.deletedAt == nil }
        let visitDishes = input.visitDishes.filter { $0.deletedAt == nil }
        let photos = deduplicate(input.photos).filter { $0.deletedAt == nil && $0.kind != .avatar }
        let companions = deduplicate(input.companions).filter { $0.deletedAt == nil }
        let sources = deduplicate(input.recommendationSources).filter { $0.deletedAt == nil }
        let restaurantsByID = Dictionary(uniqueKeysWithValues: restaurants.map { ($0.id, $0) })
        let annualVisits = allVisits.filter { period.contains($0.visitedAt) }.sorted(by: visitSort)
        let earliestVisits = earliestVisitsByRestaurant(allVisits)
        let dishesByID = Dictionary(uniqueKeysWithValues: dishes.map { ($0.id, $0) })
        let dishIDsByVisit = dishIDsByVisitMap(dishes: dishes, visitDishes: visitDishes)
        let aggregates = buildAggregates(
            visits: annualVisits, restaurantsByID: restaurantsByID,
            earliestVisits: earliestVisits, period: period,
            dishesByID: dishesByID, dishIDsByVisit: dishIDsByVisit, photos: photos
        )

        let favorite = favoriteAggregate(aggregates)
        let mostVisited = mostVisitedAggregate(aggregates)
        let newAggregates = aggregates.filter(\.isNew).sorted(by: newRestaurantSort)
        let highlight = highlightAggregate(aggregates)
        let favoriteStory = favorite.map { story($0, role: "年度最喜欢") }
        let mostVisitedStory = mostVisited.map { story($0, role: "年度最常去") }
        let bestNew = newAggregates.first.map { story($0, role: "年度新店高光") }
        let highlightStory = highlight.map { story($0, role: "年度高光") }
        let repeatCount = aggregates.filter {
            $0.visits.count >= 2 || (earliestVisits[$0.restaurantID]?.visitedAt ?? period.start) < period.start
        }.count
        let explorationRate = ratio(newAggregates.count, aggregates.count)
        let spend = spendSummary(visits: annualVisits, period: period)
        let companion = companionStory(companions: companions, visits: annualVisits, aggregates: aggregates)
        let recommendation = recommendationSummary(sources: sources, visits: annualVisits, aggregates: aggregates)
        let snapshots = monthlySnapshots(
            visits: annualVisits, aggregates: aggregates, restaurantsByID: restaurantsByID,
            earliestVisits: earliestVisits, period: period
        )
        let journey = tasteJourney(
            visits: annualVisits, aggregates: aggregates, snapshots: snapshots,
            restaurantsByID: restaurantsByID, earliestVisits: earliestVisits,
            period: period, photos: photos, dishesByID: dishesByID,
            dishIDsByVisit: dishIDsByVisit
        )
        let highlights = monthlyHighlights(
            snapshots: snapshots, visits: annualVisits, spend: spend, period: period
        )
        let keywords = annualKeywords(
            visits: annualVisits, aggregates: aggregates, topCompanion: companion,
            restaurantsByID: restaurantsByID, dishesByID: dishesByID,
            dishIDsByVisit: dishIDsByVisit, explorationRate: explorationRate,
            repeatRate: ratio(repeatCount, aggregates.count)
        )
        let representatives = representativeRestaurants(
            favorite: favoriteStory, mostVisited: mostVisitedStory, bestNew: bestNew,
            highlight: highlightStory, journey: journey, aggregates: aggregates
        )
        let topRestaurants = Array(representatives.prefix(5))
        let latestRevision = [
            input.restaurants.map(\.updatedAt).max(), input.visits.map(\.updatedAt).max(),
            input.dishes.map(\.updatedAt).max(), input.photos.map(\.updatedAt).max(),
            input.companions.map(\.updatedAt).max(), input.recommendationSources.map(\.updatedAt).max(),
        ].compactMap { $0 }.max() ?? .distantPast

        return AnnualRecapAnalysis(
            id: "annual:\(period.id):\(annualVisits.count):\(Int(latestRevision.timeIntervalSince1970))",
            kind: .annualReview, userDisplayName: input.userDisplayName,
            period: period, isCurrentPeriod: period.isCurrent(now: now),
            periodLabel: period.posterLabel(now: now), visitCount: annualVisits.count,
            restaurantCount: aggregates.count, newRestaurantCount: newAggregates.count,
            repeatRestaurantCount: repeatCount, explorationRate: explorationRate,
            spend: spend, favoriteRestaurant: favoriteStory,
            mostVisitedRestaurant: mostVisitedStory, topRestaurants: topRestaurants,
            topCompanion: companion, recommendationSummary: recommendation,
            tasteJourney: journey, monthlySnapshots: snapshots,
            monthlyHighlights: highlights, keywords: keywords,
            representativeRestaurants: representatives,
            sufficiency: AnalysisSufficiencyPolicy.level(
                sampleCount: annualVisits.count,
                emergingAt: AnalysisSufficiencyThresholds.annual.emerging,
                establishedAt: AnalysisSufficiencyThresholds.annual.established
            ),
            dataNote: "只分析你自己的本地有效记录。nil 消费不会按 ¥0 计算；私人备注、精确位置、内部身份、storage key 与未选择的关系不会进入年度海报。",
            generatedAt: now
        )
    }

    private static func buildAggregates(
        visits: [MonthlyRecapInput.VisitRecord],
        restaurantsByID: [UUID: MonthlyRecapInput.RestaurantRecord],
        earliestVisits: [UUID: MonthlyRecapInput.VisitRecord],
        period: AnnualPeriod,
        dishesByID: [UUID: MonthlyRecapInput.DishRecord],
        dishIDsByVisit: [UUID: Set<UUID>],
        photos: [MonthlyRecapInput.PhotoRecord]
    ) -> [RestaurantAggregate] {
        Dictionary(grouping: visits, by: \.restaurantID).map { restaurantID, values in
            let sortedVisits = values.sorted(by: visitSort)
            let visitIDs = Set(sortedVisits.map(\.id))
            let dishIDs = sortedVisits.reduce(into: Set<UUID>()) { result, visit in
                result.formUnion(dishIDsByVisit[visit.id] ?? [])
            }
            return RestaurantAggregate(
                restaurant: restaurantsByID[restaurantID], restaurantID: restaurantID,
                visits: sortedVisits, averageRating: mean(sortedVisits.compactMap(\.rating)),
                dishAverageRating: mean(dishIDs.compactMap { dishesByID[$0]?.rating }),
                latestVisitAt: sortedVisits.map(\.visitedAt).max() ?? period.start,
                isNew: earliestVisits[restaurantID].map { period.contains($0.visitedAt) } ?? false,
                imageReference: imageReference(
                    restaurantID: restaurantID, visitIDs: visitIDs,
                    dishIDs: dishIDs, photos: photos,
                    merchantImageURL: restaurantsByID[restaurantID]?.merchantImageURL
                ),
                hasNote: sortedVisits.contains {
                    $0.note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                }
            )
        }.sorted { $0.restaurantID.uuidString < $1.restaurantID.uuidString }
    }

    private static func spendSummary(
        visits: [MonthlyRecapInput.VisitRecord], period: AnnualPeriod
    ) -> AnnualSpendSummary {
        let values = AnalysisStatisticsDefinitions.recordedSpendValues(
            in: visits,
            spend: \.myActualSpend
        ).sorted()
        let coverage = AnalysisStatisticsDefinitions.coverage(
            recordedCount: values.count,
            totalCount: visits.count
        )
        let state: AnnualSpendDisplayState
        if values.isEmpty { state = .none }
        else if coverage < AnnualRecapSufficiencyPolicy.minimumSpendCoverageForProminence { state = .lowCoverage }
        else if coverage < 1 { state = .recorded }
        else { state = .complete }
        let monthly = (1...12).map { month -> AnnualMonthlySpend in
            let monthVisits = visits.filter { period.month(month).contains($0.visitedAt) }
            let monthValues = monthVisits.compactMap(validSpend)
            return AnnualMonthlySpend(
                month: month, recordedTotal: monthValues.isEmpty ? nil : monthValues.reduce(0, +),
                recordedVisitCount: monthValues.count, visitCount: monthVisits.count,
                coverage: ratio(monthValues.count, monthVisits.count)
            )
        }
        return AnnualSpendSummary(
            recordedTotal: values.isEmpty ? nil : values.reduce(0, +), median: AnalysisStatisticsDefinitions.median(values),
            recordedVisitCount: values.count, visitCount: visits.count, coverage: coverage,
            displayState: state, monthlyDistribution: monthly,
            sufficiency: AnalysisSufficiencyPolicy.level(sampleCount: values.count, emergingAt: 3, establishedAt: 12)
        )
    }

    private static func validSpend(_ visit: MonthlyRecapInput.VisitRecord) -> Double? {
        guard let spend = visit.myActualSpend else { return nil }
        let value = NSDecimalNumber(decimal: spend).doubleValue
        return value.isFinite && value >= 0 ? value : nil
    }

    private static func favoriteAggregate(_ values: [RestaurantAggregate]) -> RestaurantAggregate? {
        values.filter { $0.averageRating != nil || $0.visits.count >= 2 }.sorted(by: favoriteSort).first
    }

    private static func favoriteSort(_ lhs: RestaurantAggregate, _ rhs: RestaurantAggregate) -> Bool {
        let lhsScore = favoriteScore(lhs), rhsScore = favoriteScore(rhs)
        if abs(lhsScore - rhsScore) > 0.000_001 { return lhsScore > rhsScore }
        if lhs.averageRating != rhs.averageRating { return (lhs.averageRating ?? -1) > (rhs.averageRating ?? -1) }
        if lhs.visits.count != rhs.visits.count { return lhs.visits.count > rhs.visits.count }
        if lhs.latestVisitAt != rhs.latestVisitAt { return lhs.latestVisitAt > rhs.latestVisitAt }
        return lhs.restaurantID.uuidString < rhs.restaurantID.uuidString
    }

    private static func favoriteScore(_ value: RestaurantAggregate) -> Double {
        let rating = (value.averageRating ?? 0) * 0.72
        let evidence = min(1, Double(value.visits.count) / 6) * 0.70
        let repeatBonus = value.visits.count >= 2 ? 0.35 : 0
        let dish = (value.dishAverageRating ?? 0) / 5 * 0.15
        return rating + evidence + repeatBonus + dish
    }

    private static func mostVisitedAggregate(_ values: [RestaurantAggregate]) -> RestaurantAggregate? {
        values.sorted {
            if $0.visits.count != $1.visits.count { return $0.visits.count > $1.visits.count }
            if $0.averageRating != $1.averageRating { return ($0.averageRating ?? -1) > ($1.averageRating ?? -1) }
            if $0.latestVisitAt != $1.latestVisitAt { return $0.latestVisitAt > $1.latestVisitAt }
            return $0.restaurantID.uuidString < $1.restaurantID.uuidString
        }.first
    }

    private static func newRestaurantSort(_ lhs: RestaurantAggregate, _ rhs: RestaurantAggregate) -> Bool {
        if lhs.averageRating != rhs.averageRating { return (lhs.averageRating ?? -1) > (rhs.averageRating ?? -1) }
        if lhs.visits.count != rhs.visits.count { return lhs.visits.count > rhs.visits.count }
        if lhs.imageReference != rhs.imageReference { return imageRank(lhs.imageReference) < imageRank(rhs.imageReference) }
        return lhs.restaurantID.uuidString < rhs.restaurantID.uuidString
    }

    private static func highlightAggregate(_ values: [RestaurantAggregate]) -> RestaurantAggregate? {
        values.sorted {
            let lhs = highlightScore($0), rhs = highlightScore($1)
            if abs(lhs - rhs) > 0.000_001 { return lhs > rhs }
            if $0.latestVisitAt != $1.latestVisitAt { return $0.latestVisitAt > $1.latestVisitAt }
            return $0.restaurantID.uuidString < $1.restaurantID.uuidString
        }.first
    }

    private static func highlightScore(_ value: RestaurantAggregate) -> Double {
        (value.averageRating ?? 0) * 1.4 + min(6, Double(value.visits.count)) * 0.45
            + (value.isNew ? 0.45 : 0) + (value.imageReference == .none ? 0 : 0.55)
            + (value.hasNote ? 0.25 : 0)
    }

    private static func story(_ value: RestaurantAggregate, role: String) -> AnnualRestaurantStory {
        let rating = value.averageRating.map { " · 平均 \(String(format: "%.1f", $0)) 分" } ?? ""
        return AnnualRestaurantStory(
            id: value.restaurantID, name: value.restaurant?.name ?? "未命名餐厅",
            city: value.restaurant?.city ?? "", role: role,
            detail: "\(value.visits.count) 次到访\(rating)\(value.isNew ? " · 年度新店" : "")",
            visitCount: value.visits.count, averageRating: value.averageRating,
            latestVisitAt: value.latestVisitAt, isNew: value.isNew,
            imageReference: value.imageReference
        )
    }

    private static func companionStory(
        companions: [MonthlyRecapInput.CompanionRecord],
        visits: [MonthlyRecapInput.VisitRecord], aggregates: [RestaurantAggregate]
    ) -> AnnualCompanionStory? {
        let resolver = IdentityResolver(values: companions.map { ($0.id, $0.identifiers, $0.displayName) })
        let records = Dictionary(uniqueKeysWithValues: companions.map { ($0.id, $0) })
        var buckets: [UUID: CompanionBucket] = [:]
        for visit in visits {
            var ids = Set<UUID>()
            for identifier in visit.companionIDs {
                if let id = resolver.resolve(identifier: identifier) { ids.insert(id) }
            }
            if visit.companionIDs.isEmpty {
                for name in visit.companionNames {
                    if let id = resolver.resolveUniqueName(name) { ids.insert(id) }
                }
            }
            for id in ids {
                guard let record = records[id] else { continue }
                var bucket = buckets[id] ?? CompanionBucket(record: record)
                bucket.visitIDs.insert(visit.id)
                bucket.restaurantIDs.insert(visit.restaurantID)
                bucket.latestVisitAt = max(bucket.latestVisitAt, visit.visitedAt)
                buckets[id] = bucket
            }
        }
        guard let winner = buckets.values.sorted(by: companionSort).first else { return nil }
        let representative = aggregates.filter { winner.restaurantIDs.contains($0.restaurantID) }
            .sorted { lhs, rhs in
                let lhsCount = lhs.visits.filter { winner.visitIDs.contains($0.id) }.count
                let rhsCount = rhs.visits.filter { winner.visitIDs.contains($0.id) }.count
                if lhsCount != rhsCount { return lhsCount > rhsCount }
                return lhs.restaurantID.uuidString < rhs.restaurantID.uuidString
            }.first.map { story($0, role: "共同餐桌") }
        return AnnualCompanionStory(
            id: winner.record.id, displayName: winner.record.displayName,
            sharedVisitCount: winner.visitIDs.count, restaurantCount: winner.restaurantIDs.count,
            representativeRestaurant: representative,
            sufficiency: AnalysisSufficiencyPolicy.level(sampleCount: winner.visitIDs.count, emergingAt: 2, establishedAt: 6)
        )
    }

    private static func companionSort(_ lhs: CompanionBucket, _ rhs: CompanionBucket) -> Bool {
        if lhs.visitIDs.count != rhs.visitIDs.count { return lhs.visitIDs.count > rhs.visitIDs.count }
        if lhs.restaurantIDs.count != rhs.restaurantIDs.count { return lhs.restaurantIDs.count > rhs.restaurantIDs.count }
        if lhs.latestVisitAt != rhs.latestVisitAt { return lhs.latestVisitAt > rhs.latestVisitAt }
        return lhs.record.id.uuidString < rhs.record.id.uuidString
    }

    private static func recommendationSummary(
        sources: [MonthlyRecapInput.SourceRecord],
        visits: [MonthlyRecapInput.VisitRecord], aggregates: [RestaurantAggregate]
    ) -> AnnualRecommendationSummary {
        let resolver = SourceResolver(sources: sources)
        let sourcesByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
        let aggregateByID = Dictionary(uniqueKeysWithValues: aggregates.map { ($0.restaurantID, $0) })
        let groupedVisits = Dictionary(grouping: visits, by: \.restaurantID)
        var bySource: [UUID: [RestaurantAggregate]] = [:]
        for (restaurantID, restaurantVisits) in groupedVisits {
            guard let aggregate = aggregateByID[restaurantID] else { continue }
            let sourceID = restaurantVisits.sorted(by: visitSort).compactMap(resolver.resolve).first
            if let sourceID { bySource[sourceID, default: []].append(aggregate) }
        }
        let allRatings = bySource.values.flatMap { $0.compactMap(\.averageRating) }
        let overall = mean(allRatings)
        let evidence = sources.compactMap { source -> SourceEvidence? in
            let restaurants = bySource[source.id] ?? []
            guard !restaurants.isEmpty else { return nil }
            let ratings = restaurants.compactMap(\.averageRating)
            let high = ratings.filter { $0 >= RecommendationSourceAnalyzer.highRatingThreshold }.count
            let low = ratings.filter { $0 <= RecommendationSourceAnalyzer.lowRatingThreshold }.count
            let repeated = restaurants.filter { $0.visits.count >= 2 }.count
            let deviation = standardDeviation(ratings) ?? 1
            let sampleConfidence = min(1, Double(ratings.count) / Double(AnnualRecapSufficiencyPolicy.stableRatedRestaurantCount))
            let normalizedAverage = max(0, min(1, ((mean(ratings) ?? 2.5) - 0.5) / 4.5))
            let highRate = ratio(high, ratings.count), lowRate = ratio(low, ratings.count)
            let repeatRate = ratio(repeated, restaurants.count)
            let stability = max(0, 1 - min(1, deviation / 1.5))
            let baseline = max(0, min(1, ((mean(ratings) ?? 0) - (overall ?? mean(ratings) ?? 0) + 1) / 2))
            let eligible = ratings.count >= AnnualRecapSufficiencyPolicy.minimumRatedRestaurantsForSourceRanking
            let reliability = eligible
                ? normalizedAverage * 0.30 + highRate * 0.27 + repeatRate * 0.16
                    + stability * 0.10 + baseline * 0.10 + sampleConfidence * 0.07
                : nil
            let lowAverage = max(0, min(1, (3.5 - (mean(ratings) ?? 3.5)) / 3))
            let pitfall = eligible
                ? lowRate * 0.34 + (1 - highRate) * 0.22 + (1 - repeatRate) * 0.10
                    + lowAverage * 0.22 + (1 - stability) * 0.05 + sampleConfidence * 0.07
                : nil
            return SourceEvidence(
                source: sourcesByID[source.id] ?? source, restaurants: restaurants,
                ratings: ratings, highCount: high, lowCount: low, repeatCount: repeated,
                reliability: reliability, pitfall: pitfall
            )
        }
        let most = evidence.sorted(by: mostUsedSourceSort).first
        let eligible = evidence.filter { $0.reliability != nil && $0.pitfall != nil }
        let best = eligible.count >= 2 ? eligible.sorted(by: bestSourceSort).first : nil
        let worst = eligible.count >= 2 ? eligible.sorted(by: worstSourceSort).first : nil
        return AnnualRecommendationSummary(
            mostUsed: most.map { sourceConclusion($0, kind: "年度最常使用来源") },
            best: best.map { sourceConclusion($0, kind: "年度最靠谱推荐来源") },
            worst: worst.map { sourceConclusion($0, kind: "年度最坑推荐来源") },
            usedSourceCount: evidence.count,
            attributedRestaurantCount: evidence.reduce(0) { $0 + $1.restaurants.count },
            rankingSufficiency: eligible.count >= 2 ? .established : (evidence.isEmpty ? .insufficient : .emerging)
        )
    }

    private static func sourceConclusion(_ value: SourceEvidence, kind: String) -> AnnualSourceConclusion {
        let average = mean(value.ratings)
        let representative: RestaurantAggregate?
        if kind.contains("最坑") {
            representative = value.restaurants.sorted {
                if $0.averageRating != $1.averageRating { return ($0.averageRating ?? 6) < ($1.averageRating ?? 6) }
                return $0.restaurantID.uuidString < $1.restaurantID.uuidString
            }.first
        } else {
            representative = value.restaurants.sorted(by: favoriteSort).first
        }
        let statement: String
        if kind.contains("最常") {
            statement = "通过 \(value.source.displayName) 记录了 \(value.restaurants.count) 家不同餐厅。"
        } else if kind.contains("最坑") {
            statement = "\(value.ratings.count) 家有评分餐厅中，\(value.lowCount) 家不高于 2.5 分；样本达到 P4-C 门槛后才显示。"
        } else {
            statement = "\(value.ratings.count) 家有评分餐厅中，\(value.highCount) 家达到 4.0 分，\(value.repeatCount) 家后来又去。"
        }
        return AnnualSourceConclusion(
            sourceID: value.source.id, displayName: value.source.displayName,
            sourceType: value.source.sourceType, title: kind, statement: statement,
            restaurantCount: value.restaurants.count, ratedRestaurantCount: value.ratings.count,
            averageRating: average,
            score: kind.contains("最坑") ? value.pitfall : value.reliability,
            representativeRestaurant: representative.map { story($0, role: kind) },
            sufficiency: AnalysisSufficiencyPolicy.level(
                sampleCount: value.ratings.count, emergingAt: 2,
                establishedAt: AnnualRecapSufficiencyPolicy.minimumRatedRestaurantsForSourceRanking
            )
        )
    }

    private static func monthlySnapshots(
        visits: [MonthlyRecapInput.VisitRecord], aggregates: [RestaurantAggregate],
        restaurantsByID: [UUID: MonthlyRecapInput.RestaurantRecord],
        earliestVisits: [UUID: MonthlyRecapInput.VisitRecord], period: AnnualPeriod
    ) -> [AnnualMonthSnapshot] {
        (1...12).map { month in
            let monthPeriod = period.month(month)
            let monthVisits = visits.filter { monthPeriod.contains($0.visitedAt) }
            let ids = Set(monthVisits.map(\.restaurantID))
            let newCount = ids.filter { id in
                earliestVisits[id].map { monthPeriod.contains($0.visitedAt) } ?? false
            }.count
            let repeatCount = ids.filter { id in
                monthVisits.filter { $0.restaurantID == id }.count >= 2
                    || (earliestVisits[id]?.visitedAt ?? monthPeriod.start) < monthPeriod.start
            }.count
            return AnnualMonthSnapshot(
                month: month, visitCount: monthVisits.count, restaurantCount: ids.count,
                newRestaurantCount: newCount,
                dominantCuisine: dominantCuisine(visits: monthVisits, restaurantsByID: restaurantsByID)?.name,
                explorationRate: ratio(newCount, ids.count), repeatRate: ratio(repeatCount, ids.count)
            )
        }
    }

    private static func tasteJourney(
        visits: [MonthlyRecapInput.VisitRecord], aggregates: [RestaurantAggregate],
        snapshots: [AnnualMonthSnapshot],
        restaurantsByID: [UUID: MonthlyRecapInput.RestaurantRecord],
        earliestVisits: [UUID: MonthlyRecapInput.VisitRecord], period: AnnualPeriod,
        photos: [MonthlyRecapInput.PhotoRecord],
        dishesByID: [UUID: MonthlyRecapInput.DishRecord], dishIDsByVisit: [UUID: Set<UUID>]
    ) -> AnnualTasteJourney {
        let activeMonths = snapshots.filter { $0.visitCount > 0 }
        let granularity: AnnualTasteJourneyGranularity
        if visits.count >= AnnualRecapSufficiencyPolicy.minimumVisitsForMonthlyJourney,
           activeMonths.count >= AnnualRecapSufficiencyPolicy.minimumActiveMonthsForMonthlyJourney {
            granularity = .monthly
        } else {
            let activeQuarterCount = Set(visits.map { (period.calendar.component(.month, from: $0.visitedAt) - 1) / 3 }).count
            granularity = visits.count >= AnnualRecapSufficiencyPolicy.minimumVisitsForQuarterlyJourney
                && activeQuarterCount >= AnnualRecapSufficiencyPolicy.minimumActiveQuartersForQuarterlyJourney
                ? .quarterly : .insufficient
        }
        guard granularity != .insufficient else {
            return AnnualTasteJourney(granularity: .insufficient, milestones: [], changeSummaries: [], sufficiency: .insufficient)
        }
        let buckets: [JourneyBucket]
        if granularity == .monthly {
            buckets = activeMonths.map { snapshot in
                journeyBucket(
                    id: "month-\(snapshot.month)", label: "\(snapshot.month) 月",
                    month: snapshot.month,
                    visits: visits.filter { period.month(snapshot.month).contains($0.visitedAt) },
                    aggregates: aggregates, restaurantsByID: restaurantsByID,
                    earliestVisits: earliestVisits, period: period
                )
            }
        } else {
            buckets = (1...4).compactMap { quarter in
                let quarterVisits = visits.filter {
                    let month = period.calendar.component(.month, from: $0.visitedAt)
                    return ((month - 1) / 3) + 1 == quarter
                }
                guard !quarterVisits.isEmpty else { return nil }
                return journeyBucket(
                    id: "quarter-\(quarter)", label: "第 \(quarter) 季度",
                    month: (quarter - 1) * 3 + 1, visits: quarterVisits,
                    aggregates: aggregates, restaurantsByID: restaurantsByID,
                    earliestVisits: earliestVisits, period: period
                )
            }
        }
        let selected = selectJourneyBuckets(buckets)
        let aggregateByID = Dictionary(uniqueKeysWithValues: aggregates.map { ($0.restaurantID, $0) })
        let milestones = selected.map { bucket -> AnnualTasteMilestone in
            let representativeID = Dictionary(grouping: bucket.visits, by: \.restaurantID).sorted {
                if $0.value.count != $1.value.count { return $0.value.count > $1.value.count }
                return $0.key.uuidString < $1.key.uuidString
            }.first?.key
            let aggregate = representativeID.flatMap { aggregateByID[$0] }
            let title = bucket.dominantCuisine.map { "\($0) 出现得更多" } ?? "记录了 \(bucket.visits.count) 次用餐"
            let detail: String
            if bucket.explorationRate >= 0.6 { detail = "\(bucket.visits.count) 次到访里，新店探索更集中。" }
            else if bucket.repeatRate >= 0.6 { detail = "\(bucket.visits.count) 次到访里，更常回到熟悉的店。" }
            else { detail = "\(bucket.visits.count) 次到访，\(Set(bucket.visits.map(\.restaurantID)).count) 家餐厅。" }
            return AnnualTasteMilestone(
                id: bucket.id, periodLabel: bucket.label, title: title, detail: detail,
                month: bucket.month, visitCount: bucket.visits.count,
                restaurantID: representativeID,
                imageReference: aggregate?.imageReference ?? .none
            )
        }
        let summaries = annualChangeSummaries(
            visits: visits, restaurantsByID: restaurantsByID,
            earliestVisits: earliestVisits, period: period
        )
        return AnnualTasteJourney(
            granularity: granularity, milestones: Array(milestones.prefix(5)),
            changeSummaries: Array(summaries.prefix(3)),
            sufficiency: AnalysisSufficiencyPolicy.level(sampleCount: visits.count, emergingAt: 6, establishedAt: 18)
        )
    }

    private static func journeyBucket(
        id: String, label: String, month: Int,
        visits: [MonthlyRecapInput.VisitRecord], aggregates: [RestaurantAggregate],
        restaurantsByID: [UUID: MonthlyRecapInput.RestaurantRecord],
        earliestVisits: [UUID: MonthlyRecapInput.VisitRecord], period: AnnualPeriod
    ) -> JourneyBucket {
        let ids = Set(visits.map(\.restaurantID))
        let newCount = ids.filter { id in earliestVisits[id].map { period.contains($0.visitedAt) } ?? false }.count
        let repeatCount = ids.filter { id in
            visits.filter { $0.restaurantID == id }.count >= 2
                || (earliestVisits[id]?.visitedAt ?? period.start) < period.start
        }.count
        return JourneyBucket(
            id: id, label: label, month: month, visits: visits,
            aggregates: aggregates.filter { ids.contains($0.restaurantID) },
            dominantCuisine: dominantCuisine(visits: visits, restaurantsByID: restaurantsByID)?.name,
            explorationRate: ratio(newCount, ids.count), repeatRate: ratio(repeatCount, ids.count)
        )
    }

    private static func selectJourneyBuckets(_ values: [JourneyBucket]) -> [JourneyBucket] {
        guard values.count > 5 else { return values }
        var selected: [JourneyBucket] = []
        if let first = values.first { selected.append(first) }
        for value in values.dropFirst().dropLast() {
            guard selected.count < 4 else { break }
            let previous = selected.last
            if value.dominantCuisine != previous?.dominantCuisine
                || abs(value.explorationRate - (previous?.explorationRate ?? 0)) >= 0.25
                || abs(value.repeatRate - (previous?.repeatRate ?? 0)) >= 0.25 {
                selected.append(value)
            }
        }
        if selected.count < 4 {
            for value in values.sorted(by: { $0.visits.count > $1.visits.count })
            where !selected.contains(where: { $0.id == value.id }) && selected.count < 4 {
                selected.append(value)
            }
        }
        if let last = values.last, !selected.contains(where: { $0.id == last.id }) { selected.append(last) }
        return selected.sorted { $0.month < $1.month }
    }

    private static func annualChangeSummaries(
        visits: [MonthlyRecapInput.VisitRecord],
        restaurantsByID: [UUID: MonthlyRecapInput.RestaurantRecord],
        earliestVisits: [UUID: MonthlyRecapInput.VisitRecord], period: AnnualPeriod
    ) -> [String] {
        let first = visits.filter { period.calendar.component(.month, from: $0.visitedAt) <= 6 }
        let second = visits.filter { period.calendar.component(.month, from: $0.visitedAt) >= 7 }
        guard first.count >= AnnualRecapSufficiencyPolicy.minimumVisitsPerHalfForChange,
              second.count >= AnnualRecapSufficiencyPolicy.minimumVisitsPerHalfForChange,
              Set(first.map(\.restaurantID)).count >= AnnualRecapSufficiencyPolicy.minimumRestaurantsPerHalfForChange,
              Set(second.map(\.restaurantID)).count >= AnnualRecapSufficiencyPolicy.minimumRestaurantsPerHalfForChange else { return [] }
        var result: [String] = []
        let firstCuisine = dominantCuisine(visits: first, restaurantsByID: restaurantsByID)
        let secondCuisine = dominantCuisine(visits: second, restaurantsByID: restaurantsByID)
        if let secondCuisine, secondCuisine.share - cuisineShare(
            secondCuisine.name, visits: first, restaurantsByID: restaurantsByID
        ) >= AnnualRecapSufficiencyPolicy.materialShareDelta {
            result.append("下半年更常出现 \(secondCuisine.name)：占比比上半年高 \(Int(((secondCuisine.share - cuisineShare(secondCuisine.name, visits: first, restaurantsByID: restaurantsByID)) * 100).rounded())) 个百分点。")
        } else if let firstCuisine, firstCuisine.share - cuisineShare(
            firstCuisine.name, visits: second, restaurantsByID: restaurantsByID
        ) >= AnnualRecapSufficiencyPolicy.materialShareDelta {
            result.append("\(firstCuisine.name) 更集中在上半年；下半年占比下降。")
        }
        let firstExplore = explorationRate(visits: first, earliestVisits: earliestVisits, period: period)
        let secondExplore = explorationRate(visits: second, earliestVisits: earliestVisits, period: period)
        if secondExplore - firstExplore >= AnnualRecapSufficiencyPolicy.materialShareDelta {
            result.append("下半年新店探索比例比上半年高 \(Int(((secondExplore - firstExplore) * 100).rounded())) 个百分点。")
        } else if firstExplore - secondExplore >= AnnualRecapSufficiencyPolicy.materialShareDelta {
            result.append("下半年更常回到熟店；新店比例比上半年低 \(Int(((firstExplore - secondExplore) * 100).rounded())) 个百分点。")
        }
        let firstContext = dominantLabel(first.flatMap(\.diningOccasionLabels))
        let secondContext = dominantLabel(second.flatMap(\.diningOccasionLabels))
        if let secondContext, secondContext.name != firstContext?.name,
           secondContext.share >= 0.4 {
            result.append("下半年更常记录“\(secondContext.name)”场景。")
        }
        return result
    }

    private static func monthlyHighlights(
        snapshots: [AnnualMonthSnapshot], visits: [MonthlyRecapInput.VisitRecord],
        spend: AnnualSpendSummary, period: AnnualPeriod
    ) -> [AnnualMonthHighlight] {
        let active = snapshots.filter { $0.visitCount > 0 }
        var result: [AnnualMonthHighlight] = []
        var seenMonths = Set<Int>()
        if let busiest = active.sorted(by: { $0.visitCount == $1.visitCount ? $0.month < $1.month : $0.visitCount > $1.visitCount }).first {
            result.append(.init(kind: .busiest, month: busiest.month, title: "吃得最多的月份", value: "\(busiest.month) 月 · \(busiest.visitCount) 次", detail: "记录了 \(busiest.restaurantCount) 家餐厅。"))
            seenMonths.insert(busiest.month)
        }
        if let explorer = active.filter({ $0.newRestaurantCount > 0 }).sorted(by: {
            $0.newRestaurantCount == $1.newRestaurantCount ? $0.month < $1.month : $0.newRestaurantCount > $1.newRestaurantCount
        }).first, seenMonths.insert(explorer.month).inserted {
            result.append(.init(kind: .exploration, month: explorer.month, title: "新店最多的月份", value: "\(explorer.month) 月 · \(explorer.newRestaurantCount) 家新店", detail: "按人生第一次有效 Visit 计算。"))
        }
        let ratedByMonth = Dictionary(grouping: visits.filter { $0.rating != nil }) {
            period.calendar.component(.month, from: $0.visitedAt)
        }.compactMap { month, values -> (Int, Double, Int)? in
            guard values.count >= 2, let average = mean(values.compactMap(\.rating)) else { return nil }
            return (month, average, values.count)
        }.sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }
        if let rated = ratedByMonth.first, seenMonths.insert(rated.0).inserted {
            result.append(.init(kind: .rating, month: rated.0, title: "评分更高的月份", value: "\(rated.0) 月 · \(String(format: "%.1f", rated.1)) 分", detail: "基于 \(rated.2) 次有评分到访。"))
        }
        if result.count < 3, let highSpend = spend.monthlyDistribution.filter({
            $0.recordedTotal != nil && $0.coverage >= AnnualRecapSufficiencyPolicy.minimumSpendCoverageForProminence
        }).sorted(by: { ($0.recordedTotal ?? 0) == ($1.recordedTotal ?? 0) ? $0.month < $1.month : ($0.recordedTotal ?? 0) > ($1.recordedTotal ?? 0) }).first,
           seenMonths.insert(highSpend.month).inserted {
            result.append(.init(kind: .spend, month: highSpend.month, title: "已记录消费较高", value: "\(highSpend.month) 月 · ¥\(Int((highSpend.recordedTotal ?? 0).rounded()))", detail: "该月消费覆盖 \(Int((highSpend.coverage * 100).rounded()))%。"))
        }
        return Array(result.prefix(3))
    }

    private static func annualKeywords(
        visits: [MonthlyRecapInput.VisitRecord], aggregates: [RestaurantAggregate],
        topCompanion: AnnualCompanionStory?,
        restaurantsByID: [UUID: MonthlyRecapInput.RestaurantRecord],
        dishesByID: [UUID: MonthlyRecapInput.DishRecord],
        dishIDsByVisit: [UUID: Set<UUID>], explorationRate: Double, repeatRate: Double
    ) -> [String] {
        guard !visits.isEmpty else { return [] }
        var candidates: [(category: String, value: String, score: Double)] = []
        let cuisineCounts = labelCounts(visits.flatMap { restaurantsByID[$0.restaurantID]?.tags ?? [] })
        for (index, item) in cuisineCounts.prefix(2).enumerated() {
            candidates.append(("cuisine-\(index)", item.name, Double(item.count)))
        }
        let dishNames = visits.flatMap { visit in
            (dishIDsByVisit[visit.id] ?? []).compactMap { dishesByID[$0]?.name }
        }
        if let dish = labelCounts(dishNames).first { candidates.append(("dish", dish.name, Double(dish.count) + 0.2)) }
        if explorationRate >= 0.55 { candidates.append(("behavior", "探新店", explorationRate * 10)) }
        else if repeatRate >= 0.55 { candidates.append(("behavior", "熟店派", repeatRate * 10)) }
        if let context = labelCounts(visits.flatMap(\.diningOccasionLabels)).first, context.count >= 2 {
            candidates.append(("context", context.name, Double(context.count)))
        }
        if let companion = topCompanion, companion.sharedVisitCount >= 3 {
            candidates.append(("companion", "常和\(companion.displayName)吃", Double(companion.sharedVisitCount)))
        }
        var categories = Set<String>(), normalizedValues = Set<String>()
        return candidates.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.value.localizedStandardCompare($1.value) == .orderedAscending
        }.compactMap { candidate in
            let normalized = normalize(candidate.value)
            guard categories.insert(candidate.category).inserted,
                  normalizedValues.insert(normalized).inserted else { return nil }
            return candidate.value
        }.prefix(6).map { $0 }
    }

    private static func representativeRestaurants(
        favorite: AnnualRestaurantStory?, mostVisited: AnnualRestaurantStory?,
        bestNew: AnnualRestaurantStory?, highlight: AnnualRestaurantStory?,
        journey: AnnualTasteJourney, aggregates: [RestaurantAggregate]
    ) -> [AnnualRestaurantStory] {
        let map = Dictionary(uniqueKeysWithValues: aggregates.map { ($0.restaurantID, $0) })
        var result: [AnnualRestaurantStory] = [], seen = Set<UUID>()
        func append(_ value: AnnualRestaurantStory?) {
            guard let value, seen.insert(value.id).inserted else { return }
            result.append(value)
        }
        append(favorite); append(mostVisited); append(bestNew)
        for milestone in journey.milestones {
            guard let id = milestone.restaurantID, let aggregate = map[id] else { continue }
            append(story(aggregate, role: "\(milestone.periodLabel) 味觉节点"))
        }
        append(highlight)
        for aggregate in aggregates.sorted(by: favoriteSort) where result.count < 6 {
            append(story(aggregate, role: "年度代表餐厅"))
        }
        return Array(result.prefix(6))
    }

    private static func dominantCuisine(
        visits: [MonthlyRecapInput.VisitRecord],
        restaurantsByID: [UUID: MonthlyRecapInput.RestaurantRecord]
    ) -> (name: String, share: Double)? {
        let values = visits.flatMap { visit in restaurantsByID[visit.restaurantID]?.tags ?? [] }
        guard let first = labelCounts(values).first else { return nil }
        return (first.name, ratio(first.count, values.count))
    }

    private static func cuisineShare(
        _ cuisine: String, visits: [MonthlyRecapInput.VisitRecord],
        restaurantsByID: [UUID: MonthlyRecapInput.RestaurantRecord]
    ) -> Double {
        let values = visits.flatMap { restaurantsByID[$0.restaurantID]?.tags ?? [] }
        return ratio(values.filter { normalize($0) == normalize(cuisine) }.count, values.count)
    }

    private static func explorationRate(
        visits: [MonthlyRecapInput.VisitRecord],
        earliestVisits: [UUID: MonthlyRecapInput.VisitRecord], period: AnnualPeriod
    ) -> Double {
        let ids = Set(visits.map(\.restaurantID))
        let newCount = ids.filter { earliestVisits[$0].map { period.contains($0.visitedAt) } ?? false }.count
        return ratio(newCount, ids.count)
    }

    private static func imageReference(
        restaurantID: UUID, visitIDs: Set<UUID>, dishIDs: Set<UUID>,
        photos: [MonthlyRecapInput.PhotoRecord], merchantImageURL: URL?
    ) -> AnalysisImageReference {
        let eligible = photos.filter {
            ($0.kind == .dish && $0.dishID.map(dishIDs.contains) == true)
                || ($0.kind == .visit && $0.visitID.map(visitIDs.contains) == true)
                || ($0.kind == .restaurantMarker && $0.restaurantID == restaurantID)
        }
        let selected = eligible.sorted {
            let lhs = photoPriority($0), rhs = photoPriority($1)
            if lhs != rhs { return lhs < rhs }
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id.uuidString < $1.id.uuidString
        }.first
        return selected.map { .photo($0.id) }
            ?? merchantImageURL.map(AnalysisImageReference.provider)
            ?? .none
    }

    private static func photoPriority(_ value: MonthlyRecapInput.PhotoRecord) -> Int {
        switch value.kind {
        case .dish: 0
        case .visit: 1
        case .restaurantMarker: 2
        case .avatar: 3
        }
    }

    private static func imageRank(_ value: AnalysisImageReference) -> Int {
        switch value { case .photo: 0; case .provider: 1; case .asset: 2; case .none: 3 }
    }

    private static func earliestVisitsByRestaurant(
        _ visits: [MonthlyRecapInput.VisitRecord]
    ) -> [UUID: MonthlyRecapInput.VisitRecord] {
        visits.reduce(into: [:]) { result, visit in
            if let current = result[visit.restaurantID] {
                if visitSort(visit, current) { result[visit.restaurantID] = visit }
            } else { result[visit.restaurantID] = visit }
        }
    }

    private static func dishIDsByVisitMap(
        dishes: [MonthlyRecapInput.DishRecord], visitDishes: [MonthlyRecapInput.VisitDishRecord]
    ) -> [UUID: Set<UUID>] {
        var result: [UUID: Set<UUID>] = [:]
        for dish in dishes { result[dish.originVisitID, default: []].insert(dish.id) }
        for item in visitDishes { result[item.visitID, default: []].insert(item.dishID) }
        return result
    }

    private struct IdentityResolver {
        let identifiers: [String: UUID]
        let names: [String: UUID]
        init(values: [(UUID, [String], String)]) {
            var identifierMap: [String: UUID] = [:]
            for (id, values, _) in values { for value in values { identifierMap[normalize(value)] = id } }
            let grouped = Dictionary(grouping: values, by: { normalize($0.2) })
            identifiers = identifierMap
            names = grouped.compactMapValues { $0.count == 1 ? $0[0].0 : nil }
        }
        func resolve(identifier: String) -> UUID? { identifiers[normalize(identifier)] }
        func resolveUniqueName(_ value: String) -> UUID? { names[normalize(value)] }
    }

    private struct SourceResolver {
        let identity: IdentityResolver
        init(sources: [MonthlyRecapInput.SourceRecord]) {
            identity = IdentityResolver(values: sources.map { ($0.id, $0.identifiers, $0.displayName) })
        }
        func resolve(_ visit: MonthlyRecapInput.VisitRecord) -> UUID? {
            if let identifier = visit.recommendationSourceID?.trimmingCharacters(in: .whitespacesAndNewlines),
               !identifier.isEmpty { return identity.resolve(identifier: identifier) }
            guard let name = visit.recommendationSourceText?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { return nil }
            return identity.resolveUniqueName(name)
        }
    }

    private static func mostUsedSourceSort(_ lhs: SourceEvidence, _ rhs: SourceEvidence) -> Bool {
        if lhs.restaurants.count != rhs.restaurants.count { return lhs.restaurants.count > rhs.restaurants.count }
        if lhs.ratings.count != rhs.ratings.count { return lhs.ratings.count > rhs.ratings.count }
        return lhs.source.id.uuidString < rhs.source.id.uuidString
    }
    private static func bestSourceSort(_ lhs: SourceEvidence, _ rhs: SourceEvidence) -> Bool {
        if lhs.reliability != rhs.reliability { return (lhs.reliability ?? 0) > (rhs.reliability ?? 0) }
        if lhs.ratings.count != rhs.ratings.count { return lhs.ratings.count > rhs.ratings.count }
        return lhs.source.id.uuidString < rhs.source.id.uuidString
    }
    private static func worstSourceSort(_ lhs: SourceEvidence, _ rhs: SourceEvidence) -> Bool {
        if lhs.pitfall != rhs.pitfall { return (lhs.pitfall ?? 0) > (rhs.pitfall ?? 0) }
        if lhs.ratings.count != rhs.ratings.count { return lhs.ratings.count > rhs.ratings.count }
        return lhs.source.id.uuidString < rhs.source.id.uuidString
    }

    private static func visitSort(
        _ lhs: MonthlyRecapInput.VisitRecord, _ rhs: MonthlyRecapInput.VisitRecord
    ) -> Bool {
        lhs.visitedAt == rhs.visitedAt ? lhs.id.uuidString < rhs.id.uuidString : lhs.visitedAt < rhs.visitedAt
    }

    private static func deduplicate(
        _ values: [MonthlyRecapInput.RestaurantRecord]
    ) -> [MonthlyRecapInput.RestaurantRecord] {
        Dictionary(grouping: values, by: \.id).compactMap { _, items in
            items.max { $0.updatedAt == $1.updatedAt ? $0.name > $1.name : $0.updatedAt < $1.updatedAt }
        }
    }
    private static func deduplicate(
        _ values: [MonthlyRecapInput.VisitRecord]
    ) -> [MonthlyRecapInput.VisitRecord] {
        Dictionary(grouping: values, by: \.id).compactMap { _, items in
            items.max { $0.updatedAt == $1.updatedAt ? $0.visitedAt > $1.visitedAt : $0.updatedAt < $1.updatedAt }
        }
    }
    private static func deduplicate(
        _ values: [MonthlyRecapInput.DishRecord]
    ) -> [MonthlyRecapInput.DishRecord] {
        Dictionary(grouping: values, by: \.id).compactMap { _, items in
            items.max { $0.updatedAt == $1.updatedAt ? $0.name > $1.name : $0.updatedAt < $1.updatedAt }
        }
    }
    private static func deduplicate(
        _ values: [MonthlyRecapInput.PhotoRecord]
    ) -> [MonthlyRecapInput.PhotoRecord] {
        Dictionary(grouping: values, by: \.id).compactMap { _, items in
            items.max { $0.updatedAt == $1.updatedAt ? $0.sortOrder > $1.sortOrder : $0.updatedAt < $1.updatedAt }
        }
    }
    private static func deduplicate(
        _ values: [MonthlyRecapInput.CompanionRecord]
    ) -> [MonthlyRecapInput.CompanionRecord] {
        Dictionary(grouping: values, by: \.id).compactMap { _, items in
            items.max { $0.updatedAt == $1.updatedAt ? $0.displayName > $1.displayName : $0.updatedAt < $1.updatedAt }
        }
    }
    private static func deduplicate(
        _ values: [MonthlyRecapInput.SourceRecord]
    ) -> [MonthlyRecapInput.SourceRecord] {
        Dictionary(grouping: values, by: \.id).compactMap { _, items in
            items.max { $0.updatedAt == $1.updatedAt ? $0.displayName > $1.displayName : $0.updatedAt < $1.updatedAt }
        }
    }

    private static func labelCounts(_ values: [String]) -> [(name: String, count: Int)] {
        Dictionary(grouping: values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }, by: normalize).compactMap { _, values in
                guard let display = values.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }).first else { return nil }
                return (display, values.count)
            }.sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    private static func dominantLabel(_ values: [String]) -> (name: String, share: Double)? {
        guard let first = labelCounts(values).first else { return nil }
        return (first.name, ratio(first.count, values.count))
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).folding(
            options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "zh_Hans_CN")
        )
    }
    private static func ratio(_ numerator: Int, _ denominator: Int) -> Double {
        denominator == 0 ? 0 : Double(numerator) / Double(denominator)
    }
    private static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted(), middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
    private static func standardDeviation(_ values: [Double]) -> Double? {
        guard values.count >= 2, let average = mean(values) else { return nil }
        return sqrt(values.reduce(0) { $0 + pow($1 - average, 2) } / Double(values.count))
    }
}
