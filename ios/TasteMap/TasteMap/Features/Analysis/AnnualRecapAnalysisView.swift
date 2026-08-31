import SwiftData
import SwiftUI

struct AnnualRecapAnalysisScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.localAccountScope) private var accountScope
    @Query private var restaurants: [Restaurant]
    @Query private var visits: [Visit]
    @Query private var dishes: [Dish]
    @Query private var visitDishes: [VisitDish]
    @Query private var photos: [PhotoAsset]
    @Query private var companions: [DiningCompanion]
    @Query private var recommendationSources: [RecommendationSource]
    @Query private var profiles: [UserProfile]

    @State private var selectedPeriod = AnnualPeriod.current()
    @State private var report: AnnualRecapAnalysis?
    @State private var fixtureMessage: String?

    private var owned: ProfileOwnedContentScope.Snapshot {
        ProfileOwnedContentScope.capture(
            currentUserID: accountScope.ownerUserID,
            restaurants: restaurants, visits: visits, photos: photos,
            dishes: dishes, visitDishes: visitDishes,
            companions: companions, recommendationSources: recommendationSources
        )
    }

    private var photosByID: [UUID: PhotoAsset] {
        Dictionary(uniqueKeysWithValues: owned.photos.filter { $0.deletedAt == nil }.map { ($0.id, $0) })
    }
    private var restaurantsByID: [UUID: Restaurant] {
        Dictionary(uniqueKeysWithValues: owned.restaurants.filter { $0.deletedAt == nil }.map { ($0.id, $0) })
    }
    private var availablePeriods: [AnnualPeriod] {
        let calendar = selectedPeriod.calendar
        let periods = owned.visits.filter { $0.deletedAt == nil }.map {
            AnnualPeriod(date: $0.visitedAt, calendar: calendar)
        } + [AnnualPeriod.current(calendar: calendar)]
        return Dictionary(grouping: periods, by: \.id).compactMap { $0.value.first }
            .sorted { $0.year > $1.year }
    }
    private var dataRevision: String {
        let dates = restaurants.map { max($0.updatedAt, $0.deletedAt ?? .distantPast) }
            + visits.map { max($0.updatedAt, $0.deletedAt ?? .distantPast) }
            + dishes.map { max($0.updatedAt, $0.deletedAt ?? .distantPast) }
            + visitDishes.map { max($0.updatedAt, $0.deletedAt ?? .distantPast) }
            + photos.map { max($0.updatedAt, $0.deletedAt ?? .distantPast) }
            + companions.map { max($0.updatedAt, $0.deletedAt ?? .distantPast) }
            + recommendationSources.map { max($0.updatedAt, $0.deletedAt ?? .distantPast) }
            + profiles.map { max($0.updatedAt, $0.deletedAt ?? .distantPast) }
        return [restaurants.count, visits.count, dishes.count, visitDishes.count, photos.count,
                companions.count, recommendationSources.count, profiles.count]
            .map(String.init).joined(separator: ":")
            + ":\(dates.max()?.timeIntervalSince1970 ?? 0):\(selectedPeriod.id)"
    }

    var body: some View {
        PremiumFeatureGate(feature: .annualRecap) {
            unlockedContent
        }
    }

    private var unlockedContent: some View {
        Group {
            if let report, report.period.id == selectedPeriod.id {
                AnnualRecapAnalysisView(
                    report: report, availablePeriods: availablePeriods,
                    photosByID: photosByID, restaurantsByID: restaurantsByID,
                    onSelectPeriod: { selectedPeriod = $0 }, fixtureMessage: fixtureMessage,
                    onFixtureAddVisit: annualFixtureAction
                )
            } else {
                ProgressView("正在整理这一年的味觉旅程…")
                    .tint(TasteMapAnalysisTheme.brand)
            }
        }
        .task(id: dataRevision) {
            let period = selectedPeriod
            let input = MonthlyRecapInput.capture(
                restaurants: owned.restaurants, visits: owned.visits, dishes: owned.dishes,
                visitDishes: owned.visitDishes, photos: owned.photos, companions: owned.companions,
                recommendationSources: owned.recommendationSources,
                profile: profiles.first(where: {
                    $0.tasteMapUserID == accountScope.ownerUserID && $0.deletedAt == nil
                })
            )
            report = await Task.detached(priority: .userInitiated) {
                AnnualRecapAnalyzer.analyze(input, period: period)
            }.value
        }
    }

    private var annualFixtureAction: (() -> Void)? {
#if DEBUG
        guard TasteMapUITestFixtures.usesAnnualRecapFixture else { return nil }
        return {
            do {
                try TasteMapUITestFixtures.addAnnualRecapFixtureVisit(in: modelContext)
                let period = selectedPeriod
                let input = try AnalysisFixtureRefreshInput.capture(
                    in: modelContext,
                    currentUserID: accountScope.ownerUserID
                )
                fixtureMessage = nil
                Task {
                    let updated = await Task.detached(priority: .userInitiated) {
                        AnnualRecapAnalyzer.analyze(input, period: period)
                    }.value
                    guard selectedPeriod.id == period.id else { return }
                    report = updated
                    fixtureMessage = "已新增 1 次本年度到访，年度回顾已刷新。"
                }
            } catch { fixtureMessage = "测试到访新增失败。" }
        }
#else
        nil
#endif
    }
}

struct AnnualRecapAnalysisView: View {
    let report: AnnualRecapAnalysis
    let availablePeriods: [AnnualPeriod]
    let photosByID: [UUID: PhotoAsset]
    let restaurantsByID: [UUID: Restaurant]
    let onSelectPeriod: (AnnualPeriod) -> Void
    var fixtureMessage: String? = nil
    var onFixtureAddVisit: (() -> Void)? = nil

    @State private var isShowingPoster = false
    private let metricColumns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 30) {
                header
                yearSelector
#if DEBUG
                if let onFixtureAddVisit {
                    Button("新增一条本年度 Visit 验证刷新", action: onFixtureAddVisit)
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("annual-recap-fixture-add-visit")
                    if let fixtureMessage {
                        Text(fixtureMessage).font(.caption.weight(.semibold))
                            .foregroundStyle(TasteMapAnalysisTheme.brandDeep)
                            .accessibilityIdentifier("annual-recap-fixture-result")
                    }
                }
#endif
                if report.hasData {
                    hero
                    coreStatistics
                    restaurantHighlights
                    tasteJourney
                    monthlyHighlights
                    peopleAndSources
                    keywordSection
                    representativeRestaurants
                    shareCallToAction
                    privacyNote
                } else { emptyYear }
            }
            .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 48)
        }
        .background(TasteMapAnalysisTheme.canvas.ignoresSafeArea())
        .tasteMapBottomNavigationHidden()
        .navigationTitle("年度回顾")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if report.hasData {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isShowingPoster = true } label: {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                    .tint(TasteMapAnalysisTheme.brand)
                    .accessibilityIdentifier("annual-recap-share-toolbar")
                }
            }
        }
        .sheet(isPresented: $isShowingPoster) {
            AnnualRecapPosterSheet(report: report, photosByID: photosByID)
        }
        .accessibilityIdentifier("annual-recap-analysis-page")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ANNUAL TASTE JOURNEY").font(.caption2.weight(.bold)).tracking(1.8)
                Spacer()
                Label(report.isCurrentPeriod ? "持续更新" : "完整年度", systemImage: "sparkles")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(TasteMapAnalysisTheme.brand)
            Text(report.isCurrentPeriod ? "这一年，味道走到了哪里？" : "那一年，哪些味道留下来了？")
                .font(.largeTitle.weight(.heavy)).foregroundStyle(TasteMapAnalysisTheme.ink)
            Text(report.isCurrentPeriod
                 ? "当前自然年尚未结束；每一条真实记录都会继续补全这段旅程。"
                 : "按当时的有效到访，还原一个完整自然年的餐桌、人物与发现。")
                .font(.subheadline).foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
        }
    }

    private var yearSelector: some View {
        HStack(spacing: 12) {
            Button { onSelectPeriod(report.period.previous) } label: {
                Image(systemName: "chevron.left").frame(width: 38, height: 38).background(TasteMapAnalysisTheme.card, in: Circle())
            }
            .accessibilityLabel("上一年")
            .accessibilityIdentifier("annual-recap-previous-year")
            Menu {
                ForEach(availablePeriods) { period in
                    Button(period.title) { onSelectPeriod(period) }
                }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "calendar.badge.clock")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(report.period.title).font(.headline)
                        Text(report.isCurrentPeriod ? "截至今天" : "历史年度")
                            .font(.caption2).foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }
                .foregroundStyle(TasteMapAnalysisTheme.ink)
                .padding(.horizontal, 15).padding(.vertical, 10)
                .background(TasteMapAnalysisTheme.card, in: RoundedRectangle(cornerRadius: 18))
            }
            .accessibilityIdentifier("annual-recap-year-menu")
            Button { onSelectPeriod(report.period.next) } label: {
                Image(systemName: "chevron.right").frame(width: 38, height: 38).background(TasteMapAnalysisTheme.card, in: Circle())
            }
            .disabled(report.period.next.year > AnnualPeriod.current(calendar: report.period.calendar).year)
            .accessibilityLabel("下一年")
            .accessibilityIdentifier("annual-recap-next-year")
        }
        .foregroundStyle(TasteMapAnalysisTheme.brand)
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            AnnualPhotoCollage(stories: report.representativeRestaurants, photosByID: photosByID)
            LinearGradient(colors: [.clear, TasteMapAnalysisTheme.ink.opacity(0.82)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 7) {
                Text(report.periodLabel.uppercased()).font(.caption2.weight(.bold)).tracking(1.5)
                Text("\(report.visitCount) 次用餐，\(report.restaurantCount) 家餐厅")
                    .font(.title.weight(.heavy))
                Text(report.tasteJourney.changeSummaries.first
                     ?? report.favoriteRestaurant.map { "年度代表味道：\($0.name)" }
                     ?? "真实到访组成了这一年的味觉地图。")
                    .font(.subheadline.weight(.semibold)).opacity(0.92).lineLimit(2)
            }
            .foregroundStyle(.white).padding(20)
        }
        .frame(height: 390).clipShape(RoundedRectangle(cornerRadius: 32))
        .shadow(color: TasteMapAnalysisTheme.brandDeep.opacity(0.14), radius: 20, y: 10)
        .accessibilityIdentifier("annual-recap-hero")
    }

    private var coreStatistics: some View {
        VStack(alignment: .leading, spacing: 15) {
            AnalysisSectionHeader("这一年的餐桌", eyebrow: "YEAR AT A GLANCE", detail: "Visit 是用餐次数；Restaurant 按 Taste Map 全局 UUID 去重。")
            LazyVGrid(columns: metricColumns, spacing: 12) {
                AnnualMetricTile(
                    symbol: "🍽️",
                    title: "去过次数",
                    value: "\(report.visitCount) 次",
                    valueAccessibilityIdentifier: "annual-recap-visit-count",
                    tone: .brand
                )
                AnnualMetricTile(symbol: "📍", title: "餐厅", value: "\(report.restaurantCount) 家", tone: .ingredientRed)
                AnnualMetricTile(symbol: "✨", title: "人生新店", value: "\(report.newRestaurantCount) 家", note: explorationNote, tone: .leafGreen)
                AnnualMetricTile(symbol: "🧾", title: report.spend.displayState.label,
                                 value: report.spend.recordedTotal.map { "¥\(Int($0.rounded()))" } ?? "未记录",
                                 note: spendCoverageNote, tone: .caramel)
            }
        }
        .accessibilityIdentifier("annual-recap-core-statistics")
    }

    private var explorationNote: String {
        guard report.restaurantCount > 0 else { return "" }
        return "探索率 \(Int((report.explorationRate * 100).rounded()))% · 仅作辅助"
    }
    private var spendCoverageNote: String {
        guard report.visitCount > 0 else { return "" }
        if report.spend.displayState == .none { return "没有把空值当作 ¥0" }
        return "覆盖 \(report.spend.recordedVisitCount)/\(report.visitCount) 次到访"
    }

    private var restaurantHighlights: some View {
        VStack(alignment: .leading, spacing: 15) {
            AnalysisSectionHeader("年度餐桌主角", eyebrow: "ANNUAL FAVORITES", detail: "最喜欢综合评分、有效样本与重复到访；最常去按全年 Visit 数。")
            if report.favoriteRestaurant == nil && report.mostVisitedRestaurant == nil {
                AnalysisGrowthPrompt(symbol: "⭐️", title: "年度主角正在形成", detail: "评分或重复到访会让年度最喜欢更有依据。")
            } else {
                VStack(spacing: 12) {
                    if let favorite = report.favoriteRestaurant {
                        storyLink(favorite, identifier: "annual-recap-favorite")
                        if favorite.id == report.mostVisitedRestaurant?.id {
                            Label("同时也是年度最常去", systemImage: "repeat.circle.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(TasteMapAnalysisTheme.brandDeep)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                        }
                    }
                    if let most = report.mostVisitedRestaurant, most.id != report.favoriteRestaurant?.id {
                        storyLink(most, identifier: "annual-recap-most-visited")
                    }
                }
            }
        }
    }

    private var tasteJourney: some View {
        VStack(alignment: .leading, spacing: 16) {
            AnalysisSectionHeader("年度味觉轨迹", eyebrow: "TASTE JOURNEY", detail: journeyDetail)
            if report.tasteJourney.milestones.isEmpty {
                AnalysisGrowthPrompt(symbol: "🌱", title: "味觉轨迹正在形成", detail: "少数据年份仍保留真实统计和照片，不生成复杂变化结论。")
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(report.tasteJourney.milestones) { milestone in
                            AnnualMilestoneCard(milestone: milestone, photosByID: photosByID)
                                .containerRelativeFrame(.horizontal, count: 10, span: 8, spacing: 12)
                        }
                    }.scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned).scrollIndicators(.hidden)
                ForEach(report.tasteJourney.changeSummaries, id: \.self) { summary in
                    AnalysisInsightStoryCard(insight: AnalysisInsight(
                        id: summary, icon: "🧭", title: "年度变化", value: report.tasteJourney.granularity.title,
                        detail: summary, tone: .ingredientRed, sufficiency: report.tasteJourney.sufficiency
                    ))
                }
            }
        }
        .accessibilityIdentifier("annual-recap-taste-journey")
    }
    private var journeyDetail: String {
        switch report.tasteJourney.granularity {
        case .monthly: "样本覆盖足够月份，按月选择 3～5 个真实变化节点。"
        case .quarterly: "年度记录较少，统一按季度呈现，避免放大单月波动。"
        case .insufficient: "需要至少 6 次到访与 2 个活跃季度，才生成复杂轨迹。"
        }
    }

    private var monthlyHighlights: some View {
        VStack(alignment: .leading, spacing: 15) {
            AnalysisSectionHeader("年度月份高光", eyebrow: "MOMENTS IN TIME", detail: "只选少数有真实证据的月份，不堆叠 12 张月报。")
            if report.monthlyHighlights.isEmpty {
                AnalysisGrowthPrompt(symbol: "🗓️", title: "月份高光还在形成", detail: "有更多月份记录后，这里会出现最活跃、新店或评分高光。")
            } else {
                ForEach(report.monthlyHighlights) { item in
                    HStack(spacing: 14) {
                        AnalysisFoodGlyph(symbol: highlightSymbol(item.kind), tone: highlightTone(item.kind), size: 48)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).font(.caption.weight(.bold)).foregroundStyle(TasteMapAnalysisTheme.brand)
                            Text(item.value).font(.headline).foregroundStyle(TasteMapAnalysisTheme.ink)
                            Text(item.detail).font(.caption).foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
                        }
                        Spacer()
                    }
                    .padding(15).background(TasteMapAnalysisTheme.card, in: RoundedRectangle(cornerRadius: 20))
                }
            }
        }
        .accessibilityIdentifier("annual-recap-month-highlights")
    }

    private var peopleAndSources: some View {
        VStack(alignment: .leading, spacing: 15) {
            AnalysisSectionHeader("这一年，和谁吃、从哪里发现", eyebrow: "PEOPLE & TRAILS", detail: "只使用 Visit 中明确记录的饭搭子和稳定 RecommendationSource identity。")
            if let companion = report.topCompanion {
                AnalysisInsightStoryCard(insight: AnalysisInsight(
                    id: "annual-companion", icon: "🥢", title: "年度饭搭子", value: companion.displayName,
                    detail: "一起吃了 \(companion.sharedVisitCount) 次，去过 \(companion.restaurantCount) 家餐厅。",
                    tone: .leafGreen, sufficiency: companion.sufficiency
                )).accessibilityIdentifier("annual-recap-companion")
            }
            if let source = report.recommendationSummary.best ?? report.recommendationSummary.mostUsed {
                sourceCard(source, identifier: "annual-recap-source")
            }
            if let worst = report.recommendationSummary.worst {
                sourceCard(worst, identifier: "annual-recap-worst-source")
            }
            if report.topCompanion == nil && report.recommendationSummary.mostUsed == nil {
                AnalysisGrowthPrompt(symbol: "🍲", title: "人物与来源故事还没有被记录", detail: "不会从好友关系推断共同到访，也不会按相似文字猜来源。")
            }
        }
    }

    private func sourceCard(_ source: AnnualSourceConclusion, identifier: String) -> some View {
        AnalysisInsightStoryCard(insight: AnalysisInsight(
            id: source.id, icon: source.sourceType.analysisSymbol, title: source.title,
            value: source.displayName, detail: source.statement,
            tone: source.title.contains("最坑") ? .ingredientRed : source.sourceType.analysisTone,
            sufficiency: source.sufficiency
        )).accessibilityIdentifier(identifier)
    }

    private var keywordSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            AnalysisSectionHeader("年度关键词", eyebrow: "THE YEAR IN FLAVORS", detail: "按 cuisine、Dish、探新/熟店、场景和正式饭搭子证据去重生成。")
            if report.keywords.isEmpty {
                AnalysisGrowthPrompt(symbol: "🏷️", title: "关键词正在形成", detail: "不会为了填满页面硬编码年度标签。")
            } else { AnalysisTagFlow(tags: report.keywords) }
        }
        .accessibilityIdentifier("annual-recap-keywords")
    }

    private var representativeRestaurants: some View {
        VStack(alignment: .leading, spacing: 15) {
            AnalysisSectionHeader("这一年值得记住的店", eyebrow: "ANNUAL TABLE", detail: "最喜欢、最常去、新店、时间节点与高光去重后选 3～6 家。")
            ScrollView(.horizontal) {
                LazyHStack(spacing: 14) {
                    ForEach(report.representativeRestaurants) { story in
                        compactStoryLink(story, identifier: "annual-recap-representative-\(story.id.uuidString.lowercased())")
                            .containerRelativeFrame(.horizontal, count: 10, span: 8, spacing: 14)
                    }
                }.scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned).scrollIndicators(.hidden)
        }
        .accessibilityIdentifier("annual-recap-representatives")
    }

    private var shareCallToAction: some View {
        Button { isShowingPoster = true } label: {
            HStack(spacing: 13) {
                AnalysisFoodGlyph(symbol: "🧭", tone: .cream, size: 54)
                VStack(alignment: .leading, spacing: 3) {
                    Text("生成年度味觉旅程海报").font(.headline)
                    Text("独立年度总结名片，不是页面截图").font(.caption).opacity(0.86)
                }
                Spacer(); Image(systemName: "arrow.up.right")
            }
            .padding(17).foregroundStyle(.white)
            .background(TasteMapAnalysisTheme.brand, in: RoundedRectangle(cornerRadius: 22))
            .shadow(color: TasteMapAnalysisTheme.brand.opacity(0.2), radius: 14, y: 7)
        }
        .buttonStyle(.plain).accessibilityIdentifier("annual-recap-share-poster")
    }

    private var privacyNote: some View {
        Label(report.dataNote, systemImage: "lock.shield")
            .font(.caption).foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(TasteMapAnalysisTheme.leafGreenSoft.opacity(0.66), in: RoundedRectangle(cornerRadius: 20))
    }

    private var emptyYear: some View {
        VStack(spacing: 15) {
            AnalysisFoodGlyph(symbol: "🗺️", tone: .brand, size: 76)
            Text("这一年还没有记录").font(.title2.weight(.heavy)).foregroundStyle(TasteMapAnalysisTheme.ink)
            Text("这里不会生成全是 0 的年度海报。你可以切换到有数据的年份，或保存一次真实到访。")
                .font(.subheadline).multilineTextAlignment(.center).foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
            if !report.isCurrentPeriod {
                Button("返回今年") { onSelectPeriod(.current(calendar: report.period.calendar)) }
                    .buttonStyle(.borderedProminent).tint(TasteMapAnalysisTheme.brand)
                    .accessibilityIdentifier("annual-recap-return-current")
            }
        }
        .frame(maxWidth: .infinity).padding(.horizontal, 24).padding(.vertical, 56)
        .background(TasteMapAnalysisTheme.card, in: RoundedRectangle(cornerRadius: 28))
        .accessibilityIdentifier("annual-recap-empty")
    }

    @ViewBuilder
    private func storyLink(_ item: AnnualRestaurantStory, identifier: String) -> some View {
        let content = AnnualRestaurantRow(story: item, photosByID: photosByID)
        if let restaurant = restaurantsByID[item.id] {
            NavigationLink { RestaurantDetailView(restaurant: restaurant, entrySource: .analysis) } label: { content }
                .buttonStyle(.plain).accessibilityIdentifier(identifier)
        } else { content.accessibilityIdentifier(identifier) }
    }
    @ViewBuilder
    private func compactStoryLink(_ item: AnnualRestaurantStory, identifier: String) -> some View {
        let content = RestaurantStoryCard(
            restaurant: RepresentativeRestaurant(
                id: item.id, name: item.name, role: item.role, detail: item.detail,
                averageRating: item.averageRating, visitCount: item.visitCount,
                imageReference: item.imageReference
            ), photosByID: photosByID
        )
        if let restaurant = restaurantsByID[item.id] {
            NavigationLink { RestaurantDetailView(restaurant: restaurant, entrySource: .analysis) } label: { content }
                .buttonStyle(.plain).accessibilityIdentifier(identifier)
        } else { content.accessibilityIdentifier(identifier) }
    }
    private func highlightSymbol(_ kind: AnnualHighlightKind) -> String {
        switch kind { case .busiest: "🍽️"; case .exploration: "🧭"; case .rating: "⭐️"; case .spend: "🧾" }
    }
    private func highlightTone(_ kind: AnnualHighlightKind) -> AnalysisTone {
        switch kind { case .busiest: .brand; case .exploration: .leafGreen; case .rating: .ingredientRed; case .spend: .caramel }
    }
}

private struct AnnualMetricTile: View {
    let symbol: String; let title: String; let value: String
    var note: String = ""
    var valueAccessibilityIdentifier: String? = nil
    let tone: AnalysisTone
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            AnalysisFoodGlyph(symbol: symbol, tone: tone, size: 40, semanticID: title)
            Text(title).font(.caption.weight(.bold)).foregroundStyle(TasteMapAnalysisTheme.color(for: tone))
            Text(value).font(.title2.weight(.heavy)).foregroundStyle(TasteMapAnalysisTheme.ink)
                .lineLimit(1).minimumScaleFactor(0.62)
                .accessibilityIdentifier(valueAccessibilityIdentifier ?? "")
            if !note.isEmpty { Text(note).font(.caption2).foregroundStyle(TasteMapAnalysisTheme.secondaryInk).lineLimit(2) }
        }
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading).padding(16)
        .background(TasteMapAnalysisTheme.softColor(for: tone).opacity(0.62), in: RoundedRectangle(cornerRadius: 22))
        .overlay { RoundedRectangle(cornerRadius: 22).stroke(TasteMapAnalysisTheme.hairline, lineWidth: 1) }
    }
}

private struct AnnualRestaurantRow: View {
    let story: AnnualRestaurantStory; let photosByID: [UUID: PhotoAsset]
    var body: some View {
        HStack(spacing: 14) {
            RestaurantEvidenceImage(reference: story.imageReference, photosByID: photosByID, height: 108)
                .frame(width: 118).clipShape(RoundedRectangle(cornerRadius: 18))
            VStack(alignment: .leading, spacing: 6) {
                Text(story.role).font(.caption.weight(.bold)).foregroundStyle(TasteMapAnalysisTheme.brand)
                Text(story.name).font(.headline).foregroundStyle(TasteMapAnalysisTheme.ink).lineLimit(2)
                Text(story.detail).font(.caption).foregroundStyle(TasteMapAnalysisTheme.secondaryInk).lineLimit(2)
            }
            Spacer(minLength: 4); Image(systemName: "chevron.right").foregroundStyle(TasteMapAnalysisTheme.brand)
        }
        .padding(12).background(TasteMapAnalysisTheme.card, in: RoundedRectangle(cornerRadius: 22))
    }
}

private struct AnnualMilestoneCard: View {
    let milestone: AnnualTasteMilestone; let photosByID: [UUID: PhotoAsset]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RestaurantEvidenceImage(reference: milestone.imageReference, photosByID: photosByID, height: 150)
                .frame(maxWidth: .infinity).clipped()
            VStack(alignment: .leading, spacing: 7) {
                Text(milestone.periodLabel).font(.caption.weight(.bold)).foregroundStyle(TasteMapAnalysisTheme.brand)
                Text(milestone.title).font(.headline).foregroundStyle(TasteMapAnalysisTheme.ink).lineLimit(2)
                Text(milestone.detail).font(.caption).foregroundStyle(TasteMapAnalysisTheme.secondaryInk).lineLimit(3)
            }.padding(15)
        }
        .background(TasteMapAnalysisTheme.card, in: RoundedRectangle(cornerRadius: 24)).clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

private struct AnnualPhotoCollage: View {
    let stories: [AnnualRestaurantStory]; let photosByID: [UUID: PhotoAsset]
    var body: some View {
        GeometryReader { proxy in
            if stories.count >= 3 {
                HStack(spacing: 6) {
                    RestaurantEvidenceImage(reference: stories[0].imageReference, photosByID: photosByID, height: proxy.size.height)
                        .frame(width: proxy.size.width * 0.58).clipped()
                    VStack(spacing: 6) {
                        RestaurantEvidenceImage(reference: stories[1].imageReference, photosByID: photosByID, height: proxy.size.height / 2)
                        RestaurantEvidenceImage(reference: stories[2].imageReference, photosByID: photosByID, height: proxy.size.height / 2)
                    }.clipped()
                }
            } else if let first = stories.first {
                RestaurantEvidenceImage(reference: first.imageReference, photosByID: photosByID, height: proxy.size.height)
            } else {
                ZStack {
                    LinearGradient(colors: [TasteMapAnalysisTheme.creamSoft, TasteMapAnalysisTheme.brandSoft], startPoint: .topLeading, endPoint: .bottomTrailing)
                    FoodDiningVisualIcon(
                        kind: .genericDining,
                        usage: .decorative,
                        size: 88,
                        foregroundColor: TasteMapAnalysisTheme.brandDeep,
                        backgroundColor: .white.opacity(0.72)
                    )
                }
            }
        }
    }
}
