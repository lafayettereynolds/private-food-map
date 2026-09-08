import Foundation

enum TasteProfileAnalyzer {
    private nonisolated struct PreferenceAccumulator {
        var visitIDs = Set<UUID>()
        var restaurantIDs = Set<UUID>()
        var ratings: [Double] = []
        var latestVisit = Date.distantPast
    }

    private nonisolated struct RankedDish {
        let id: UUID
        let name: String
        let taste: String
        let restaurantID: UUID
        let visitCount: Int
        let averageRating: Double?
        let latestVisit: Date
        let score: Double
    }

    private nonisolated struct PriceBucket {
        let id: String
        let label: String
        let lowerBound: Double
        let upperBound: Double?

        func contains(_ value: Double) -> Bool {
            value >= lowerBound && (upperBound.map { value < $0 } ?? true)
        }
    }

    private nonisolated static let priceBuckets = [
        PriceBucket(id: "under-50", label: "¥0–50", lowerBound: 0, upperBound: 50),
        PriceBucket(id: "50-100", label: "¥50–100", lowerBound: 50, upperBound: 100),
        PriceBucket(id: "100-200", label: "¥100–200", lowerBound: 100, upperBound: 200),
        PriceBucket(id: "200-300", label: "¥200–300", lowerBound: 200, upperBound: 300),
        PriceBucket(id: "300-500", label: "¥300–500", lowerBound: 300, upperBound: 500),
        PriceBucket(id: "500-800", label: "¥500–800", lowerBound: 500, upperBound: 800),
        PriceBucket(id: "over-800", label: "¥800+", lowerBound: 800, upperBound: nil),
    ]

    private nonisolated static let nonCuisineTerms = [
        "约会", "聚餐", "朋友", "家人", "同事", "庆祝", "商务", "一个人", "独处",
        "安静", "热闹", "舒适", "拥挤", "宽敞", "精致", "氛围", "景观", "夜景", "露台",
        "会再去", "打卡", "环境", "服务", "性价比", "偏贵", "合理", "划算", "超值",
        "商场", "中心", "广场", "附近", "排队", "交通", "停车", "方便", "外卖",
    ]

    /// Deterministic score adapted from the Web taste-profile core. A rating signal is
    /// reliability-weighted so one isolated five-star visit cannot dominate repeat behavior.
    nonisolated static func analyze(
        _ input: TasteProfileInput,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> TasteProfileAnalysis {
        let activeRestaurants = input.restaurants.filter { $0.deletedAt == nil }
        let restaurantByID = Dictionary(uniqueKeysWithValues: activeRestaurants.map { ($0.id, $0) })
        let activeVisits = input.visits
            .filter { $0.deletedAt == nil && $0.visitedAt <= now && restaurantByID[$0.restaurantID] != nil }
            .sorted { lhs, rhs in
                lhs.visitedAt == rhs.visitedAt ? lhs.id.uuidString < rhs.id.uuidString : lhs.visitedAt < rhs.visitedAt
            }
        let visitByID = Dictionary(uniqueKeysWithValues: activeVisits.map { ($0.id, $0) })
        let visitsByRestaurant = Dictionary(grouping: activeVisits, by: \.restaurantID)
        let activeDishes = input.dishes.filter { $0.deletedAt == nil && restaurantByID[$0.restaurantID] != nil }
        let dishByID = Dictionary(uniqueKeysWithValues: activeDishes.map { ($0.id, $0) })
        let activePhotos = input.photos.filter { $0.deletedAt == nil && $0.kind != PhotoAssetKind.avatar.rawValue }

        let cuisineRanking = rankCuisines(
            visits: activeVisits,
            restaurantByID: restaurantByID,
            visitsByRestaurant: visitsByRestaurant,
            now: now,
            calendar: calendar
        )
        let dishes = rankDishes(
            dishes: activeDishes,
            associations: input.visitDishes,
            visitByID: visitByID
        )
        let spend = analyzeSpend(activeVisits)
        let scenes = frequency(
            activeVisits.flatMap { visit in
                var labels = visit.diningOccasionLabels
                labels.append(contentsOf: visit.environmentTags)
                if let noise = visit.noiseLevelLabel { labels.append(noise) }
                return labels
            },
            total: activeVisits.count
        )
        let sourceDirectory = directory(input.recommendationSources)
        let sourceLabels = activeVisits.compactMap { visit -> String? in
            if let id = visit.recommendationSourceID?.normalizedKey,
               let name = sourceDirectory[id] { return name }
            if let text = visit.recommendationSourceText?.trimmed.nilIfEmpty { return text }
            return visit.recommendationSourceTypeLabel
        }
        let recommendationSources = frequency(sourceLabels, total: activeVisits.count)
        let companionDirectory = directory(input.companions)
        let companionLabels = activeVisits.flatMap { visit -> [String] in
            var result = visit.companionIDs.compactMap { companionDirectory[$0.normalizedKey] }
            result.append(contentsOf: visit.companionNames)
            return stableUnique(result.map(\.trimmed).filter { !$0.isEmpty })
        }
        let companions = frequency(companionLabels, total: activeVisits.count)
        let ratingStyle = analyzeRatings(activeVisits)
        let repeatAnalysis = analyzeRepeat(visitsByRestaurant)
        let diningTime = analyzeDiningTime(activeVisits, calendar: calendar)
        let representatives = representativeRestaurants(
            restaurantByID: restaurantByID,
            visitsByRestaurant: visitsByRestaurant,
            cuisineRanking: cuisineRanking,
            activePhotos: activePhotos,
            visitByID: visitByID,
            dishByID: dishByID,
            now: now,
            calendar: calendar
        )
        let hero = foodHero(
            cuisineRanking: cuisineRanking,
            dishes: dishes,
            representatives: representatives,
            photos: activePhotos,
            dishByID: dishByID
        )
        let overallSufficiency = AnalysisSufficiencyPolicy.level(
            sampleCount: activeVisits.count,
            emergingAt: AnalysisSufficiencyThresholds.tasteProfile.emerging,
            establishedAt: AnalysisSufficiencyThresholds.tasteProfile.established
        )
        let favorite = favoriteStatement(
            cuisine: cuisineRanking.first,
            dish: dishes.first,
            sufficiency: overallSufficiency
        )
        let keywords = tasteKeywords(
            cuisines: cuisineRanking,
            dishes: dishes,
            scenes: scenes,
            visits: activeVisits,
            repeatAnalysis: repeatAnalysis
        )
        let summary = summary(
            visitCount: activeVisits.count,
            favorite: favorite,
            spend: spend,
            repeatAnalysis: repeatAnalysis,
            diningTime: diningTime
        )
        let callouts = buildCallouts(
            favorite: favorite,
            cuisine: cuisineRanking.first,
            dish: dishes.first,
            spend: spend,
            ratingStyle: ratingStyle,
            repeatAnalysis: repeatAnalysis,
            overallSufficiency: overallSufficiency
        )
        let insights = buildInsights(
            favorite: favorite,
            cuisines: cuisineRanking,
            spend: spend,
            scenes: scenes,
            sources: recommendationSources,
            companions: companions,
            ratingStyle: ratingStyle,
            repeatAnalysis: repeatAnalysis,
            diningTime: diningTime,
            overallSufficiency: overallSufficiency
        )

        return TasteProfileAnalysis(
            id: stableReportID(input: input, visits: activeVisits),
            kind: .tasteProfile,
            userDisplayName: input.userDisplayName,
            title: "我的口味档案",
            eyebrow: "MY TASTE PROFILE",
            subtitle: activeVisits.isEmpty ? "从第一次真实到访开始" : "基于 \(activeVisits.count) 次真实到访生成",
            summary: summary,
            generatedAt: now,
            visitCount: activeVisits.count,
            ratedVisitCount: activeVisits.compactMap(\.rating).count,
            sufficiency: overallSufficiency,
            favoriteStatement: favorite,
            cuisineRanking: cuisineRanking,
            spend: spend,
            diningScenes: scenes,
            recommendationSources: recommendationSources,
            companions: companions,
            ratingStyle: ratingStyle,
            repeatAnalysis: repeatAnalysis,
            diningTime: diningTime,
            keywords: keywords,
            hero: hero,
            callouts: callouts,
            insights: insights,
            restaurants: representatives,
            dataNote: "只分析你本机已同步的个人记录；nil 评分与 nil 消费不会当作 0。\(diningTime.timeZoneNotice)",
            footer: "Taste Map · 记录每一次真实的味觉记忆",
            recentComparison: AnalysisStatisticsDefinitions.recentComparison(
                in: activeVisits, now: now, calendar: calendar,
                visitedAt: \.visitedAt, restaurantID: \.restaurantID, rating: \.rating
            )
        )
    }

    private nonisolated static func rankCuisines(
        visits: [TasteProfileInput.VisitRecord],
        restaurantByID: [UUID: TasteProfileInput.RestaurantRecord],
        visitsByRestaurant: [UUID: [TasteProfileInput.VisitRecord]],
        now: Date,
        calendar: Calendar
    ) -> [TastePreferenceRank] {
        var accumulators: [String: PreferenceAccumulator] = [:]
        for visit in visits {
            guard let restaurant = restaurantByID[visit.restaurantID] else { continue }
            let cuisines = Set(restaurant.tags.compactMap(cuisineLabel))
            for label in cuisines {
                var value = accumulators[label] ?? PreferenceAccumulator()
                value.visitIDs.insert(visit.id)
                value.restaurantIDs.insert(visit.restaurantID)
                if let rating = visit.rating { value.ratings.append(rating) }
                value.latestVisit = max(value.latestVisit, visit.visitedAt)
                accumulators[label] = value
            }
        }

        return accumulators.map { label, value in
            let visits = value.visitIDs.count
            let repeatVisits = value.restaurantIDs.reduce(0) { partial, id in
                partial + max(0, (visitsByRestaurant[id]?.count ?? 0) - 1)
            }
            let representativeRatings = AnalysisStatisticsDefinitions.representativeRatings(
                in: value.restaurantIDs.flatMap { visitsByRestaurant[$0] ?? [] },
                restaurantID: \.restaurantID, rating: \.rating
            )
            let averageRating = average(representativeRatings)
            let highShare = share(representativeRatings.filter { $0 >= 4 }.count, representativeRatings.count)
            let ratingReliability = min(1, Double(representativeRatings.count) / 3)
            let ratingScore = ((averageRating ?? 0) * 2 * 0.48 + highShare * 3) * ratingReliability
            let frequencyScore = log2(Double(visits) + 1) * 1.15
            let repeatScore = log2(Double(repeatVisits) + 1) * 0.75
            let breadthScore = Double(min(3, value.restaurantIDs.count)) * 0.2
            let age = calendar.dateComponents([.day], from: value.latestVisit, to: now).day ?? 999
            let recencyScore = age <= 90 ? 0.45 : age <= 180 ? 0.2 : 0
            return TastePreferenceRank(
                id: label.normalizedKey,
                label: label,
                score: ratingScore + frequencyScore + repeatScore + breadthScore + recencyScore,
                visitCount: visits,
                restaurantCount: value.restaurantIDs.count,
                repeatVisitCount: repeatVisits,
                averageRating: averageRating,
                ratedVisitCount: value.ratings.count,
                ratedRestaurantCount: representativeRatings.count,
                observedSpanDays: value.latestVisit.timeIntervalSince(value.restaurantIDs.flatMap { visitsByRestaurant[$0] ?? [] }.map(\.visitedAt).min() ?? value.latestVisit) / 86_400
            )
        }
        .sorted { lhs, rhs in
            if abs(lhs.score - rhs.score) > 0.000_001 { return lhs.score > rhs.score }
            if lhs.visitCount != rhs.visitCount { return lhs.visitCount > rhs.visitCount }
            if lhs.restaurantCount != rhs.restaurantCount { return lhs.restaurantCount > rhs.restaurantCount }
            return lhs.label.localizedStandardCompare(rhs.label) == .orderedAscending
        }
    }

    private nonisolated static func rankDishes(
        dishes: [TasteProfileInput.DishRecord],
        associations: [TasteProfileInput.VisitDishRecord],
        visitByID: [UUID: TasteProfileInput.VisitRecord]
    ) -> [RankedDish] {
        let dishByID = Dictionary(uniqueKeysWithValues: dishes.map { ($0.id, $0) })
        var visitsByDish: [UUID: Set<UUID>] = [:]
        for association in associations where association.deletedAt == nil {
            guard dishByID[association.dishID] != nil, visitByID[association.visitID] != nil else { continue }
            visitsByDish[association.dishID, default: []].insert(association.visitID)
        }
        for dish in dishes where visitByID[dish.originVisitID] != nil {
            visitsByDish[dish.id, default: []].insert(dish.originVisitID)
        }

        return dishes.compactMap { dish -> RankedDish? in
            let visitIDs = visitsByDish[dish.id] ?? []
            guard !visitIDs.isEmpty else { return nil }
            let visits = visitIDs.compactMap { visitByID[$0] }
            let ratings = [dish.rating].compactMap { $0 } + visits.compactMap(\.rating)
            let averageRating = average(ratings)
            let latest = visits.map(\.visitedAt).max() ?? dish.updatedAt
            let ratingScore = (averageRating ?? 0) * min(1, Double(ratings.count) / 2)
            let score = log2(Double(visits.count) + 1) * 1.3 + ratingScore
            return RankedDish(
                id: dish.id,
                name: dish.name,
                taste: dish.taste,
                restaurantID: dish.restaurantID,
                visitCount: visits.count,
                averageRating: averageRating,
                latestVisit: latest,
                score: score
            )
        }
        .sorted { lhs, rhs in
            if abs(lhs.score - rhs.score) > 0.000_001 { return lhs.score > rhs.score }
            if lhs.visitCount != rhs.visitCount { return lhs.visitCount > rhs.visitCount }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private nonisolated static func analyzeSpend(
        _ visits: [TasteProfileInput.VisitRecord]
    ) -> TasteProfileSpendAnalysis {
        let values = AnalysisStatisticsDefinitions.recordedSpendValues(
            in: visits,
            spend: \.myActualSpend
        ).sorted()
        let distribution = priceBuckets.compactMap { bucket -> SpendDistributionItem? in
            let count = values.filter(bucket.contains).count
            guard count > 0 else { return nil }
            return SpendDistributionItem(
                id: bucket.id,
                label: bucket.label,
                count: count,
                share: share(count, values.count)
            )
        }
        let typical = distribution.sorted { lhs, rhs in
            lhs.count == rhs.count ? lhs.id < rhs.id : lhs.count > rhs.count
        }.first?.label
        return TasteProfileSpendAnalysis(
            sampleCount: values.count,
            median: percentile(values, 0.5),
            lowerQuartile: percentile(values, 0.25),
            upperQuartile: percentile(values, 0.75),
            typicalBucket: typical,
            distribution: distribution,
            sufficiency: AnalysisSufficiencyPolicy.level(sampleCount: values.count, emergingAt: 2, establishedAt: 8)
        )
    }

    private nonisolated static func analyzeRatings(
        _ visits: [TasteProfileInput.VisitRecord]
    ) -> TasteProfileRatingStyle {
        let ratings = AnalysisStatisticsDefinitions.overallRatings(in: visits, rating: \.rating).sorted()
        let sufficiency = AnalysisSufficiencyPolicy.level(
            sampleCount: ratings.count,
            emergingAt: AnalysisSufficiencyThresholds.tasteProfile.emerging,
            establishedAt: AnalysisSufficiencyThresholds.tasteProfile.established
        )
        let mean = average(ratings)
        let median = percentile(ratings, 0.5)
        let deviation = mean.map { mean in
            sqrt(ratings.reduce(0) { $0 + pow($1 - mean, 2) } / Double(max(1, ratings.count)))
        }
        let label: String
        if sufficiency == .insufficient {
            label = ratings.isEmpty ? "未评分" : "评分仍在形成"
        } else if let mean, let deviation, mean >= 4.3, deviation < 0.55 {
            label = "高分稳定型"
        } else if let mean, mean < 3.6 {
            label = "打分比较克制"
        } else if let deviation, deviation >= 0.9 {
            label = "好坏分得很清楚"
        } else {
            label = "温和稳定型"
        }
        let dimensions: [(String, Double?)] = [
            ("性价比", average(visits.compactMap(\.valueRating))),
            ("环境", average(visits.compactMap(\.environmentRating))),
            ("服务", average(visits.compactMap(\.serviceRating))),
        ]
        let dimensionSummary = dimensions
            .compactMap { label, value in value.map { "\(label) \(oneDecimal($0))" } }
            .nilIfEmpty
            .map { $0.joined(separator: " · ") }
        let detail: String
        if let mean, let deviation, sufficiency != .insufficient {
            detail = "\(ratings.count) 次评分，平均 \(oneDecimal(mean))，波动 \(oneDecimal(deviation))。"
        } else if ratings.isEmpty {
            detail = "未评分也可以保存；这里不会把空评分当作 0。"
        } else {
            detail = "已有 \(ratings.count) 次评分，再记录几次后判断评分风格。"
        }
        return TasteProfileRatingStyle(
            sampleCount: ratings.count,
            average: mean,
            median: median,
            standardDeviation: deviation,
            highRatingShare: share(ratings.filter { $0 >= 4 }.count, ratings.count),
            lowRatingShare: share(ratings.filter { $0 < 3 }.count, ratings.count),
            label: label,
            detail: detail,
            dimensionSummary: dimensionSummary,
            sufficiency: sufficiency
        )
    }

    private nonisolated static func analyzeRepeat(
        _ visitsByRestaurant: [UUID: [TasteProfileInput.VisitRecord]]
    ) -> TasteProfileRepeatAnalysis {
        let visited = visitsByRestaurant.count
        let repeated = visitsByRestaurant.values.filter { $0.count >= 2 }.count
        let rate = share(repeated, visited)
        let sufficiency = AnalysisSufficiencyPolicy.level(sampleCount: visited, emergingAt: 2, establishedAt: 10)
        let label: String
        if sufficiency == .insufficient {
            label = "回头偏好形成中"
        } else if rate >= 0.4 {
            label = "熟店偏爱明显"
        } else if rate >= 0.2 {
            label = "熟店与新店平衡"
        } else {
            label = "更偏向探索新店"
        }
        let detail = visited == 0
            ? "保存到访后开始计算。"
            : "\(visited) 家去过的餐厅中，\(repeated) 家有 2 次以上到访。"
        return TasteProfileRepeatAnalysis(
            repeatedRestaurantCount: repeated,
            visitedRestaurantCount: visited,
            rate: rate,
            label: label,
            detail: detail,
            sufficiency: sufficiency
        )
    }

    private nonisolated static func analyzeDiningTime(
        _ visits: [TasteProfileInput.VisitRecord],
        calendar: Calendar
    ) -> TasteProfileTimeAnalysis {
        let notice = "到访时间按当前设备时区解释；旧记录未保存原始录入时区，因此不做跨时区精确结论。"
        guard !visits.isEmpty else {
            return TasteProfileTimeAnalysis(
                label: nil, sampleCount: 0, share: 0, detail: "记录到访时间后开始分析。",
                timeZoneNotice: notice, sufficiency: .insufficient
            )
        }
        let labels = visits.map { visit -> String in
            switch calendar.component(.hour, from: visit.visitedAt) {
            case 5..<10: "早餐"
            case 10..<14: "午餐"
            case 14..<17: "下午茶"
            case 17..<22: "晚餐"
            default: "夜宵"
            }
        }
        let items = frequency(labels, total: labels.count)
        let leading = items.first
        let sufficiency = AnalysisSufficiencyPolicy.level(sampleCount: labels.count, emergingAt: 3, establishedAt: 10)
        return TasteProfileTimeAnalysis(
            label: leading?.label,
            sampleCount: labels.count,
            share: leading?.share ?? 0,
            detail: leading.map { "\($0.count) 次记录发生在\($0.label)时段。" } ?? "记录到访时间后开始分析。",
            timeZoneNotice: notice,
            sufficiency: sufficiency
        )
    }

    private nonisolated static func representativeRestaurants(
        restaurantByID: [UUID: TasteProfileInput.RestaurantRecord],
        visitsByRestaurant: [UUID: [TasteProfileInput.VisitRecord]],
        cuisineRanking: [TastePreferenceRank],
        activePhotos: [TasteProfileInput.PhotoRecord],
        visitByID: [UUID: TasteProfileInput.VisitRecord],
        dishByID: [UUID: TasteProfileInput.DishRecord],
        now: Date,
        calendar: Calendar
    ) -> [RepresentativeRestaurant] {
        guard !visitsByRestaurant.isEmpty else { return [] }
        var candidates: [(UUID, String)] = []
        if let id = visitsByRestaurant.keys.sorted(by: uuidLess).max(by: { lhs, rhs in
            let left = visitsByRestaurant[lhs]?.count ?? 0
            let right = visitsByRestaurant[rhs]?.count ?? 0
            return left == right ? uuidLess(lhs, rhs) : left < right
        }) {
            candidates.append((id, "你最常去的店"))
        }

        let favorite = visitsByRestaurant.compactMap { id, visits -> (UUID, Double, Int, Date)? in
            guard let rating = average(visits.compactMap(\.rating)) else { return nil }
            return (id, rating, visits.count, visits.map(\.visitedAt).max() ?? .distantPast)
        }.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            if lhs.2 != rhs.2 { return lhs.2 > rhs.2 }
            if lhs.3 != rhs.3 { return lhs.3 > rhs.3 }
            return uuidLess(lhs.0, rhs.0)
        }.first?.0
        if let favorite { candidates.append((favorite, "你最喜欢的店")) }

        let recentCutoff = calendar.date(byAdding: .day, value: -90, to: now) ?? .distantPast
        let recent = visitsByRestaurant.map { id, visits in
            (id, visits.filter { $0.visitedAt >= recentCutoff }.count, visits.map(\.visitedAt).max() ?? .distantPast)
        }.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            if lhs.2 != rhs.2 { return lhs.2 > rhs.2 }
            return uuidLess(lhs.0, rhs.0)
        }.first?.0
        if let recent { candidates.append((recent, "近期常去的店")) }

        let topCuisine = cuisineRanking.first?.label
        let representative = visitsByRestaurant.keys.map { id -> (UUID, Double) in
            let visits = visitsByRestaurant[id] ?? []
            let restaurant = restaurantByID[id]
            let cuisineMatch = restaurant?.tags.compactMap(cuisineLabel).contains(topCuisine ?? "") == true ? 2.5 : 0
            let rating = (average(visits.compactMap(\.rating)) ?? 0) * 0.8
            let repeatScore = log2(Double(visits.count) + 1) * 1.2
            return (id, cuisineMatch + rating + repeatScore)
        }.sorted { lhs, rhs in
            lhs.1 == rhs.1 ? uuidLess(lhs.0, rhs.0) : lhs.1 > rhs.1
        }.first?.0
        if let representative { candidates.append((representative, "最能代表你口味的店")) }

        for id in visitsByRestaurant.keys.sorted(by: uuidLess) where candidates.count < 8 {
            candidates.append((id, "代表你的餐厅"))
        }

        var used = Set<UUID>()
        return candidates.compactMap { id, role -> RepresentativeRestaurant? in
            guard used.insert(id).inserted,
                  let restaurant = restaurantByID[id],
                  let visits = visitsByRestaurant[id] else { return nil }
            let rating = average(visits.compactMap(\.rating))
            let latest = visits.map(\.visitedAt).max()
            let detail = [
                "\(visits.count) 次到访",
                rating.map { "平均 \(oneDecimal($0))" },
                latest.map { shortDate($0, calendar: calendar) },
            ].compactMap { $0 }.joined(separator: " · ")
            let photo = preferredPhoto(
                for: id,
                photos: activePhotos,
                visitByID: visitByID,
                dishByID: dishByID
            )
            return RepresentativeRestaurant(
                id: id,
                name: restaurant.name,
                role: role,
                detail: detail,
                averageRating: rating,
                visitCount: visits.count,
                imageReference: photo.map { .photo($0.id, providerFallback: restaurant.merchantImageURL) }
                    ?? restaurant.merchantImageURL.map(AnalysisImageReference.provider)
                    ?? .none
            )
        }.prefix(4).map { $0 }
    }

    private nonisolated static func foodHero(
        cuisineRanking: [TastePreferenceRank],
        dishes: [RankedDish],
        representatives: [RepresentativeRestaurant],
        photos: [TasteProfileInput.PhotoRecord],
        dishByID: [UUID: TasteProfileInput.DishRecord]
    ) -> FoodHeroPresentation {
        let cuisineLabels = cuisineRanking.prefix(4).map(\.label)
        let dishLabels = dishes.prefix(4).map(\.name)
        let theme = resolveHeroTheme(labels: cuisineLabels + dishLabels)
        var imageReferences: [AnalysisImageReference] = []
        for dish in dishes.prefix(4) {
            let dishPhotos = photos
                .filter { $0.dishID == dish.id && $0.deletedAt == nil }
                .sorted(by: photoSort)
            if let photo = dishPhotos.first {
                imageReferences.append(.photo(photo.id))
            }
        }
        imageReferences.append(contentsOf: representatives.map(\.imageReference))
        imageReferences = stableUnique(imageReferences.filter {
            if case .none = $0 { return false }
            return true
        }).prefix(4).map { $0 }
        if imageReferences.isEmpty { imageReferences = [.asset(theme.assetName)] }

        let labels = stableUnique(cuisineLabels + dishLabels).prefix(4).map { $0 }
        let primary = cuisineLabels.first ?? dishLabels.first ?? "口味正在形成"
        return FoodHeroPresentation(
            theme: theme,
            primaryTheme: primary,
            secondaryThemes: Array(labels.dropFirst()),
            labels: labels,
            imageReferences: imageReferences,
            fallbackAssetName: theme.assetName,
            tone: tone(for: theme)
        )
    }

    nonisolated static func resolveHeroTheme(labels: [String]) -> FoodHeroTheme {
        var scores: [FoodHeroTheme: Int] = [:]
        for label in labels {
            let value = label.normalizedKey
            let theme: FoodHeroTheme?
            if containsAny(value, ["日料", "日本", "寿司", "刺身", "居酒屋", "拉面", "sushi", "japanese"]) {
                theme = .japanese
            } else if containsAny(value, ["火锅", "烧烤", "烤肉", "串", "hotpot", "bbq", "grill"]) {
                theme = .hotpotGrill
            } else if containsAny(value, ["咖啡", "甜品", "甜点", "烘焙", "面包", "早午餐", "brunch", "cafe", "dessert"]) {
                theme = .cafe
            } else if containsAny(value, ["西餐", "牛排", "意面", "法餐", "意大利", "汉堡", "western", "steak", "pasta"]) {
                theme = .western
            } else if containsAny(value, ["中餐", "川菜", "粤菜", "湘菜", "本帮", "江浙", "面", "饺", "小笼", "家常"]) {
                theme = .chinese
            } else {
                theme = nil
            }
            if let theme { scores[theme, default: 0] += 1 }
        }
        let ranked = scores.sorted { lhs, rhs in
            lhs.value == rhs.value ? lhs.key.rawValue < rhs.key.rawValue : lhs.value > rhs.value
        }
        guard let first = ranked.first else { return .mixed }
        if ranked.count > 1, Double(ranked[1].value) >= Double(first.value) * 0.6 { return .mixed }
        return first.key
    }

    private nonisolated static func tasteKeywords(
        cuisines: [TastePreferenceRank],
        dishes: [RankedDish],
        scenes: [AnalysisFrequencyItem],
        visits: [TasteProfileInput.VisitRecord],
        repeatAnalysis: TasteProfileRepeatAnalysis
    ) -> [String] {
        var values = cuisines.prefix(3).map(\.label)
        values.append(contentsOf: dishes.filter { $0.visitCount >= 2 || ($0.averageRating ?? 0) >= 4 }.prefix(2).map(\.name))
        values.append(contentsOf: scenes.prefix(1).map(\.label))
        let highRated = visits.filter { ($0.rating ?? 0) >= 4 }
        let traitCounts = frequency(
            highRated.flatMap { $0.valueTags + $0.environmentTags + $0.serviceTags },
            total: max(1, highRated.count)
        )
        values.append(contentsOf: traitCounts.prefix(2).map(\.label))
        if repeatAnalysis.sufficiency != .insufficient, repeatAnalysis.rate >= 0.25 {
            values.append("喜欢回熟店")
        }
        return Array(stableUnique(values.map(\.trimmed).filter { !$0.isEmpty }).prefix(7))
    }

    private nonisolated static func buildCallouts(
        favorite: String,
        cuisine: TastePreferenceRank?,
        dish: RankedDish?,
        spend: TasteProfileSpendAnalysis,
        ratingStyle: TasteProfileRatingStyle,
        repeatAnalysis: TasteProfileRepeatAnalysis,
        overallSufficiency: AnalysisDataSufficiency
    ) -> [AnalysisCallout] {
        let favoriteSufficiency: AnalysisDataSufficiency = cuisine != nil || dish != nil ? overallSufficiency : .insufficient
        return [
            AnalysisCallout(
                id: "favorite", icon: "🍽️", title: "真正喜欢", value: favorite,
                detail: cuisine.map { "\($0.visitCount) 次到访 · \($0.restaurantCount) 家餐厅" }
                    ?? dish.map { "在 \($0.visitCount) 次到访里记录" }
                    ?? "等待真实菜系或菜品记录",
                tone: .ingredientRed, sufficiency: favoriteSufficiency
            ),
            AnalysisCallout(
                id: "spend", icon: "🧾", title: "典型消费",
                value: spend.typicalBucket ?? "待消费记录",
                detail: spend.median.map { "中位数 \(currency($0)) · \(spend.sampleCount) 次" } ?? "nil 消费不会当作 0",
                tone: .cream, sufficiency: spend.sufficiency
            ),
            AnalysisCallout(
                id: "rating", icon: "🥢", title: "评分风格", value: ratingStyle.label,
                detail: ratingStyle.average.map { "平均 \(oneDecimal($0)) · \(ratingStyle.sampleCount) 次" } ?? "用户可以完全不评分",
                tone: .leafGreen, sufficiency: ratingStyle.sufficiency
            ),
            AnalysisCallout(
                id: "repeat", icon: "🍲", title: "回头率",
                value: repeatAnalysis.sufficiency == .insufficient ? "继续记录" : percent(repeatAnalysis.rate),
                detail: repeatAnalysis.detail,
                tone: .caramel, sufficiency: repeatAnalysis.sufficiency
            ),
        ]
    }

    private nonisolated static func buildInsights(
        favorite: String,
        cuisines: [TastePreferenceRank],
        spend: TasteProfileSpendAnalysis,
        scenes: [AnalysisFrequencyItem],
        sources: [AnalysisFrequencyItem],
        companions: [AnalysisFrequencyItem],
        ratingStyle: TasteProfileRatingStyle,
        repeatAnalysis: TasteProfileRepeatAnalysis,
        diningTime: TasteProfileTimeAnalysis,
        overallSufficiency: AnalysisDataSufficiency
    ) -> [AnalysisInsight] {
        let cuisineSufficiency = AnalysisSufficiencyPolicy.level(
            sampleCount: cuisines.first?.visitCount ?? 0,
            emergingAt: 2,
            establishedAt: 6
        )
        let sceneSufficiency = AnalysisSufficiencyPolicy.level(
            sampleCount: scenes.first?.count ?? 0,
            emergingAt: 2,
            establishedAt: 5
        )
        let sourceSufficiency = AnalysisSufficiencyPolicy.level(
            sampleCount: sources.first?.count ?? 0,
            emergingAt: 1,
            establishedAt: 4
        )
        let companionSufficiency = AnalysisSufficiencyPolicy.level(
            sampleCount: companions.first?.count ?? 0,
            emergingAt: 1,
            establishedAt: 4
        )
        return [
            AnalysisInsight(
                id: "favorite", icon: "🍽️", title: "你真正喜欢什么", value: favorite,
                detail: "综合到访频率、跨餐厅覆盖、重复到访、可靠评分与近期性；不会用一次到访生成假精确结论。",
                tone: .ingredientRed, sufficiency: cuisines.isEmpty ? overallSufficiency : cuisineSufficiency
            ),
            AnalysisInsight(
                id: "cuisine", icon: "🥟", title: "常吃菜系 / 偏好排行",
                value: cuisines.prefix(3).map(\.label).joined(separator: " · ").nilIfEmpty ?? "菜系仍在形成",
                detail: cuisines.first.map { "第 1 位覆盖 \($0.restaurantCount) 家餐厅、\($0.visitCount) 次到访。" }
                    ?? "仅使用 Restaurant 的真实结构化标签，不从店名猜菜系。",
                tone: .brand, sufficiency: cuisineSufficiency
            ),
            AnalysisInsight(
                id: "spend", icon: "🧾", title: "常去价位",
                value: spend.typicalBucket ?? "待实际消费记录",
                detail: spend.median.map { "中位数 \(currency($0))；四分位范围 \(currency(spend.lowerQuartile ?? $0))～\(currency(spend.upperQuartile ?? $0))。" }
                    ?? "只使用 myActualSpend，Dish price 和空值都不会替代。",
                tone: .cream, sufficiency: spend.sufficiency
            ),
            AnalysisInsight(
                id: "scene", icon: "🕯️", title: "用餐氛围 / 场景",
                value: scenes.prefix(3).map(\.label).joined(separator: " · ").nilIfEmpty ?? "待场景记录",
                detail: scenes.first.map { "\($0.count) 次到访出现“\($0.label)”。" }
                    ?? "使用到访场景、环境标签与噪音记录。",
                tone: .leafGreen, sufficiency: sceneSufficiency
            ),
            AnalysisInsight(
                id: "source", icon: "📍", title: "推荐来源",
                value: sources.first?.label ?? "待推荐来源记录",
                detail: sources.first.map { "\($0.count) 次到访来自这个来源；完整靠谱度分析留给 P4-C。" }
                    ?? "这里只做出现频率概览，不生成“最靠谱/最坑”结论。",
                tone: .brand, sufficiency: sourceSufficiency
            ),
            AnalysisInsight(
                id: "companion", icon: "🥂", title: "常见饭搭子",
                value: companions.first?.label ?? "待饭搭子记录",
                detail: companions.first.map { "共同出现 \($0.count) 次；完整关系画像留给 P4-B。" }
                    ?? "不从备注猜测人名。",
                tone: .caramel, sufficiency: companionSufficiency
            ),
            AnalysisInsight(
                id: "rating", icon: "⭐️", title: "评分风格", value: ratingStyle.label,
                detail: [ratingStyle.detail, ratingStyle.dimensionSummary].compactMap { $0 }.joined(separator: " "),
                tone: .leafGreen, sufficiency: ratingStyle.sufficiency
            ),
            AnalysisInsight(
                id: "repeat", icon: "🔁", title: "回头率 / 稳定偏爱",
                value: repeatAnalysis.sufficiency == .insufficient ? "继续记录" : "\(percent(repeatAnalysis.rate)) · \(repeatAnalysis.label)",
                detail: repeatAnalysis.detail,
                tone: .ingredientRed, sufficiency: repeatAnalysis.sufficiency
            ),
            AnalysisInsight(
                id: "time", icon: "🌙", title: "用餐时间偏好",
                value: diningTime.label ?? "待时间记录",
                detail: "\(diningTime.detail) \(diningTime.timeZoneNotice)",
                tone: .brand, sufficiency: diningTime.sufficiency
            ),
        ]
    }

    private nonisolated static func favoriteStatement(
        cuisine: TastePreferenceRank?,
        dish: RankedDish?,
        sufficiency: AnalysisDataSufficiency
    ) -> String {
        guard sufficiency != .insufficient else { return "口味正在形成" }
        if let cuisine, cuisine.ratedRestaurantCount >= 5 {
            return cuisine.ratedRestaurantCount >= 10 && cuisine.observedSpanDays >= 30
                ? "最稳定偏爱 \(cuisine.label)"
                : "\(cuisine.label)正在成为偏爱"
        }
        if let dish, dish.visitCount >= 2 {
            return "常记住 \(dish.name)"
        }
        return "口味正在形成"
    }

    private nonisolated static func summary(
        visitCount: Int,
        favorite: String,
        spend: TasteProfileSpendAnalysis,
        repeatAnalysis: TasteProfileRepeatAnalysis,
        diningTime: TasteProfileTimeAnalysis
    ) -> String {
        guard visitCount > 0 else {
            return "保存第一次真实到访后，Taste Map 会把菜系、消费、评分和回头选择慢慢拼成你的味觉地图。"
        }
        var pieces: [String] = []
        if favorite != "口味正在形成" { pieces.append(favorite) }
        if let bucket = spend.typicalBucket { pieces.append("实际消费多落在\(bucket)") }
        if repeatAnalysis.sufficiency != .insufficient, repeatAnalysis.rate >= 0.25 {
            pieces.append("你也会回到稳定喜欢的店")
        }
        if diningTime.sufficiency != .insufficient, let label = diningTime.label {
            pieces.append("\(label)是最常记录的时段")
        }
        if pieces.isEmpty { return "已经收下 \(visitCount) 次真实到访；更多结构化记录会让结论逐渐清晰。" }
        return pieces.joined(separator: "，") + "。"
    }

    private nonisolated static func frequency(_ labels: [String], total: Int) -> [AnalysisFrequencyItem] {
        var counts: [String: (label: String, count: Int)] = [:]
        for raw in labels {
            let label = raw.trimmed
            guard !label.isEmpty else { continue }
            let key = label.normalizedKey
            let existing = counts[key]
            counts[key] = (existing?.label ?? label, (existing?.count ?? 0) + 1)
        }
        return counts.map { key, value in
            AnalysisFrequencyItem(
                id: key,
                label: value.label,
                count: value.count,
                share: share(value.count, total)
            )
        }.sorted { lhs, rhs in
            lhs.count == rhs.count
                ? lhs.label.localizedStandardCompare(rhs.label) == .orderedAscending
                : lhs.count > rhs.count
        }
    }

    private nonisolated static func directory(
        _ records: [TasteProfileInput.DirectoryRecord]
    ) -> [String: String] {
        var result: [String: String] = [:]
        for record in records where record.deletedAt == nil {
            for identifier in record.identifiers { result[identifier.normalizedKey] = record.displayName }
        }
        return result
    }

    private nonisolated static func cuisineLabel(_ raw: String) -> String? {
        let value = raw.trimmed
        guard !value.isEmpty, value.count <= 16,
              !nonCuisineTerms.contains(where: value.contains) else { return nil }
        let normalized = value.normalizedKey
        if containsAny(normalized, ["日料", "日本", "寿司", "刺身", "居酒屋", "japanese", "sushi"]) { return "日料" }
        if containsAny(normalized, ["火锅", "涮锅", "hotpot"]) { return "火锅" }
        if containsAny(normalized, ["烧烤", "烤肉", "烤串", "bbq", "grill"]) { return "烧烤" }
        if containsAny(normalized, ["西餐", "牛排", "意面", "法餐", "意大利", "western", "steak", "pasta"]) { return "西餐" }
        if containsAny(normalized, ["咖啡", "甜品", "甜点", "烘焙", "面包", "brunch", "cafe", "dessert"]) { return "咖啡甜点" }
        return value
    }

    private nonisolated static func preferredPhoto(
        for restaurantID: UUID,
        photos: [TasteProfileInput.PhotoRecord],
        visitByID: [UUID: TasteProfileInput.VisitRecord],
        dishByID: [UUID: TasteProfileInput.DishRecord]
    ) -> TasteProfileInput.PhotoRecord? {
        photos.filter { photo in
            if photo.restaurantID == restaurantID { return true }
            if let visitID = photo.visitID, visitByID[visitID]?.restaurantID == restaurantID { return true }
            if let dishID = photo.dishID, dishByID[dishID]?.restaurantID == restaurantID { return true }
            return false
        }.sorted(by: photoSort).first
    }

    private nonisolated static func photoSort(
        _ lhs: TasteProfileInput.PhotoRecord,
        _ rhs: TasteProfileInput.PhotoRecord
    ) -> Bool {
        func priority(_ kind: String) -> Int {
            if kind == PhotoAssetKind.dish.rawValue { return 0 }
            if kind == PhotoAssetKind.visit.rawValue { return 1 }
            if kind == PhotoAssetKind.restaurantMarker.rawValue { return 2 }
            return 3
        }
        let left = priority(lhs.kind)
        let right = priority(rhs.kind)
        if left != right { return left < right }
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return uuidLess(lhs.id, rhs.id)
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

    private nonisolated static func stableReportID(
        input: TasteProfileInput,
        visits: [TasteProfileInput.VisitRecord]
    ) -> String {
        let newest = visits.map(\.updatedAt).max()?.timeIntervalSince1970 ?? 0
        return "taste-profile:\(input.userDisplayName.normalizedKey):\(visits.count):\(Int(newest))"
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

    private nonisolated static func average(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private nonisolated static func share(_ count: Int, _ total: Int) -> Double {
        total == 0 ? 0 : Double(count) / Double(total)
    }

    private nonisolated static func currency(_ value: Double) -> String {
        "¥\(Int(value.rounded()))"
    }

    private nonisolated static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private nonisolated static func oneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private nonisolated static func shortDate(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0).\(components.month ?? 0).\(components.day ?? 0)"
    }

    private nonisolated static func containsAny(_ value: String, _ terms: [String]) -> Bool {
        terms.contains(where: value.contains)
    }

    private nonisolated static func uuidLess(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }

    private nonisolated static func stableUnique<T: Hashable>(_ values: [T]) -> [T] {
        var seen = Set<T>()
        return values.filter { seen.insert($0).inserted }
    }
}

private extension String {
    nonisolated var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    nonisolated var nilIfEmpty: String? { isEmpty ? nil : self }
    nonisolated var normalizedKey: String {
        precomposedStringWithCompatibilityMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

private extension Array {
    nonisolated var nilIfEmpty: Self? { isEmpty ? nil : self }
}
