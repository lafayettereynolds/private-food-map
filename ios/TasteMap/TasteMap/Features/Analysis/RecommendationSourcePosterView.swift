import SwiftUI
import UIKit

struct RecommendationSourcePosterView: View {
    static let canvasSize = CGSize(width: 1080, height: 1920)

    let overview: RecommendationSourceOverview
    var resolvedImages: [UUID: UIImage] = [:]
    var brandConfiguration = SharePosterBrandConfiguration.current()

    var body: some View {
        ZStack {
            TasteMapAnalysisTheme.canvas
            Circle()
                .fill(TasteMapAnalysisTheme.brandSoft.opacity(0.88))
                .frame(width: 690, height: 690)
                .offset(x: 440, y: -800)
            Circle()
                .fill(TasteMapAnalysisTheme.ingredientRedSoft.opacity(0.65))
                .frame(width: 540, height: 540)
                .offset(x: -470, y: 820)

            VStack(alignment: .leading, spacing: 0) {
                header
                sourceTrail.padding(.top, 22)
                verdicts.padding(.top, 22)
                restaurantEvidence.padding(.top, 24)
                Spacer(minLength: 14)
                footer
            }
            .padding(.horizontal, 62)
            .padding(.vertical, 56)
        }
        .frame(width: Self.canvasSize.width, height: Self.canvasSize.height)
        .environment(\.colorScheme, .light)
        .clipped()
        .accessibilityIdentifier("recommendation-source-poster-canvas")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("RECOMMENDATION TRAILS")
                    .font(.system(size: 21, weight: .bold, design: .rounded)).tracking(4)
                Spacer()
                Label("\(overview.attributedRestaurantCount) 家真实餐厅", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(TasteMapAnalysisTheme.brand)
            Text("谁最会种草")
                .font(.system(size: 60, weight: .heavy, design: .rounded))
                .foregroundStyle(TasteMapAnalysisTheme.ink)
            Text("\(overview.userDisplayName) · 谁真正带我吃到了好店")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
        }
    }

    private var sourceTrail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 46)
                .fill(.white.opacity(0.95))
                .overlay { RoundedRectangle(cornerRadius: 46).stroke(.white, lineWidth: 2) }
                .shadow(color: TasteMapAnalysisTheme.brandDeep.opacity(0.09), radius: 28, y: 15)
            AnalysisConnectorWeb()
                .stroke(TasteMapAnalysisTheme.brand.opacity(0.24), style: StrokeStyle(lineWidth: 2.5, dash: [9, 12]))
                .padding(.horizontal, 160).padding(.vertical, 92)
            ZStack {
                Circle().fill(TasteMapAnalysisTheme.caramelSoft).frame(width: 300, height: 300)
                Circle().stroke(.white, lineWidth: 12).frame(width: 270, height: 270)
                Image("FoodHeroMixed")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 260, height: 260)
                    .accessibilityHidden(true)
            }
            .offset(y: 8)
            ForEach(Array(overview.sources.filter(\.hasUsage).prefix(4).enumerated()), id: \.element.id) { index, source in
                sourceTicket(source)
                    .frame(width: 230)
                    .position(ticketPosition(index))
            }
            Text("来源小票 → 我的餐桌")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(TasteMapAnalysisTheme.brandDeep)
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(.white.opacity(0.94), in: Capsule())
                .offset(y: 205)
        }
        .frame(height: 540)
    }

    private func sourceTicket(_ source: RecommendationSourceAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                FoodDiningVisualIcon(
                    kind: source.sourceType.analysisVisualKind,
                    usage: .dataLinked,
                    size: 38,
                    foregroundColor: TasteMapAnalysisTheme.brandDeep,
                    backgroundColor: TasteMapAnalysisTheme.brandSoft,
                    accessibilityLabel: source.sourceType.title
                )
                Spacer()
                Text("\(source.restaurantCount) 家")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(TasteMapAnalysisTheme.brand)
            }
            Text(source.displayName)
                .font(.system(size: 19, weight: .heavy, design: .rounded))
                .foregroundStyle(TasteMapAnalysisTheme.ink)
                .lineLimit(2).minimumScaleFactor(0.66)
            Text(source.averageRating.map { "餐厅平均 \($0.formatted(.number.precision(.fractionLength(1))))" } ?? "评分正在形成")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
        }
        .padding(16)
        .frame(height: 120, alignment: .topLeading)
        .background(.white, in: ReceiptShape())
        .shadow(color: TasteMapAnalysisTheme.brandDeep.opacity(0.1), radius: 12, y: 6)
    }

    private var verdicts: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("这次来源结论")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(TasteMapAnalysisTheme.ink)
                Spacer()
                Text("SOURCE VERDICT")
                    .font(.system(size: 15, weight: .bold, design: .rounded)).tracking(2)
                    .foregroundStyle(TasteMapAnalysisTheme.brand)
            }
            HStack(spacing: 14) {
                posterVerdict(overview.mostUsed, title: "最常使用来源", symbol: "🧭", tone: .brand)
                posterVerdict(overview.bestSource, title: "最靠谱推荐来源", symbol: "🥬", tone: .leafGreen)
                posterVerdict(overview.worstSource, title: "最坑推荐来源", symbol: "🌶️", tone: .ingredientRed)
            }
        }
    }

    private func posterVerdict(
        _ conclusion: RecommendationSourceConclusion?,
        title: String,
        symbol: String,
        tone: AnalysisTone
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                AnalysisFoodGlyph(symbol: symbol, tone: tone, size: 36, semanticID: "source-\(title)")
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(TasteMapAnalysisTheme.color(for: tone))
                    .lineLimit(1).minimumScaleFactor(0.74)
            }
            Text(conclusion?.value ?? "暂不下结论")
                .font(.system(size: 21, weight: .heavy, design: .rounded))
                .foregroundStyle(TasteMapAnalysisTheme.ink)
                .lineLimit(2).minimumScaleFactor(0.64)
            Text(conclusion?.explanation ?? "需要至少两个来源分别达到 6 家有评分餐厅。")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
                .lineLimit(4).minimumScaleFactor(0.72)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 178, alignment: .topLeading)
        .background(.white, in: RoundedRectangle(cornerRadius: 23))
    }

    private var restaurantEvidence: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("餐厅证据")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(TasteMapAnalysisTheme.ink)
                Spacer()
                Text("REAL RESTAURANTS")
                    .font(.system(size: 15, weight: .bold, design: .rounded)).tracking(2)
                    .foregroundStyle(TasteMapAnalysisTheme.brand)
            }
            if overview.representativeRestaurants.isEmpty {
                HStack(spacing: 15) {
                    FoodDiningVisualIcon(
                        kind: .genericDining,
                        usage: .decorative,
                        size: 56,
                        foregroundColor: TasteMapAnalysisTheme.brandDeep,
                        backgroundColor: TasteMapAnalysisTheme.brandSoft
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text("餐厅证据正在形成")
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                        Text("不会生成假餐厅、假评分或假图片。")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
                    }
                }
                .padding(22).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white, in: RoundedRectangle(cornerRadius: 26))
            } else {
                HStack(spacing: 16) {
                    ForEach(overview.representativeRestaurants.prefix(3)) { evidence in
                        PosterRestaurantCard(
                            restaurant: RepresentativeRestaurant(
                                id: evidence.id, name: evidence.name, role: evidence.role,
                                detail: evidence.detail, averageRating: evidence.averageRating,
                                visitCount: evidence.visitCount, imageReference: evidence.imageReference
                            ),
                            image: image(for: evidence.imageReference)
                        )
                    }
                }
            }
        }
    }

    private var footer: some View {
        SharePosterBrandFooter(
            supportingText: "真实记录生成 · 每家餐厅只给来源贡献一次评分样本",
            tagline: "谁安利，谁负责",
            configuration: brandConfiguration
        )
    }

    private func ticketPosition(_ index: Int) -> CGPoint {
        switch index {
        case 0: CGPoint(x: 145, y: 105)
        case 1: CGPoint(x: 835, y: 105)
        case 2: CGPoint(x: 145, y: 435)
        default: CGPoint(x: 835, y: 435)
        }
    }

    private func image(for reference: AnalysisImageReference) -> UIImage? {
        switch reference {
        case .photo(let id, _): resolvedImages[id]
        case .provider: reference.resolutionKey.flatMap { resolvedImages[$0] }
        case .asset(let name): UIImage(named: name)
        case .none: nil
        }
    }
}

struct RecommendationSourcePosterSheet: View {
    let overview: RecommendationSourceOverview
    let photosByID: [UUID: PhotoAsset]

    var body: some View {
        AnalysisPosterExportSheet(
            posterID: overview.id,
            requiredFeature: .recommendationSourceAnalysis,
            progressMessage: "正在把来源线索排成小票海报…",
            references: overview.photoReferences,
            photosByID: photosByID,
            render: { images in
                try AnalysisPosterRenderer.render(
                    content: RecommendationSourcePosterView(overview: overview, resolvedImages: images),
                    canvasSize: RecommendationSourcePosterView.canvasSize
                )
            }
        )
    }
}

#if DEBUG
#Preview("18 推荐来源海报 · 完整") {
    ScrollView([.horizontal, .vertical]) {
        RecommendationSourcePosterView(overview: RecommendationSourcePreviewFixtures.posterRich)
            .scaleEffect(0.3, anchor: .topLeading)
            .frame(
                width: RecommendationSourcePosterView.canvasSize.width * 0.3,
                height: RecommendationSourcePosterView.canvasSize.height * 0.3,
                alignment: .topLeading
            )
    }
}

#Preview("19 推荐来源海报 · 样本不足") {
    ScrollView([.horizontal, .vertical]) {
        RecommendationSourcePosterView(overview: RecommendationSourcePreviewFixtures.posterSparse)
            .scaleEffect(0.3, anchor: .topLeading)
            .frame(
                width: RecommendationSourcePosterView.canvasSize.width * 0.3,
                height: RecommendationSourcePosterView.canvasSize.height * 0.3,
                alignment: .topLeading
            )
    }
}
#endif
