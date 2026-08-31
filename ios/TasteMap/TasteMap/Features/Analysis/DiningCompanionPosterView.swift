import SwiftUI
import UIKit

struct DiningCompanionPosterView: View {
    static let canvasSize = CGSize(width: 1080, height: 1920)

    let report: DiningCompanionAnalysis
    var resolvedImages: [UUID: UIImage] = [:]

    var body: some View {
        ZStack {
            TasteMapAnalysisTheme.canvas

            Circle()
                .fill(TasteMapAnalysisTheme.brandSoft.opacity(0.82))
                .frame(width: 700, height: 700)
                .blur(radius: 12)
                .offset(x: 450, y: -790)
            Circle()
                .fill(TasteMapAnalysisTheme.leafGreenSoft.opacity(0.72))
                .frame(width: 570, height: 570)
                .blur(radius: 16)
                .offset(x: -470, y: 760)

            VStack(alignment: .leading, spacing: 0) {
                header
                sharedTable.padding(.top, 24)
                metricStrip.padding(.top, 24)
                keywordStrip.padding(.top, 22)
                restaurantStories.padding(.top, 26)
                nextMeal.padding(.top, 22)
                Spacer(minLength: 12)
                footer
            }
            .padding(.horizontal, 64)
            .padding(.vertical, 58)
        }
        .frame(width: Self.canvasSize.width, height: Self.canvasSize.height)
        .environment(\.colorScheme, .light)
        .clipped()
        .accessibilityIdentifier("companion-poster-canvas")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("DINING COMPANION")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .tracking(4)
                Spacer()
                Label("真实共同到访生成", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(TasteMapAnalysisTheme.brand)

            Text("最佳饭搭子 · 我和 \(report.companionDisplayName)")
                .font(.system(size: 56, weight: .heavy, design: .rounded))
                .foregroundStyle(TasteMapAnalysisTheme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.64)
            Text("\(report.userDisplayName) · \(report.sufficiency.title)")
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
            Text(report.summary)
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .foregroundStyle(TasteMapAnalysisTheme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
        }
    }

    private var sharedTable: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 48, style: .continuous)
                .fill(.white.opacity(0.94))
                .overlay { RoundedRectangle(cornerRadius: 48).stroke(.white, lineWidth: 2) }
                .shadow(color: TasteMapAnalysisTheme.brandDeep.opacity(0.09), radius: 28, y: 15)

            Capsule()
                .fill(TasteMapAnalysisTheme.caramelSoft.opacity(0.78))
                .frame(width: 660, height: 250)
                .offset(y: 22)

            PosterHeroMedia(hero: report.hero, resolvedImages: resolvedImages, size: 430)
                .offset(y: 18)

            posterIdentity(
                name: report.userDisplayName,
                presentation: nil,
                symbol: "🥢",
                tone: .brand
            )
            .position(x: 150, y: 118)

            posterIdentity(
                name: report.companionDisplayName,
                presentation: report.avatar,
                symbol: "🍚",
                tone: .ingredientRed
            )
            .position(x: 838, y: 118)

            HStack(spacing: 12) {
                Text("共享餐桌")
                Circle().fill(TasteMapAnalysisTheme.ingredientRed).frame(width: 7, height: 7)
                Text(report.hero.primaryTheme)
            }
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundStyle(TasteMapAnalysisTheme.brandDeep)
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .background(.white.opacity(0.92), in: Capsule())
            .offset(y: 236)
        }
        .frame(height: 620)
    }

    private func posterIdentity(
        name: String,
        presentation: DiningCompanionAvatarPresentation?,
        symbol: String,
        tone: AnalysisTone
    ) -> some View {
        VStack(spacing: 10) {
            if let presentation {
                DiningCompanionAvatarView(
                    presentation: presentation,
                    displayName: name,
                    size: 112
                )
            } else {
                AnalysisFoodGlyph(
                    symbol: symbol,
                    tone: tone,
                    size: 112,
                    semanticID: "shared-companion"
                )
                .overlay { Circle().stroke(.white, lineWidth: 6) }
            }
            Text(name)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(TasteMapAnalysisTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .frame(width: 190)
        }
    }

    private var metricStrip: some View {
        HStack(spacing: 14) {
            ForEach(Array(report.callouts.prefix(4))) { callout in
                PosterCalloutCard(callout: callout)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var keywordStrip: some View {
        HStack(spacing: 10) {
            Text("共同吃饭关键词")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(TasteMapAnalysisTheme.brandDeep)
            if report.keywords.isEmpty {
                Text("继续记录后形成")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
            } else {
                ForEach(Array(report.keywords.prefix(4)), id: \.self) { keyword in
                    Text(keyword)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(TasteMapAnalysisTheme.brandDeep)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(TasteMapAnalysisTheme.brandSoft, in: Capsule())
                }
            }
        }
    }

    private var restaurantStories: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("共同餐厅故事")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(TasteMapAnalysisTheme.ink)
                Spacer()
                Text("SHARED PLACES")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(TasteMapAnalysisTheme.brand)
            }
            if report.representativeRestaurants.isEmpty {
                HStack(spacing: 14) {
                    FoodDiningVisualIcon(
                        kind: .genericDining,
                        usage: .decorative,
                        size: 58,
                        foregroundColor: TasteMapAnalysisTheme.brandDeep,
                        backgroundColor: TasteMapAnalysisTheme.brandSoft
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text("代表餐厅正在形成")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("海报不会为凑版式复制餐厅或生成假图片。")
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            } else {
                HStack(spacing: 16) {
                    ForEach(Array(report.representativeRestaurants.prefix(3))) { restaurant in
                        PosterRestaurantCard(
                            restaurant: restaurant,
                            image: image(for: restaurant.imageReference)
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var nextMeal: some View {
        if let recommendation = report.recommendations.first {
            HStack(spacing: 16) {
                FoodDiningVisualIcon(
                    kind: .location,
                    usage: .dataLinked,
                    size: 52,
                    foregroundColor: TasteMapAnalysisTheme.brand,
                    backgroundColor: TasteMapAnalysisTheme.brandSoft,
                    accessibilityLabel: "下次餐厅推荐"
                )
                VStack(alignment: .leading, spacing: 5) {
                    Text("下次和 TA 吃")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(TasteMapAnalysisTheme.brand)
                    Text(recommendation.name)
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(TasteMapAnalysisTheme.ink)
                        .lineLimit(1)
                    Text(recommendation.reason)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
                        .lineLimit(2)
                }
                Spacer()
                if !recommendation.city.isEmpty {
                    Text(recommendation.city)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(TasteMapAnalysisTheme.brandDeep)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(TasteMapAnalysisTheme.brandSoft, in: Capsule())
                }
            }
            .padding(20)
            .background(.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(TasteMapAnalysisTheme.brand)
                Image(systemName: "fork.knife")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text("Taste Map")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(TasteMapAnalysisTheme.ink)
                Text("仅基于我记录的共同到访 · 不含 TA 私人历史或私人备注")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
            }
            Spacer()
            Text("一起吃过，才算数")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(TasteMapAnalysisTheme.brand)
        }
    }

    private func image(for reference: AnalysisImageReference) -> UIImage? {
        switch reference {
        case .photo(let id): resolvedImages[id]
        case .asset(let name): UIImage(named: name)
        case .none: nil
        }
    }
}

struct DiningCompanionPosterSheet: View {
    let report: DiningCompanionAnalysis
    let photosByID: [UUID: PhotoAsset]

    var body: some View {
        AnalysisPosterExportSheet(
            posterID: report.id,
            requiredFeature: .companionAnalysis,
            progressMessage: "正在把共同餐桌排成海报…",
            references: report.photoReferences,
            photosByID: photosByID,
            render: { images in
                try AnalysisPosterRenderer.render(
                    content: DiningCompanionPosterView(report: report, resolvedImages: images),
                    canvasSize: DiningCompanionPosterView.canvasSize
                )
            }
        )
    }
}

#if DEBUG
#Preview("饭搭子海报 · 数据完整") {
    ScrollView([.horizontal, .vertical]) {
        DiningCompanionPosterView(report: DiningCompanionPreviewFixtures.rich.analyses[0])
            .scaleEffect(0.3, anchor: .topLeading)
            .frame(
                width: DiningCompanionPosterView.canvasSize.width * 0.3,
                height: DiningCompanionPosterView.canvasSize.height * 0.3,
                alignment: .topLeading
            )
    }
    .background(Color.gray.opacity(0.12))
}

#Preview("饭搭子海报 · 数据不足") {
    ScrollView([.horizontal, .vertical]) {
        DiningCompanionPosterView(report: DiningCompanionPreviewFixtures.singleVisit.analyses[0])
            .scaleEffect(0.3, anchor: .topLeading)
            .frame(
                width: DiningCompanionPosterView.canvasSize.width * 0.3,
                height: DiningCompanionPosterView.canvasSize.height * 0.3,
                alignment: .topLeading
            )
    }
}
#endif
