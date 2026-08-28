import Foundation

nonisolated enum MonthlyRecapSufficiencyPolicy {
    static let minimumVisitsForTasteChange = 3
    static let minimumRestaurantsForTasteChange = 2
    static let minimumSpendCoverageForProminence = 0.6
    static let highRatingThreshold = 4.0
    static let materialShareDelta = 0.20

    static func tasteChangeLevel(visitCount: Int, restaurantCount: Int) -> AnalysisDataSufficiency {
        guard visitCount >= minimumVisitsForTasteChange,
              restaurantCount >= minimumRestaurantsForTasteChange else { return .insufficient }
        return AnalysisSufficiencyPolicy.level(sampleCount: visitCount, emergingAt: 3, establishedAt: 8)
    }
}

nonisolated enum MonthlyRecapAnalyzer {
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

    private struct SourceBucket {
        let record: MonthlyRecapInput.SourceRecord
        var restaurantIDs = Set<UUID>()
    }

    static func analyze(
        _ input: MonthlyRecapInput,
        period: MonthlyPeriod = .current(),
        now: Date = .now
    ) -> MonthlyRecapAnalysis {
        let restaurants = deduplicate(input.restaurants).filter { $0.deletedAt == nil }
        let allVisits = deduplicate(input.visits).filter { $0.deletedAt == nil }
        let dishes = deduplicate(input.dishes).filter { $0.deletedAt == nil }
        let visitDishes = input.visitDishes.filter { $0.deletedAt == nil }
        let photos = deduplicate(input.photos).filter { $0.deletedAt == nil && $0.kind != .avatar }
        let companions = deduplicate(input.companions).filter { $0.deletedAt == nil }
        let sources = deduplicate(input.recommendationSources).filter { $0.deletedAt == nil }
        let restaurantsByID = Dictionary(uniqueKeysWithValues: restaurants.map { ($0.id, $0) })
        let currentVisits = allVisits.filter { period.contains($0.visitedAt) }
            .sorted(by: chronologicalVisitSort)
        let comparisonPeriod = period.previous
        let comparisonVisits = allVisits.filter { comparisonPeriod.contains($0.visitedAt) }
            .sorted(by: chronologicalVisitSort)
        let earliestVisits = earliestVisitsByRestaurant(allVisits)
        let dishesByID = Dictionary(uniqueKeysWithValues: dishes.map { ($0.id, $0) })
        let dishIDsByVisit = dishIDsByVisitMap(dishes: dishes, visitDishes: visitDishes)
        let aggregates = buildAggregates(
            visits: currentVisits, restaurantsByID: restaurantsByID,
            earliestVisits: earliestVisits, period: period,
            dishesByID: dishesByID, dishIDsByVisit: dishIDsByVisit,
            photos: photos
        )
        let previousAggregates = buildAggregates(
            visits: comparisonVisits, restaurantsByID: restaurantsByID,
            earliestVisits: earliestVisits, period: comparisonPeriod,
            dishesByID: dishesByID, dishIDsByVisit: dishIDsByVisit,
            photos: []
        )

        let spend = spendSummary(visits: currentVisits)
        let favorite = favoriteAggregate(aggregates)
        let mostVisited = mostVisitedAggregate(aggregates)
        let newAggregates = aggregates.filter(\.isNew).sorted(by: newRestaurantSort)
        let highlight = highlightAggregate(aggregates)

        let favoriteStory = favorite.map { story($0, role: "本月最喜欢") }
        let mostVisitedStory = mostVisited.map { story($0, role: "本月最常去") }
        let newStories = newAggregates.prefix(3).map { story($0, role: "本月新发现") }
        let highlightStory = highlight.map { story($0, role: "本月高光") }
        let topCompanion = companionStory(
            companions: companions, visits: currentVisits, aggregates: aggregates
        )
        let recommendationStory = recommendationStory(
            sources: sources, visits: currentVisits, aggregates: aggregates
        )
        let tasteResult = tasteChange(
            currentVisits: currentVisits, currentAggregates: aggregates,
            previousVisits: comparisonVisits, previousAggregates: previousAggregates,
            restaurantsByID: restaurantsByID, earliestVisits: earliestVisits,
            currentPeriod: period, previousPeriod: comparisonPeriod
        )
        let keywords = monthlyKeywords(
            visits: currentVisits, aggregates: aggregates,
            restaurantsByID: restaurantsByID, dishesByID: dishesByID,
            dishIDsByVisit: dishIDsByVisit
        )
        let representatives = representatives(
            favorite: favoriteStory, mostVisited: mostVisitedStory,
            newRestaurant: newStories.first, highlight: highlightStory
        )
        let latestRevision = [
            input.restaurants.map(\.updatedAt).max(), input.visits.map(\.updatedAt).max(),
            input.dishes.map(\.updatedAt).max(), input.photos.map(\.updatedAt).max(),
        ].compactMap { $0 }.max() ?? .distantPast
        let repeatCount = repeatRestaurantCount(
            aggregates: aggregates, earliestVisits: earliestVisits, period: period
        )
        return MonthlyRecapAnalysis(
            id: "monthly:\(period.id):\(currentVisits.count):\(Int(latestRevision.timeIntervalSince1970))",
            kind: .monthlyReview,
            userDisplayName: input.userDisplayName,
            period: period,
            comparisonPeriod: comparisonPeriod,
            isCurrentPeriod: period.isCurrent(now: now),
            periodLabel: period.posterLabel(now: now),
            visitCount: currentVisits.count,
            restaurantCount: aggregates.count,
            newRestaurantCount: newAggregates.count,
            repeatRestaurantCount: repeatCount,
            spend: spend,
            favoriteRestaurant: favoriteStory,
            mostVisitedRestaurant: mostVisitedStory,
            newRestaurants: Array(newStories),
            topCompanion: topCompanion,
            recommendationStory: recommendationStory,
            tasteChange: tasteResult.change,
            keywords: keywords,
            highlight: highlightStory,
            representativeRestaurants: representatives,
            sufficiency: AnalysisSufficiencyPolicy.level(
                sampleCount: currentVisits.count, emergingAt: 3, establishedAt: 10
            ),
            tasteChangeSufficiency: tasteResult.sufficiency,
            dataNote: "只分析你自己的本地有效记录。nil 消费不会按 ¥0 计算；私人备注、精确位置、内部身份与未选择的关系不会进入海报。",
            generatedAt: now
        )
    }

    private static func buildAggregates(
        visits: [MonthlyRecapInput.VisitRecord],
        restaurantsByID: [UUID: MonthlyRecapInput.RestaurantRecord],
        earliestVisits: [UUID: MonthlyRecapInput.VisitRecord],
        period: MonthlyPeriod,
        dishesByID: [UUID: MonthlyRecapInput.DishRecord],
        dishIDsByVisit: [UUID: Set<UUID>],
        photos: [MonthlyRecapInput.PhotoRecord]
    ) -> [RestaurantAggregate] {
        Dictionary(grouping: visits, by: \.restaurantID).map { restaurantID, restaurantVisits in
            let sortedVisits = restaurantVisits.sorted(by: chronologicalVisitSort)
            let visitIDs = Set(sortedVisits.map(\.id))
            let dishIDs = sortedVisits.reduce(into: Set<UUID>()) { result, visit in
                result.formUnion(dishIDsByVisit[visit.id] ?? [])
            }
            let dishRatings = dishIDs.compactMap { dishesByID[$0]?.rating }
            return RestaurantAggregate(
                restaurant: restaurantsByID[restaurantID],
                restaurantID: restaurantID,
                visits: sortedVisits,
                averageRating: mean(sortedVisits.compactMap(\.rating)),
                dishAverageRating: mean(dishRatings),
                latestVisitAt: sortedVisits.map(\.visitedAt).max() ?? period.start,
                isNew: earliestVisits[restaurantID].map { period.contains($0.visitedAt) } ?? false,
                imageReference: imageReference(
                    restaurantID: restaurantID, visitIDs: visitIDs, dishIDs: dishIDs, photos: photos
                ),
                hasNote: sortedVisits.contains { $0.note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
            )
        }.sorted { $0.restaurantID.uuidString < $1.restaurantID.uuidString }
    }

    private static func spendSummary(visits: [MonthlyRecapInput.VisitRecord]) -> MonthlySpendSummary {
        let values = visits.compactMap { visit -> Double? in
            guard let value = visit.myActualSpend else { return nil }
            let double = NSDecimalNumber(decimal: value).doubleValue
            return double.isFinite && double >= 0 ? double : nil
        }.sorted()
        let coverage = ratio(values.count, visits.count)
        let state: MonthlySpendDisplayState
        if values.isEmpty { state = .none }
        else if coverage < MonthlyRecapSufficiencyPolicy.minimumSpendCoverageForProminence { state = .lowCoverage }
        else if coverage < 1 { state = .recorded }
        else { state = .complete }
        return MonthlySpendSummary(
            recordedTotal: values.isEmpty ? nil : values.reduce(0, +),
            median: median(values), recordedVisitCount: values.count, visitCount: visits.count,
            coverage: coverage, displayState: state,
            sufficiency: AnalysisSufficiencyPolicy.level(sampleCount: values.count, emergingAt: 2, establishedAt: 6)
        )
    }

    private static func favoriteAggregate(_ values: [RestaurantAggregate]) -> RestaurantAggregate? {
        values.filter { $0.averageRating != nil || $0.visits.count >= 2 }.sorted(by: favoriteSort).first
    }

    private static func favoriteSort(_ lhs: RestaurantAggregate, _ rhs: RestaurantAggregate) -> Bool {
        let lhsScore = favoriteScore(lhs)
        let rhsScore = favoriteScore(rhs)
        if abs(lhsScore - rhsScore) > 0.000_001 { return lhsScore > rhsScore }
        if lhs.averageRating != rhs.averageRating { return (lhs.averageRating ?? -1) > (rhs.averageRating ?? -1) }
        if lhs.visits.count != rhs.visits.count { return lhs.visits.count > rhs.visits.count }
        if lhs.latestVisitAt != rhs.latestVisitAt { return lhs.latestVisitAt > rhs.latestVisitAt }
        return lhs.restaurantID.uuidString < rhs.restaurantID.uuidString
    }

    private static func favoriteScore(_ item: RestaurantAggregate) -> Double {
        let rating = (item.averageRating ?? 0) * 0.72
        let evidence = min(1, Double(item.visits.count) / 4) * 0.55
        let repeatBonus = item.visits.count >= 2 ? 0.30 : 0
        let dish = (item.dishAverageRating ?? 0) / 5 * 0.15
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
        if (lhs.imageReference == .none) != (rhs.imageReference == .none) {
            return lhs.imageReference != .none
        }
        if lhs.latestVisitAt != rhs.latestVisitAt { return lhs.latestVisitAt > rhs.latestVisitAt }
        return lhs.restaurantID.uuidString < rhs.restaurantID.uuidString
    }

    private static func highlightAggregate(_ values: [RestaurantAggregate]) -> RestaurantAggregate? {
        values.sorted {
            let lhsScore = highlightScore($0)
            let rhsScore = highlightScore($1)
            if abs(lhsScore - rhsScore) > 0.000_001 { return lhsScore > rhsScore }
            if $0.latestVisitAt != $1.latestVisitAt { return $0.latestVisitAt > $1.latestVisitAt }
            return $0.restaurantID.uuidString < $1.restaurantID.uuidString
        }.first
    }

    private static func highlightScore(_ item: RestaurantAggregate) -> Double {
        (item.averageRating ?? 0) * 1.2
            + min(3, Double(item.visits.count)) * 0.45
            + (item.imageReference == .none ? 0 : 1.1)
            + (item.hasNote ? 0.5 : 0)
            + (item.isNew ? 0.25 : 0)
    }

    private static func story(_ aggregate: RestaurantAggregate, role: String) -> MonthlyRestaurantStory {
        let name = aggregate.restaurant?.name.trimmingCharacters(in: .whitespacesAndNewlines).monthlyNonEmpty
            ?? "未命名餐厅"
        var facts = ["\(aggregate.visits.count) 次到访"]
        if let rating = aggregate.averageRating { facts.append("平均 \(rating.oneDecimal) 分") }
        if aggregate.isNew { facts.append("本月第一次记录") }
        return MonthlyRestaurantStory(
            id: aggregate.restaurantID, name: name, city: aggregate.restaurant?.city ?? "",
            role: role, detail: facts.joined(separator: " · "), visitCount: aggregate.visits.count,
            averageRating: aggregate.averageRating, latestVisitAt: aggregate.latestVisitAt,
            isNew: aggregate.isNew, imageReference: aggregate.imageReference
        )
    }

    private static func companionStory(
        companions: [MonthlyRecapInput.CompanionRecord],
        visits: [MonthlyRecapInput.VisitRecord],
        aggregates: [RestaurantAggregate]
    ) -> MonthlyCompanionStory? {
        let resolver = CompanionResolver(companions)
        var buckets: [UUID: CompanionBucket] = [:]
        for visit in visits {
            let resolved = resolver.resolve(visit)
            for record in Dictionary(grouping: resolved, by: \.id).compactMap({ $0.value.first }) {
                var bucket = buckets[record.id] ?? CompanionBucket(record: record)
                bucket.visitIDs.insert(visit.id)
                bucket.restaurantIDs.insert(visit.restaurantID)
                bucket.latestVisitAt = max(bucket.latestVisitAt, visit.visitedAt)
                buckets[record.id] = bucket
            }
        }
        guard let top = buckets.values.sorted(by: companionSort).first else { return nil }
        let representative = aggregates.filter { top.restaurantIDs.contains($0.restaurantID) }.sorted(by: favoriteSort).first
        return MonthlyCompanionStory(
            id: top.record.id, displayName: top.record.displayName,
            sharedVisitCount: top.visitIDs.count, restaurantCount: top.restaurantIDs.count,
            representativeRestaurant: representative.map { story($0, role: "和 \(top.record.displayName) 的本月餐桌") },
            sufficiency: AnalysisSufficiencyPolicy.level(
                sampleCount: top.visitIDs.count, emergingAt: 2, establishedAt: 5
            )
        )
    }

    private static func companionSort(_ lhs: CompanionBucket, _ rhs: CompanionBucket) -> Bool {
        if lhs.visitIDs.count != rhs.visitIDs.count { return lhs.visitIDs.count > rhs.visitIDs.count }
        if lhs.restaurantIDs.count != rhs.restaurantIDs.count { return lhs.restaurantIDs.count > rhs.restaurantIDs.count }
        if lhs.latestVisitAt != rhs.latestVisitAt { return lhs.latestVisitAt > rhs.latestVisitAt }
        return lhs.record.id.uuidString < rhs.record.id.uuidString
    }

    private static func recommendationStory(
        sources: [MonthlyRecapInput.SourceRecord],
        visits: [MonthlyRecapInput.VisitRecord],
        aggregates: [RestaurantAggregate]
    ) -> MonthlyRecommendationStory? {
        let resolver = SourceResolver(sources)
        var buckets: [UUID: SourceBucket] = [:]
        let byRestaurant = Dictionary(grouping: visits, by: \.restaurantID)
        for (restaurantID, restaurantVisits) in byRestaurant {
            guard let source = restaurantVisits.sorted(by: chronologicalVisitSort).compactMap({ resolver.resolve($0) }).first else {
                continue
            }
            var bucket = buckets[source.id] ?? SourceBucket(record: source)
            bucket.restaurantIDs.insert(restaurantID)
            buckets[source.id] = bucket
        }
        let aggregatesByID = Dictionary(uniqueKeysWithValues: aggregates.map { ($0.restaurantID, $0) })
        let candidates = buckets.values.map { bucket -> (SourceBucket, [RestaurantAggregate], [Double], Int) in
            let items = bucket.restaurantIDs.compactMap { aggregatesByID[$0] }
            let ratings = items.compactMap(\.averageRating)
            return (bucket, items, ratings, ratings.filter { $0 >= MonthlyRecapSufficiencyPolicy.highRatingThreshold }.count)
        }.sorted {
            if $0.0.restaurantIDs.count != $1.0.restaurantIDs.count { return $0.0.restaurantIDs.count > $1.0.restaurantIDs.count }
            if $0.3 != $1.3 { return $0.3 > $1.3 }
            if mean($0.2) != mean($1.2) { return (mean($0.2) ?? -1) > (mean($1.2) ?? -1) }
            return $0.0.record.id.uuidString < $1.0.record.id.uuidString
        }
        guard let top = candidates.first else { return nil }
        let average = mean(top.2)
        let statement: String
        if !top.2.isEmpty {
            statement = "本月从 \(top.0.record.displayName) 发现了 \(top.0.restaurantIDs.count) 家店，其中 \(top.3) 家达到 4.0 分以上。"
        } else {
            statement = "本月从 \(top.0.record.displayName) 发现了 \(top.0.restaurantIDs.count) 家店；评分仍在等待你的真实记录。"
        }
        let representative = top.1.sorted(by: favoriteSort).first
        return MonthlyRecommendationStory(
            sourceID: top.0.record.id, displayName: top.0.record.displayName,
            sourceType: top.0.record.sourceType, restaurantCount: top.0.restaurantIDs.count,
            ratedRestaurantCount: top.2.count, highRatedRestaurantCount: top.3,
            averageRating: average, statement: statement,
            representativeRestaurant: representative.map { story($0, role: "本月来源故事") },
            sufficiency: AnalysisSufficiencyPolicy.level(
                sampleCount: top.0.restaurantIDs.count, emergingAt: 2, establishedAt: 5
            )
        )
    }

    private static func tasteChange(
        currentVisits: [MonthlyRecapInput.VisitRecord],
        currentAggregates: [RestaurantAggregate],
        previousVisits: [MonthlyRecapInput.VisitRecord],
        previousAggregates: [RestaurantAggregate],
        restaurantsByID: [UUID: MonthlyRecapInput.RestaurantRecord],
        earliestVisits: [UUID: MonthlyRecapInput.VisitRecord],
        currentPeriod: MonthlyPeriod,
        previousPeriod: MonthlyPeriod
    ) -> (change: MonthlyTasteChange?, sufficiency: AnalysisDataSufficiency) {
        let currentLevel = MonthlyRecapSufficiencyPolicy.tasteChangeLevel(
            visitCount: currentVisits.count, restaurantCount: currentAggregates.count
        )
        let previousLevel = MonthlyRecapSufficiencyPolicy.tasteChangeLevel(
            visitCount: previousVisits.count, restaurantCount: previousAggregates.count
        )
        guard currentLevel != .insufficient, previousLevel != .insufficient else {
            return (nil, .insufficient)
        }

        let currentTags = tagShares(visits: currentVisits, restaurantsByID: restaurantsByID)
        let previousTags = tagShares(visits: previousVisits, restaurantsByID: restaurantsByID)
        var candidates: [MonthlyTasteChange] = []
        for label in Set(currentTags.keys).union(previousTags.keys).sorted() {
            let delta = (currentTags[label] ?? 0) - (previousTags[label] ?? 0)
            guard abs(delta) >= MonthlyRecapSufficiencyPolicy.materialShareDelta else { continue }
            if delta > 0 {
                candidates.append(MonthlyTasteChange(
                    kind: .cuisineIncrease, title: "本月更常出现 \(label)",
                    statement: "与上个月相比，\(label) 在有效到访标签中的占比提高了 \(delta.percent)。",
                    magnitude: abs(delta), sufficiency: lessMature(currentLevel, previousLevel)
                ))
            } else {
                candidates.append(MonthlyTasteChange(
                    kind: .cuisineDecrease, title: "本月少了一点 \(label)",
                    statement: "与上个月相比，\(label) 在有效到访标签中的占比下降了 \(abs(delta).percent)。",
                    magnitude: abs(delta), sufficiency: lessMature(currentLevel, previousLevel)
                ))
            }
        }

        let currentExploration = ratio(
            currentAggregates.filter { $0.isNew }.count, currentAggregates.count
        )
        let previousExploration = ratio(
            previousAggregates.filter { $0.isNew }.count, previousAggregates.count
        )
        let explorationDelta = currentExploration - previousExploration
        if explorationDelta >= MonthlyRecapSufficiencyPolicy.materialShareDelta {
            candidates.append(MonthlyTasteChange(
                kind: .explorationIncrease, title: "这个月更爱探索新店",
                statement: "新店占比比上个月提高了 \(explorationDelta.percent)，所有新店都按人生第一次有效到访计算。",
                magnitude: explorationDelta, sufficiency: lessMature(currentLevel, previousLevel)
            ))
        }

        let currentRepeat = ratio(
            repeatRestaurantCount(aggregates: currentAggregates, earliestVisits: earliestVisits, period: currentPeriod),
            currentAggregates.count
        )
        let previousRepeat = ratio(
            repeatRestaurantCount(aggregates: previousAggregates, earliestVisits: earliestVisits, period: previousPeriod),
            previousAggregates.count
        )
        let repeatDelta = currentRepeat - previousRepeat
        if repeatDelta >= MonthlyRecapSufficiencyPolicy.materialShareDelta {
            candidates.append(MonthlyTasteChange(
                kind: .repeatIncrease, title: "这个月更常回到熟店",
                statement: "熟店或月内重复到访占比比上个月提高了 \(repeatDelta.percent)。",
                magnitude: repeatDelta, sufficiency: lessMature(currentLevel, previousLevel)
            ))
        }

        let priority: [MonthlyTasteChangeKind: Int] = [
            .cuisineIncrease: 0, .explorationIncrease: 1, .repeatIncrease: 2, .cuisineDecrease: 3,
        ]
        let best = candidates.sorted {
            if abs($0.magnitude - $1.magnitude) > 0.000_001 { return $0.magnitude > $1.magnitude }
            if priority[$0.kind] != priority[$1.kind] { return (priority[$0.kind] ?? 99) < (priority[$1.kind] ?? 99) }
            return $0.title < $1.title
        }.first
        return (best, lessMature(currentLevel, previousLevel))
    }

    private static func monthlyKeywords(
        visits: [MonthlyRecapInput.VisitRecord],
        aggregates: [RestaurantAggregate],
        restaurantsByID: [UUID: MonthlyRecapInput.RestaurantRecord],
        dishesByID: [UUID: MonthlyRecapInput.DishRecord],
        dishIDsByVisit: [UUID: Set<UUID>]
    ) -> [String] {
        guard !visits.isEmpty else { return [] }
        var result: [String] = []
        let tags = tagCounts(visits: visits, restaurantsByID: restaurantsByID)
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map(\.key)
        result.append(contentsOf: tags.prefix(2))

        let dishCounts = visits.reduce(into: [String: Int]()) { counts, visit in
            for dishID in dishIDsByVisit[visit.id] ?? [] {
                guard let name = dishesByID[dishID]?.name.trimmingCharacters(in: .whitespacesAndNewlines).monthlyNonEmpty else { continue }
                counts[name, default: 0] += 1
            }
        }
        if let dish = dishCounts.sorted(by: { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }).first?.key {
            result.append(dish)
        }
        let occasionCounts = visits.flatMap(\.diningOccasionLabels).reduce(into: [String: Int]()) {
            $0[$1, default: 0] += 1
        }
        if let occasion = occasionCounts.sorted(by: { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }).first?.key {
            result.append(occasion)
        }
        let newShare = ratio(aggregates.filter(\.isNew).count, aggregates.count)
        if newShare >= 0.5 { result.append("探新店") }
        else if aggregates.contains(where: { $0.visits.count >= 2 }) { result.append("熟店回访") }
        if result.isEmpty { result.append("本月餐桌") }
        var seen = Set<String>()
        return result.filter { seen.insert(normalize($0)).inserted }.prefix(5).map { $0 }
    }

    private static func representatives(
        favorite: MonthlyRestaurantStory?,
        mostVisited: MonthlyRestaurantStory?,
        newRestaurant: MonthlyRestaurantStory?,
        highlight: MonthlyRestaurantStory?
    ) -> [MonthlyRestaurantStory] {
        var result: [MonthlyRestaurantStory] = []
        var seen = Set<UUID>()
        func append(_ item: MonthlyRestaurantStory?) {
            guard let item, seen.insert(item.id).inserted else { return }
            result.append(item)
        }
        append(favorite)
        append(mostVisited)
        append(newRestaurant)
        append(highlight)
        return Array(result.prefix(4))
    }

    private static func repeatRestaurantCount(
        aggregates: [RestaurantAggregate],
        earliestVisits: [UUID: MonthlyRecapInput.VisitRecord],
        period: MonthlyPeriod
    ) -> Int {
        aggregates.filter { aggregate in
            aggregate.visits.count >= 2 || (earliestVisits[aggregate.restaurantID]?.visitedAt ?? period.start) < period.start
        }.count
    }

    private static func tagShares(
        visits: [MonthlyRecapInput.VisitRecord],
        restaurantsByID: [UUID: MonthlyRecapInput.RestaurantRecord]
    ) -> [String: Double] {
        let counts = tagCounts(visits: visits, restaurantsByID: restaurantsByID)
        let total = counts.values.reduce(0, +)
        guard total > 0 else { return [:] }
        return counts.mapValues { Double($0) / Double(total) }
    }

    private static func tagCounts(
        visits: [MonthlyRecapInput.VisitRecord],
        restaurantsByID: [UUID: MonthlyRecapInput.RestaurantRecord]
    ) -> [String: Int] {
        var labels: [String: String] = [:]
        var counts: [String: Int] = [:]
        for visit in visits {
            let uniqueTags = Set((restaurantsByID[visit.restaurantID]?.tags ?? []).compactMap {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).monthlyNonEmpty
            })
            for tag in uniqueTags {
                let key = normalize(tag)
                labels[key] = labels[key] ?? tag
                counts[key, default: 0] += 1
            }
        }
        return Dictionary(uniqueKeysWithValues: counts.map { (labels[$0.key] ?? $0.key, $0.value) })
    }

    private static func earliestVisitsByRestaurant(
        _ visits: [MonthlyRecapInput.VisitRecord]
    ) -> [UUID: MonthlyRecapInput.VisitRecord] {
        Dictionary(grouping: visits, by: \.restaurantID).compactMapValues {
            $0.sorted(by: chronologicalVisitSort).first
        }
    }

    private static func dishIDsByVisitMap(
        dishes: [MonthlyRecapInput.DishRecord],
        visitDishes: [MonthlyRecapInput.VisitDishRecord]
    ) -> [UUID: Set<UUID>] {
        var result: [UUID: Set<UUID>] = [:]
        for dish in dishes { result[dish.originVisitID, default: []].insert(dish.id) }
        for association in visitDishes { result[association.visitID, default: []].insert(association.dishID) }
        return result
    }

    private static func imageReference(
        restaurantID: UUID,
        visitIDs: Set<UUID>,
        dishIDs: Set<UUID>,
        photos: [MonthlyRecapInput.PhotoRecord]
    ) -> AnalysisImageReference {
        let eligible = photos.filter { photo in
            photo.visitID.map(visitIDs.contains) == true
                || photo.dishID.map(dishIDs.contains) == true
                || (photo.kind == .restaurantMarker && photo.restaurantID == restaurantID)
        }
        let selected = eligible.sorted {
            let lhsPriority = photoPriority($0, visitIDs: visitIDs, dishIDs: dishIDs)
            let rhsPriority = photoPriority($1, visitIDs: visitIDs, dishIDs: dishIDs)
            if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id.uuidString < $1.id.uuidString
        }.first
        return selected.map { .photo($0.id) } ?? .none
    }

    private static func photoPriority(
        _ photo: MonthlyRecapInput.PhotoRecord,
        visitIDs: Set<UUID>,
        dishIDs: Set<UUID>
    ) -> Int {
        if photo.kind == .dish && photo.dishID.map(dishIDs.contains) == true { return 0 }
        if photo.kind == .visit && photo.visitID.map(visitIDs.contains) == true { return 1 }
        if photo.kind == .restaurantMarker { return 2 }
        return 3
    }

    private struct CompanionResolver {
        let identifiers: [String: MonthlyRecapInput.CompanionRecord]
        let uniqueNames: [String: MonthlyRecapInput.CompanionRecord]

        init(_ records: [MonthlyRecapInput.CompanionRecord]) {
            var identifierMap: [String: MonthlyRecapInput.CompanionRecord] = [:]
            for record in records {
                for identifier in record.identifiers { identifierMap[normalize(identifier)] = record }
            }
            let names = Dictionary(grouping: records, by: { normalize($0.displayName) })
            identifiers = identifierMap
            uniqueNames = names.compactMapValues { $0.count == 1 ? $0[0] : nil }
        }

        func resolve(_ visit: MonthlyRecapInput.VisitRecord) -> [MonthlyRecapInput.CompanionRecord] {
            if !visit.companionIDs.isEmpty {
                return visit.companionIDs.compactMap { identifiers[normalize($0)] }
            }
            return visit.companionNames.compactMap { uniqueNames[normalize($0)] }
        }
    }

    private struct SourceResolver {
        let identifiers: [String: MonthlyRecapInput.SourceRecord]
        let uniqueNames: [String: MonthlyRecapInput.SourceRecord]

        init(_ records: [MonthlyRecapInput.SourceRecord]) {
            var identifierMap: [String: MonthlyRecapInput.SourceRecord] = [:]
            for record in records {
                for identifier in record.identifiers { identifierMap[normalize(identifier)] = record }
            }
            let names = Dictionary(grouping: records, by: { normalize($0.displayName) })
            identifiers = identifierMap
            uniqueNames = names.compactMapValues { $0.count == 1 ? $0[0] : nil }
        }

        func resolve(_ visit: MonthlyRecapInput.VisitRecord) -> MonthlyRecapInput.SourceRecord? {
            if let id = visit.recommendationSourceID?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
                return identifiers[normalize(id)]
            }
            guard let text = visit.recommendationSourceText?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return nil }
            return uniqueNames[normalize(text)]
        }
    }

    private static func chronologicalVisitSort(
        _ lhs: MonthlyRecapInput.VisitRecord,
        _ rhs: MonthlyRecapInput.VisitRecord
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
            items.max { $0.updatedAt == $1.updatedAt ? $0.id.uuidString > $1.id.uuidString : $0.updatedAt < $1.updatedAt }
        }
    }

    private static func deduplicate(
        _ values: [MonthlyRecapInput.DishRecord]
    ) -> [MonthlyRecapInput.DishRecord] {
        Dictionary(grouping: values, by: \.id).compactMap { _, items in items.max { $0.updatedAt < $1.updatedAt } }
    }

    private static func deduplicate(
        _ values: [MonthlyRecapInput.PhotoRecord]
    ) -> [MonthlyRecapInput.PhotoRecord] {
        Dictionary(grouping: values, by: \.id).compactMap { _, items in items.max { $0.updatedAt < $1.updatedAt } }
    }

    private static func deduplicate(
        _ values: [MonthlyRecapInput.CompanionRecord]
    ) -> [MonthlyRecapInput.CompanionRecord] {
        Dictionary(grouping: values, by: \.id).compactMap { _, items in items.max { $0.updatedAt < $1.updatedAt } }
    }

    private static func deduplicate(
        _ values: [MonthlyRecapInput.SourceRecord]
    ) -> [MonthlyRecapInput.SourceRecord] {
        Dictionary(grouping: values, by: \.id).compactMap { _, items in items.max { $0.updatedAt < $1.updatedAt } }
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).folding(
            options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "zh_Hans_CN")
        )
    }

    private static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let middle = values.count / 2
        return values.count.isMultiple(of: 2) ? (values[middle - 1] + values[middle]) / 2 : values[middle]
    }

    private static func ratio(_ numerator: Int, _ denominator: Int) -> Double {
        denominator == 0 ? 0 : Double(numerator) / Double(denominator)
    }

    private static func lessMature(
        _ lhs: AnalysisDataSufficiency,
        _ rhs: AnalysisDataSufficiency
    ) -> AnalysisDataSufficiency {
        let rank: [AnalysisDataSufficiency: Int] = [.insufficient: 0, .emerging: 1, .established: 2]
        return (rank[lhs] ?? 0) <= (rank[rhs] ?? 0) ? lhs : rhs
    }
}

private extension Double {
    nonisolated var oneDecimal: String { formatted(.number.precision(.fractionLength(1))) }
    nonisolated var percent: String { formatted(.percent.precision(.fractionLength(0))) }
}

private extension String {
    nonisolated var monthlyNonEmpty: String? { isEmpty ? nil : self }
}
