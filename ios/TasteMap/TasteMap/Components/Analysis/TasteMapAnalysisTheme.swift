import SwiftUI
import UIKit

/// Testable light-mode values from the previously approved Analysis visual system.
/// Keeping this contract separate from `TasteMapCorePaletteContract` protects the
/// intended Analysis/Core theme boundary from future global restyling.
enum TasteMapAnalysisPaletteContract {
    static let brand = CoreRGB(80, 108, 140)
    static let brandDeep = CoreRGB(52, 79, 105)
    static let canvas = CoreRGB(251, 250, 247)
    static let card = CoreRGB(255, 255, 255)
    static let ink = CoreRGB(36, 49, 60)
    static let secondaryInk = CoreRGB(102, 113, 121)
    static let hairline = CoreRGB(226, 229, 226)
}

/// Shared visual language for in-app analysis and share-first poster compositions.
/// In-app surfaces resolve semantically in Dark Mode. Exported poster roots explicitly
/// force Light Mode, so their established warm-white composition remains deterministic.
enum TasteMapAnalysisTheme {
    // Analysis deliberately has its own warm-white editorial palette. It shares
    // Taste Map's established grey-blue brand, but does not inherit the Core App
    // canvas wholesale; posters and story-led analysis need a distinct identity.
    static let brand = dynamic(light: TasteMapAnalysisPaletteContract.brand, dark: .init(151, 183, 218))
    static let brandDeep = dynamic(light: TasteMapAnalysisPaletteContract.brandDeep, dark: .init(193, 214, 236))
    static let brandSoft = dynamic(light: .init(237, 242, 246), dark: .init(28, 48, 62))
    static let canvas = dynamic(light: TasteMapAnalysisPaletteContract.canvas, dark: .init(18, 20, 22))
    static let card = dynamic(light: TasteMapAnalysisPaletteContract.card, dark: .init(29, 32, 35))
    static let ink = dynamic(light: TasteMapAnalysisPaletteContract.ink, dark: .init(238, 241, 243))
    static let secondaryInk = dynamic(light: TasteMapAnalysisPaletteContract.secondaryInk, dark: .init(173, 181, 187))
    static let ingredientRed = Color(red: 0.88, green: 0.30, blue: 0.27)
    static let ingredientRedSoft = dynamic(light: .init(255, 235, 230), dark: .init(64, 38, 37))
    static let leafGreen = Color(red: 0.25, green: 0.60, blue: 0.38)
    static let leafGreenSoft = dynamic(light: .init(232, 247, 232), dark: .init(34, 55, 40))
    static let cream = Color(red: 0.96, green: 0.88, blue: 0.70)
    static let creamSoft = dynamic(light: .init(255, 247, 227), dark: .init(58, 50, 34))
    static let caramel = Color(red: 0.70, green: 0.43, blue: 0.25)
    static let caramelSoft = dynamic(light: .init(247, 232, 217), dark: .init(60, 46, 37))
    static let hairline = dynamic(light: TasteMapAnalysisPaletteContract.hairline, dark: .init(58, 63, 67))

    private static func dynamic(light: CoreRGB, dark: CoreRGB) -> Color {
        Color(uiColor: UIColor { traits in
            (traits.userInterfaceStyle == .dark ? dark : light).uiColorForAnalysis
        })
    }

    static func color(for tone: AnalysisTone) -> Color {
        switch tone {
        case .brand: brand
        case .ingredientRed: ingredientRed
        case .leafGreen: leafGreen
        case .cream: cream
        case .caramel: caramel
        }
    }

    static func softColor(for tone: AnalysisTone) -> Color {
        switch tone {
        case .brand: brandSoft
        case .ingredientRed: ingredientRedSoft
        case .leafGreen: leafGreenSoft
        case .cream: creamSoft
        case .caramel: caramelSoft
        }
    }
}

private extension CoreRGB {
    var uiColorForAnalysis: UIColor {
        UIColor(
            red: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: alpha
        )
    }
}
struct AnalysisSectionHeader: View {
    let eyebrow: String
    let title: String
    let detail: String?

    init(_ title: String, eyebrow: String, detail: String? = nil) {
        self.eyebrow = eyebrow
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(1.7)
                .foregroundStyle(TasteMapAnalysisTheme.brand)
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(TasteMapAnalysisTheme.ink)
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AnalysisFoodGlyph: View {
    let symbol: String
    let tone: AnalysisTone
    var size: CGFloat = 44
    var semanticID: String? = nil
    var usage: FoodDiningVisualUsage = .dataLinked

    var body: some View {
        FoodDiningVisualIcon(
            kind: FoodDiningVisualLibrary.kind(semanticID: semanticID, legacySymbol: symbol),
            usage: usage,
            size: size,
            foregroundColor: TasteMapAnalysisTheme.color(for: tone),
            backgroundColor: TasteMapAnalysisTheme.softColor(for: tone)
        )
    }
}

struct AnalysisTagFlow: View {
    let tags: [String]

    var body: some View {
        AnalysisFlowLayout(spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TasteMapAnalysisTheme.brandDeep)
                    .lineLimit(1)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .background(TasteMapAnalysisTheme.brandSoft, in: Capsule())
                    .overlay { Capsule().stroke(TasteMapAnalysisTheme.brand.opacity(0.12)) }
            }
        }
    }
}

struct AnalysisFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var width: CGFloat = 0
        var height: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if width > 0, width + spacing + size.width > maxWidth {
                height += rowHeight + spacing
                width = 0
                rowHeight = 0
            }
            width += (width == 0 ? 0 : spacing) + size.width
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : width, height: height + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct AnalysisConnectorWeb: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        for point in [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY),
        ] {
            path.move(to: center)
            path.addQuadCurve(
                to: point,
                control: CGPoint(x: (point.x + center.x) / 2, y: center.y)
            )
        }
        return path
    }
}

struct ReceiptShape: Shape {
    func path(in rect: CGRect) -> Path {
        let tooth: CGFloat = 10
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + tooth / 2))
        var x = rect.minX
        var rises = true
        while x < rect.maxX {
            x = min(x + tooth, rect.maxX)
            path.addLine(to: CGPoint(x: x, y: rect.minY + (rises ? 0 : tooth)))
            rises.toggle()
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - tooth / 2))
        rises = true
        while x > rect.minX {
            x = max(x - tooth, rect.minX)
            path.addLine(to: CGPoint(x: x, y: rect.maxY - (rises ? 0 : tooth)))
            rises.toggle()
        }
        path.closeSubpath()
        return path
    }
}

struct AnalysisHeroMedia: View {
    let hero: FoodHeroPresentation
    let photosByID: [UUID: PhotoAsset]
    var size: CGFloat = 250

    private var visibleReferences: [AnalysisImageReference] {
        let valid = hero.imageReferences.filter { reference in
            if case .photo(let id, let providerFallback) = reference {
                return photosByID[id] != nil || providerFallback != nil
            }
            if case .none = reference { return false }
            return true
        }
        return Array(valid.prefix(3))
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white, TasteMapAnalysisTheme.creamSoft.opacity(0.82)],
                        center: .center,
                        startRadius: 28,
                        endRadius: size / 2
                    )
                )
                .shadow(color: TasteMapAnalysisTheme.brandDeep.opacity(0.11), radius: 22, y: 12)

            if visibleReferences.count <= 1 {
                heroImage(visibleReferences.first ?? .asset(hero.fallbackAssetName))
                    .frame(width: size * 0.9, height: size * 0.9)
                    .clipShape(Circle())
            } else {
                ForEach(Array(visibleReferences.enumerated()), id: \.element) { index, reference in
                    heroImage(reference)
                        .frame(width: size * 0.55, height: size * 0.55)
                        .clipShape(Circle())
                        .overlay { Circle().stroke(.white, lineWidth: size * 0.025) }
                        .offset(collageOffset(index))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("中心食物主视觉：\(hero.primaryTheme)")
    }

    @ViewBuilder
    private func heroImage(_ reference: AnalysisImageReference) -> some View {
        switch reference {
        case .photo, .provider:
            if let resolution = reference.restaurantResolution {
                TasteMapRestaurantImage(
                    resolution: resolution,
                    photosByID: photosByID,
                    semanticID: reference.resolutionKey?.uuidString ?? hero.primaryTheme,
                    variant: .display,
                    fallbackBackgroundColor: TasteMapAnalysisTheme.creamSoft,
                    fallbackIconSize: size * 0.25,
                    accessibilityLabel: "分析餐厅图片"
                )
            } else { fallback }
        case .asset(let name):
            Image(name).resizable().scaledToFit().padding(size * 0.025)
        case .none:
            fallback
        }
    }

    private var fallback: some View {
        Image(hero.fallbackAssetName).resizable().scaledToFit().padding(size * 0.025)
    }

    private func collageOffset(_ index: Int) -> CGSize {
        switch index {
        case 0: CGSize(width: -size * 0.15, height: -size * 0.12)
        case 1: CGSize(width: size * 0.17, height: size * 0.03)
        default: CGSize(width: -size * 0.02, height: size * 0.22)
        }
    }
}

/// Canonical page-level infographic used by the approved historical Analysis
/// family. The center is always a real Restaurant image when one resolves; the
/// Food Hero asset is an honest fallback. The surrounding facts are supplied by
/// the existing owner-scoped analyzers rather than invented for decoration.
struct LegacyAnalysisInfographicHero: View {
    let centerReference: AnalysisImageReference
    let fallbackAssetName: String
    let centerLabel: String
    let callouts: [AnalysisCallout]
    let photosByID: [UUID: PhotoAsset]
    var accessibilityIdentifier: String

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let cardWidth = min(148, width * 0.43)
            ZStack {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [TasteMapAnalysisTheme.card, TasteMapAnalysisTheme.creamSoft.opacity(0.72)],
                            center: .center,
                            startRadius: 34,
                            endRadius: 260
                        )
                    )
                    .overlay { RoundedRectangle(cornerRadius: 34).stroke(TasteMapAnalysisTheme.hairline, lineWidth: 1.5) }
                    .shadow(color: TasteMapAnalysisTheme.brandDeep.opacity(0.08), radius: 20, y: 11)

                AnalysisConnectorWeb()
                    .stroke(
                        TasteMapAnalysisTheme.brand.opacity(0.27),
                        style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [5, 7])
                    )
                    .padding(.horizontal, 54)
                    .padding(.vertical, 70)

                centerImage
                    .frame(width: min(214, width * 0.56), height: min(214, width * 0.56))
                    .clipShape(Circle())
                    .overlay { Circle().stroke(.white, lineWidth: 5) }
                    .shadow(color: TasteMapAnalysisTheme.brandDeep.opacity(0.14), radius: 18, y: 9)
                    .offset(y: 6)

                Text(centerLabel)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(TasteMapAnalysisTheme.brandDeep)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
                    .position(x: width / 2, y: 356)

                ForEach(Array(callouts.prefix(4).enumerated()), id: \.element.id) { index, callout in
                    LegacyInfographicCalloutCard(callout: callout)
                        .frame(width: cardWidth)
                        .position(position(for: index, width: width))
                }
            }
        }
        .frame(height: 430)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    @ViewBuilder
    private var centerImage: some View {
        switch centerReference {
        case .none:
            Image(fallbackAssetName).resizable().scaledToFit().padding(4)
                .background(TasteMapAnalysisTheme.creamSoft)
        default:
            RestaurantEvidenceImage(reference: centerReference, photosByID: photosByID, height: 214)
        }
    }

    private func position(for index: Int, width: CGFloat) -> CGPoint {
        switch index {
        case 0: CGPoint(x: width * 0.23, y: 74)
        case 1: CGPoint(x: width * 0.77, y: 74)
        case 2: CGPoint(x: width * 0.23, y: 360)
        default: CGPoint(x: width * 0.77, y: 360)
        }
    }
}

private struct LegacyInfographicCalloutCard: View {
    let callout: AnalysisCallout

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                AnalysisFoodGlyph(symbol: callout.icon, tone: callout.tone, size: 24, semanticID: callout.id)
                Text(callout.title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
            }
            Text(callout.value)
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(callout.sufficiency == .insufficient
                    ? TasteMapAnalysisTheme.secondaryInk : TasteMapAnalysisTheme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.68)
            Text(callout.detail)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
                .lineLimit(2)
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .background(TasteMapAnalysisTheme.card.opacity(0.96), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .leading) {
            Capsule().fill(TasteMapAnalysisTheme.color(for: callout.tone))
                .frame(width: 4).padding(.vertical, 13)
        }
        .shadow(color: TasteMapAnalysisTheme.brandDeep.opacity(0.09), radius: 10, y: 5)
    }
}

struct RestaurantEvidenceImage: View {
    let reference: AnalysisImageReference
    let photosByID: [UUID: PhotoAsset]
    var height: CGFloat = 150

    var body: some View {
        Group {
            switch reference {
            case .photo, .provider:
                if let resolution = reference.restaurantResolution {
                    TasteMapRestaurantImage(
                        resolution: resolution,
                        photosByID: photosByID,
                        semanticID: reference.resolutionKey?.uuidString ?? "analysis-evidence",
                        fallbackBackgroundColor: TasteMapAnalysisTheme.creamSoft,
                        fallbackIconSize: 42,
                        accessibilityLabel: "代表餐厅图片"
                    )
                } else { missingImage }
            case .asset(let name):
                Image(name).resizable().scaledToFill()
            case .none:
                missingImage
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
    }

    private var missingImage: some View {
        ZStack {
            LinearGradient(
                colors: [TasteMapAnalysisTheme.creamSoft, TasteMapAnalysisTheme.brandSoft],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 5) {
                FoodDiningVisualIcon(
                    kind: .genericDining,
                    usage: .decorative,
                    size: 42,
                    foregroundColor: TasteMapAnalysisTheme.brandDeep,
                    backgroundColor: .white.opacity(0.72)
                )
                Text("暂无真实图片")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
            }
        }
    }
}

struct DiningCompanionAvatarView: View {
    let presentation: DiningCompanionAvatarPresentation
    let displayName: String
    var size: CGFloat = 64

    var body: some View {
        Group {
            switch presentation {
            case .initial(let initial, let tone):
                Text(initial)
                    .font(.system(size: size * 0.4, weight: .heavy, design: .rounded))
                    .foregroundStyle(TasteMapAnalysisTheme.color(for: tone))
                    .frame(width: size, height: size)
                    .background(TasteMapAnalysisTheme.softColor(for: tone), in: Circle())
            case .preset(let preset):
                PresetProfileAvatarView(preset: preset)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            }
        }
        .overlay { Circle().stroke(.white, lineWidth: max(2, size * 0.045)) }
        .shadow(color: TasteMapAnalysisTheme.brandDeep.opacity(0.12), radius: size * 0.12, y: size * 0.06)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(displayName)的饭搭子标识")
    }
}

/// P4-B's food-first visual center: two place settings around one shared table.
struct SharedDiningTableHero: View {
    let userDisplayName: String
    let companionDisplayName: String
    let companionAvatar: DiningCompanionAvatarPresentation
    let hero: FoodHeroPresentation
    let photosByID: [UUID: PhotoAsset]
    var height: CGFloat = 390

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack {
                RoundedRectangle(cornerRadius: 38, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [.white, TasteMapAnalysisTheme.creamSoft.opacity(0.86)],
                            center: .center,
                            startRadius: 40,
                            endRadius: 280
                        )
                    )
                    .overlay { RoundedRectangle(cornerRadius: 38).stroke(.white, lineWidth: 2) }
                    .shadow(color: TasteMapAnalysisTheme.brandDeep.opacity(0.09), radius: 20, y: 12)

                Capsule()
                    .fill(TasteMapAnalysisTheme.caramelSoft.opacity(0.72))
                    .frame(width: width * 0.74, height: 170)
                    .overlay { Capsule().stroke(TasteMapAnalysisTheme.caramel.opacity(0.08)) }
                    .offset(y: 28)

                AnalysisHeroMedia(hero: hero, photosByID: photosByID, size: min(218, width * 0.56))
                    .offset(y: 20)

                placeSetting(label: shortName(userDisplayName), tone: .brand)
                    .position(x: width * 0.19, y: 94)

                VStack(spacing: 7) {
                    DiningCompanionAvatarView(
                        presentation: companionAvatar,
                        displayName: companionDisplayName,
                        size: 68
                    )
                    Text(shortName(companionDisplayName))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TasteMapAnalysisTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .position(x: width * 0.81, y: 94)

                HStack(spacing: 8) {
                    Text("两套餐具")
                    Circle().fill(TasteMapAnalysisTheme.ingredientRed).frame(width: 5, height: 5)
                    Text(hero.primaryTheme)
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(TasteMapAnalysisTheme.brandDeep)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.white.opacity(0.92), in: Capsule())
                .position(x: width / 2, y: height - 38)
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(userDisplayName)和\(companionDisplayName)的共同餐桌")
    }

    private func placeSetting(label: String, tone: AnalysisTone) -> some View {
        VStack(spacing: 7) {
            FoodDiningVisualIcon(
                kind: .tableware,
                usage: .dataLinked,
                size: 68,
                foregroundColor: TasteMapAnalysisTheme.color(for: tone),
                backgroundColor: TasteMapAnalysisTheme.softColor(for: tone),
                accessibilityLabel: "你的餐具"
            )
            .overlay { Circle().stroke(.white, lineWidth: 3) }
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(TasteMapAnalysisTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    private func shortName(_ value: String) -> String {
        value.count > 10 ? String(value.prefix(10)) + "…" : value
    }
}
