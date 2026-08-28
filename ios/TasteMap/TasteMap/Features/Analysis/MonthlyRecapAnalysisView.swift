import SwiftData
import SwiftUI

struct MonthlyRecapAnalysisScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var restaurants: [Restaurant]
    @Query private var visits: [Visit]
    @Query private var dishes: [Dish]
    @Query private var visitDishes: [VisitDish]
    @Query private var photos: [PhotoAsset]
    @Query private var companions: [DiningCompanion]
    @Query private var recommendationSources: [RecommendationSource]
    @Query private var profiles: [UserProfile]

    @State private var selectedPeriod = MonthlyPeriod.current()
    @State private var report: MonthlyRecapAnalysis?
    @State private var fixtureMessage: String?

    private var photosByID: [UUID: PhotoAsset] {
        Dictionary(uniqueKeysWithValues: photos.filter { $0.deletedAt == nil }.map { ($0.id, $0) })
    }

    private var restaurantsByID: [UUID: Restaurant] {
        Dictionary(uniqueKeysWithValues: restaurants.filter { $0.deletedAt == nil }.map { ($0.id, $0) })
    }

    private var availablePeriods: [MonthlyPeriod] {
        let calendar = selectedPeriod.calendar
        let periods = visits.filter { $0.deletedAt == nil }.map {
            MonthlyPeriod(date: $0.visitedAt, calendar: calendar)
        } + [MonthlyPeriod.current(calendar: calendar)]
        return Dictionary(grouping: periods, by: \.id).compactMap { $0.value.first }.sorted {
            $0.start > $1.start
        }
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
        return [
            restaurants.count, visits.count, dishes.count, visitDishes.count, photos.count,
            companions.count, recommendationSources.count, profiles.count,
        ].map(String.init).joined(separator: ":")
            + ":\(dates.max()?.timeIntervalSince1970 ?? 0):\(selectedPeriod.id)"
    }

    var body: some View {
        Group {
            if let report, report.period.id == selectedPeriod.id {
                MonthlyRecapAnalysisView(
                    report: report,
                    availablePeriods: availablePeriods,
                    photosByID: photosByID,
                    restaurantsByID: restaurantsByID,
                    onSelectPeriod: { selectedPeriod = $0 },
                    fixtureMessage: fixtureMessage,
                    onFixtureAddVisit: monthlyFixtureAction
                )
            } else {
                ProgressView("正在翻开这个月的餐桌…")
                    .tint(TasteMapAnalysisTheme.brand)
            }
        }
        .task(id: dataRevision) {
            let period = selectedPeriod
            let input = MonthlyRecapInput.capture(
                restaurants: restaurants, visits: visits, dishes: dishes,
                visitDishes: visitDishes, photos: photos, companions: companions,
                recommendationSources: recommendationSources,
                profile: profiles.first(where: { $0.deletedAt == nil })
            )
            report = await Task.detached(priority: .userInitiated) {
                MonthlyRecapAnalyzer.analyze(input, period: period)
            }.value
        }
    }

    private var monthlyFixtureAction: (() -> Void)? {
#if DEBUG
        guard TasteMapUITestFixtures.usesMonthlyRecapFixture else { return nil }
        return {
            do {
                try TasteMapUITestFixtures.addMonthlyRecapFixtureVisit(in: modelContext)
                fixtureMessage = "已新增 1 次本月到访，回顾已刷新。"
            } catch {
                fixtureMessage = "测试到访新增失败。"
            }
        }
#else
        nil
#endif
    }
}

struct MonthlyRecapAnalysisView: View {
    let report: MonthlyRecapAnalysis
    let availablePeriods: [MonthlyPeriod]
    let photosByID: [UUID: PhotoAsset]
    let restaurantsByID: [UUID: Restaurant]
    let onSelectPeriod: (MonthlyPeriod) -> Void
    var fixtureMessage: String? = nil
    var onFixtureAddVisit: (() -> Void)? = nil

    @State private var isShowingPoster = false
    private let metricColumns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 28) {
                header
                monthSelector
#if DEBUG
                if let onFixtureAddVisit {
                    Button("新增一条本月 Visit 验证刷新", action: onFixtureAddVisit)
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("monthly-recap-fixture-add-visit")
                    if let fixtureMessage {
                        Text(fixtureMessage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(TasteMapAnalysisTheme.brandDeep)
                            .accessibilityIdentifier("monthly-recap-fixture-result")
                    }
                }
#endif
                if report.hasData {
                    hero
                    coreStatistics
                    restaurantHighlights
                    newRestaurantSection
                    peopleAndSources
                    tasteChangeSection
                    representativeRestaurants
                    shareCallToAction
                    privacyNote
                } else {
                    emptyMonth
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 48)
        }
        .background(TasteMapAnalysisTheme.canvas.ignoresSafeArea())
        .tasteMapBottomNavigationHidden()
        .navigationTitle("本月回顾")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if report.hasData {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isShowingPoster = true } label: {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                    .tint(TasteMapAnalysisTheme.brand)
                    .accessibilityIdentifier("monthly-recap-share-toolbar")
                }
            }
        }
        .sheet(isPresented: $isShowingPoster) {
            MonthlyRecapPosterSheet(report: report, photosByID: photosByID)
        }
        .accessibilityIdentifier("monthly-recap-analysis-page")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("MONTHLY FOOD DIARY")
                    .font(.caption2.weight(.bold)).tracking(1.8)
                Spacer()
                Label(report.isCurrentPeriod ? "持续更新" : "完整月份", systemImage: "calendar.badge.checkmark")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(TasteMapAnalysisTheme.brand)
            Text(report.isCurrentPeriod ? "这个月，你吃了什么？" : "那个月，你留下了什么味道？")
                .font(.largeTitle.weight(.heavy))
                .foregroundStyle(TasteMapAnalysisTheme.ink)
            Text(report.isCurrentPeriod
                 ? "当前自然月尚未结束，统计会随你的真实记录继续更新。"
                 : "按当时的有效到访，还原一个完整自然月的餐桌故事。")
                .font(.subheadline)
                .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
        }
    }

    private var monthSelector: some View {
        HStack(spacing: 12) {
            Button { onSelectPeriod(report.period.previous) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 38, height: 38)
                    .background(.white, in: Circle())
            }
            .accessibilityLabel("上个月")
            .accessibilityIdentifier("monthly-recap-previous-month")

            Menu {
                ForEach(availablePeriods) { period in
                    Button(period.title) { onSelectPeriod(period) }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(report.period.title).font(.headline)
                        Text(report.isCurrentPeriod ? "截至今天" : "历史月份")
                            .font(.caption2).foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }
                .foregroundStyle(TasteMapAnalysisTheme.ink)
                .padding(.horizontal, 15).padding(.vertical, 10)
                .background(.white, in: RoundedRectangle(cornerRadius: 18))
            }
            .accessibilityIdentifier("monthly-recap-month-menu")

            Button { onSelectPeriod(report.period.next) } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 38, height: 38)
                    .background(.white, in: Circle())
            }
            .disabled(report.period.next.start > MonthlyPeriod.current(calendar: report.period.calendar).start)
            .accessibilityLabel("下个月")
            .accessibilityIdentifier("monthly-recap-next-month")
        }
        .foregroundStyle(TasteMapAnalysisTheme.brand)
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            MonthlyPhotoCollage(
                stories: report.representativeRestaurants,
                photosByID: photosByID
            )
            LinearGradient(
                colors: [.clear, TasteMapAnalysisTheme.ink.opacity(0.78)],
                startPoint: .center, endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 7) {
                Text(report.periodLabel.uppercased())
                    .font(.caption2.weight(.bold)).tracking(1.5)
                Text("\(report.visitCount) 次用餐，\(report.restaurantCount) 家餐厅")
                    .font(.title.weight(.heavy))
                Text(heroCaption)
                    .font(.subheadline.weight(.semibold)).opacity(0.9)
            }
            .foregroundStyle(.white)
            .padding(20)
        }
        .frame(height: 360)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: TasteMapAnalysisTheme.brandDeep.opacity(0.13), radius: 18, y: 10)
        .accessibilityIdentifier("monthly-recap-hero")
    }

    private var heroCaption: String {
        if let highlight = report.highlight { return "本月高光：\(highlight.name)" }
        return "每一次真实到访，都留在这张月度餐桌上。"
    }

    private var coreStatistics: some View {
        VStack(alignment: .leading, spacing: 15) {
            AnalysisSectionHeader(
                "这个月的餐桌",
                eyebrow: "AT A GLANCE",
                detail: "Visit 是用餐次数；Restaurant 按 Taste Map 全局 UUID 去重。"
            )
            LazyVGrid(columns: metricColumns, spacing: 12) {
                MonthlyMetricTile(symbol: "🍽️", title: "去过次数", value: "\(report.visitCount) 次", tone: .brand)
                MonthlyMetricTile(symbol: "📍", title: "餐厅", value: "\(report.restaurantCount) 家", tone: .ingredientRed)
                MonthlyMetricTile(symbol: "✨", title: "人生新店", value: "\(report.newRestaurantCount) 家", tone: .leafGreen)
                MonthlyMetricTile(
                    symbol: "🧾", title: report.spend.displayState.label,
                    value: report.spend.recordedTotal.map { "¥\(Int($0.rounded()))" } ?? "未记录",
                    note: spendCoverageNote, tone: .caramel
                )
            }
        }
        .accessibilityIdentifier("monthly-recap-core-statistics")
    }

    private var spendCoverageNote: String {
        guard report.visitCount > 0 else { return "" }
        if report.spend.displayState == .none { return "没有把空值当作 ¥0" }
        return "覆盖 \(report.spend.recordedVisitCount)/\(report.visitCount) 次到访"
    }

    private var restaurantHighlights: some View {
        VStack(alignment: .leading, spacing: 15) {
            AnalysisSectionHeader(
                "本月餐桌主角",
                eyebrow: "MONTHLY FAVORITES",
                detail: "“最喜欢”综合评分与重复到访；“最常去”按 Visit 次数排序。"
            )
            if report.favoriteRestaurant == nil && report.mostVisitedRestaurant == nil {
                AnalysisGrowthPrompt(symbol: "⭐️", title: "这个月的主角正在形成", detail: "评分或重复到访会让最喜欢的餐厅更有依据。")
            } else {
                VStack(spacing: 12) {
                    if let favorite = report.favoriteRestaurant { storyLink(favorite, identifier: "monthly-recap-favorite") }
                    if let mostVisited = report.mostVisitedRestaurant, mostVisited.id != report.favoriteRestaurant?.id {
                        storyLink(mostVisited, identifier: "monthly-recap-most-visited")
                    }
                }
            }
        }
    }

    private var newRestaurantSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            AnalysisSectionHeader(
                "本月新店",
                eyebrow: "FIRST-EVER VISITS",
                detail: "只有人生第一次有效 Visit 落在这个月，才算新店。"
            )
            if report.newRestaurants.isEmpty {
                AnalysisGrowthPrompt(
                    symbol: "🏠", title: "这个月没有新店",
                    detail: report.repeatRestaurantCount > 0 ? "你把更多餐桌留给了熟悉的店。" : "这是自然结果，不会为了月报硬凑新发现。"
                )
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 13) {
                        ForEach(report.newRestaurants) { item in
                            compactStoryLink(item, identifier: "monthly-recap-new-\(item.id.uuidString.lowercased())")
                                .containerRelativeFrame(.horizontal, count: 10, span: 8, spacing: 13)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
            }
        }
        .accessibilityIdentifier("monthly-recap-new-restaurants")
    }

    private var peopleAndSources: some View {
        VStack(alignment: .leading, spacing: 15) {
            AnalysisSectionHeader(
                "和谁吃，从哪里发现",
                eyebrow: "PEOPLE & TRAILS",
                detail: "只使用 Visit 中明确记录的饭搭子与推荐来源。"
            )
            if let companion = report.topCompanion {
                AnalysisInsightStoryCard(insight: AnalysisInsight(
                    id: "monthly-companion", icon: "🥢", title: "本月常见饭搭子",
                    value: companion.displayName,
                    detail: "一起吃了 \(companion.sharedVisitCount) 次，去过 \(companion.restaurantCount) 家不同餐厅。",
                    tone: .leafGreen, sufficiency: companion.sufficiency
                ))
                .accessibilityIdentifier("monthly-recap-companion")
            }
            if let source = report.recommendationStory {
                AnalysisInsightStoryCard(insight: AnalysisInsight(
                    id: "monthly-source", icon: source.sourceType.analysisSymbol,
                    title: "本月推荐来源故事", value: source.displayName,
                    detail: source.statement, tone: source.sourceType.analysisTone,
                    sufficiency: source.sufficiency
                ))
                .accessibilityIdentifier("monthly-recap-source-story")
            }
            if report.topCompanion == nil && report.recommendationStory == nil {
                AnalysisGrowthPrompt(
                    symbol: "🍲", title: "这部分故事还没有被记录",
                    detail: "不会从好友关系推断一起吃过，也不会从餐厅名称猜推荐来源。"
                )
            }
        }
    }

    private var tasteChangeSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            AnalysisSectionHeader(
                "本月口味变化",
                eyebrow: "MONTH OVER MONTH",
                detail: "只和紧邻的上个月比较；两个月都至少 3 次到访、2 家餐厅才下趋势结论。"
            )
            if let change = report.tasteChange {
                AnalysisInsightStoryCard(insight: AnalysisInsight(
                    id: "monthly-taste-change", icon: tasteChangeIcon(change.kind),
                    title: change.title, value: "对比 \(report.comparisonPeriod.title)",
                    detail: change.statement, tone: .ingredientRed, sufficiency: change.sufficiency
                ))
                .accessibilityIdentifier("monthly-recap-taste-change")
            } else {
                AnalysisGrowthPrompt(
                    symbol: "🌱", title: report.tasteChangeSufficiency == .insufficient ? "记录更多后，可以看到月度口味变化" : "和上个月相比，没有足够明显的变化",
                    detail: report.tasteChangeSufficiency == .insufficient
                        ? "需要当前月与上个月都有足够样本；不会跨半年冒充“比上个月”。"
                        : "只有差异达到集中门槛才展示，不夸大轻微波动。"
                )
            }
            if !report.keywords.isEmpty {
                AnalysisTagFlow(tags: report.keywords)
                    .accessibilityIdentifier("monthly-recap-keywords")
            }
        }
    }

    private var representativeRestaurants: some View {
        VStack(alignment: .leading, spacing: 15) {
            AnalysisSectionHeader(
                "这个月值得记住的店",
                eyebrow: "MONTHLY TABLE",
                detail: "最喜欢、最常去、新店与高光去重后选出；图片优先你本月自己的 Dish / Visit Photo。"
            )
            ScrollView(.horizontal) {
                LazyHStack(spacing: 14) {
                    ForEach(report.representativeRestaurants) { item in
                        compactStoryLink(item, identifier: "monthly-recap-representative-\(item.id.uuidString.lowercased())")
                            .containerRelativeFrame(.horizontal, count: 10, span: 8, spacing: 14)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
        }
        .accessibilityIdentifier("monthly-recap-representatives")
    }

    private var shareCallToAction: some View {
        Button { isShowingPoster = true } label: {
            HStack(spacing: 13) {
                AnalysisFoodGlyph(symbol: "🗓️", tone: .cream, size: 54)
                VStack(alignment: .leading, spacing: 3) {
                    Text("生成本月分享海报").font(.headline)
                    Text("独立 9:16 月度餐桌设计，不是页面截图").font(.caption).opacity(0.86)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
            }
            .padding(17)
            .foregroundStyle(.white)
            .background(TasteMapAnalysisTheme.brand, in: RoundedRectangle(cornerRadius: 22))
            .shadow(color: TasteMapAnalysisTheme.brand.opacity(0.2), radius: 14, y: 7)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("monthly-recap-share-poster")
    }

    private var privacyNote: some View {
        Label(report.dataNote, systemImage: "lock.shield")
            .font(.caption)
            .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(TasteMapAnalysisTheme.leafGreenSoft.opacity(0.66), in: RoundedRectangle(cornerRadius: 20))
    }

    private var emptyMonth: some View {
        VStack(spacing: 15) {
            AnalysisFoodGlyph(symbol: "🍽️", tone: .brand, size: 76)
            Text("这个月还没有记录")
                .font(.title2.weight(.heavy)).foregroundStyle(TasteMapAnalysisTheme.ink)
            Text("这里不会用全是 0 的月报填满页面。你可以切换到有数据的月份，或保存一次真实到访。")
                .font(.subheadline).multilineTextAlignment(.center)
                .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
            if !report.isCurrentPeriod {
                Button("返回本月") { onSelectPeriod(.current(calendar: report.period.calendar)) }
                    .buttonStyle(.borderedProminent).tint(TasteMapAnalysisTheme.brand)
                    .accessibilityIdentifier("monthly-recap-return-current")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24).padding(.vertical, 56)
        .background(.white, in: RoundedRectangle(cornerRadius: 28))
        .accessibilityIdentifier("monthly-recap-empty")
    }

    @ViewBuilder
    private func storyLink(_ item: MonthlyRestaurantStory, identifier: String) -> some View {
        let content = MonthlyRestaurantRow(story: item, photosByID: photosByID)
        if let restaurant = restaurantsByID[item.id] {
            NavigationLink { RestaurantDetailView(restaurant: restaurant) } label: { content }
                .buttonStyle(.plain).accessibilityIdentifier(identifier)
        } else { content.accessibilityIdentifier(identifier) }
    }

    @ViewBuilder
    private func compactStoryLink(_ item: MonthlyRestaurantStory, identifier: String) -> some View {
        let content = RestaurantStoryCard(
            restaurant: RepresentativeRestaurant(
                id: item.id, name: item.name, role: item.role, detail: item.detail,
                averageRating: item.averageRating, visitCount: item.visitCount,
                imageReference: item.imageReference
            ),
            photosByID: photosByID
        )
        if let restaurant = restaurantsByID[item.id] {
            NavigationLink { RestaurantDetailView(restaurant: restaurant) } label: { content }
                .buttonStyle(.plain).accessibilityIdentifier(identifier)
        } else { content.accessibilityIdentifier(identifier) }
    }

    private func tasteChangeIcon(_ kind: MonthlyTasteChangeKind) -> String {
        switch kind {
        case .cuisineIncrease: "🍜"
        case .cuisineDecrease: "🥗"
        case .explorationIncrease: "🧭"
        case .repeatIncrease: "🔁"
        }
    }
}

private struct MonthlyMetricTile: View {
    let symbol: String
    let title: String
    let value: String
    var note: String = ""
    let tone: AnalysisTone

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(symbol).font(.title2)
            Text(title).font(.caption.weight(.bold)).foregroundStyle(TasteMapAnalysisTheme.color(for: tone))
            Text(value).font(.title2.weight(.heavy)).foregroundStyle(TasteMapAnalysisTheme.ink)
                .lineLimit(1).minimumScaleFactor(0.68)
            if !note.isEmpty {
                Text(note).font(.caption2).foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .padding(16)
        .background(TasteMapAnalysisTheme.softColor(for: tone).opacity(0.62), in: RoundedRectangle(cornerRadius: 22))
        .overlay { RoundedRectangle(cornerRadius: 22).stroke(.white, lineWidth: 1) }
    }
}

private struct MonthlyRestaurantRow: View {
    let story: MonthlyRestaurantStory
    let photosByID: [UUID: PhotoAsset]

    var body: some View {
        HStack(spacing: 14) {
            RestaurantEvidenceImage(reference: story.imageReference, photosByID: photosByID, height: 108)
                .frame(width: 118)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            VStack(alignment: .leading, spacing: 6) {
                Text(story.role).font(.caption.weight(.bold)).foregroundStyle(TasteMapAnalysisTheme.brand)
                Text(story.name).font(.headline).foregroundStyle(TasteMapAnalysisTheme.ink).lineLimit(2)
                Text(story.detail).font(.caption).foregroundStyle(TasteMapAnalysisTheme.secondaryInk).lineLimit(2)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").foregroundStyle(TasteMapAnalysisTheme.brand)
        }
        .padding(12)
        .background(.white, in: RoundedRectangle(cornerRadius: 22))
    }
}

private struct MonthlyPhotoCollage: View {
    let stories: [MonthlyRestaurantStory]
    let photosByID: [UUID: PhotoAsset]

    var body: some View {
        GeometryReader { proxy in
            let items = Array(stories.prefix(3))
            if items.count <= 1 {
                RestaurantEvidenceImage(
                    reference: items.first?.imageReference ?? .asset(FoodHeroTheme.mixed.assetName),
                    photosByID: photosByID, height: proxy.size.height
                )
            } else {
                HStack(spacing: 3) {
                    RestaurantEvidenceImage(reference: items[0].imageReference, photosByID: photosByID, height: proxy.size.height)
                        .frame(width: proxy.size.width * 0.62)
                    VStack(spacing: 3) {
                        ForEach(Array(items.dropFirst().prefix(2))) { item in
                            RestaurantEvidenceImage(
                                reference: item.imageReference,
                                photosByID: photosByID,
                                height: (proxy.size.height - 3) / 2
                            )
                        }
                    }
                }
            }
        }
    }
}
