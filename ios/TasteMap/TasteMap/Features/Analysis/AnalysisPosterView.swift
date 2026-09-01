import SwiftUI
import UIKit

/// A share-first 9:16 composition. It deliberately does not mirror the scrolling page.
struct AnalysisPosterView: View {
    static let canvasSize = CGSize(width: 1080, height: 1920)

    let report: TasteProfileAnalysis
    var resolvedImages: [UUID: UIImage] = [:]
    var brandConfiguration = SharePosterBrandConfiguration.current()

    var body: some View {
        ZStack {
            TasteMapAnalysisTheme.canvas

            Circle()
                .fill(TasteMapAnalysisTheme.brandSoft.opacity(0.8))
                .frame(width: 720, height: 720)
                .blur(radius: 10)
                .offset(x: 430, y: -790)
            Circle()
                .fill(TasteMapAnalysisTheme.ingredientRedSoft.opacity(0.7))
                .frame(width: 560, height: 560)
                .blur(radius: 18)
                .offset(x: -470, y: 790)

            VStack(alignment: .leading, spacing: 0) {
                posterHeader
                posterHero.padding(.top, 24)
                conclusionStrip.padding(.top, 24)
                keywordStrip.padding(.top, 22)
                restaurantStories.padding(.top, 28)
                Spacer(minLength: 16)
                posterFooter
            }
            .padding(.horizontal, 64)
            .padding(.vertical, 58)
        }
        .frame(width: Self.canvasSize.width, height: Self.canvasSize.height)
        .environment(\.colorScheme, .light)
        .clipped()
        .accessibilityIdentifier("analysis-poster-canvas")
    }

    private var posterHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(report.eyebrow)
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .tracking(4)
                Spacer()
                Label("\(report.visitCount) 次真实到访", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(TasteMapAnalysisTheme.brand)

            Text(report.title)
                .font(.system(size: 62, weight: .heavy, design: .rounded))
                .foregroundStyle(TasteMapAnalysisTheme.ink)
            Text("\(report.userDisplayName) · \(report.sufficiency.title)")
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
            Text(report.summary)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(TasteMapAnalysisTheme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.76)
        }
    }

    private var posterHero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 48, style: .continuous)
                .fill(.white.opacity(0.93))
                .overlay { RoundedRectangle(cornerRadius: 48).stroke(.white, lineWidth: 2) }
                .shadow(color: TasteMapAnalysisTheme.brandDeep.opacity(0.08), radius: 28, y: 15)

            AnalysisConnectorWeb()
                .stroke(
                    TasteMapAnalysisTheme.brand.opacity(0.25),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [9, 12])
                )
                .padding(.horizontal, 170)
                .padding(.vertical, 112)

            PosterHeroMedia(hero: report.hero, resolvedImages: resolvedImages, size: 470)
                .offset(y: 4)

            Text(report.hero.primaryTheme)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(TasteMapAnalysisTheme.brandDeep)
                .lineLimit(1)
                .padding(.horizontal, 20)
                .padding(.vertical, 11)
                .background(.white.opacity(0.9), in: Capsule())
                .offset(y: 232)

            ForEach(Array(report.callouts.prefix(4).enumerated()), id: \.element.id) { index, callout in
                PosterCalloutCard(callout: callout)
                    .frame(width: 252)
                    .position(calloutPosition(index))
            }
        }
        .frame(height: 660)
    }

    private var conclusionStrip: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("这就是你的味觉线索")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(TasteMapAnalysisTheme.ink)
                Spacer()
                Text("TASTE NOTES")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(TasteMapAnalysisTheme.brand)
            }
            HStack(spacing: 12) {
                ForEach(Array(posterInsights.prefix(4))) { insight in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            AnalysisFoodGlyph(
                                symbol: insight.icon,
                                tone: insight.tone,
                                size: 32,
                                semanticID: insight.id
                            )
                            Text(insight.title)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(TasteMapAnalysisTheme.color(for: insight.tone))
                                .lineLimit(1)
                        }
                        Text(insight.value)
                            .font(.system(size: 19, weight: .heavy, design: .rounded))
                            .foregroundStyle(TasteMapAnalysisTheme.ink)
                            .lineLimit(2)
                            .minimumScaleFactor(0.68)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
            }
        }
    }

    @ViewBuilder
    private var keywordStrip: some View {
        if report.keywords.isEmpty {
            HStack(spacing: 12) {
                FoodDiningVisualIcon(
                    kind: .tag,
                    usage: .dataLinked,
                    size: 34,
                    foregroundColor: TasteMapAnalysisTheme.brandDeep,
                    backgroundColor: TasteMapAnalysisTheme.brandSoft,
                    accessibilityLabel: "口味关键词"
                )
                Text("口味关键词正在形成")
            }
            .font(.system(size: 20, weight: .semibold, design: .rounded))
            .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
        } else {
            HStack(spacing: 10) {
                Text("口味关键词")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(TasteMapAnalysisTheme.brandDeep)
                ForEach(Array(report.keywords.prefix(6)), id: \.self) { keyword in
                    Text(keyword)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(TasteMapAnalysisTheme.brandDeep)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(TasteMapAnalysisTheme.brandSoft, in: Capsule())
                }
            }
        }
    }

    private var restaurantStories: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .firstTextBaseline) {
                Text("代表你的几家店")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(TasteMapAnalysisTheme.ink)
                Spacer()
                Text("RESTAURANT STORIES")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(TasteMapAnalysisTheme.brand)
            }

            if report.restaurants.isEmpty {
                HStack(spacing: 16) {
                    FoodDiningVisualIcon(
                        kind: .genericDining,
                        usage: .decorative,
                        size: 52,
                        foregroundColor: TasteMapAnalysisTheme.brandDeep,
                        backgroundColor: TasteMapAnalysisTheme.brandSoft
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text("代表餐厅还在形成")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("继续保存真实到访，海报会自动收下最能代表你的餐厅故事。")
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            } else {
                HStack(spacing: 16) {
                    ForEach(Array(report.restaurants.prefix(3))) { restaurant in
                        PosterRestaurantCard(
                            restaurant: restaurant,
                            image: image(for: restaurant.imageReference)
                        )
                    }
                }
            }
        }
    }

    private var posterFooter: some View {
        SharePosterBrandFooter(
            supportingText: "真实记录生成 · 不含未记录的猜测",
            tagline: "每一口，都算数",
            configuration: brandConfiguration
        )
    }

    private var posterInsights: [AnalysisInsight] {
        let priorities = ["scene", "source", "companion", "time", "rating", "repeat", "spend", "cuisine"]
        return report.availableInsights.sorted { lhs, rhs in
            (priorities.firstIndex(of: lhs.id) ?? .max) < (priorities.firstIndex(of: rhs.id) ?? .max)
        }
    }

    private func image(for reference: AnalysisImageReference) -> UIImage? {
        if let key = reference.resolutionKey, let image = resolvedImages[key] { return image }
        if case .asset(let name) = reference { return UIImage(named: name) }
        return nil
    }

    private func calloutPosition(_ index: Int) -> CGPoint {
        switch index {
        case 0: CGPoint(x: 160, y: 112)
        case 1: CGPoint(x: 824, y: 112)
        case 2: CGPoint(x: 160, y: 548)
        default: CGPoint(x: 824, y: 548)
        }
    }
}

struct PosterHeroMedia: View {
    let hero: FoodHeroPresentation
    let resolvedImages: [UUID: UIImage]
    let size: CGFloat

    private var images: [UIImage] {
        let values = hero.imageReferences.compactMap { reference -> UIImage? in
            switch reference {
            case .photo(let id, _): resolvedImages[id]
            case .provider: reference.resolutionKey.flatMap { resolvedImages[$0] }
            case .asset(let name): UIImage(named: name)
            case .none: nil
            }
        }
        return values.isEmpty ? [UIImage(named: hero.fallbackAssetName)].compactMap { $0 } : Array(values.prefix(3))
    }

    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(
                colors: [.white, TasteMapAnalysisTheme.creamSoft],
                center: .center,
                startRadius: 65,
                endRadius: size / 2
            ))
            if images.count <= 1, let image = images.first {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(width: size * 0.9, height: size * 0.9).clipShape(Circle())
            } else {
                ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: size * 0.55, height: size * 0.55)
                        .clipShape(Circle()).overlay { Circle().stroke(.white, lineWidth: 12) }
                        .offset(collageOffset(index))
                }
            }
        }
        .frame(width: size, height: size)
    }

    private func collageOffset(_ index: Int) -> CGSize {
        switch index {
        case 0: CGSize(width: -size * 0.15, height: -size * 0.12)
        case 1: CGSize(width: size * 0.17, height: size * 0.03)
        default: CGSize(width: -size * 0.02, height: size * 0.22)
        }
    }
}

struct PosterCalloutCard: View {
    let callout: AnalysisCallout

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                AnalysisFoodGlyph(
                    symbol: callout.icon,
                    tone: callout.tone,
                    size: 36,
                    semanticID: callout.id
                )
                Text(callout.title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
            }
            Text(callout.value)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(callout.sufficiency == .insufficient
                    ? TasteMapAnalysisTheme.secondaryInk : TasteMapAnalysisTheme.ink)
                .lineLimit(2).minimumScaleFactor(0.68)
            Text(callout.detail)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
                .lineLimit(2)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
        .background(.white.opacity(0.97), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(alignment: .leading) {
            Capsule().fill(TasteMapAnalysisTheme.color(for: callout.tone))
                .frame(width: 6).padding(.vertical, 18)
        }
        .shadow(color: TasteMapAnalysisTheme.brandDeep.opacity(0.1), radius: 14, y: 7)
    }
}

struct PosterRestaurantCard: View {
    let restaurant: RepresentativeRestaurant
    let image: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    ZStack {
                        LinearGradient(
                            colors: [TasteMapAnalysisTheme.creamSoft, TasteMapAnalysisTheme.brandSoft],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        FoodDiningVisualIcon(
                            kind: .genericDining,
                            usage: .decorative,
                            size: 62,
                            foregroundColor: TasteMapAnalysisTheme.brandDeep,
                            backgroundColor: .white.opacity(0.7)
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity).frame(height: 148).clipped()

            VStack(alignment: .leading, spacing: 5) {
                Text(restaurant.role)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(TasteMapAnalysisTheme.brand)
                Text(restaurant.name)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(TasteMapAnalysisTheme.ink)
                    .lineLimit(2).minimumScaleFactor(0.72)
                Text(restaurant.detail)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
                    .lineLimit(2)
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, minHeight: 258, maxHeight: 258, alignment: .top)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: TasteMapAnalysisTheme.brandDeep.opacity(0.08), radius: 13, y: 7)
    }
}

#if DEBUG
#Preview("9:16 分享海报 · 完整") {
    ScrollView([.horizontal, .vertical]) {
        AnalysisPosterView(report: TasteProfilePreviewFixtures.rich)
            .scaleEffect(0.3, anchor: .topLeading)
            .frame(
                width: AnalysisPosterView.canvasSize.width * 0.3,
                height: AnalysisPosterView.canvasSize.height * 0.3,
                alignment: .topLeading
            )
    }
    .background(Color.gray.opacity(0.12))
}

#Preview("9:16 分享海报 · 数据较少") {
    ScrollView([.horizontal, .vertical]) {
        AnalysisPosterView(report: TasteProfilePreviewFixtures.sparse)
            .scaleEffect(0.3, anchor: .topLeading)
            .frame(
                width: AnalysisPosterView.canvasSize.width * 0.3,
                height: AnalysisPosterView.canvasSize.height * 0.3,
                alignment: .topLeading
            )
    }
}
#endif
