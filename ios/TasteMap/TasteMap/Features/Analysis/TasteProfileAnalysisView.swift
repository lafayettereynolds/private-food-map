import SwiftData
import SwiftUI

struct TasteProfileAnalysisScreen: View {
    @Query private var restaurants: [Restaurant]
    @Query private var visits: [Visit]
    @Query private var dishes: [Dish]
    @Query private var visitDishes: [VisitDish]
    @Query private var photos: [PhotoAsset]
    @Query private var companions: [DiningCompanion]
    @Query private var recommendationSources: [RecommendationSource]
    @Query private var profiles: [UserProfile]

    @State private var report: TasteProfileAnalysis?

    private var photosByID: [UUID: PhotoAsset] {
        Dictionary(uniqueKeysWithValues: photos.filter { $0.deletedAt == nil }.map { ($0.id, $0) })
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
        let latest = dates.max()?.timeIntervalSince1970 ?? 0
        return "\(restaurants.count):\(visits.count):\(dishes.count):\(visitDishes.count):\(photos.count):\(companions.count):\(recommendationSources.count):\(profiles.count):\(latest)"
    }

    var body: some View {
        PremiumFeatureGate(feature: .fullTasteProfile) {
            unlockedContent
        }
    }

    private var unlockedContent: some View {
        Group {
            if let report {
                TasteProfileAnalysisView(report: report, photosByID: photosByID)
            } else {
                ProgressView("正在整理你的味觉地图…")
                    .tint(TasteMapAnalysisTheme.brand)
            }
        }
        .task(id: dataRevision) {
            let input = TasteProfileInput.capture(
                restaurants: restaurants,
                visits: visits,
                dishes: dishes,
                visitDishes: visitDishes,
                photos: photos,
                companions: companions,
                recommendationSources: recommendationSources,
                profile: profiles.first(where: { $0.deletedAt == nil })
            )
            report = await Task.detached(priority: .userInitiated) {
                TasteProfileAnalyzer.analyze(input)
            }.value
        }
    }
}

struct TasteProfileAnalysisView: View {
    let report: TasteProfileAnalysis
    let photosByID: [UUID: PhotoAsset]

    @State private var isShowingPoster = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 30) {
                titleBlock
                AnalysisHeroMap(report: report, photosByID: photosByID)
                preferenceRanking
                insights
                keywords
                spendReceipt
                restaurantStories
                closingNote
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 48)
        }
        .background(TasteMapAnalysisTheme.canvas.ignoresSafeArea())
        .tasteMapBottomNavigationHidden()
        .navigationTitle("口味档案")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isShowingPoster = true } label: {
                    Label("分享", systemImage: "square.and.arrow.up")
                }
                .tint(TasteMapAnalysisTheme.brand)
                .accessibilityIdentifier("taste-profile-share-toolbar")
            }
        }
        .sheet(isPresented: $isShowingPoster) {
            AnalysisPosterSheet(report: report, photosByID: photosByID)
        }
        .accessibilityIdentifier("taste-profile-analysis-page")
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) {
                Text(report.eyebrow)
                    .font(.caption2.weight(.bold))
                    .tracking(1.8)
                Spacer()
                Label(report.sufficiency.title, systemImage: "checkmark.seal.fill")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(TasteMapAnalysisTheme.brand)

            Text(report.title)
                .font(.largeTitle.weight(.heavy))
                .foregroundStyle(TasteMapAnalysisTheme.ink)
            Text("\(report.userDisplayName) · \(report.subtitle)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
            Text(report.summary)
                .font(.title3.weight(.semibold))
                .foregroundStyle(TasteMapAnalysisTheme.ink)
                .lineSpacing(5)

            Button { isShowingPoster = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("生成分享海报").font(.subheadline.weight(.bold))
                        Text("独立 9:16 设计，不是页面截图").font(.caption).opacity(0.84)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .foregroundStyle(.white)
                .background(TasteMapAnalysisTheme.brand, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: TasteMapAnalysisTheme.brand.opacity(0.2), radius: 14, y: 7)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("taste-profile-share-poster")
        }
    }

    @ViewBuilder
    private var preferenceRanking: some View {
        VStack(alignment: .leading, spacing: 15) {
            AnalysisSectionHeader(
                "你真正喜欢什么",
                eyebrow: "REAL PREFERENCES",
                detail: "综合频率、跨店覆盖、回头选择、可靠评分和近期记录。"
            )
            if report.cuisineRanking.isEmpty {
                AnalysisGrowthPrompt(
                    symbol: "🥟",
                    title: "菜系偏好正在形成",
                    detail: "继续为餐厅保留真实菜系标签；不会从店名猜测。"
                )
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(report.cuisineRanking.prefix(5).enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 13) {
                            Text("\(index + 1)")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(index == 0 ? TasteMapAnalysisTheme.ingredientRed : TasteMapAnalysisTheme.brand, in: Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.label).font(.headline).foregroundStyle(TasteMapAnalysisTheme.ink)
                                Text("\(item.visitCount) 次到访 · \(item.restaurantCount) 家餐厅")
                                    .font(.caption).foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
                            }
                            Spacer()
                            if let rating = item.averageRating {
                                Label(rating.formatted(.number.precision(.fractionLength(1))), systemImage: "star.fill")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(TasteMapAnalysisTheme.caramel)
                            }
                        }
                    }
                }
                .padding(17)
                .background(TasteMapAnalysisTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
        }
    }

    private var insights: some View {
        VStack(alignment: .leading, spacing: 16) {
            AnalysisSectionHeader(
                "味觉地图的生活侧写",
                eyebrow: "TASTE NOTES",
                detail: "只展示已有依据的结论；缺少的维度会告诉你怎样继续记录。"
            )
            ForEach(report.insights) { insight in
                if insight.isAvailable {
                    AnalysisInsightStoryCard(insight: insight)
                } else {
                    AnalysisGrowthPrompt(
                        symbol: insight.icon,
                        title: insight.title + "正在形成",
                        detail: insight.detail
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var keywords: some View {
        VStack(alignment: .leading, spacing: 14) {
            AnalysisSectionHeader(
                "口味关键词",
                eyebrow: "FLAVOR WORDS",
                detail: "来自菜系、菜品、场景与高分到访标签。"
            )
            if report.keywords.isEmpty {
                AnalysisGrowthPrompt(
                    symbol: "🏷️",
                    title: "关键词正在形成",
                    detail: "保存更多结构化记录后会自动更新。"
                )
            } else {
                AnalysisTagFlow(tags: report.keywords)
            }
        }
    }

    private var spendReceipt: some View {
        VStack(alignment: .leading, spacing: 16) {
            AnalysisSectionHeader(
                "我的消费分布",
                eyebrow: "MY RECEIPT",
                detail: "只统计“我的实际消费”，空值不按 ¥0 处理。"
            )
            SpendReceiptCard(spend: report.spend)
        }
    }

    private var restaurantStories: some View {
        VStack(alignment: .leading, spacing: 16) {
            AnalysisSectionHeader(
                "代表你的几家店",
                eyebrow: "RESTAURANT STORIES",
                detail: "餐厅名、到访说明和照片都来自你的记录。"
            )
            if report.restaurants.isEmpty {
                AnalysisGrowthPrompt(
                    symbol: "📸",
                    title: "代表餐厅正在形成",
                    detail: "保存到访后，会从最常去、最喜欢、近期常去和最能代表口味的餐厅中去重选择。"
                )
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 14) {
                        ForEach(report.restaurants) { restaurant in
                            RestaurantStoryCard(restaurant: restaurant, photosByID: photosByID)
                                .containerRelativeFrame(.horizontal, count: 10, span: 8, spacing: 14)
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, 1, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
            }
        }
    }

    private var closingNote: some View {
        VStack(spacing: 10) {
            Text("🍽️").font(.title)
            Text("口味档案会随真实记录持续更新")
                .font(.headline).foregroundStyle(TasteMapAnalysisTheme.ink)
            Text(report.dataNote)
                .font(.caption).multilineTextAlignment(.center)
                .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
            Text(report.footer)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(TasteMapAnalysisTheme.brand)
        }
        .padding(.vertical, 8)
    }
}

private struct AnalysisHeroMap: View {
    let report: TasteProfileAnalysis
    let photosByID: [UUID: PhotoAsset]

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let cardWidth = min(148, width * 0.43)
            ZStack {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(RadialGradient(
                        colors: [TasteMapAnalysisTheme.card, TasteMapAnalysisTheme.creamSoft.opacity(0.7)],
                        center: .center,
                        startRadius: 35,
                        endRadius: 260
                    ))
                    .overlay { RoundedRectangle(cornerRadius: 34).stroke(TasteMapAnalysisTheme.hairline, lineWidth: 1.5) }
                    .shadow(color: TasteMapAnalysisTheme.brandDeep.opacity(0.08), radius: 22, y: 12)

                AnalysisConnectorWeb()
                    .stroke(
                        TasteMapAnalysisTheme.brand.opacity(0.28),
                        style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [5, 7])
                    )
                    .padding(.horizontal, 54)
                    .padding(.vertical, 70)

                AnalysisHeroMedia(hero: report.hero, photosByID: photosByID, size: min(250, width * 0.66))
                    .offset(y: 7)

                Text(report.hero.primaryTheme)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(TasteMapAnalysisTheme.brandDeep)
                    .lineLimit(1)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
                    .position(x: width / 2, y: 365)

                ForEach(Array(report.callouts.prefix(4).enumerated()), id: \.element.id) { index, callout in
                    AnalysisCalloutCard(callout: callout)
                        .frame(width: cardWidth)
                        .position(position(for: index, width: width))
                }
            }
        }
        .frame(height: 440)
    }

    private func position(for index: Int, width: CGFloat) -> CGPoint {
        switch index {
        case 0: CGPoint(x: width * 0.23, y: 76)
        case 1: CGPoint(x: width * 0.77, y: 76)
        case 2: CGPoint(x: width * 0.23, y: 370)
        default: CGPoint(x: width * 0.77, y: 370)
        }
    }
}

struct AnalysisCalloutCard: View {
    let callout: AnalysisCallout

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Text(callout.icon)
                Text(callout.title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
            }
            Text(callout.value)
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(callout.sufficiency == .insufficient
                    ? TasteMapAnalysisTheme.secondaryInk : TasteMapAnalysisTheme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
            Text(callout.detail)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
                .lineLimit(2)
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .background(TasteMapAnalysisTheme.card.opacity(0.95), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .leading) {
            Capsule().fill(TasteMapAnalysisTheme.color(for: callout.tone))
                .frame(width: 4).padding(.vertical, 13)
        }
        .shadow(color: TasteMapAnalysisTheme.brandDeep.opacity(0.09), radius: 10, y: 5)
    }
}

struct AnalysisInsightStoryCard: View {
    let insight: AnalysisInsight

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            AnalysisFoodGlyph(symbol: insight.icon, tone: insight.tone, size: 50)
            VStack(alignment: .leading, spacing: 6) {
                Text(insight.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(TasteMapAnalysisTheme.color(for: insight.tone))
                Text(insight.value)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(TasteMapAnalysisTheme.ink)
                Text(insight.detail)
                    .font(.subheadline)
                    .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
            }
            Spacer(minLength: 0)
        }
        .padding(17)
        .background(TasteMapAnalysisTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Circle().fill(TasteMapAnalysisTheme.softColor(for: insight.tone))
                .frame(width: 44, height: 44).offset(x: 14, y: -14).clipped()
        }
    }
}

struct AnalysisGrowthPrompt: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            AnalysisFoodGlyph(symbol: symbol, tone: .brand)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline).foregroundStyle(TasteMapAnalysisTheme.ink)
                Text(detail).font(.subheadline).foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(17)
        .background(TasteMapAnalysisTheme.brandSoft.opacity(0.68), in: RoundedRectangle(cornerRadius: 22))
    }
}

private struct SpendReceiptCard: View {
    let spend: TasteProfileSpendAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TASTE MAP RECEIPT")
                        .font(.caption2.weight(.bold)).tracking(1.4)
                    Text(spend.typicalBucket ?? "消费记录正在形成")
                        .font(.title2.weight(.heavy))
                }
                Spacer()
                Text("🧾").font(.largeTitle)
            }
            .foregroundStyle(TasteMapAnalysisTheme.ink)

            if let median = spend.median {
                HStack {
                    Text("实际消费中位数")
                    Spacer()
                    Text("¥\(Int(median.rounded()))").font(.title3.bold())
                }
                .font(.subheadline)
                Divider().overlay(TasteMapAnalysisTheme.hairline)
            }

            if spend.distribution.isEmpty {
                Text("添加“我的实际消费”后，这张小票会显示真实分布。")
                    .font(.subheadline).foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
            } else {
                ForEach(spend.distribution) { item in
                    VStack(spacing: 5) {
                        HStack {
                            Text(item.label).font(.caption.weight(.semibold))
                            Spacer()
                            Text("\(item.count) 次").font(.caption.monospacedDigit())
                        }
                        GeometryReader { proxy in
                            Capsule().fill(TasteMapAnalysisTheme.brandSoft)
                                .overlay(alignment: .leading) {
                                    Capsule().fill(TasteMapAnalysisTheme.brand)
                                        .frame(width: max(8, proxy.size.width * item.share))
                                }
                        }
                        .frame(height: 8)
                    }
                }
            }

            HStack {
                Text("样本 \(spend.sampleCount)")
                Spacer()
                Text("谢谢记录")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 25)
        .background(TasteMapAnalysisTheme.card, in: ReceiptShape())
        .shadow(color: TasteMapAnalysisTheme.caramel.opacity(0.09), radius: 15, y: 8)
    }
}

struct RestaurantStoryCard: View {
    let restaurant: RepresentativeRestaurant
    let photosByID: [UUID: PhotoAsset]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RestaurantEvidenceImage(reference: restaurant.imageReference, photosByID: photosByID, height: 164)
            VStack(alignment: .leading, spacing: 6) {
                Text(restaurant.role)
                    .font(.caption.weight(.bold)).foregroundStyle(TasteMapAnalysisTheme.brand)
                Text(restaurant.name)
                    .font(.title3.weight(.bold)).foregroundStyle(TasteMapAnalysisTheme.ink)
                    .lineLimit(2)
                Text(restaurant.detail)
                    .font(.caption).foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
                    .lineLimit(2)
            }
            .padding(15)
        }
        .background(TasteMapAnalysisTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

#if DEBUG
#Preview("数据完整 · iPhone") {
    NavigationStack {
        TasteProfileAnalysisView(report: TasteProfilePreviewFixtures.rich, photosByID: [:])
    }
}

#Preview("数据中等") {
    NavigationStack {
        TasteProfileAnalysisView(report: TasteProfilePreviewFixtures.medium, photosByID: [:])
    }
}

#Preview("数据较少") {
    NavigationStack {
        TasteProfileAnalysisView(report: TasteProfilePreviewFixtures.sparse, photosByID: [:])
    }
}

#Preview("无餐厅图片") {
    NavigationStack {
        TasteProfileAnalysisView(report: TasteProfilePreviewFixtures.noPhotos, photosByID: [:])
    }
}

#Preview("多菜系拼盘") {
    NavigationStack {
        TasteProfileAnalysisView(report: TasteProfilePreviewFixtures.rich, photosByID: [:])
    }
}

#Preview("单一偏好") {
    NavigationStack {
        TasteProfileAnalysisView(report: TasteProfilePreviewFixtures.singlePreference, photosByID: [:])
    }
}

#Preview("高重复到访") {
    NavigationStack {
        TasteProfileAnalysisView(report: TasteProfilePreviewFixtures.highRepeat, photosByID: [:])
    }
}

#Preview("消费数据少") {
    NavigationStack {
        TasteProfileAnalysisView(report: TasteProfilePreviewFixtures.sparse, photosByID: [:])
    }
}

#Preview("无饭搭子与推荐来源") {
    NavigationStack {
        TasteProfileAnalysisView(report: TasteProfilePreviewFixtures.noPeopleOrSources, photosByID: [:])
    }
}

#Preview("代表餐厅有图") {
    NavigationStack {
        TasteProfileAnalysisView(report: TasteProfilePreviewFixtures.withAssetImages, photosByID: [:])
    }
}

#Preview("长文字与较多分析项") {
    NavigationStack {
        TasteProfileAnalysisView(report: TasteProfilePreviewFixtures.longContent, photosByID: [:])
    }
    .environment(\.dynamicTypeSize, .accessibility1)
}

#Preview("小屏") {
    NavigationStack {
        TasteProfileAnalysisView(report: TasteProfilePreviewFixtures.emerging, photosByID: [:])
    }
    .frame(width: 320, height: 700)
}

#Preview("大字体") {
    NavigationStack {
        TasteProfileAnalysisView(report: TasteProfilePreviewFixtures.medium, photosByID: [:])
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
