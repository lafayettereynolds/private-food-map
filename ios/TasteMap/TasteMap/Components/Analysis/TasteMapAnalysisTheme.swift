import SwiftUI

/// Shared visual language for in-app analysis and share-first poster compositions.
/// These tokens intentionally stay independent from system dark mode because exported
/// posters always use the same warm-white Taste Map canvas.
enum TasteMapAnalysisTheme {
    static let brand = Color(red: 0.03, green: 0.56, blue: 0.97)
    static let brandDeep = Color(red: 0.02, green: 0.35, blue: 0.69)
    static let brandSoft = Color(red: 0.91, green: 0.97, blue: 1.00)
    static let canvas = Color(red: 0.985, green: 0.981, blue: 0.968)
    static let card = Color.white
    static let ink = Color(red: 0.10, green: 0.15, blue: 0.19)
    static let secondaryInk = Color(red: 0.37, green: 0.43, blue: 0.47)
    static let ingredientRed = Color(red: 0.88, green: 0.30, blue: 0.27)
    static let ingredientRedSoft = Color(red: 1.00, green: 0.92, blue: 0.90)
    static let leafGreen = Color(red: 0.25, green: 0.60, blue: 0.38)
    static let leafGreenSoft = Color(red: 0.91, green: 0.97, blue: 0.91)
    static let cream = Color(red: 0.96, green: 0.88, blue: 0.70)
    static let creamSoft = Color(red: 1.00, green: 0.97, blue: 0.89)
    static let caramel = Color(red: 0.70, green: 0.43, blue: 0.25)
    static let caramelSoft = Color(red: 0.97, green: 0.91, blue: 0.85)
    static let hairline = Color(red: 0.89, green: 0.90, blue: 0.88)

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
