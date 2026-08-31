import SwiftUI
import UIKit

struct MonthlyRecapPosterView: View {
    static let canvasSize = CGSize(width: 1_080, height: 1_920)

    let report: MonthlyRecapAnalysis
    let resolvedImages: [UUID: UIImage]

    var body: some View {
        ZStack {
            TasteMapAnalysisTheme.canvas
            Circle()
                .fill(TasteMapAnalysisTheme.brandSoft.opacity(0.9))
                .frame(width: 640, height: 640)
                .offset(x: 420, y: -720)
            Circle()
                .fill(TasteMapAnalysisTheme.ingredientRedSoft.opacity(0.62))
                .frame(width: 480, height: 480)
                .offset(x: -470, y: 760)

            VStack(spacing: 0) {
                posterHeader
                    .frame(height: 190)
                heroCollage
                    .frame(height: 610)
                    .padding(.horizontal, 54)
                metricReceipt
                    .frame(height: 250)
                    .padding(.horizontal, 54)
                    .offset(y: -28)
                storyBand
                    .frame(height: 310)
                    .padding(.horizontal, 54)
                    .offset(y: -22)
                restaurantStrip
                    .frame(height: 430)
                    .padding(.horizontal, 54)
                    .offset(y: -12)
                posterFooter
                    .frame(height: 130)
            }
        }
        .frame(width: Self.canvasSize.width, height: Self.canvasSize.height)
        .clipped()
        .environment(\.colorScheme, .light)
        .accessibilityIdentifier("monthly-recap-poster")
    }

    private var posterHeader: some View {
        HStack(alignment: .center, spacing: 24) {
            ZStack {
                RoundedRectangle(cornerRadius: 28)
                    .fill(TasteMapAnalysisTheme.brand)
                Text("TM").font(.system(size: 34, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            }
            .frame(width: 84, height: 84)
            VStack(alignment: .leading, spacing: 7) {
                Text("TASTE MAP · MONTHLY FOOD DIARY")
                    .font(.system(size: 22, weight: .bold)).tracking(2.7)
                    .foregroundStyle(TasteMapAnalysisTheme.brand)
                Text(report.periodLabel)
                    .font(.system(size: 48, weight: .heavy, design: .rounded))
                    .foregroundStyle(TasteMapAnalysisTheme.ink)
            }
            Spacer()
            Text(report.userDisplayName)
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 58)
    }

    private var heroCollage: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 48)
                .fill(TasteMapAnalysisTheme.creamSoft)
            posterPhotoCollage
                .clipShape(RoundedRectangle(cornerRadius: 48))
            LinearGradient(
                colors: [.clear, TasteMapAnalysisTheme.ink.opacity(0.84)],
                startPoint: .center, endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 14) {
                Text("这个月，我认真吃了")
                    .font(.system(size: 29, weight: .bold))
                Text("\(report.visitCount) 次 · \(report.restaurantCount) 家餐厅")
                    .font(.system(size: 59, weight: .heavy, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.72)
                Text(heroStatement)
                    .font(.system(size: 27, weight: .semibold))
                    .lineLimit(2)
            }
            .foregroundStyle(.white)
            .padding(46)
        }
        .shadow(color: TasteMapAnalysisTheme.brandDeep.opacity(0.14), radius: 30, y: 16)
    }

    @ViewBuilder
    private var posterPhotoCollage: some View {
        let stories = Array(report.representativeRestaurants.prefix(3))
        if stories.count <= 1 {
            posterImage(reference: stories.first?.imageReference ?? .asset(FoodHeroTheme.mixed.assetName))
        } else {
            HStack(spacing: 5) {
                posterImage(reference: stories[0].imageReference)
                    .frame(width: 590)
                VStack(spacing: 5) {
                    ForEach(Array(stories.dropFirst().prefix(2))) { item in
                        posterImage(reference: item.imageReference)
                    }
                }
            }
        }
    }

    private var metricReceipt: some View {
        HStack(spacing: 0) {
            posterMetric("去过", "\(report.visitCount)", "次")
            posterDivider
            posterMetric("餐厅", "\(report.restaurantCount)", "家")
            posterDivider
            posterMetric("人生新店", "\(report.newRestaurantCount)", "家")
            if shouldShowSpend {
                posterDivider
                posterMetric(
                    report.spend.displayState == .complete ? "本月消费" : "已记录消费",
                    "¥\(Int((report.spend.recordedTotal ?? 0).rounded()))", ""
                )
            }
        }
        .padding(.horizontal, 34)
        .background(.white, in: ReceiptShape())
        .shadow(color: TasteMapAnalysisTheme.caramel.opacity(0.1), radius: 18, y: 9)
    }

    private var storyBand: some View {
        HStack(spacing: 20) {
            if let favorite = report.favoriteRestaurant {
                posterStory(
                    symbol: favorite.id == report.mostVisitedRestaurant?.id ? "⭐️🔁" : "⭐️",
                    eyebrow: favorite.id == report.mostVisitedRestaurant?.id ? "本月最喜欢 · 最常去" : "本月最喜欢",
                    title: favorite.name, detail: favorite.detail,
                    tone: .ingredientRed
                )
            }
            if let mostVisited = report.mostVisitedRestaurant,
               mostVisited.id != report.favoriteRestaurant?.id {
                posterStory(
                    symbol: "🔁", eyebrow: "本月最常去",
                    title: mostVisited.name, detail: mostVisited.detail,
                    tone: .brand
                )
            }
            if let companion = report.topCompanion {
                posterStory(
                    symbol: "🥢", eyebrow: "本月饭搭子", title: companion.displayName,
                    detail: "一起吃了 \(companion.sharedVisitCount) 次", tone: .leafGreen
                )
            }
            if let source = report.recommendationStory,
               report.topCompanion == nil
                || report.favoriteRestaurant?.id == report.mostVisitedRestaurant?.id {
                posterStory(
                    symbol: source.sourceType.analysisSymbol, eyebrow: "发现来源",
                    title: source.displayName, detail: "带来 \(source.restaurantCount) 家店",
                    tone: source.sourceType.analysisTone
                )
            }
        }
    }

    private var restaurantStrip: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                Text("本月餐桌故事")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(TasteMapAnalysisTheme.ink)
                Spacer()
                Text(posterInsight)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(TasteMapAnalysisTheme.brandDeep)
                    .lineLimit(1).minimumScaleFactor(0.65)
            }
            HStack(spacing: 18) {
                ForEach(Array(report.representativeRestaurants.prefix(3))) { item in
                    VStack(alignment: .leading, spacing: 0) {
                        posterImage(reference: item.imageReference)
                            .frame(height: 208)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.role)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(TasteMapAnalysisTheme.brand)
                            Text(item.name)
                                .font(.system(size: 25, weight: .heavy))
                                .foregroundStyle(TasteMapAnalysisTheme.ink)
                                .lineLimit(2).minimumScaleFactor(0.68)
                            Text(item.detail)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
                                .lineLimit(1)
                        }
                        .padding(18)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(.white, in: RoundedRectangle(cornerRadius: 30))
                    .clipShape(RoundedRectangle(cornerRadius: 30))
                }
            }
        }
    }

    private var posterFooter: some View {
        HStack(spacing: 22) {
            if !report.keywords.isEmpty {
                HStack(spacing: 9) {
                    ForEach(report.keywords.prefix(4), id: \.self) { keyword in
                        Text(keyword)
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(TasteMapAnalysisTheme.brandDeep)
                            .padding(.horizontal, 18).padding(.vertical, 10)
                            .background(TasteMapAnalysisTheme.brandSoft, in: Capsule())
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Text("Taste Map")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(TasteMapAnalysisTheme.ink)
                Text("基于我的真实记录生成")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
            }
        }
        .padding(.horizontal, 58)
    }

    private var shouldShowSpend: Bool {
        report.spend.recordedTotal != nil
            && report.spend.displayState != .lowCoverage
            && report.spend.displayState != .none
    }

    private var heroStatement: String {
        if let highlight = report.highlight { return "最值得记住的是 \(highlight.name)" }
        return "这一页，只写真实发生过的味道"
    }

    private var posterInsight: String {
        if let change = report.tasteChange { return change.title }
        if let source = report.recommendationStory { return "从 \(source.displayName) 发现新味道" }
        return report.keywords.prefix(3).joined(separator: " · ")
    }

    private var posterDivider: some View {
        Rectangle().fill(TasteMapAnalysisTheme.hairline).frame(width: 2, height: 96)
    }

    private func posterMetric(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(spacing: 8) {
            Text(label).font(.system(size: 19, weight: .bold)).foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 43, weight: .heavy, design: .rounded))
                Text(unit).font(.system(size: 20, weight: .bold))
            }
            .foregroundStyle(TasteMapAnalysisTheme.ink)
            .lineLimit(1).minimumScaleFactor(0.62)
        }
        .frame(maxWidth: .infinity)
    }

    private func posterStory(
        symbol: String,
        eyebrow: String,
        title: String,
        detail: String,
        tone: AnalysisTone
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                AnalysisFoodGlyph(
                    symbol: symbol,
                    tone: tone,
                    size: 48,
                    semanticID: eyebrow
                )
                Spacer()
                Circle().fill(TasteMapAnalysisTheme.color(for: tone)).frame(width: 10, height: 10)
            }
            Text(eyebrow).font(.system(size: 17, weight: .bold)).foregroundStyle(TasteMapAnalysisTheme.color(for: tone))
            Text(title).font(.system(size: 29, weight: .heavy)).foregroundStyle(TasteMapAnalysisTheme.ink)
                .lineLimit(2).minimumScaleFactor(0.64)
            Text(detail).font(.system(size: 18, weight: .medium)).foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
        .background(TasteMapAnalysisTheme.softColor(for: tone).opacity(0.72), in: RoundedRectangle(cornerRadius: 30))
    }

    @ViewBuilder
    private func posterImage(reference: AnalysisImageReference) -> some View {
        switch reference {
        case .photo(let id):
            if let image = resolvedImages[id] {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                posterFallback
            }
        case .asset(let name):
            Image(name).resizable().scaledToFill()
        case .none:
            posterFallback
        }
    }

    private var posterFallback: some View {
        ZStack {
            LinearGradient(
                colors: [TasteMapAnalysisTheme.creamSoft, TasteMapAnalysisTheme.brandSoft],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            FoodDiningVisualIcon(
                kind: .genericDining,
                usage: .decorative,
                size: 96,
                foregroundColor: TasteMapAnalysisTheme.brandDeep,
                backgroundColor: .white.opacity(0.72)
            )
        }
    }
}

struct MonthlyRecapPosterSheet: View {
    let report: MonthlyRecapAnalysis
    let photosByID: [UUID: PhotoAsset]

    var body: some View {
        AnalysisPosterExportSheet(
            posterID: report.id,
            requiredFeature: .monthlyRecap,
            progressMessage: "正在把这个月的餐桌排成海报…",
            references: report.photoReferences,
            photosByID: photosByID,
            render: { images in
                try AnalysisPosterRenderer.render(
                    content: MonthlyRecapPosterView(report: report, resolvedImages: images),
                    canvasSize: MonthlyRecapPosterView.canvasSize
                )
            }
        )
    }
}
