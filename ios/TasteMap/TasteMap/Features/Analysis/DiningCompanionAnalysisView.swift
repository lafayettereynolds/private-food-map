import SwiftData
import SwiftUI

struct DiningCompanionAnalysisScreen: View {
    @Query private var restaurants: [Restaurant]
    @Query private var visits: [Visit]
    @Query private var dishes: [Dish]
    @Query private var visitDishes: [VisitDish]
    @Query private var photos: [PhotoAsset]
    @Query private var companions: [DiningCompanion]
    @Query private var profiles: [UserProfile]
    @Query private var socialProfiles: [CachedSocialProfile]
    @Query private var friendships: [CachedFriendship]

    @State private var overview: DiningCompanionOverview?

    private var photosByID: [UUID: PhotoAsset] {
        Dictionary(uniqueKeysWithValues: photos.filter { $0.deletedAt == nil }.map { ($0.id, $0) })
    }

    private var restaurantsByID: [UUID: Restaurant] {
        Dictionary(uniqueKeysWithValues: restaurants.filter { $0.deletedAt == nil }.map { ($0.id, $0) })
    }

    private var dataRevision: String {
        let dates = restaurants.map { max($0.updatedAt, $0.deletedAt ?? .distantPast) }
            + visits.map { max($0.updatedAt, $0.deletedAt ?? .distantPast) }
            + dishes.map { max($0.updatedAt, $0.deletedAt ?? .distantPast) }
            + visitDishes.map { max($0.updatedAt, $0.deletedAt ?? .distantPast) }
            + photos.map { max($0.updatedAt, $0.deletedAt ?? .distantPast) }
            + companions.map { max($0.updatedAt, $0.deletedAt ?? .distantPast) }
            + profiles.map { max($0.updatedAt, $0.deletedAt ?? .distantPast) }
            + socialProfiles.map(\.fetchedAt)
            + friendships.map { max($0.updatedAt, $0.deletedAt ?? .distantPast) }
        let latest = dates.max()?.timeIntervalSince1970 ?? 0
        return [
            restaurants.count, visits.count, dishes.count, visitDishes.count, photos.count,
            companions.count, profiles.count, socialProfiles.count, friendships.count,
        ].map(String.init).joined(separator: ":") + ":\(latest)"
    }

    var body: some View {
        PremiumFeatureGate(feature: .companionAnalysis) {
            unlockedContent
        }
    }

    private var unlockedContent: some View {
        Group {
            if let overview {
                DiningCompanionOverviewView(
                    overview: overview,
                    photosByID: photosByID,
                    restaurantsByID: restaurantsByID
                )
            } else {
                ProgressView("正在整理共同餐桌…")
                    .tint(TasteMapAnalysisTheme.brand)
            }
        }
        .task(id: dataRevision) {
            let input = DiningCompanionInput.capture(
                restaurants: restaurants,
                visits: visits,
                dishes: dishes,
                visitDishes: visitDishes,
                photos: photos,
                companions: companions,
                profiles: profiles,
                socialProfiles: socialProfiles,
                friendships: friendships
            )
            overview = await Task.detached(priority: .userInitiated) {
                DiningCompanionAnalyzer.analyze(input)
            }.value
        }
    }
}

struct DiningCompanionOverviewView: View {
    let overview: DiningCompanionOverview
    let photosByID: [UUID: PhotoAsset]
    let restaurantsByID: [UUID: Restaurant]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 26) {
                header
                if let lead = overview.lead {
                    topCompanionHero(lead)
                } else {
                    AnalysisGrowthPrompt(
                        symbol: "🥢",
                        title: overview.companionCount == 0 ? "还没有饭搭子" : "共同到访正在形成",
                        detail: overview.companionCount == 0
                            ? "在 Visit 中记录一起吃饭的人后，这里会建立独立身份与共同记录。"
                            : "已经保存饭搭子，但还没有包含他们的有效到访。"
                    )
                }
                companionList
                privacyNote
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 48)
        }
        .background(TasteMapAnalysisTheme.canvas.ignoresSafeArea())
        .tasteMapBottomNavigationHidden()
        .navigationTitle("饭搭子分析")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("companion-analysis-overview")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DINING COMPANIONS")
                .font(.caption2.weight(.bold))
                .tracking(1.8)
                .foregroundStyle(TasteMapAnalysisTheme.brand)
            Text("一起吃饭的人，也有一张味觉地图")
                .font(.largeTitle.weight(.heavy))
                .foregroundStyle(TasteMapAnalysisTheme.ink)
            Text("按共同到访次数排序；次数相同再看最近一次。只分析你自己记录的 Visit。")
                .font(.subheadline)
                .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func topCompanionHero(_ report: DiningCompanionAnalysis) -> some View {
        NavigationLink {
            DiningCompanionDetailView(
                report: report,
                photosByID: photosByID,
                restaurantsByID: restaurantsByID
            )
        } label: {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("最常一起吃的人")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(TasteMapAnalysisTheme.brand)
                        Text(report.companionDisplayName)
                            .font(.title.weight(.heavy))
                            .foregroundStyle(TasteMapAnalysisTheme.ink)
                            .lineLimit(2)
                    }
                    Spacer()
                    DiningCompanionAvatarView(
                        presentation: report.avatar,
                        displayName: report.companionDisplayName,
                        size: 76
                    )
                }
                Text(report.summary)
                    .font(.headline)
                    .foregroundStyle(TasteMapAnalysisTheme.ink)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 10) {
                    overviewMetric("\(report.sharedVisitCount)", "共同到访", .brand)
                    overviewMetric("\(report.restaurantCount)", "共同餐厅", .ingredientRed)
                    overviewMetric(report.topFoods.first?.label ?? "形成中", "常一起吃", .leafGreen)
                }
            }
            .padding(20)
            .background(
                LinearGradient(
                    colors: [TasteMapAnalysisTheme.card, TasteMapAnalysisTheme.brandSoft.opacity(0.72)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 28, style: .continuous)
            )
            .overlay { RoundedRectangle(cornerRadius: 28).stroke(TasteMapAnalysisTheme.hairline, lineWidth: 1.5) }
            .shadow(color: TasteMapAnalysisTheme.brandDeep.opacity(0.08), radius: 16, y: 9)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("companion-analysis-lead")
    }

    private func overviewMetric(_ value: String, _ label: String, _ tone: AnalysisTone) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.headline.weight(.heavy))
                .foregroundStyle(TasteMapAnalysisTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TasteMapAnalysisTheme.softColor(for: tone), in: RoundedRectangle(cornerRadius: 14))
    }

    private var companionList: some View {
        VStack(alignment: .leading, spacing: 14) {
            AnalysisSectionHeader(
                "全部饭搭子",
                eyebrow: "SHARED TABLES",
                detail: "\(overview.companionsWithVisitsCount) 位已有共同记录；同名身份不会自动合并。"
            )
            if overview.summaries.isEmpty {
                Text("饭搭子目录还是空的。")
                    .font(.subheadline)
                    .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(TasteMapAnalysisTheme.card, in: RoundedRectangle(cornerRadius: 22))
            } else {
                ForEach(overview.summaries) { summary in
                    if let report = overview.analysis(for: summary.id) {
                        NavigationLink {
                            DiningCompanionDetailView(
                                report: report,
                                photosByID: photosByID,
                                restaurantsByID: restaurantsByID
                            )
                        } label: {
                            DiningCompanionSummaryCard(summary: summary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("companion-card-\(summary.id.uuidString.lowercased())")
                    }
                }
            }
        }
    }

    private var privacyNote: some View {
        Label(
            "饭搭子分析只存在于你的个人分析页；不会自动进入 Public Profile。",
            systemImage: "lock.shield"
        )
        .font(.caption)
        .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(TasteMapAnalysisTheme.leafGreenSoft.opacity(0.64), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct DiningCompanionSummaryCard: View {
    let summary: DiningCompanionSummary

    var body: some View {
        HStack(spacing: 14) {
            DiningCompanionAvatarView(
                presentation: summary.avatar,
                displayName: summary.displayName,
                size: 58
            )
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(summary.displayName)
                        .font(.headline)
                        .foregroundStyle(TasteMapAnalysisTheme.ink)
                        .lineLimit(1)
                    Text(summary.sufficiency.title)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(TasteMapAnalysisTheme.brandDeep)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(TasteMapAnalysisTheme.brandSoft, in: Capsule())
                }
                Text("\(summary.sharedVisitCount) 次共同到访 · \(summary.restaurantCount) 家餐厅")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
                Text(summary.latestVisit.map { "最近 \($0.formatted(date: .abbreviated, time: .omitted))" }
                     ?? "还没有共同到访")
                    .font(.caption)
                    .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 5) {
                Text(summary.topFood ?? "形成中")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(TasteMapAnalysisTheme.leafGreen)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .foregroundStyle(TasteMapAnalysisTheme.brand)
            }
        }
        .padding(16)
        .background(TasteMapAnalysisTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct DiningCompanionDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let report: DiningCompanionAnalysis
    let photosByID: [UUID: PhotoAsset]
    let restaurantsByID: [UUID: Restaurant]

    @State private var isShowingPoster = false
    @State private var selectedRestaurant: Restaurant?
    @State private var fixtureMutationMessage: String?
    private let metricColumns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 28) {
                titleBlock
                SharedDiningTableHero(
                    userDisplayName: report.userDisplayName,
                    companionDisplayName: report.companionDisplayName,
                    companionAvatar: report.avatar,
                    hero: report.hero,
                    photosByID: photosByID
                )
                coreMetrics
                topFoods
                topRestaurants
                contextAndNumbers
                keywords
                representativeRestaurants
                nextMeal
                privacyNote
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 48)
        }
        .background(TasteMapAnalysisTheme.canvas.ignoresSafeArea())
        .tasteMapBottomNavigationHidden()
        .navigationTitle("你和 \(report.companionDisplayName)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isShowingPoster = true } label: {
                    Label("分享", systemImage: "square.and.arrow.up")
                }
                .tint(TasteMapAnalysisTheme.brand)
                .accessibilityIdentifier("companion-analysis-share-toolbar")
            }
#if DEBUG
            if TasteMapUITestFixtures.usesCompanionAnalysisFixture {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { addFixtureVisit() } label: {
                        Label("新增共同到访测试样本", systemImage: "plus.circle")
                    }
                    .accessibilityIdentifier("companion-analysis-fixture-add-visit")
                }
            }
#endif
        }
        .sheet(isPresented: $isShowingPoster) {
            DiningCompanionPosterSheet(report: report, photosByID: photosByID)
        }
        .sheet(item: $selectedRestaurant) { restaurant in
            CompanionRestaurantDetailSheet(restaurant: restaurant)
        }
        .accessibilityIdentifier("companion-analysis-detail")
    }

#if DEBUG
    private func addFixtureVisit() {
        do {
            guard let restaurantID = report.topRestaurants.first?.id else {
                fixtureMutationMessage = "没有可用 Restaurant"
                return
            }
            let companions = try modelContext.fetch(FetchDescriptor<DiningCompanion>())
            guard let companion = companions.first(where: { $0.id == report.companionID }) else {
                fixtureMutationMessage = "没有可用 Companion"
                return
            }
            _ = try LocalTasteMapStore(context: modelContext).createVisit(
                restaurantId: restaurantID,
                draft: VisitDraft(
                    companionIDs: [companion.remoteID ?? companion.id.uuidString.lowercased()],
                    companionNames: [companion.displayName],
                    note: "P4-B Simulator refresh fixture"
                )
            )
            fixtureMutationMessage = "已新增共同到访测试样本"
        } catch {
            fixtureMutationMessage = "测试样本保存失败"
        }
    }
#endif

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("YOU & \(report.companionDisplayName.uppercased())")
                    .font(.caption2.weight(.bold))
                    .tracking(1.6)
                Spacer()
                Label(report.sufficiency.title, systemImage: "checkmark.seal.fill")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(TasteMapAnalysisTheme.brand)
            Text("你和 \(report.companionDisplayName)")
                .font(.largeTitle.weight(.heavy))
                .foregroundStyle(TasteMapAnalysisTheme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
            Text(report.summary)
                .font(.title3.weight(.semibold))
                .foregroundStyle(TasteMapAnalysisTheme.ink)
                .lineSpacing(4)
            Button { isShowingPoster = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("生成你和 TA 的分享海报").font(.subheadline.weight(.bold))
                        Text("聚合信息，不包含私人备注、内部 ID 或精确位置历史")
                            .font(.caption).opacity(0.84)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .foregroundStyle(.white)
                .background(TasteMapAnalysisTheme.brand, in: RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("companion-analysis-share-poster")
#if DEBUG
            if let fixtureMutationMessage {
                Text(fixtureMutationMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TasteMapAnalysisTheme.brandDeep)
                    .accessibilityIdentifier("companion-analysis-fixture-mutation-result")
            }
#endif
        }
    }

    private var coreMetrics: some View {
        LazyVGrid(columns: metricColumns, spacing: 12) {
            ForEach(report.callouts) { callout in
                AnalysisCalloutCard(callout: callout)
            }
        }
        .accessibilityIdentifier("companion-core-metrics")
    }

    private var topFoods: some View {
        VStack(alignment: .leading, spacing: 14) {
            AnalysisSectionHeader(
                "最常一起吃什么",
                eyebrow: "SHARED FLAVORS",
                detail: "优先使用共同 Visit 中的 Dish；证据不足时才退化到 Restaurant 菜系标签。"
            )
            if report.topFoods.isEmpty {
                AnalysisGrowthPrompt(
                    symbol: "🍲",
                    title: "共同口味正在形成",
                    detail: report.sharedVisitCount < 2
                        ? "至少两次共同到访后再判断“最常一起吃什么”。"
                        : "继续记录 Dish 或为 Restaurant 保留结构化菜系标签。"
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(report.topFoods.prefix(5).enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(index == 0 ? TasteMapAnalysisTheme.ingredientRed : TasteMapAnalysisTheme.brand, in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.label).font(.headline).foregroundStyle(TasteMapAnalysisTheme.ink)
                                Text("\(item.sharedVisitCount) 次共同到访 · \(item.source == .dish ? "Dish" : "Cuisine")")
                                    .font(.caption).foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
                            }
                            Spacer()
                            if let rating = item.averageRating {
                                Label(rating.formatted(.number.precision(.fractionLength(1))), systemImage: "star.fill")
                                    .font(.caption.weight(.bold)).foregroundStyle(TasteMapAnalysisTheme.caramel)
                            }
                        }
                    }
                }
                .padding(16)
                .background(TasteMapAnalysisTheme.card, in: RoundedRectangle(cornerRadius: 22))
            }
        }
        .accessibilityIdentifier("companion-top-foods")
    }

    private var topRestaurants: some View {
        VStack(alignment: .leading, spacing: 14) {
            AnalysisSectionHeader(
                "最常去的餐厅",
                eyebrow: "FREQUENT PLACES",
                detail: "按共同 Visit 次数排序，再比较你的平均评分和最近一次。"
            )
            if report.topRestaurants.isEmpty {
                AnalysisGrowthPrompt(symbol: "📍", title: "还没有共同餐厅", detail: "保存包含 TA 的 Visit 后开始统计。")
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 14) {
                        ForEach(report.topRestaurants.prefix(5)) { item in
                            topRestaurantLink(item)
                                .containerRelativeFrame(.horizontal, count: 10, span: 8, spacing: 14)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
            }
        }
        .accessibilityIdentifier("companion-top-restaurants")
    }

    @ViewBuilder
    private func topRestaurantLink(_ item: DiningCompanionRestaurantRank) -> some View {
        let card = DiningCompanionRestaurantCard(item: item, photosByID: photosByID)
        if let restaurant = restaurantsByID[item.id] {
            Button { selectedRestaurant = restaurant } label: { card }
                .buttonStyle(.plain)
        } else {
            card
        }
    }

    private var contextAndNumbers: some View {
        VStack(alignment: .leading, spacing: 15) {
            AnalysisSectionHeader(
                "共同用餐侧写",
                eyebrow: "SHARED DINING NOTES",
                detail: "描述共同吃饭行为，不推断现实关系质量。"
            )
            AnalysisInsightStoryCard(insight: AnalysisInsight(
                id: "portrait", icon: "🍽️", title: "共同吃饭模式",
                value: report.behavioralPortrait,
                detail: "由重复餐厅、探索比例、菜系集中和周末分布解释。",
                tone: .brand,
                sufficiency: report.sufficiency
            ))
            if report.diningContexts.isEmpty {
                AnalysisGrowthPrompt(symbol: "🕯️", title: "用餐场景正在形成", detail: "nil 场景不会参与统计。")
            } else {
                AnalysisInsightStoryCard(insight: AnalysisInsight(
                    id: "context", icon: "🕯️", title: "常见用餐场景",
                    value: report.diningContexts.prefix(3).map(\.label).joined(separator: " · "),
                    detail: report.diningContexts.first.map { "“\($0.label)”出现在 \($0.count) 次共同到访。" } ?? "",
                    tone: .leafGreen,
                    sufficiency: report.sufficiency
                ))
            }
            AnalysisInsightStoryCard(insight: AnalysisInsight(
                id: "rating", icon: "⭐️", title: "你的共同到访评分",
                value: report.rating.sharedAverage.map { "平均 \($0.formatted(.number.precision(.fractionLength(1))))" } ?? "未评分",
                detail: report.rating.summary + ratingDimensionDetail,
                tone: .caramel,
                sufficiency: report.rating.sufficiency
            ))
            AnalysisInsightStoryCard(insight: AnalysisInsight(
                id: "spend", icon: "🧾", title: "你记录的本人消费",
                value: report.spend.median.map { "中位数 ¥\(Int($0.rounded()))" } ?? "暂无样本",
                detail: report.spend.summary,
                tone: .ingredientRed,
                sufficiency: report.spend.sufficiency
            ))
        }
    }

    private var ratingDimensionDetail: String {
        let values: [String] = [
            report.rating.valueAverage.map { "性价比 \($0.formatted(.number.precision(.fractionLength(1))))" },
            report.rating.environmentAverage.map { "环境 \($0.formatted(.number.precision(.fractionLength(1))))" },
            report.rating.serviceAverage.map { "服务 \($0.formatted(.number.precision(.fractionLength(1))))" },
        ].compactMap { $0 }
        return values.isEmpty ? "" : " " + values.joined(separator: " · ")
    }

    private var keywords: some View {
        VStack(alignment: .leading, spacing: 14) {
            AnalysisSectionHeader(
                "关系关键词",
                eyebrow: "BEHAVIOR WORDS",
                detail: "只描述共同用餐行为，不计算亲密度、人格或情感分数。"
            )
            if report.keywords.isEmpty {
                AnalysisGrowthPrompt(
                    symbol: "🏷️",
                    title: "关键词正在形成",
                    detail: "数据不足时少显示，不会为了版式硬凑标签。"
                )
            } else {
                AnalysisTagFlow(tags: report.keywords)
            }
        }
        .accessibilityIdentifier("companion-keywords")
    }

    private var representativeRestaurants: some View {
        VStack(alignment: .leading, spacing: 14) {
            AnalysisSectionHeader(
                "共同回忆餐厅",
                eyebrow: "SHARED MEMORIES",
                detail: "综合到访次数、你的评分、照片、备注是否存在、场景和近期性；不会把私人备注导出到海报。"
            )
            if report.representativeRestaurants.isEmpty {
                AnalysisGrowthPrompt(symbol: "📸", title: "代表餐厅正在形成", detail: "不会复制同一家餐厅凑满卡片。")
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 14) {
                        ForEach(report.representativeRestaurants) { restaurant in
                            representativeLink(restaurant)
                                .containerRelativeFrame(.horizontal, count: 10, span: 8, spacing: 14)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
            }
        }
        .accessibilityIdentifier("companion-representative-restaurants")
    }

    @ViewBuilder
    private func representativeLink(_ item: RepresentativeRestaurant) -> some View {
        let card = RestaurantStoryCard(restaurant: item, photosByID: photosByID)
        if let restaurant = restaurantsByID[item.id] {
            Button { selectedRestaurant = restaurant } label: { card }
                .buttonStyle(.plain)
        } else {
            card
        }
    }

    private var nextMeal: some View {
        VStack(alignment: .leading, spacing: 14) {
            AnalysisSectionHeader(
                "下次和 TA 吃",
                eyebrow: "NEXT TABLE",
                detail: report.geographicScope.map { "当前地理范围：\($0)。优先想吃清单、未共同去过且符合共同口味的餐厅。" }
                    ?? "没有可靠城市范围时，不跨城市做强推荐。"
            )
            if report.recommendations.isEmpty {
                AnalysisGrowthPrompt(
                    symbol: "🗺️",
                    title: "暂时没有合适推荐",
                    detail: "离线也不会随机选店；可以先在同城想吃清单中保存候选餐厅。"
                )
            } else {
                ForEach(report.recommendations) { recommendation in
                    recommendationLink(recommendation)
                }
            }
        }
        .accessibilityIdentifier("companion-next-meal")
    }

    @ViewBuilder
    private func recommendationLink(_ recommendation: DiningCompanionRecommendation) -> some View {
        let card = HStack(alignment: .top, spacing: 14) {
            AnalysisFoodGlyph(symbol: "🗺️", tone: .brand, size: 50)
            VStack(alignment: .leading, spacing: 6) {
                Text(recommendation.name)
                    .font(.headline)
                    .foregroundStyle(TasteMapAnalysisTheme.ink)
                if !recommendation.city.isEmpty {
                    Text(recommendation.city)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TasteMapAnalysisTheme.brand)
                }
                Text(recommendation.reason)
                    .font(.subheadline)
                    .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(TasteMapAnalysisTheme.brand)
        }
        .padding(16)
        .background(TasteMapAnalysisTheme.card, in: RoundedRectangle(cornerRadius: 22))

        if let id = recommendation.localRestaurantID, let restaurant = restaurantsByID[id] {
            Button { selectedRestaurant = restaurant } label: { card }
                .buttonStyle(.plain)
        } else {
            card
        }
    }

    private var privacyNote: some View {
        VStack(spacing: 9) {
            Text("🔐").font(.title2)
            Text("这是你的共同用餐记录，不是 TA 的私人画像")
                .font(.headline).foregroundStyle(TasteMapAnalysisTheme.ink)
            Text(report.dataNote)
                .font(.caption).multilineTextAlignment(.center)
                .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(TasteMapAnalysisTheme.leafGreenSoft.opacity(0.64), in: RoundedRectangle(cornerRadius: 22))
    }
}

private struct CompanionRestaurantDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let restaurant: Restaurant

    var body: some View {
        ZStack(alignment: .topLeading) {
            RestaurantDetailView(restaurant: restaurant)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(TasteMapAnalysisTheme.ink)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(.leading, 12)
            .padding(.top, 6)
            .accessibilityLabel("关闭餐厅详情")
            .accessibilityIdentifier("companion-restaurant-detail-close")
        }
    }
}

private struct DiningCompanionRestaurantCard: View {
    let item: DiningCompanionRestaurantRank
    let photosByID: [UUID: PhotoAsset]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RestaurantEvidenceImage(reference: item.imageReference, photosByID: photosByID, height: 160)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.name)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(TasteMapAnalysisTheme.ink)
                    .lineLimit(2)
                Text("一起去过 \(item.sharedVisitCount) 次")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(TasteMapAnalysisTheme.brand)
                HStack {
                    Text(item.latestVisit.formatted(date: .abbreviated, time: .omitted))
                    if let rating = item.averageRating {
                        Spacer()
                        Label(rating.formatted(.number.precision(.fractionLength(1))), systemImage: "star.fill")
                    }
                }
                .font(.caption)
                .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
            }
            .padding(15)
        }
        .background(TasteMapAnalysisTheme.card, in: RoundedRectangle(cornerRadius: 24))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

#if DEBUG
#Preview("饭搭子总览 · 多人") {
    NavigationStack {
        DiningCompanionOverviewView(
            overview: DiningCompanionPreviewFixtures.rich,
            photosByID: [:],
            restaurantsByID: [:]
        )
    }
}

#Preview("饭搭子总览 · 无 Companion") {
    NavigationStack {
        DiningCompanionOverviewView(
            overview: DiningCompanionPreviewFixtures.empty,
            photosByID: [:],
            restaurantsByID: [:]
        )
    }
}

#Preview("你和 TA · 10 次") {
    NavigationStack {
        DiningCompanionDetailView(
            report: DiningCompanionPreviewFixtures.tenVisits.analyses[0],
            photosByID: [:],
            restaurantsByID: [:]
        )
    }
}

#Preview("你和 TA · 1 次") {
    NavigationStack {
        DiningCompanionDetailView(
            report: DiningCompanionPreviewFixtures.singleVisit.analyses[0],
            photosByID: [:],
            restaurantsByID: [:]
        )
    }
}

#Preview("长名字 · 大字体") {
    NavigationStack {
        DiningCompanionDetailView(
            report: DiningCompanionPreviewFixtures.longName.analyses[0],
            photosByID: [:],
            restaurantsByID: [:]
        )
    }
    .environment(\.dynamicTypeSize, .accessibility2)
}

#Preview("小屏 · 无图") {
    NavigationStack {
        DiningCompanionDetailView(
            report: DiningCompanionPreviewFixtures.noPhotos.analyses[0],
            photosByID: [:],
            restaurantsByID: [:]
        )
    }
    .frame(width: 320, height: 700)
}

#Preview("多 Restaurant") {
    NavigationStack {
        DiningCompanionDetailView(
            report: DiningCompanionPreviewFixtures.rich.analyses[0],
            photosByID: [:],
            restaurantsByID: [:]
        )
    }
}

#Preview("同一家反复去") {
    NavigationStack {
        DiningCompanionDetailView(
            report: DiningCompanionPreviewFixtures.repeatedRestaurant.analyses[0],
            photosByID: [:],
            restaurantsByID: [:]
        )
    }
}

#Preview("多 Cuisine") {
    NavigationStack {
        DiningCompanionDetailView(
            report: DiningCompanionPreviewFixtures.multiCuisine.analyses[0],
            photosByID: [:],
            restaurantsByID: [:]
        )
    }
}

#Preview("单一 Cuisine") {
    NavigationStack {
        DiningCompanionDetailView(
            report: DiningCompanionPreviewFixtures.singleCuisine.analyses[0],
            photosByID: [:],
            restaurantsByID: [:]
        )
    }
}

#Preview("无 Dish") {
    NavigationStack {
        DiningCompanionDetailView(
            report: DiningCompanionPreviewFixtures.noDishes.analyses[0],
            photosByID: [:],
            restaurantsByID: [:]
        )
    }
}

#Preview("有 Dish") {
    NavigationStack {
        DiningCompanionDetailView(
            report: DiningCompanionPreviewFixtures.withDishes.analyses[0],
            photosByID: [:],
            restaurantsByID: [:]
        )
    }
}

#Preview("有 Photo") {
    NavigationStack {
        DiningCompanionDetailView(
            report: DiningCompanionPreviewFixtures.withPhotos.analyses[0],
            photosByID: [:],
            restaurantsByID: [:]
        )
    }
}

#Preview("Linked User Avatar") {
    NavigationStack {
        DiningCompanionDetailView(
            report: DiningCompanionPreviewFixtures.linkedAvatar.analyses[0],
            photosByID: [:],
            restaurantsByID: [:]
        )
    }
}

#Preview("No Linked User") {
    NavigationStack {
        DiningCompanionDetailView(
            report: DiningCompanionPreviewFixtures.unlinkedAvatar.analyses[0],
            photosByID: [:],
            restaurantsByID: [:]
        )
    }
}

#Preview("数据完整 · 多 Companion") {
    NavigationStack {
        DiningCompanionOverviewView(
            overview: DiningCompanionPreviewFixtures.rich,
            photosByID: [:],
            restaurantsByID: [:]
        )
    }
}
#endif
