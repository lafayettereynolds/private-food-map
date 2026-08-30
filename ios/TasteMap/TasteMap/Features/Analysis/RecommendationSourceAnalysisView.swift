import SwiftData
import SwiftUI

struct RecommendationSourceAnalysisScreen: View {
    @Environment(\.localAccountScope) private var accountScope
    @Query private var sources: [RecommendationSource]
    @Query private var restaurants: [Restaurant]
    @Query private var visits: [Visit]
    @Query private var photos: [PhotoAsset]
    @Query private var profiles: [UserProfile]

    @State private var overview: RecommendationSourceOverview?

    private var owned: ProfileOwnedContentScope.Snapshot {
        ProfileOwnedContentScope.capture(
            currentUserID: accountScope.ownerUserID,
            restaurants: restaurants, visits: visits, photos: photos,
            recommendationSources: sources
        )
    }

    private var photosByID: [UUID: PhotoAsset] {
        Dictionary(uniqueKeysWithValues: owned.photos.filter { $0.deletedAt == nil }.map { ($0.id, $0) })
    }

    private var restaurantsByID: [UUID: Restaurant] {
        Dictionary(uniqueKeysWithValues: owned.restaurants.filter { $0.deletedAt == nil }.map { ($0.id, $0) })
    }

    private var dataRevision: String {
        let dates = sources.map { max($0.updatedAt, $0.deletedAt ?? .distantPast) }
            + restaurants.map { max($0.updatedAt, $0.deletedAt ?? .distantPast) }
            + visits.map { max($0.updatedAt, $0.deletedAt ?? .distantPast) }
            + photos.map { max($0.updatedAt, $0.deletedAt ?? .distantPast) }
            + profiles.map { max($0.updatedAt, $0.deletedAt ?? .distantPast) }
        return [sources.count, restaurants.count, visits.count, photos.count, profiles.count]
            .map(String.init).joined(separator: ":")
            + ":\(dates.max()?.timeIntervalSince1970 ?? 0)"
    }

    var body: some View {
        PremiumFeatureGate(feature: .recommendationSourceAnalysis) {
            unlockedContent
        }
    }

    private var unlockedContent: some View {
        Group {
            if let overview {
                RecommendationSourceOverviewView(
                    overview: overview,
                    photosByID: photosByID,
                    restaurantsByID: restaurantsByID
                )
            } else {
                ProgressView("正在整理推荐来源线索…")
                    .tint(TasteMapAnalysisTheme.brand)
            }
        }
        .task(id: dataRevision) {
            let input = RecommendationSourceInput.capture(
                sources: owned.recommendationSources,
                restaurants: owned.restaurants,
                visits: owned.visits,
                photos: owned.photos,
                profile: profiles.first(where: {
                    $0.tasteMapUserID == accountScope.ownerUserID && $0.deletedAt == nil
                })
            )
            overview = await Task.detached(priority: .userInitiated) {
                RecommendationSourceAnalyzer.analyze(input)
            }.value
        }
    }
}

struct RecommendationSourceOverviewView: View {
    let overview: RecommendationSourceOverview
    let photosByID: [UUID: PhotoAsset]
    let restaurantsByID: [UUID: Restaurant]

    @State private var isShowingPoster = false
    private let conclusionColumns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 28) {
                header
                RecommendationSourceTrailHero(overview: overview, photosByID: photosByID)
                conclusions
                sourceLandscape
                representativeRestaurants
                sourceList
                privacyNote
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 48)
        }
        .background(TasteMapAnalysisTheme.canvas.ignoresSafeArea())
        .tasteMapBottomNavigationHidden()
        .navigationTitle("谁最会种草")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isShowingPoster = true } label: {
                    Label("分享", systemImage: "square.and.arrow.up")
                }
                .tint(TasteMapAnalysisTheme.brand)
                .accessibilityIdentifier("recommendation-source-share-toolbar")
            }
        }
        .sheet(isPresented: $isShowingPoster) {
            RecommendationSourcePosterSheet(overview: overview, photosByID: photosByID)
        }
        .accessibilityIdentifier("recommendation-source-analysis-overview")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("RECOMMENDATION TRAILS")
                    .font(.caption2.weight(.bold)).tracking(1.8)
                Spacer()
                Label("本地真实记录", systemImage: "checkmark.seal.fill")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(TasteMapAnalysisTheme.brand)
            Text("谁真正带你吃到了好店？")
                .font(.largeTitle.weight(.heavy))
                .foregroundStyle(TasteMapAnalysisTheme.ink)
            Text("按来源首次带来的不同餐厅统计；同一家店反复到访不会把来源次数重复放大。")
                .font(.subheadline)
                .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
            Button { isShowingPoster = true } label: {
                HStack(spacing: 10) {
                    Text("🧾")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("生成推荐来源分享海报").font(.subheadline.weight(.bold))
                        Text("包含“最坑推荐来源”，但不会暴露私人备注").font(.caption).opacity(0.84)
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
            .accessibilityIdentifier("recommendation-source-share-poster")
        }
    }

    private var conclusions: some View {
        VStack(alignment: .leading, spacing: 15) {
            AnalysisSectionHeader(
                "先看结论",
                eyebrow: "SOURCE VERDICT",
                detail: "靠谱和最坑都至少需要 6 家有评分餐厅，并且要有两个合格来源可比较。"
            )
            LazyVGrid(columns: conclusionColumns, spacing: 12) {
                conclusionCard(overview.mostUsed, fallbackTitle: "最常使用来源", symbol: "🧭", tone: .brand)
                conclusionCard(overview.highestAverage, fallbackTitle: "平均分更高", symbol: "⭐️", tone: .caramel)
                conclusionCard(overview.bestSource, fallbackTitle: "最靠谱推荐来源", symbol: "🥬", tone: .leafGreen)
                conclusionCard(overview.worstSource, fallbackTitle: "最坑推荐来源", symbol: "🌶️", tone: .ingredientRed)
            }
        }
        .accessibilityIdentifier("recommendation-source-conclusions")
    }

    @ViewBuilder
    private func conclusionCard(
        _ conclusion: RecommendationSourceConclusion?,
        fallbackTitle: String,
        symbol: String,
        tone: AnalysisTone
    ) -> some View {
        if let conclusion, let analysis = overview.analysis(for: conclusion.sourceID) {
            NavigationLink {
                RecommendationSourceDetailView(
                    analysis: analysis,
                    photosByID: photosByID,
                    restaurantsByID: restaurantsByID
                )
            } label: {
                RecommendationConclusionCard(conclusion: conclusion)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("recommendation-source-conclusion-\(conclusion.sourceID.uuidString.lowercased())")
        } else {
            VStack(alignment: .leading, spacing: 7) {
                AnalysisFoodGlyph(symbol: symbol, tone: tone, size: 42)
                Text(fallbackTitle).font(.caption.weight(.bold)).foregroundStyle(TasteMapAnalysisTheme.color(for: tone))
                Text("暂不下结论").font(.headline).foregroundStyle(TasteMapAnalysisTheme.ink)
                Text(fallbackTitle.contains("靠谱") || fallbackTitle.contains("最坑")
                     ? "至少两个来源分别达到 6 家有评分餐厅。" : "继续记录来源与餐厅评分。")
                    .font(.caption).foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
            }
            .frame(maxWidth: .infinity, minHeight: 178, alignment: .topLeading)
            .padding(15)
            .background(TasteMapAnalysisTheme.softColor(for: tone).opacity(0.66), in: RoundedRectangle(cornerRadius: 22))
        }
    }

    private var sourceLandscape: some View {
        VStack(alignment: .leading, spacing: 14) {
            AnalysisSectionHeader(
                "来源全景",
                eyebrow: "THE RECEIPT",
                detail: "Want To Go 当前没有正式来源字段，因此不会伪造或借用 Visit 来源。"
            )
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TASTE MAP SOURCE RECEIPT")
                            .font(.caption2.weight(.bold)).tracking(1.4)
                        Text("\(overview.attributedRestaurantCount) 家餐厅有可解释来源")
                            .font(.title2.weight(.heavy))
                    }
                    Spacer()
                    Text("🧾").font(.largeTitle)
                }
                Divider().overlay(TasteMapAnalysisTheme.hairline)
                receiptRow("来源目录", value: "\(overview.sourceCount) 个")
                receiptRow("实际使用", value: "\(overview.usedSourceCount) 个")
                receiptRow("有评分餐厅", value: "\(overview.ratedRestaurantCount) 家")
                receiptRow("餐厅整体平均", value: overview.overallRestaurantRating.map { "\($0.formatted(.number.precision(.fractionLength(1)))) / 5" } ?? "未评分")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 25)
            .background(TasteMapAnalysisTheme.card, in: ReceiptShape())
            .shadow(color: TasteMapAnalysisTheme.caramel.opacity(0.08), radius: 14, y: 7)
        }
    }

    private func receiptRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
            Spacer()
            Text(value).fontWeight(.bold).foregroundStyle(TasteMapAnalysisTheme.ink)
        }
        .font(.subheadline)
    }

    private var representativeRestaurants: some View {
        VStack(alignment: .leading, spacing: 14) {
            AnalysisSectionHeader(
                "这几家店解释了结论",
                eyebrow: "RESTAURANT EVIDENCE",
                detail: "只展示真实 Restaurant、你的餐厅级评分与自己的照片。"
            )
            if overview.representativeRestaurants.isEmpty {
                AnalysisGrowthPrompt(symbol: "📸", title: "餐厅证据正在形成", detail: "不会复制餐厅或生成假图片凑满版式。")
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 14) {
                        ForEach(overview.representativeRestaurants) { evidence in
                            evidenceButton(evidence)
                                .containerRelativeFrame(.horizontal, count: 10, span: 8, spacing: 14)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
            }
        }
    }

    private var sourceList: some View {
        VStack(alignment: .leading, spacing: 14) {
            AnalysisSectionHeader(
                "全部推荐来源",
                eyebrow: "SOURCE DIRECTORY",
                detail: "展示你写下的具体来源名称；平台类型只作为辅助分类，不替代来源身份。"
            )
            if overview.sources.isEmpty {
                AnalysisGrowthPrompt(symbol: "🗺️", title: "还没有推荐来源", detail: "在 Visit 中记录具体来源后，这里会开始积累。")
            } else {
                ForEach(overview.sources) { source in
                    NavigationLink {
                        RecommendationSourceDetailView(
                            analysis: source,
                            photosByID: photosByID,
                            restaurantsByID: restaurantsByID
                        )
                    } label: {
                        RecommendationSourceSummaryCard(source: source)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("recommendation-source-card-\(source.id.uuidString.lowercased())")
                }
            }
        }
    }

    private var privacyNote: some View {
        Label(overview.dataNote, systemImage: "lock.shield")
            .font(.caption)
            .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(TasteMapAnalysisTheme.leafGreenSoft.opacity(0.66), in: RoundedRectangle(cornerRadius: 20))
    }

    @ViewBuilder
    private func evidenceButton(_ evidence: RecommendationSourceRestaurantEvidence) -> some View {
        let card = RestaurantStoryCard(
            restaurant: RepresentativeRestaurant(
                id: evidence.id,
                name: evidence.name,
                role: evidence.role,
                detail: evidence.detail,
                averageRating: evidence.averageRating,
                visitCount: evidence.visitCount,
                imageReference: evidence.imageReference
            ),
            photosByID: photosByID
        )
        if let restaurant = restaurantsByID[evidence.id] {
            NavigationLink { RestaurantDetailView(restaurant: restaurant) } label: { card }
                .buttonStyle(.plain)
        } else { card }
    }
}

private struct RecommendationConclusionCard: View {
    let conclusion: RecommendationSourceConclusion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AnalysisFoodGlyph(symbol: conclusion.symbol, tone: conclusion.tone, size: 42)
            Text(conclusion.title)
                .font(.caption.weight(.bold))
                .foregroundStyle(TasteMapAnalysisTheme.color(for: conclusion.tone))
            Text(conclusion.value)
                .font(.headline.weight(.heavy))
                .foregroundStyle(TasteMapAnalysisTheme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
            Text(conclusion.explanation)
                .font(.caption)
                .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
                .lineLimit(4)
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.right").foregroundStyle(TasteMapAnalysisTheme.brand)
        }
        .frame(maxWidth: .infinity, minHeight: 202, alignment: .topLeading)
        .padding(15)
        .background(TasteMapAnalysisTheme.card, in: RoundedRectangle(cornerRadius: 22))
    }
}

private struct RecommendationSourceSummaryCard: View {
    let source: RecommendationSourceAnalysis

    var body: some View {
        HStack(spacing: 14) {
            AnalysisFoodGlyph(symbol: source.sourceType.analysisSymbol, tone: source.sourceType.analysisTone, size: 54)
            VStack(alignment: .leading, spacing: 5) {
                Text(source.displayName)
                    .font(.headline)
                    .foregroundStyle(TasteMapAnalysisTheme.ink)
                    .lineLimit(2)
                Text(source.sourceType.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TasteMapAnalysisTheme.color(for: source.sourceType.analysisTone))
                Text("\(source.restaurantCount) 家餐厅 · \(source.ratedRestaurantCount) 家有评分 · \(source.trend.title)")
                    .font(.caption)
                    .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
            }
            Spacer(minLength: 5)
            VStack(alignment: .trailing, spacing: 5) {
                Text(source.averageRating.map { "\($0.formatted(.number.precision(.fractionLength(1)))) ⭐️" } ?? "未评分")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(TasteMapAnalysisTheme.caramel)
                Image(systemName: "chevron.right").foregroundStyle(TasteMapAnalysisTheme.brand)
            }
        }
        .padding(16)
        .background(TasteMapAnalysisTheme.card, in: RoundedRectangle(cornerRadius: 22))
    }
}

struct RecommendationSourceDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let analysis: RecommendationSourceAnalysis
    let photosByID: [UUID: PhotoAsset]
    let restaurantsByID: [UUID: Restaurant]

    @State private var selectedRestaurant: Restaurant?
    @State private var fixtureMessage: String?
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 27) {
                detailHero
                metricGrid
                ratingStory
                trendStory
                restaurantEvidence
                privacyNote
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 48)
        }
        .background(TasteMapAnalysisTheme.canvas.ignoresSafeArea())
        .tasteMapBottomNavigationHidden()
        .navigationTitle(analysis.displayName)
        .navigationBarTitleDisplayMode(.inline)
#if DEBUG
        .toolbar {
            if TasteMapUITestFixtures.usesRecommendationSourceAnalysisFixture {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { mutateFixtureRating() } label: {
                        Label("修改一条评分测试样本", systemImage: "star.circle")
                    }
                    .accessibilityIdentifier("recommendation-source-fixture-change-rating")
                }
            }
        }
#endif
        .sheet(item: $selectedRestaurant) { restaurant in
            RecommendationSourceRestaurantDetailSheet(restaurant: restaurant)
        }
        .accessibilityIdentifier("recommendation-source-detail")
    }

    private var detailHero: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 34)
                    .fill(LinearGradient(
                        colors: [TasteMapAnalysisTheme.card, TasteMapAnalysisTheme.softColor(for: analysis.sourceType.analysisTone)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                VStack(spacing: 12) {
                    AnalysisFoodGlyph(symbol: analysis.sourceType.analysisSymbol, tone: analysis.sourceType.analysisTone, size: 92)
                    Text(analysis.displayName)
                        .font(.title.weight(.heavy))
                        .foregroundStyle(TasteMapAnalysisTheme.ink)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.68)
                    Text(analysis.sourceType.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(TasteMapAnalysisTheme.color(for: analysis.sourceType.analysisTone))
                        .padding(.horizontal, 13).padding(.vertical, 7)
                        .background(TasteMapAnalysisTheme.card.opacity(0.86), in: Capsule())
                    Text("\(analysis.restaurantCount) 家不同餐厅沿着这条线索进入你的 Taste Map")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
                }
                .padding(26)
            }
            .frame(minHeight: 286)
            .shadow(color: TasteMapAnalysisTheme.brandDeep.opacity(0.08), radius: 18, y: 10)
#if DEBUG
            if let fixtureMessage {
                Text(fixtureMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TasteMapAnalysisTheme.brandDeep)
                    .accessibilityIdentifier("recommendation-source-fixture-result")
            }
#endif
        }
    }

    private var metricGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            detailMetric("🧭", "带来餐厅", "\(analysis.restaurantCount) 家", .brand)
            detailMetric("⭐️", "餐厅平均", analysis.averageRating.map { "\($0.formatted(.number.precision(.fractionLength(1)))) / 5" } ?? "未评分", .caramel)
            detailMetric("🥬", "高分命中", "\(analysis.highRatingCount) 家", .leafGreen)
            detailMetric("🌶️", "低分餐厅", "\(analysis.lowRatingCount) 家", .ingredientRed)
            detailMetric("🔁", "回头餐厅", analysis.repeatConversionRate.formatted(.percent.precision(.fractionLength(0))), .brand)
            detailMetric("📈", "来源趋势", analysis.trend.title, .cream)
        }
    }

    private func detailMetric(_ icon: String, _ title: String, _ value: String, _ tone: AnalysisTone) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(icon).font(.title3)
            Text(title).font(.caption.weight(.bold)).foregroundStyle(TasteMapAnalysisTheme.color(for: tone))
            Text(value).font(.headline.weight(.heavy)).foregroundStyle(TasteMapAnalysisTheme.ink)
                .lineLimit(2).minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .padding(15)
        .background(TasteMapAnalysisTheme.card, in: RoundedRectangle(cornerRadius: 20))
    }

    private var ratingStory: some View {
        VStack(alignment: .leading, spacing: 14) {
            AnalysisSectionHeader(
                "评分表现",
                eyebrow: "RATING EVIDENCE",
                detail: "同一家 Restaurant 的多次 Visit 先聚合成一个评分样本；nil 不按 0 分。"
            )
            AnalysisInsightStoryCard(insight: AnalysisInsight(
                id: "stability", icon: "🎯", title: "评分稳定性",
                value: analysis.ratingStability.title,
                detail: analysis.ratingStandardDeviation.map { "餐厅级评分标准差 \($0.formatted(.number.precision(.fractionLength(2))))，样本 \(analysis.ratedRestaurantCount) 家。" }
                    ?? "至少 3 家有评分餐厅后再判断稳定性。",
                tone: analysis.ratingStability == .volatile ? .ingredientRed : .leafGreen,
                sufficiency: analysis.sufficiency
            ))
            if [analysis.valueAverage, analysis.environmentAverage, analysis.serviceAverage].contains(where: { $0 != nil }) {
                HStack(spacing: 10) {
                    dimensionPill("性价比", analysis.valueAverage)
                    dimensionPill("环境", analysis.environmentAverage)
                    dimensionPill("服务", analysis.serviceAverage)
                }
            }
        }
    }

    private func dimensionPill(_ title: String, _ value: Double?) -> some View {
        VStack(spacing: 3) {
            Text(title).font(.caption2).foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
            Text(value.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—")
                .font(.subheadline.weight(.bold)).foregroundStyle(TasteMapAnalysisTheme.ink)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(TasteMapAnalysisTheme.caramelSoft, in: RoundedRectangle(cornerRadius: 16))
    }

    private var trendStory: some View {
        VStack(alignment: .leading, spacing: 14) {
            AnalysisSectionHeader("近期变化", eyebrow: "SOURCE TREND", detail: "比较最近 90 天与此前 90 天首次归因的不同餐厅数。")
            HStack(spacing: 14) {
                detailMetric("🗓️", "最近 90 天", "\(analysis.recentRestaurantCount) 家", .brand)
                detailMetric("🧾", "此前 90 天", "\(analysis.previousRestaurantCount) 家", .cream)
            }
        }
    }

    private var restaurantEvidence: some View {
        VStack(alignment: .leading, spacing: 14) {
            AnalysisSectionHeader(
                "来源带来的餐厅",
                eyebrow: "THE PLACES",
                detail: "按你的餐厅平均评分、回头次数和归因日期排列。"
            )
            if analysis.restaurants.isEmpty {
                AnalysisGrowthPrompt(symbol: "🍽️", title: "还没有可解释餐厅", detail: "来源已存在，但还没有有效 Visit 归因到它。")
            } else {
                ForEach(analysis.restaurants) { evidence in
                    Button {
                        selectedRestaurant = restaurantsByID[evidence.id]
                    } label: {
                        HStack(spacing: 13) {
                            RestaurantEvidenceImage(reference: evidence.imageReference, photosByID: photosByID, height: 90)
                                .frame(width: 104)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(evidence.role).font(.caption.weight(.bold)).foregroundStyle(TasteMapAnalysisTheme.brand)
                                Text(evidence.name).font(.headline).foregroundStyle(TasteMapAnalysisTheme.ink).lineLimit(2)
                                Text(evidence.detail).font(.caption).foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
                            }
                            Spacer(minLength: 3)
                            Image(systemName: "chevron.right").foregroundStyle(TasteMapAnalysisTheme.brand)
                        }
                        .padding(12)
                        .background(TasteMapAnalysisTheme.card, in: RoundedRectangle(cornerRadius: 20))
                    }
                    .buttonStyle(.plain)
                    .disabled(restaurantsByID[evidence.id] == nil)
                    .accessibilityIdentifier("recommendation-source-restaurant-\(evidence.id.uuidString.lowercased())")
                }
            }
        }
    }

    private var privacyNote: some View {
        Label("这里只解释你的记录，不读取推荐人的私人数据，也不把内部 source ID 放进分享海报。", systemImage: "lock.shield")
            .font(.caption)
            .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
            .padding(16)
            .background(TasteMapAnalysisTheme.leafGreenSoft, in: RoundedRectangle(cornerRadius: 20))
    }

#if DEBUG
    private func mutateFixtureRating() {
        do {
            let restaurantIDs = Set(analysis.restaurants.map(\.id))
            guard let visit = try modelContext.fetch(FetchDescriptor<Visit>())
                .filter({ $0.deletedAt == nil && restaurantIDs.contains($0.restaurantId) })
                .sorted(by: { $0.visitedAt < $1.visitedAt }).first else {
                fixtureMessage = "没有可修改的 Visit"
                return
            }
            var draft = VisitDraft(visit: visit)
            draft.rating = visit.rating == 1.5 ? 5 : 1.5
            try LocalTasteMapStore(context: modelContext).update(
                visit,
                draft: draft,
                actorUserID: visit.ownerUserID
            )
            fixtureMessage = "已修改一条 Visit 评分"
        } catch {
            fixtureMessage = "测试评分修改失败"
        }
    }
#endif
}

private struct RecommendationSourceTrailHero: View {
    let overview: RecommendationSourceOverview
    let photosByID: [UUID: PhotoAsset]

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack {
                RoundedRectangle(cornerRadius: 38)
                    .fill(RadialGradient(
                        colors: [TasteMapAnalysisTheme.card, TasteMapAnalysisTheme.creamSoft.opacity(0.88)],
                        center: .center, startRadius: 30, endRadius: 260
                    ))
                    .overlay { RoundedRectangle(cornerRadius: 38).stroke(TasteMapAnalysisTheme.hairline, lineWidth: 2) }
                    .shadow(color: TasteMapAnalysisTheme.brandDeep.opacity(0.09), radius: 20, y: 12)
                AnalysisConnectorWeb()
                    .stroke(TasteMapAnalysisTheme.brand.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [6, 8]))
                    .padding(68)
                ZStack {
                    Circle().fill(TasteMapAnalysisTheme.caramelSoft).frame(width: 176, height: 176)
                    Text("🍲").font(.system(size: 78))
                }
                .position(x: width / 2, y: 185)
                ForEach(Array(overview.sources.filter(\.hasUsage).prefix(4).enumerated()), id: \.element.id) { index, source in
                    sourceTicket(source, index: index)
                        .position(ticketPosition(index, width: width))
                }
                Text("来源线索汇进你的餐桌")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(TasteMapAnalysisTheme.brandDeep)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(TasteMapAnalysisTheme.card.opacity(0.92), in: Capsule())
                    .position(x: width / 2, y: 335)
            }
        }
        .frame(height: 370)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("推荐来源线索主视觉")
    }

    private func sourceTicket(_ source: RecommendationSourceAnalysis, index: Int) -> some View {
        VStack(spacing: 3) {
            Text(source.sourceType.analysisSymbol).font(.title3)
            Text(source.displayName).font(.caption2.weight(.bold)).lineLimit(2).minimumScaleFactor(0.68)
            Text("\(source.restaurantCount) 家").font(.caption2).foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
        }
        .foregroundStyle(TasteMapAnalysisTheme.ink)
        .frame(width: 112)
        .frame(minHeight: 76)
        .padding(7)
        .background(TasteMapAnalysisTheme.card, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: TasteMapAnalysisTheme.brandDeep.opacity(0.08), radius: 10, y: 5)
    }

    private func ticketPosition(_ index: Int, width: CGFloat) -> CGPoint {
        switch index {
        case 0: CGPoint(x: width * 0.2, y: 78)
        case 1: CGPoint(x: width * 0.8, y: 78)
        case 2: CGPoint(x: width * 0.18, y: 286)
        default: CGPoint(x: width * 0.82, y: 286)
        }
    }
}

private struct RecommendationSourceRestaurantDetailSheet: View {
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
            .padding(.leading, 12).padding(.top, 6)
            .accessibilityLabel("关闭餐厅详情")
            .accessibilityIdentifier("recommendation-source-restaurant-detail-close")
        }
    }
}

extension RecommendationSourceType {
    nonisolated var analysisSymbol: String {
        switch self {
        case .friend: "🥢"
        case .xiaohongshu, .douyin: "📱"
        case .dianping: "🧾"
        case .blogger: "📝"
        case .self: "🗺️"
        case .other: "💡"
        }
    }

    nonisolated var analysisTone: AnalysisTone {
        switch self {
        case .friend: .ingredientRed
        case .xiaohongshu, .douyin: .brand
        case .dianping: .caramel
        case .blogger: .leafGreen
        case .self: .cream
        case .other: .brand
        }
    }
}

#if DEBUG
#Preview("01 空状态") { NavigationStack { RecommendationSourceOverviewView(overview: RecommendationSourcePreviewFixtures.empty, photosByID: [:], restaurantsByID: [:]) } }
#Preview("02 一个来源") { NavigationStack { RecommendationSourceOverviewView(overview: RecommendationSourcePreviewFixtures.oneSource, photosByID: [:], restaurantsByID: [:]) } }
#Preview("03 两个来源样本不足") { NavigationStack { RecommendationSourceOverviewView(overview: RecommendationSourcePreviewFixtures.twoInsufficient, photosByID: [:], restaurantsByID: [:]) } }
#Preview("04 数据完整") { NavigationStack { RecommendationSourceOverviewView(overview: RecommendationSourcePreviewFixtures.rich, photosByID: [:], restaurantsByID: [:]) } }
#Preview("05 明确靠谱与最坑") { NavigationStack { RecommendationSourceOverviewView(overview: RecommendationSourcePreviewFixtures.clearBestWorst, photosByID: [:], restaurantsByID: [:]) } }
#Preview("06 稳定高分") { NavigationStack { RecommendationSourceOverviewView(overview: RecommendationSourcePreviewFixtures.stableHigh, photosByID: [:], restaurantsByID: [:]) } }
#Preview("07 评分波动") { NavigationStack { RecommendationSourceOverviewView(overview: RecommendationSourcePreviewFixtures.volatile, photosByID: [:], restaurantsByID: [:]) } }
#Preview("08 低分来源") { NavigationStack { RecommendationSourceOverviewView(overview: RecommendationSourcePreviewFixtures.lowSource, photosByID: [:], restaurantsByID: [:]) } }
#Preview("09 Want To Go 不计入") { NavigationStack { RecommendationSourceOverviewView(overview: RecommendationSourcePreviewFixtures.wantToGoExcluded, photosByID: [:], restaurantsByID: [:]) } }
#Preview("10 有照片引用") { NavigationStack { RecommendationSourceOverviewView(overview: RecommendationSourcePreviewFixtures.withPhotos, photosByID: [:], restaurantsByID: [:]) } }
#Preview("11 无照片") { NavigationStack { RecommendationSourceOverviewView(overview: RecommendationSourcePreviewFixtures.noPhotos, photosByID: [:], restaurantsByID: [:]) } }
#Preview("12 长来源名") { NavigationStack { RecommendationSourceOverviewView(overview: RecommendationSourcePreviewFixtures.longSourceName, photosByID: [:], restaurantsByID: [:]) } }
#Preview("13 长餐厅名") { NavigationStack { RecommendationSourceOverviewView(overview: RecommendationSourcePreviewFixtures.longRestaurantName, photosByID: [:], restaurantsByID: [:]) } }
#Preview("14 来源详情") { NavigationStack { RecommendationSourceDetailView(analysis: RecommendationSourcePreviewFixtures.rich.sources[0], photosByID: [:], restaurantsByID: [:]) } }
#Preview("15 小屏") { NavigationStack { RecommendationSourceOverviewView(overview: RecommendationSourcePreviewFixtures.rich, photosByID: [:], restaurantsByID: [:]) }.frame(width: 320, height: 700) }
#Preview("16 大字体") { NavigationStack { RecommendationSourceOverviewView(overview: RecommendationSourcePreviewFixtures.longSourceName, photosByID: [:], restaurantsByID: [:]) }.environment(\.dynamicTypeSize, .accessibility3) }
#Preview("17 详情样本不足") { NavigationStack { RecommendationSourceDetailView(analysis: RecommendationSourcePreviewFixtures.oneSource.sources[0], photosByID: [:], restaurantsByID: [:]) } }
#endif
