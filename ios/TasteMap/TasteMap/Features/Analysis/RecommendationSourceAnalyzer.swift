import Foundation

enum RecommendationSourceAnalyzer {
    nonisolated static let highRatingThreshold = 4.0
    nonisolated static let lowRatingThreshold = 2.5
    nonisolated static let minimumRatedRestaurantsForRanking = AnalysisSufficiencyThresholds.recommendationSourceRankingRatedRestaurants
    nonisolated static let stableRatedRestaurantCount = AnalysisSufficiencyThresholds.recommendationSourceStableRatedRestaurants
    nonisolated static let minimumRatedRestaurantsForAverage = AnalysisSufficiencyThresholds.recommendationSourceAverageRatedRestaurants

    private nonisolated struct AcquiredRestaurant {
        let restaurant: RecommendationSourceInput.RestaurantRecord
        let sourceID: UUID
        let acquisitionDate: Date
        let isNewDiscovery: Bool
        let visits: [RecommendationSourceInput.VisitRecord]
        let averageRating: Double?
        let valueAverage: Double?
        let environmentAverage: Double?
        let serviceAverage: Double?
        let imageReference: AnalysisImageReference
    }

    nonisolated static func analyze(
        _ input: RecommendationSourceInput,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> RecommendationSourceOverview {
        let sources = deduplicate(input.sources.filter { $0.deletedAt == nil })
        let restaurants = deduplicate(input.restaurants.filter { $0.deletedAt == nil })
        let restaurantByID = Dictionary(uniqueKeysWithValues: restaurants.map { ($0.id, $0) })
        let visits = input.visits.filter { $0.deletedAt == nil && restaurantByID[$0.restaurantID] != nil }
        let photos = input.photos.filter { $0.deletedAt == nil && $0.kind != .avatar }
        let visitsByRestaurant = Dictionary(grouping: visits, by: \.restaurantID)
        let resolver = SourceResolver(sources: sources)

        let acquired: [AcquiredRestaurant] = restaurants.compactMap { restaurant in
            let restaurantVisits = (visitsByRestaurant[restaurant.id] ?? []).sorted(by: visitSort)
            guard let firstResolved = restaurantVisits.enumerated().compactMap({ index, visit -> (Int, RecommendationSourceInput.VisitRecord, UUID)? in
                guard let sourceID = resolver.resolve(visit) else { return nil }
                return (index, visit, sourceID)
            }).first else { return nil }
            let ratings = restaurantVisits.compactMap(\.rating)
            return AcquiredRestaurant(
                restaurant: restaurant,
                sourceID: firstResolved.2,
                acquisitionDate: firstResolved.1.visitedAt,
                isNewDiscovery: firstResolved.0 == 0,
                visits: restaurantVisits,
                averageRating: mean(ratings),
                valueAverage: mean(restaurantVisits.compactMap(\.valueRating)),
                environmentAverage: mean(restaurantVisits.compactMap(\.environmentRating)),
                serviceAverage: mean(restaurantVisits.compactMap(\.serviceRating)),
                imageReference: imageReference(
                    restaurantID: restaurant.id,
                    visitIDs: Set(restaurantVisits.map(\.id)),
                    photos: photos,
                    merchantImageURL: restaurant.merchantImageURL
                )
            )
        }

        let acquiredBySource = Dictionary(grouping: acquired, by: \.sourceID)
        let allRestaurantRatings = acquired.compactMap(\.averageRating)
        let overallAverage = mean(allRestaurantRatings)

        let analyses = sources.map { source in
            sourceAnalysis(
                source: source,
                acquired: acquiredBySource[source.id] ?? [],
                overallAverage: overallAverage,
                now: now,
                calendar: calendar
            )
        }.sorted(by: sourceSort)

        let mostUsedAnalysis = analyses.filter(\.hasUsage).sorted(by: mostUsedSort).first
        let highestAverageAnalysis = analyses.filter {
            $0.ratedRestaurantCount >= minimumRatedRestaurantsForAverage && $0.averageRating != nil
        }.sorted(by: averageSort).first
        let eligible = analyses.filter {
            $0.ratedRestaurantCount >= minimumRatedRestaurantsForRanking && $0.averageRating != nil
        }
        let bestAnalysis = eligible.count >= 2 ? eligible.sorted(by: bestSort).first : nil
        let worstAnalysis = eligible.count >= 2 ? eligible.sorted(by: worstSort).first : nil

        let mostUsed = mostUsedAnalysis.map {
            RecommendationSourceConclusion(
                sourceID: $0.id,
                displayName: $0.displayName,
                title: "最常使用来源",
                value: $0.displayName,
                explanation: "带你发现了 \($0.restaurantCount) 家不同餐厅；重复到访不会重复计算来源次数。",
                tone: .brand,
                symbol: "🧭"
            )
        }
        let highestAverage = highestAverageAnalysis.map {
            RecommendationSourceConclusion(
                sourceID: $0.id,
                displayName: $0.displayName,
                title: "平均分更高",
                value: $0.averageRating.map { "\($0.oneDecimal) / 5" } ?? "样本不足",
                explanation: "按 \($0.ratedRestaurantCount) 家有评分餐厅各计一次，平均分为 \($0.averageRating?.oneDecimal ?? "—")。",
                tone: .caramel,
                symbol: "⭐️"
            )
        }
        let best = bestAnalysis.map { analysis in
            RecommendationSourceConclusion(
                sourceID: analysis.id,
                displayName: analysis.displayName,
                title: "最靠谱推荐来源",
                value: analysis.displayName,
                explanation: bestExplanation(analysis, overallAverage: overallAverage),
                tone: .leafGreen,
                symbol: "🥬"
            )
        }
        let worst = worstAnalysis.map { analysis in
            RecommendationSourceConclusion(
                sourceID: analysis.id,
                displayName: analysis.displayName,
                title: "最坑推荐来源",
                value: analysis.displayName,
                explanation: worstExplanation(analysis, overallAverage: overallAverage),
                tone: .ingredientRed,
                symbol: "🌶️"
            )
        }

        let representatives = representativeRestaurants(
            mostUsed: mostUsedAnalysis,
            best: bestAnalysis,
            worst: worstAnalysis
        )
        let latest = max(
            sources.map(\.updatedAt).max() ?? .distantPast,
            visits.map(\.updatedAt).max() ?? .distantPast
        ).timeIntervalSince1970
        return RecommendationSourceOverview(
            id: "recommendation-sources:\(sources.count):\(acquired.count):\(Int(latest))",
            kind: .recommendationSource,
            userDisplayName: input.userDisplayName,
            sourceCount: sources.count,
            usedSourceCount: analyses.filter(\.hasUsage).count,
            attributedRestaurantCount: acquired.count,
            ratedRestaurantCount: allRestaurantRatings.count,
            overallRestaurantRating: overallAverage,
            sources: analyses,
            mostUsed: mostUsed,
            highestAverage: highestAverage,
            bestSource: best,
            worstSource: worst,
            representativeRestaurants: representatives,
            dataNote: "只分析你自己记录的有效 Visit 与当前可解释的推荐来源。nil 评分不进入平均分，私人备注、身份 ID 与精确位置不会进入海报。",
            generatedAt: now
        )
    }

    private nonisolated static func sourceAnalysis(
        source: RecommendationSourceInput.SourceRecord,
        acquired: [AcquiredRestaurant],
        overallAverage: Double?,
        now: Date,
        calendar: Calendar
    ) -> RecommendationSourceAnalysis {
        let ratings = acquired.compactMap(\.averageRating)
        let average = mean(ratings)
        let high = ratings.filter { $0 >= highRatingThreshold }.count
        let low = ratings.filter { $0 <= lowRatingThreshold }.count
        let repeated = acquired.filter { $0.visits.count >= 2 }.count
        let deviation = standardDeviation(ratings)
        let stability: RecommendationSourceRatingStability
        if ratings.count < 3 { stability = .insufficient }
        else if (deviation ?? 0) <= 0.5 { stability = .stable }
        else if (deviation ?? 0) >= 1.0 { stability = .volatile }
        else { stability = .forming }

        let currentStart = calendar.date(byAdding: .day, value: -90, to: now) ?? now
        let previousStart = calendar.date(byAdding: .day, value: -180, to: now) ?? now
        let recent = acquired.filter { $0.acquisitionDate >= currentStart && $0.acquisitionDate <= now }.count
        let previous = acquired.filter { $0.acquisitionDate >= previousStart && $0.acquisitionDate < currentStart }.count
        let trend: RecommendationSourceTrend
        if recent > 0 && previous == 0 { trend = .new }
        else if recent > previous { trend = .rising }
        else if recent == previous && recent > 0 { trend = .steady }
        else if recent > 0 { trend = .cooling }
        else { trend = .inactive }

        let sampleConfidence = min(1, Double(ratings.count) / Double(stableRatedRestaurantCount))
        let normalizedAverage = max(0, min(1, ((average ?? 2.5) - 0.5) / 4.5))
        let highRate = ratio(high, ratings.count)
        let lowRate = ratio(low, ratings.count)
        let repeatRate = ratio(repeated, acquired.count)
        let stabilityValue = max(0, 1 - min(1, (deviation ?? 1) / 1.5))
        let baselineDelta = max(0, min(1, ((average ?? 0) - (overallAverage ?? average ?? 0) + 1) / 2))
        let reliability = ratings.count >= minimumRatedRestaurantsForRanking
            ? normalizedAverage * 0.30 + highRate * 0.27 + repeatRate * 0.16
                + stabilityValue * 0.10 + baselineDelta * 0.10 + sampleConfidence * 0.07
            : nil
        let normalizedLowAverage = max(0, min(1, (3.5 - (average ?? 3.5)) / 3))
        let pitfall = ratings.count >= minimumRatedRestaurantsForRanking
            ? lowRate * 0.34 + (1 - highRate) * 0.22 + (1 - repeatRate) * 0.10
                + normalizedLowAverage * 0.22 + (1 - stabilityValue) * 0.05 + sampleConfidence * 0.07
            : nil

        let sortedRestaurants = acquired.sorted(by: restaurantEvidenceSort)
        return RecommendationSourceAnalysis(
            id: source.id,
            displayName: source.displayName,
            sourceType: source.sourceType,
            usageCount: acquired.count,
            restaurantCount: acquired.count,
            ratedRestaurantCount: ratings.count,
            newDiscoveryCount: acquired.filter(\.isNewDiscovery).count,
            repeatedRestaurantCount: repeated,
            averageRating: average,
            valueAverage: mean(acquired.compactMap(\.valueAverage)),
            environmentAverage: mean(acquired.compactMap(\.environmentAverage)),
            serviceAverage: mean(acquired.compactMap(\.serviceAverage)),
            highRatingCount: high,
            lowRatingCount: low,
            highRatingRate: highRate,
            lowRatingRate: lowRate,
            repeatConversionRate: repeatRate,
            ratingStandardDeviation: deviation,
            ratingStability: stability,
            trend: trend,
            recentRestaurantCount: recent,
            previousRestaurantCount: previous,
            latestUsageAt: acquired.map(\.acquisitionDate).max(),
            sufficiency: AnalysisSufficiencyPolicy.level(
                sampleCount: ratings.count,
                emergingAt: minimumRatedRestaurantsForAverage,
                establishedAt: stableRatedRestaurantCount
            ),
            reliabilityScore: reliability,
            pitfallScore: pitfall,
            restaurants: sortedRestaurants.map { item in
                RecommendationSourceRestaurantEvidence(
                    id: item.restaurant.id,
                    name: item.restaurant.name,
                    city: item.restaurant.city,
                    role: evidenceRole(item),
                    detail: evidenceDetail(item),
                    averageRating: item.averageRating,
                    visitCount: item.visits.count,
                    acquisitionDate: item.acquisitionDate,
                    imageReference: item.imageReference
                )
            },
            updatedAt: max(source.updatedAt, acquired.flatMap(\.visits).map(\.updatedAt).max() ?? source.updatedAt)
        )
    }

    private nonisolated struct SourceResolver {
        let identifierOwners: [String: UUID]
        let uniqueNameOwners: [String: UUID]

        init(sources: [RecommendationSourceInput.SourceRecord]) {
            var identifiers: [String: UUID] = [:]
            for source in sources {
                for identifier in source.identifiers { identifiers[normalize(identifier)] = source.id }
            }
            let names = Dictionary(grouping: sources, by: { normalize($0.displayName) })
            identifierOwners = identifiers
            uniqueNameOwners = names.compactMapValues { $0.count == 1 ? $0[0].id : nil }
        }

        func resolve(_ visit: RecommendationSourceInput.VisitRecord) -> UUID? {
            if let identifier = visit.recommendationSourceID?.trimmingCharacters(in: .whitespacesAndNewlines),
               !identifier.isEmpty {
                return identifierOwners[normalize(identifier)]
            }
            guard let text = visit.recommendationSourceText?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return nil }
            return uniqueNameOwners[normalize(text)]
        }
    }

    private nonisolated static func representativeRestaurants(
        mostUsed: RecommendationSourceAnalysis?,
        best: RecommendationSourceAnalysis?,
        worst: RecommendationSourceAnalysis?
    ) -> [RecommendationSourceRestaurantEvidence] {
        var result: [RecommendationSourceRestaurantEvidence] = []
        var seen = Set<UUID>()
        func append(_ item: RecommendationSourceRestaurantEvidence?, role: String) {
            guard let item, seen.insert(item.id).inserted else { return }
            result.append(.init(
                id: item.id, name: item.name, city: item.city, role: role,
                detail: item.detail, averageRating: item.averageRating,
                visitCount: item.visitCount, acquisitionDate: item.acquisitionDate,
                imageReference: item.imageReference
            ))
        }
        append(mostUsed?.restaurants.max(by: { $0.acquisitionDate < $1.acquisitionDate }), role: "近期来源故事")
        append(best?.restaurants.filter { ($0.averageRating ?? 0) >= highRatingThreshold }
            .max(by: { ($0.averageRating ?? 0) < ($1.averageRating ?? 0) }), role: "靠谱来源代表")
        append(worst?.restaurants.filter { ($0.averageRating ?? 6) <= lowRatingThreshold }
            .min(by: { ($0.averageRating ?? 6) < ($1.averageRating ?? 6) }), role: "最坑来源证据")
        return Array(result.prefix(3))
    }

    private nonisolated static func bestExplanation(
        _ item: RecommendationSourceAnalysis,
        overallAverage: Double?
    ) -> String {
        let comparison: String
        if let average = item.averageRating, let overallAverage {
            let delta = average - overallAverage
            comparison = abs(delta) < 0.05
                ? "与全部来源平均基本持平"
                : "比全部来源平均\(delta > 0 ? "高" : "低") \(abs(delta).oneDecimal) 分"
        } else { comparison = "暂无整体评分对比" }
        return "\(item.ratedRestaurantCount) 家有评分餐厅中，\(item.highRatingCount) 家达到 4.0 分；\(comparison)，回头餐厅占 \(item.repeatConversionRate.percent)。"
    }

    private nonisolated static func worstExplanation(
        _ item: RecommendationSourceAnalysis,
        overallAverage: Double?
    ) -> String {
        let averageText = item.averageRating.map { "餐厅平均 \($0.oneDecimal) 分" } ?? "平均分不足"
        return "\(item.ratedRestaurantCount) 家有评分餐厅中，\(item.lowRatingCount) 家不高于 2.5 分；\(averageText)，且回头餐厅占 \(item.repeatConversionRate.percent)。"
    }

    private nonisolated static func evidenceRole(_ item: AcquiredRestaurant) -> String {
        if let rating = item.averageRating, rating >= highRatingThreshold { return "高分命中" }
        if let rating = item.averageRating, rating <= lowRatingThreshold { return "低分证据" }
        if item.visits.count >= 2 { return "后来又回去" }
        return "来源带来的餐厅"
    }

    private nonisolated static func evidenceDetail(_ item: AcquiredRestaurant) -> String {
        let rating = item.averageRating.map { "你的餐厅平均 \($0.oneDecimal)" } ?? "你还没有评分"
        return "\(rating) · \(item.visits.count) 次到访"
    }

    private nonisolated static func imageReference(
        restaurantID: UUID,
        visitIDs: Set<UUID>,
        photos: [RecommendationSourceInput.PhotoRecord],
        merchantImageURL: URL?
    ) -> AnalysisImageReference {
        let eligible = photos.filter {
            $0.restaurantID == restaurantID || $0.visitID.map(visitIDs.contains) == true
        }
        let photo = eligible.sorted {
            let lhs = photoPriority($0)
            let rhs = photoPriority($1)
            if lhs != rhs { return lhs < rhs }
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id.uuidString < $1.id.uuidString
        }.first
        return photo.map { .photo($0.id, providerFallback: merchantImageURL) }
            ?? merchantImageURL.map(AnalysisImageReference.provider)
            ?? .none
    }

    private nonisolated static func photoPriority(_ photo: RecommendationSourceInput.PhotoRecord) -> Int {
        switch photo.kind {
        case .dish: 0
        case .visit: 1
        case .restaurantMarker: 2
        case .avatar: 3
        }
    }

    private nonisolated static func deduplicate(
        _ values: [RecommendationSourceInput.SourceRecord]
    ) -> [RecommendationSourceInput.SourceRecord] {
        Dictionary(grouping: values, by: \.id).compactMap { _, items in
            items.max { lhs, rhs in
                lhs.updatedAt == rhs.updatedAt
                    ? lhs.displayName > rhs.displayName
                    : lhs.updatedAt < rhs.updatedAt
            }
        }
    }

    private nonisolated static func deduplicate(
        _ values: [RecommendationSourceInput.RestaurantRecord]
    ) -> [RecommendationSourceInput.RestaurantRecord] {
        Dictionary(grouping: values, by: \.id).compactMap { _, items in
            items.max { lhs, rhs in
                lhs.updatedAt == rhs.updatedAt
                    ? lhs.name > rhs.name
                    : lhs.updatedAt < rhs.updatedAt
            }
        }
    }

    private nonisolated static func visitSort(
        _ lhs: RecommendationSourceInput.VisitRecord,
        _ rhs: RecommendationSourceInput.VisitRecord
    ) -> Bool {
        lhs.visitedAt == rhs.visitedAt ? lhs.id.uuidString < rhs.id.uuidString : lhs.visitedAt < rhs.visitedAt
    }

    private nonisolated static func sourceSort(_ lhs: RecommendationSourceAnalysis, _ rhs: RecommendationSourceAnalysis) -> Bool {
        if lhs.restaurantCount != rhs.restaurantCount { return lhs.restaurantCount > rhs.restaurantCount }
        if lhs.latestUsageAt != rhs.latestUsageAt { return (lhs.latestUsageAt ?? .distantPast) > (rhs.latestUsageAt ?? .distantPast) }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private nonisolated static func mostUsedSort(_ lhs: RecommendationSourceAnalysis, _ rhs: RecommendationSourceAnalysis) -> Bool {
        if lhs.restaurantCount != rhs.restaurantCount { return lhs.restaurantCount > rhs.restaurantCount }
        if lhs.ratedRestaurantCount != rhs.ratedRestaurantCount { return lhs.ratedRestaurantCount > rhs.ratedRestaurantCount }
        if lhs.latestUsageAt != rhs.latestUsageAt { return (lhs.latestUsageAt ?? .distantPast) > (rhs.latestUsageAt ?? .distantPast) }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private nonisolated static func averageSort(_ lhs: RecommendationSourceAnalysis, _ rhs: RecommendationSourceAnalysis) -> Bool {
        if lhs.averageRating != rhs.averageRating { return (lhs.averageRating ?? 0) > (rhs.averageRating ?? 0) }
        if lhs.ratedRestaurantCount != rhs.ratedRestaurantCount { return lhs.ratedRestaurantCount > rhs.ratedRestaurantCount }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private nonisolated static func bestSort(_ lhs: RecommendationSourceAnalysis, _ rhs: RecommendationSourceAnalysis) -> Bool {
        if lhs.reliabilityScore != rhs.reliabilityScore { return (lhs.reliabilityScore ?? 0) > (rhs.reliabilityScore ?? 0) }
        if lhs.ratedRestaurantCount != rhs.ratedRestaurantCount { return lhs.ratedRestaurantCount > rhs.ratedRestaurantCount }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private nonisolated static func worstSort(_ lhs: RecommendationSourceAnalysis, _ rhs: RecommendationSourceAnalysis) -> Bool {
        if lhs.pitfallScore != rhs.pitfallScore { return (lhs.pitfallScore ?? 0) > (rhs.pitfallScore ?? 0) }
        if lhs.ratedRestaurantCount != rhs.ratedRestaurantCount { return lhs.ratedRestaurantCount > rhs.ratedRestaurantCount }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private nonisolated static func restaurantEvidenceSort(_ lhs: AcquiredRestaurant, _ rhs: AcquiredRestaurant) -> Bool {
        if lhs.averageRating != rhs.averageRating { return (lhs.averageRating ?? -1) > (rhs.averageRating ?? -1) }
        if lhs.visits.count != rhs.visits.count { return lhs.visits.count > rhs.visits.count }
        if lhs.acquisitionDate != rhs.acquisitionDate { return lhs.acquisitionDate > rhs.acquisitionDate }
        return lhs.restaurant.id.uuidString < rhs.restaurant.id.uuidString
    }

    private nonisolated static func normalize(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private nonisolated static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private nonisolated static func standardDeviation(_ values: [Double]) -> Double? {
        guard values.count >= 2, let average = mean(values) else { return nil }
        let variance = values.reduce(0) { $0 + pow($1 - average, 2) } / Double(values.count)
        return sqrt(variance)
    }

    private nonisolated static func ratio(_ numerator: Int, _ denominator: Int) -> Double {
        denominator == 0 ? 0 : Double(numerator) / Double(denominator)
    }
}

private extension Double {
    nonisolated var oneDecimal: String { formatted(.number.precision(.fractionLength(1))) }
    nonisolated var percent: String { formatted(.percent.precision(.fractionLength(0))) }
}
