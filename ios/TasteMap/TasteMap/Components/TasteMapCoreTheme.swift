import SwiftUI
import UIKit

/// Shared visual foundation for the product UI.
///
/// The values mirror the established Web product palette. Analysis pages and
/// exported posters intentionally continue to use `TasteMapAnalysisTheme`.
enum TasteMapCoreTheme {
    static let brand = Color(uiColor: dynamicColor(light: .init(80, 108, 140), dark: .init(142, 167, 192)))
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
    static let cardRadius: CGFloat = 20
    static let compactRadius: CGFloat = 12
    static let pageInset: CGFloat = 16
    static let sectionSpacing: CGFloat = 16

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
                    .stroke(TasteMapCoreTheme.border.opacity(0.9), lineWidth: 1)
            }
            .shadow(
                color: showsShadow ? TasteMapCoreTheme.cardShadow : .clear,
                radius: showsShadow ? 12 : 0,
                y: showsShadow ? 5 : 0
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
        HStack(alignment: .top, spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TasteMapCoreTheme.brand)
                    .frame(width: 32, height: 32)
                    .background(TasteMapCoreTheme.brandSoft, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(TasteMapCoreTheme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
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
        HStack(spacing: 4) {
            ForEach(items) { item in
                Button {
                    withAnimation(.easeOut(duration: 0.16)) { selection = item.option }
                } label: {
                    HStack(spacing: 5) {
                        if let systemImage = item.systemImage {
                            Image(systemName: systemImage).accessibilityHidden(true)
                        }
                        Text(item.title).lineLimit(1)
                    }
                    .font(.subheadline.weight(selection == item.option ? .semibold : .medium))
                    .foregroundStyle(
                        selection == item.option
                            ? TasteMapCoreTheme.brandDeep
                            : TasteMapCoreTheme.textSecondary
                    )
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background(
                        selection == item.option ? TasteMapCoreTheme.surface : .clear,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .shadow(
                        color: selection == item.option ? TasteMapCoreTheme.cardShadow : .clear,
                        radius: 5,
                        y: 2
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
        .padding(4)
        .background(TasteMapCoreTheme.brandSoft, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(TasteMapCoreTheme.border.opacity(0.72))
        }
    }
}

struct TasteMapEmptyState: View {
    let title: String
    let message: String
    let systemImage: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 13) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(TasteMapCoreTheme.brand)
                .frame(width: 54, height: 54)
                .background(TasteMapCoreTheme.brandSoft, in: RoundedRectangle(cornerRadius: 17))
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .foregroundStyle(TasteMapCoreTheme.textPrimary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(TasteMapCoreTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .tasteMapCoreCard(showsShadow: true)
        .accessibilityElement(children: .contain)
    }
}

#Preview("Core visual foundation") {
    VStack(spacing: 18) {
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
                .init("for-you", title: "适合你"),
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
