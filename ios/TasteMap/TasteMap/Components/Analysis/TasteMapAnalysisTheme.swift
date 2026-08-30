import SwiftUI
import UIKit

/// Shared visual language for in-app analysis and share-first poster compositions.
/// In-app surfaces resolve semantically in Dark Mode. Exported poster roots explicitly
/// force Light Mode, so their established warm-white composition remains deterministic.
enum TasteMapAnalysisTheme {
    static let brand = Color(red: 0.03, green: 0.56, blue: 0.97)
    static let brandDeep = Color(red: 0.02, green: 0.35, blue: 0.69)
    static let brandSoft = dynamic(light: .init(232, 247, 255), dark: .init(28, 48, 62))
    static let canvas = TasteMapCoreTheme.page
    static let card = TasteMapCoreTheme.surface
    static let ink = TasteMapCoreTheme.textPrimary
    static let secondaryInk = TasteMapCoreTheme.textSecondary
    static let ingredientRed = Color(red: 0.88, green: 0.30, blue: 0.27)
    static let ingredientRedSoft = dynamic(light: .init(255, 235, 230), dark: .init(64, 38, 37))
    static let leafGreen = Color(red: 0.25, green: 0.60, blue: 0.38)
    static let leafGreenSoft = dynamic(light: .init(232, 247, 232), dark: .init(34, 55, 40))
    static let cream = Color(red: 0.96, green: 0.88, blue: 0.70)
    static let creamSoft = dynamic(light: .init(255, 247, 227), dark: .init(58, 50, 34))
    static let caramel = Color(red: 0.70, green: 0.43, blue: 0.25)
    static let caramelSoft = dynamic(light: .init(247, 232, 217), dark: .init(60, 46, 37))
    static let hairline = TasteMapCoreTheme.border

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

    var body: some View {
        Text(symbol)
            .font(.system(size: size * 0.48))
            .frame(width: size, height: size)
            .background(TasteMapAnalysisTheme.softColor(for: tone), in: Circle())
            .overlay {
                Circle().stroke(TasteMapAnalysisTheme.color(for: tone).opacity(0.14), lineWidth: 1)
            }
            .accessibilityHidden(true)
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
            if case .photo(let id) = reference { return photosByID[id] != nil }
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
        case .photo(let id):
            if let photo = photosByID[id] {
                PhotoAssetImageView(photo: photo, variant: .display)
            } else {
                fallback
            }
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

struct RestaurantEvidenceImage: View {
    let reference: AnalysisImageReference
    let photosByID: [UUID: PhotoAsset]
    var height: CGFloat = 150

    var body: some View {
        Group {
            switch reference {
            case .photo(let id):
                if let photo = photosByID[id] {
                    PhotoAssetImageView(photo: photo, variant: .thumbnail)
                } else {
                    missingImage
                }
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
                Text("🍽️").font(.title2)
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

                placeSetting(symbol: "🥢", label: shortName(userDisplayName), tone: .brand)
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

    private func placeSetting(symbol: String, label: String, tone: AnalysisTone) -> some View {
        VStack(spacing: 7) {
            Text(symbol)
                .font(.system(size: 30))
                .frame(width: 68, height: 68)
                .background(TasteMapAnalysisTheme.softColor(for: tone), in: Circle())
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
