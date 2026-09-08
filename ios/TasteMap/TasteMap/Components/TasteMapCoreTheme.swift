import SwiftUI
import UIKit

/// Shared visual foundation for the product UI.
///
/// The values mirror the established Web product palette. Analysis pages and
/// exported posters intentionally continue to use `TasteMapAnalysisTheme`.
enum TasteMapCoreTheme {
    static let brandUIColor = dynamicColor(light: .init(80, 108, 140), dark: .init(142, 167, 192))
    static let brand = Color(uiColor: brandUIColor)
    static let onBrand = Color(uiColor: dynamicColor(light: .init(255, 255, 255), dark: .init(23, 42, 58)))
    static let brandDeep = Color(uiColor: dynamicColor(light: .init(52, 79, 105), dark: .init(183, 202, 220)))
    static let brandSoft = Color(uiColor: dynamicColor(light: .init(237, 242, 246), dark: .init(34, 47, 59)))

    static let page = Color(uiColor: dynamicColor(light: .init(247, 247, 245), dark: .init(16, 21, 25)))
    static let surface = Color(uiColor: dynamicColor(light: .init(255, 255, 255), dark: .init(27, 34, 40)))
    static let surfaceSubtle = Color(uiColor: dynamicColor(light: .init(248, 250, 252), dark: .init(34, 42, 49)))
    static let border = Color(uiColor: dynamicColor(light: .init(227, 230, 232), dark: .init(58, 69, 79)))
    static let textPrimary = Color(uiColor: dynamicColor(light: .init(23, 42, 58), dark: .init(235, 240, 244)))
    static let textSecondary = Color(uiColor: dynamicColor(light: .init(101, 116, 128), dark: .init(165, 177, 187)))

    static let warmAccent = Color(red: 208 / 255, green: 154 / 255, blue: 99 / 255)
    static let danger = Color(red: 184 / 255, green: 79 / 255, blue: 79 / 255)
    // Compatibility aliases for feature code written before the formal token
    // layer. New shared components should consume `TasteMapDesignTokens`
    // directly so the scale remains explicit and testable.
    static let cardRadius = TasteMapDesignTokens.Radius.card
    static let compactRadius = TasteMapDesignTokens.Radius.compact
    static let pageInset = TasteMapDesignTokens.Layout.pageInset
    static let sectionSpacing = TasteMapDesignTokens.Layout.standardSectionSpacing

    static let cardShadow = Color(uiColor: dynamicColor(
        light: .init(52, 79, 105, alpha: 0.075),
        dark: .init(0, 0, 0, alpha: 0.18)
    ))

    private static func dynamicColor(light: CoreRGB, dark: CoreRGB) -> UIColor {
        UIColor { traits in
            (traits.userInterfaceStyle == .dark ? dark : light).uiColor
        }
    }
}

nonisolated struct CoreRGB: Equatable, Sendable {
    let red: Int
    let green: Int
    let blue: Int
    let alpha: Double

    init(_ red: Int, _ green: Int, _ blue: Int, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    var hex: String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }

    fileprivate var uiColor: UIColor {
        UIColor(
            red: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: alpha
        )
    }
}

nonisolated enum TasteMapCorePaletteContract {
    static let webBrand = CoreRGB(80, 108, 140)
    static let webBrandDeep = CoreRGB(52, 79, 105)
    static let webBackground = CoreRGB(247, 247, 245)
    static let webSurface = CoreRGB(255, 255, 255)
    static let webTextPrimary = CoreRGB(23, 42, 58)
    static let webDivider = CoreRGB(227, 230, 232)
}

nonisolated enum TasteMapCoreDarkPaletteContract {
    static let background = CoreRGB(16, 21, 25)
    static let surface = CoreRGB(27, 34, 40)
    static let textPrimary = CoreRGB(235, 240, 244)
    static let divider = CoreRGB(58, 69, 79)
}

private struct TasteMapCoreCardModifier: ViewModifier {
    let radius: CGFloat
    let padding: CGFloat?
    let showsShadow: Bool

    func body(content: Content) -> some View {
        content
            .padding(padding ?? 0)
            .background(
                TasteMapCoreTheme.surface,
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(
                        TasteMapCoreTheme.border.opacity(0.9),
                        lineWidth: TasteMapDesignTokens.Border.standard
                    )
            }
            .shadow(
                color: showsShadow ? TasteMapCoreTheme.cardShadow : .clear,
                radius: showsShadow ? TasteMapDesignTokens.Shadow.cardRadius : 0,
                y: showsShadow ? TasteMapDesignTokens.Shadow.cardYOffset : 0
            )
    }
}

extension View {
    func tasteMapCoreCard(
        radius: CGFloat = TasteMapCoreTheme.cardRadius,
        padding: CGFloat? = nil,
        showsShadow: Bool = false
    ) -> some View {
        modifier(TasteMapCoreCardModifier(radius: radius, padding: padding, showsShadow: showsShadow))
    }

    func tasteMapCorePage() -> some View {
        background(TasteMapCoreTheme.page.ignoresSafeArea())
            .tint(TasteMapCoreTheme.brand)
    }

    /// Shared compact filtering language used by Map/List and Discovery.
    /// Keeping this token here prevents each feature from inventing a second
    /// pill height, border, active color, or touch target.
    func tasteMapFilterChipStyle(isActive: Bool) -> some View {
        self
            .font(TasteMapDesignTokens.Typography.filterLabel)
            .foregroundStyle(isActive ? Color.white : TasteMapCoreTheme.brandDeep)
            .padding(.horizontal, TasteMapDesignTokens.Control.filterChipHorizontalPadding)
            .frame(height: TasteMapDesignTokens.Control.chipVisibleHeight)
            .background(isActive ? TasteMapCoreTheme.brand : TasteMapCoreTheme.surface, in: Capsule())
            .overlay { Capsule().stroke(isActive ? TasteMapCoreTheme.brand : TasteMapCoreTheme.border) }
            .buttonStyle(.plain)
    }
}

/// Canonical semantics for compact product filters. Feature screens may omit
/// dimensions they do not support, but must not invent a conflicting symbol.
nonisolated enum TasteMapFilterSemantic: String, CaseIterable, Sendable {
    case allFilters
    case city
    case distance
    case rating
    case price
    case visitCount
    case companion
    case cuisine
    case recommendationSource
    case openNow
    case timeWindow
    case sort
    case clear
    case more

    var systemImage: String {
        switch self {
        case .allFilters: "line.3.horizontal.decrease"
        case .city: "building.2.fill"
        case .distance: "ruler"
        case .rating: "star.fill"
        case .price: "receipt"
        case .visitCount: "fork.knife.circle.fill"
        case .companion: "person.2.fill"
        case .cuisine: "menucard.fill"
        case .recommendationSource: "sparkles"
        case .openNow: "clock.badge.checkmark"
        case .timeWindow: "calendar"
        case .sort: "arrow.up.arrow.down"
        case .clear: "xmark"
        case .more: "ellipsis"
        }
    }
}

struct TasteMapFilterChipLabel: View {
    let title: String
    let semantic: TasteMapFilterSemantic
    let isActive: Bool
    var count: Int?

    var body: some View {
        HStack(spacing: TasteMapDesignTokens.Spacing.compact) {
            Image(systemName: semantic.systemImage)
                .accessibilityHidden(true)
            Text(title)
                .lineLimit(1)
            if let count, count > 0 {
                Text("\(count)")
                    .font(TasteMapDesignTokens.Typography.filterBadge)
                    .padding(.horizontal, TasteMapDesignTokens.Spacing.compact)
                    .frame(minHeight: TasteMapDesignTokens.Control.filterBadgeMinimumHeight)
                    .foregroundStyle(isActive ? TasteMapCoreTheme.brandDeep : TasteMapCoreTheme.textSecondary)
                    .background(
                        (isActive ? Color.white : TasteMapCoreTheme.brandSoft).opacity(0.92),
                        in: Capsule()
                    )
                    .accessibilityLabel("\(count) 项")
            }
        }
        .tasteMapFilterChipStyle(isActive: isActive)
        .contentShape(Capsule())
    }
}

/// One canonical chip implementation for Map/List, Discovery and later
/// restaurant collections. The visible pill is compact while its hit target
/// remains at least 44 points.
struct TasteMapFilterChip: View {
    let title: String
    let semantic: TasteMapFilterSemantic
    let isActive: Bool
    var count: Int?
    var accessibilityIdentifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            TasteMapFilterChipLabel(
                title: title,
                semantic: semantic,
                isActive: isActive,
                count: count
            )
        }
        .buttonStyle(TasteMapFilterChipButtonStyle())
        .frame(minHeight: TasteMapDesignTokens.Control.minimumHitTarget)
        .accessibilityLabel(title)
        .accessibilityValue(isActive ? "已启用" : "未启用")
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityIdentifier(accessibilityIdentifier ?? "taste-map-filter-\(semantic.rawValue)")
    }
}

private struct TasteMapFilterChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.84 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Canonical single-row horizontally scrolling filter container.
struct TasteMapFilterBar<Content: View>: View {
    let content: Content
    var horizontalPadding: CGFloat
    var accessibilityIdentifier: String

    init(
        horizontalPadding: CGFloat = TasteMapCoreTheme.pageInset,
        accessibilityIdentifier: String = "taste-map-filter-bar",
        @ViewBuilder content: () -> Content
    ) {
        self.horizontalPadding = horizontalPadding
        self.accessibilityIdentifier = accessibilityIdentifier
        self.content = content()
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TasteMapDesignTokens.Spacing.small) {
                content
            }
            .padding(.horizontal, horizontalPadding)
        }
        .scrollClipDisabled()
        .frame(minHeight: TasteMapDesignTokens.Control.minimumHitTarget)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

/// My Map's three scopes and Discovery's five scopes share this exact visual
/// hierarchy while retaining their own data meanings.
struct TasteMapPrimaryTabBar<Option: Hashable>: View {
    struct Item: Identifiable {
        let option: Option
        let title: String
        var count: Int?
        var accessibilityIdentifier: String?
        var id: String { String(describing: option) }

        init(
            _ option: Option,
            title: String,
            count: Int? = nil,
            accessibilityIdentifier: String? = nil
        ) {
            self.option = option
            self.title = title
            self.count = count
            self.accessibilityIdentifier = accessibilityIdentifier
        }
    }

    @Binding var selection: Option
    let items: [Item]
    var accessibilityIdentifier: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if TasteMapPrimaryTabLayout.resolve(dynamicTypeSize) == .horizontallyScrollable {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: TasteMapDesignTokens.Spacing.small) { tabItems(equalWidth: false) }
                        .padding(.horizontal, TasteMapDesignTokens.Spacing.xSmall)
                }
                .scrollClipDisabled()
            } else {
                HStack(spacing: 0) { tabItems(equalWidth: true) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    @ViewBuilder
    private func tabItems(equalWidth: Bool) -> some View {
            ForEach(items) { item in
                Button {
                    selection = item.option
                } label: {
                    VStack(spacing: 7) {
                        HStack(spacing: 5) {
                            Text(item.title)
                                .font(
                                    selection == item.option
                                        ? TasteMapDesignTokens.Typography.primaryTabSelected
                                        : TasteMapDesignTokens.Typography.primaryTab
                                )
                                .foregroundStyle(
                                    selection == item.option
                                        ? TasteMapCoreTheme.textPrimary
                                        : TasteMapCoreTheme.textSecondary
                                )
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.82)
                                .multilineTextAlignment(.center)
                            if let count = item.count {
                                Text(count.formatted(.number.grouping(.automatic)))
                                    .font(.caption2.weight(.bold))
                                    .monospacedDigit()
                                    .foregroundStyle(
                                        selection == item.option
                                            ? Color.white
                                            : TasteMapCoreTheme.brandDeep
                                    )
                                    .padding(.horizontal, 5)
                                    .frame(minWidth: 18, minHeight: 18)
                                    .background(
                                        selection == item.option
                                            ? TasteMapCoreTheme.brand
                                            : TasteMapCoreTheme.brandSoft,
                                        in: Capsule()
                                    )
                                    .accessibilityHidden(true)
                            }
                        }
                        Capsule()
                            .fill(selection == item.option ? TasteMapCoreTheme.brand : .clear)
                            .frame(height: TasteMapDesignTokens.Control.primaryTabIndicatorHeight)
                    }
                    .frame(
                        minWidth: equalWidth
                            ? 0
                            : TasteMapDesignTokens.Control.primaryTabCompactMinimumWidth,
                        maxWidth: equalWidth ? .infinity : nil,
                        minHeight: TasteMapDesignTokens.Control.primaryTabMinimumHeight
                    )
                    .padding(
                        .horizontal,
                        equalWidth ? 0 : TasteMapDesignTokens.Spacing.small
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    item.count.map { "\(item.title)，\($0) 家餐厅" } ?? item.title
                )
                .accessibilityValue(selection == item.option ? "已选择" : "未选择")
                .accessibilityAddTraits(selection == item.option ? .isSelected : [])
                .accessibilityIdentifier(
                    item.accessibilityIdentifier ?? "\(accessibilityIdentifier)-\(item.title)"
                )
            }
    }
}

nonisolated enum TasteMapPrimaryTabLayout: Equatable, Sendable {
    case equalWidth
    case horizontallyScrollable

    static func resolve(_ dynamicTypeSize: DynamicTypeSize) -> Self {
        dynamicTypeSize.isAccessibilitySize ? .horizontallyScrollable : .equalWidth
    }
}

/// Shared Visit/Activity rating presentation. It never falls back to a
/// Restaurant aggregate rating; callers must pass the activity's own rating.
struct TasteMapActivityRatingBadge: View {
    let rating: Double?
    var prefix = "这次到访"
    var accessibilityIdentifier: String?

    private var score: Double? {
        RestaurantScoreColorPolicy.score(forFivePointRating: rating)
    }

    private var scoreColor: Color {
        let value = RestaurantScoreColorPolicy.color(forFivePointRating: rating)
        return Color(red: value.red, green: value.green, blue: value.blue)
    }

    var body: some View {
        Text(score.map { String(format: "%.1f", $0) } ?? "未评分")
            .font(.system(size: score == nil ? 9 : 14, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(scoreColor)
            .frame(width: 46, height: 46)
            .background(scoreColor.opacity(0.04), in: Circle())
            .overlay { Circle().stroke(scoreColor, lineWidth: 1.5) }
            .accessibilityLabel(score.map { String(format: "\(prefix)评分 %.1f", $0) } ?? "\(prefix)未评分")
            .accessibilityIdentifier(accessibilityIdentifier ?? "taste-map-activity-rating")
    }
}

/// Canonical open feed surface shared by recommendation Activity cards and
/// Community Activity cards. Features supply their authorized content and
/// actions while the feed rhythm and separation remain one product component.
struct TasteMapActivityCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, TasteMapDesignTokens.Spacing.xxxSmall)
            .padding(.vertical, TasteMapDesignTokens.Spacing.regular)
            .overlay(alignment: .bottom) { Divider() }
            .accessibilityElement(children: .contain)
    }
}

/// Complete supplied reasons are readable without opening a second presentation.
struct TasteMapRecommendationReasons: View {
    let reasons: [String]

    private var normalizedReasons: [String] {
        var seen = Set<String>()
        return reasons.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    var body: some View {
          TasteMapEvidenceFlowLayout(spacing: TasteMapDesignTokens.Activity.reasonGap) {
            ForEach(normalizedReasons, id: \.self) { reason in
                Text(reason)
                    .font(TasteMapDesignTokens.Activity.reasonFont)
                    .foregroundStyle(TasteMapCoreTheme.brandDeep)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, TasteMapDesignTokens.Activity.reasonHorizontalInset)
                    .padding(.vertical, TasteMapDesignTokens.Activity.reasonVerticalInset)
                    .background(TasteMapCoreTheme.brand.opacity(0.08), in: RoundedRectangle(cornerRadius: TasteMapDesignTokens.Activity.reasonRadius))
            }
          }
          .accessibilityElement(children: .contain)
          .accessibilityLabel("推荐理由")
    }
}

private struct TasteMapEvidenceFlowLayout: Layout {
    let spacing: CGFloat

    private func layout(width: CGFloat, subviews: Subviews) -> (CGSize, [CGRect]) {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            usedWidth = max(usedWidth, x + size.width)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: usedWidth, height: y + rowHeight), frames)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(width: proposal.width ?? .infinity, subviews: subviews).0
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (_, frames) = layout(width: bounds.width, subviews: subviews)
        for (subview, frame) in zip(subviews, frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }
}

/// Native rendering of the same two-dice Lucide glyph used by React's RestaurantQuickActions (ISC).
struct TasteMapDiceActionGlyph: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                path.addRoundedRect(in: CGRect(x: 2, y: 10, width: 12, height: 12), cornerSize: CGSize(width: 2, height: 2))
                path.move(to: CGPoint(x: 17.92, y: 14))
                path.addLine(to: CGPoint(x: 21.42, y: 10.5))
                path.addCurve(to: CGPoint(x: 21.42, y: 7.5), control1: CGPoint(x: 22.25, y: 9.67), control2: CGPoint(x: 22.25, y: 8.33))
                path.addLine(to: CGPoint(x: 16.42, y: 2.58))
                path.addCurve(to: CGPoint(x: 13.42, y: 2.58), control1: CGPoint(x: 15.59, y: 1.75), control2: CGPoint(x: 14.25, y: 1.75))
                path.addLine(to: CGPoint(x: 10, y: 6))
                for point in [CGPoint(x: 6, y: 18), CGPoint(x: 10, y: 14), CGPoint(x: 15, y: 6), CGPoint(x: 18, y: 9)] {
                    path.move(to: point); path.addLine(to: CGPoint(x: point.x + 0.01, y: point.y))
                }
            }
            .applying(CGAffineTransform(scaleX: geometry.size.width / 24, y: geometry.size.height / 24))
            .stroke(style: StrokeStyle(lineWidth: geometry.size.width / 12, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

struct TasteMapSocialActionLabel: View {
    let systemImage: String
    let count: Int

    var body: some View {
        HStack(spacing: TasteMapDesignTokens.Activity.socialCountGap) {
            Image(systemName: systemImage)
                .font(.system(size: TasteMapDesignTokens.Icon.standard, weight: .regular))
            if count > 0 {
                Text(count, format: .number.notation(.compactName))
                    .font(TasteMapDesignTokens.Activity.socialCountFont)
                    .foregroundStyle(TasteMapCoreTheme.textSecondary)
            }
        }
        .frame(minWidth: TasteMapDesignTokens.Control.minimumHitTarget, minHeight: TasteMapDesignTokens.Control.minimumHitTarget)
        .contentShape(Rectangle())
    }
}

/// The legacy percentage is a match index. Only an approved, validated model
/// target may supply probability; adding owner records alone never enables it.
struct TasteMapRecommendationSignalView: View {
    let matchPercent: Int?
    let probability: TasteMapCalibratedLikeProbabilityDTO?
    @State private var showingExplanation = false

    private var validatedProbability: TasteMapCalibratedLikeProbabilityDTO? {
        probability.flatMap { $0.isDisplayable() ? $0 : nil }
    }
    private var label: String { validatedProbability == nil ? "口味匹配度" : "喜欢概率" }
    private var signalColor: Color {
        let percent: Double?
        if let probability = validatedProbability {
            percent = (probability.value * 100).rounded()
        } else if let matchPercent, (0...100).contains(matchPercent) {
            percent = Double(matchPercent)
        } else {
            percent = nil
        }
        let rgb = RestaurantScoreColorPolicy.color(forTenPointScore: percent.map { $0 / 10 })
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
    private var value: String {
        if let probability = validatedProbability { return "\(Int((probability.value * 100).rounded()))%" }
        guard let matchPercent, (0...100).contains(matchPercent) else { return "积累中" }
        return "\(matchPercent)%"
    }
    private var explanation: String {
        if let probability = validatedProbability {
            return "经校准模型估计的正反馈概率。正反馈定义：\(probability.positiveFeedbackDefinition)。模型 \(probability.modelVersion) · 校准 \(probability.calibrationVersion) · 经过验证的样本 \(probability.validationSampleCount) 条。"
        }
        return "根据已有口味记录计算的匹配指数，不代表喜欢这家餐厅的概率。尚无符合展示条件的经校准概率；记录数量增加不会自动变成喜欢概率。"
    }
    var body: some View {
        Button { showingExplanation = true } label: {
          TasteMapRecommendationMedalArtwork(accent: signalColor, value: value, label: label)
          .frame(width: TasteMapDesignTokens.Activity.recommendationMedalWidth, height: TasteMapDesignTokens.Activity.recommendationMedalHeight)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) \(value)，查看说明")
        .alert(label, isPresented: $showingExplanation) { Button("知道了", role: .cancel) {} } message: { Text(explanation) }
    }
}

/// The same ornamental rosette/ribbon geometry as the shared React signal.
/// It is decoration, not an award or an additional recommendation claim.
private struct TasteMapRecommendationMedalArtwork: View {
    let accent: Color
    let value: String
    let label: String
    private let gold = Gradient(colors: [Color(red: 0.65, green: 0.42, blue: 0.11), Color(red: 0.96, green: 0.84, blue: 0.49), Color(red: 1, green: 0.94, blue: 0.72), Color(red: 0.76, green: 0.55, blue: 0.18), Color(red: 0.94, green: 0.82, blue: 0.48)])

    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 72, y: size.height / 80)
            func polygon(_ points: [CGPoint]) -> Path {
                Path { path in
                    if let first = points.first { path.move(to: first) }
                    for point in points.dropFirst() { path.addLine(to: point) }
                    path.closeSubpath()
                }
            }
            let ribbon = polygon([.init(x: 20, y: 51), .init(x: 12, y: 75), .init(x: 23, y: 70), .init(x: 29, y: 77), .init(x: 35, y: 56)])
            let ribbonRight = polygon([.init(x: 37, y: 56), .init(x: 43, y: 77), .init(x: 49, y: 70), .init(x: 60, y: 75), .init(x: 52, y: 51)])
            context.fill(ribbon, with: .color(Color(red: 0.255, green: 0.345, blue: 0.42)))
            context.fill(ribbonRight, with: .color(Color(red: 0.255, green: 0.345, blue: 0.42)))
            for points in [[CGPoint(x: 25, y: 53), .init(x: 20, y: 71), .init(x: 25, y: 68), .init(x: 29, y: 73), .init(x: 34, y: 57)], [.init(x: 38, y: 57), .init(x: 43, y: 73), .init(x: 47, y: 68), .init(x: 52, y: 71), .init(x: 47, y: 53)]] {
                context.fill(polygon(points), with: .linearGradient(gold, startPoint: .zero, endPoint: .init(x: 72, y: 86)))
            }
            let seal = polygon((0..<144).map { index in
                let angle = Double(index) * .pi / 72 - .pi / 2
                let radius = 30 + 1.6 * cos(Double(index) * .pi / 6)
                return CGPoint(x: 36 + cos(angle) * radius, y: 34 + sin(angle) * radius)
            })
            context.fill(seal, with: .linearGradient(gold, startPoint: .zero, endPoint: .init(x: 72, y: 68)))
            context.stroke(seal, with: .color(.brown.opacity(0.7)), lineWidth: 0.8)
            context.stroke(Path(ellipseIn: CGRect(x: 8.6, y: 6.6, width: 54.8, height: 54.8)), with: .color(Color(red: 1, green: 0.96, blue: 0.8)), lineWidth: 0.8)
            context.fill(Path(ellipseIn: CGRect(x: 11.5, y: 9.5, width: 49, height: 49)), with: .color(Color(red: 1, green: 0.992, blue: 0.96)))
            context.stroke(Path(ellipseIn: CGRect(x: 13.5, y: 11.5, width: 45, height: 45)), with: .color(accent), lineWidth: 1)
            let crown = polygon([.init(x: 30, y: 16), .init(x: 32, y: 21), .init(x: 40, y: 21), .init(x: 42, y: 16), .init(x: 38, y: 18), .init(x: 36, y: 14), .init(x: 34, y: 18)])
            context.fill(crown, with: .color(Color(red: 0.75, green: 0.55, blue: 0.21)))
            context.draw(Text(value).font(.system(size: value == "积累中" ? 12 : value == "100%" ? 13 : 16, weight: .bold)).monospacedDigit().foregroundStyle(accent), at: CGPoint(x: 36, y: 31), anchor: .center)
            context.draw(Text(label).font(.system(size: 7.3, weight: .semibold)).foregroundStyle(Color(red: 0.41, green: 0.35, blue: 0.26)), at: CGPoint(x: 36, y: 43.5), anchor: .center)
        }
        .accessibilityHidden(true)
    }
}

struct TasteMapSectionHeader: View {
    let title: String
    let subtitle: String?
    let systemImage: String?

    init(_ title: String, subtitle: String? = nil, systemImage: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(alignment: .top, spacing: TasteMapDesignTokens.Spacing.medium) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(TasteMapDesignTokens.Typography.selectedControl)
                    .foregroundStyle(TasteMapCoreTheme.brand)
                    .frame(
                        width: TasteMapDesignTokens.Icon.sectionContainer,
                        height: TasteMapDesignTokens.Icon.sectionContainer
                    )
                    .background(
                        TasteMapCoreTheme.brandSoft,
                        in: RoundedRectangle(cornerRadius: TasteMapDesignTokens.Radius.small)
                    )
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: TasteMapDesignTokens.Spacing.xxSmall) {
                Text(title)
                    .font(TasteMapDesignTokens.Typography.sectionTitle)
                    .foregroundStyle(TasteMapCoreTheme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                    .font(TasteMapDesignTokens.Typography.sectionSubtitle)
                        .foregroundStyle(TasteMapCoreTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

struct TasteMapSegmentedControl<Option: Hashable>: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    struct Item: Identifiable {
        let option: Option
        let title: String
        let systemImage: String?
        var id: String { String(describing: option) }

        init(_ option: Option, title: String, systemImage: String? = nil) {
            self.option = option
            self.title = title
            self.systemImage = systemImage
        }
    }

    @Binding var selection: Option
    let items: [Item]
    var accessibilityIdentifier: String?

    var body: some View {
        HStack(spacing: TasteMapDesignTokens.Spacing.xSmall) {
            ForEach(items) { item in
                Button {
                    withAnimation(accessibilityReduceMotion ? nil : .easeOut(duration: 0.16)) {
                        selection = item.option
                    }
                } label: {
                    HStack(spacing: TasteMapDesignTokens.Spacing.compact) {
                        if let systemImage = item.systemImage {
                            Image(systemName: systemImage).accessibilityHidden(true)
                        }
                        Text(item.title).lineLimit(1)
                    }
                    .font(
                        selection == item.option
                            ? TasteMapDesignTokens.Typography.selectedControl
                            : TasteMapDesignTokens.Typography.control
                    )
                    .foregroundStyle(
                        selection == item.option
                            ? TasteMapCoreTheme.brandDeep
                            : TasteMapCoreTheme.textSecondary
                    )
                    .frame(
                        maxWidth: .infinity,
                        minHeight: TasteMapDesignTokens.Control.segmentedVisibleHeight
                    )
                    .background(
                        selection == item.option ? TasteMapCoreTheme.surface : .clear,
                        in: RoundedRectangle(
                            cornerRadius: TasteMapDesignTokens.Radius.small,
                            style: .continuous
                        )
                    )
                    .shadow(
                        color: selection == item.option ? TasteMapCoreTheme.cardShadow : .clear,
                        radius: TasteMapDesignTokens.Shadow.selectedControlRadius,
                        y: TasteMapDesignTokens.Shadow.selectedControlYOffset
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(selection == item.option ? .isSelected : [])
                .accessibilityIdentifier(
                    "\(accessibilityIdentifier ?? "taste-map-segment")-\(item.title)"
                )
            }
        }
        .padding(TasteMapDesignTokens.Spacing.xSmall)
        .background(
            TasteMapCoreTheme.brandSoft,
            in: RoundedRectangle(
                cornerRadius: TasteMapDesignTokens.Radius.control,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: TasteMapDesignTokens.Radius.control,
                style: .continuous
            )
            .stroke(
                TasteMapCoreTheme.border.opacity(0.72),
                lineWidth: TasteMapDesignTokens.Border.standard
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier ?? "taste-map-segment")
    }
}

enum TasteMapEmptyStatePresentation: Sendable {
    case card
    case embedded
}

struct TasteMapEmptyState: View {
    let title: String
    let message: String
    let systemImage: String
    var foodDiningVisualKind: FoodDiningVisualKind? = nil
    var actionTitle: String?
    var action: (() -> Void)?
    var actionAccessibilityIdentifier: String?
    var secondaryActionTitle: String?
    var secondaryAction: (() -> Void)?
    var secondaryActionAccessibilityIdentifier: String?
    var presentation: TasteMapEmptyStatePresentation = .card
    var accessibilityIdentifier: String?

    var body: some View {
        Group {
            switch presentation {
            case .card:
                stateContent
                    .padding(TasteMapDesignTokens.Spacing.xxLarge)
                    .tasteMapCoreCard(showsShadow: true)
            case .embedded:
                stateContent
                    .padding(.horizontal, TasteMapDesignTokens.Spacing.large)
                    .padding(.vertical, TasteMapDesignTokens.Spacing.xxLarge)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier ?? "taste-map-empty-state")
    }

    private var stateContent: some View {
        VStack(spacing: TasteMapDesignTokens.Spacing.stateContent) {
            if let foodDiningVisualKind {
                FoodDiningVisualIcon(
                    kind: foodDiningVisualKind,
                    usage: .decorative,
                    size: TasteMapDesignTokens.Icon.foodEmptyArtwork
                )
            } else {
                Image(systemName: systemImage)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(TasteMapCoreTheme.brand)
                    .frame(
                        width: TasteMapDesignTokens.Icon.emptyContainer,
                        height: TasteMapDesignTokens.Icon.emptyContainer
                    )
                    .background(
                        TasteMapCoreTheme.brandSoft,
                        in: RoundedRectangle(cornerRadius: TasteMapDesignTokens.Radius.emptyArtwork)
                    )
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(TasteMapDesignTokens.Typography.emptyTitle)
                .foregroundStyle(TasteMapCoreTheme.textPrimary)
            Text(message)
                .font(TasteMapDesignTokens.Typography.emptyMessage)
                .foregroundStyle(TasteMapCoreTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier(actionAccessibilityIdentifier ?? "taste-map-empty-primary-action")
            }
            if let secondaryActionTitle, let secondaryAction {
                Button(secondaryActionTitle, action: secondaryAction)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityIdentifier(
                        secondaryActionAccessibilityIdentifier ?? "taste-map-empty-secondary-action"
                    )
            }
        }
    }
}

#Preview("Core visual foundation") {
    VStack(spacing: TasteMapDesignTokens.Spacing.large) {
        TasteMapSectionHeader(
            "你的餐厅",
            subtitle: "低饱和灰蓝、冷白表面与清晰的信息层级",
            systemImage: "fork.knife"
        )
        TasteMapSegmentedControl(
            selection: .constant("visited"),
            items: [
                .init("visited", title: "去过"),
                .init("wishlist", title: "想吃"),
                .init("for-you", title: "推荐"),
            ]
        )
        TasteMapEmptyState(
            title: "还没有餐厅",
            message: "搜索真实餐厅，开始记录你的味觉地图。",
            systemImage: "map"
        )
    }
    .padding()
    .tasteMapCorePage()
}
