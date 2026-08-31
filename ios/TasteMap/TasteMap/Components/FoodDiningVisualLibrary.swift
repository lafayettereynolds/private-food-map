import SwiftUI

/// Taste Map's shared food-and-dining visual vocabulary.
///
/// `decorative` visuals add brand character without claiming a data meaning.
/// `dataLinked` visuals must be selected from the value they label. Keeping the
/// distinction explicit prevents a decorative food symbol from becoming a fake
/// cuisine or preference conclusion.
enum FoodDiningVisualUsage: Sendable {
    case decorative
    case dataLinked
}

enum FoodDiningVisualKind: String, CaseIterable, Sendable {
    case genericDining
    case food
    case drink
    case tableware
    case receipt
    case menu
    case takeaway
    case sharedMeal
    case restaurant
    case rating
    case calendar
    case repeatVisit
    case time
    case photo
    case tag
    case location
    case trend
    case discovery

    var systemImageName: String {
        switch self {
        case .genericDining, .food: "fork.knife"
        case .drink: "cup.and.saucer.fill"
        case .tableware: "fork.knife.circle.fill"
        case .receipt: "receipt"
        case .menu: "menucard.fill"
        case .takeaway: "takeoutbag.and.cup.and.straw.fill"
        case .sharedMeal: "person.2.fill"
        case .restaurant: "building.2.fill"
        case .rating: "star.fill"
        case .calendar: "calendar"
        case .repeatVisit: "arrow.triangle.2.circlepath"
        case .time: "moon.stars.fill"
        case .photo: "photo.fill"
        case .tag: "tag.fill"
        case .location: "mappin.and.ellipse"
        case .trend: "chart.line.uptrend.xyaxis"
        case .discovery: "sparkles"
        }
    }

    var defaultAccessibilityLabel: String {
        switch self {
        case .genericDining: "餐饮"
        case .food: "食物"
        case .drink: "饮品"
        case .tableware: "餐具"
        case .receipt: "消费"
        case .menu: "菜单"
        case .takeaway: "外带"
        case .sharedMeal: "饭搭子"
        case .restaurant: "餐厅"
        case .rating: "评分"
        case .calendar: "日期"
        case .repeatVisit: "再次到访"
        case .time: "用餐时间"
        case .photo: "照片"
        case .tag: "标签"
        case .location: "位置"
        case .trend: "趋势"
        case .discovery: "发现"
        }
    }
}

enum FoodDiningVisualLibrary {
    /// Maps stable product semantics first, then legacy presentation symbols.
    /// Legacy emoji remain accepted as input while older analysis payloads are
    /// migrated; they are never rendered directly by the formal UI.
    static func kind(semanticID: String? = nil, legacySymbol: String? = nil) -> FoodDiningVisualKind {
        let normalizedID = semanticID?.lowercased() ?? ""

        if normalizedID.contains("spend") || normalizedID.contains("expense") || normalizedID.contains("receipt") {
            return .receipt
        }
        if normalizedID.contains("rating") || normalizedID.contains("favorite") {
            return .rating
        }
        if normalizedID.contains("repeat") || normalizedID.contains("return") {
            return .repeatVisit
        }
        if normalizedID.contains("companion") || normalizedID.contains("friend") || normalizedID.contains("together") {
            return .sharedMeal
        }
        if normalizedID.contains("restaurant") || normalizedID.contains("place") {
            return .restaurant
        }
        if normalizedID.contains("photo") || normalizedID.contains("image") {
            return .photo
        }
        if normalizedID.contains("tag") || normalizedID.contains("keyword") {
            return .tag
        }
        if normalizedID.contains("time") || normalizedID.contains("evening") {
            return .time
        }
        if normalizedID.contains("date") || normalizedID.contains("calendar") || normalizedID.contains("recent") {
            return .calendar
        }
        if normalizedID.contains("source") || normalizedID.contains("discover") {
            return .discovery
        }
        if normalizedID.contains("trend") || normalizedID.contains("change") {
            return .trend
        }
        if normalizedID.contains("visit") {
            return .tableware
        }
        if normalizedID.contains("food") || normalizedID.contains("cuisine") || normalizedID.contains("taste") {
            return .food
        }

        switch legacySymbol {
        case "🧾", "💰": return .receipt
        case "⭐️", "⭐": return .rating
        case "🔁": return .repeatVisit
        case "🥢", "👥": return .sharedMeal
        case "📍", "🗺️", "🧭": return .location
        case "📅", "🗓️", "🗓": return .calendar
        case "📸": return .photo
        case "🏷️": return .tag
        case "🌙": return .time
        case "☕️", "☕": return .drink
        case "🍽️", "🍽": return .genericDining
        case "🍲", "🍜", "🍣", "🥩", "🍖": return .food
        case "🥬", "🌶️", "🌶": return .food
        case "📈": return .trend
        default: return .genericDining
        }
    }
}

struct FoodDiningVisualIcon: View {
    let kind: FoodDiningVisualKind
    let usage: FoodDiningVisualUsage
    var size: CGFloat = 44
    var foregroundColor: Color = TasteMapCoreTheme.brand
    var backgroundColor: Color = TasteMapCoreTheme.brandSoft
    var accessibilityLabel: String?

    var body: some View {
        Image(systemName: kind.systemImageName)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .frame(width: size, height: size)
            .background(backgroundColor, in: Circle())
            .overlay {
                Circle().stroke(foregroundColor.opacity(0.14), lineWidth: 1)
            }
            .accessibilityElement(children: .ignore)
            .modifier(FoodDiningAccessibilityModifier(
                usage: usage,
                label: accessibilityLabel ?? kind.defaultAccessibilityLabel
            ))
            .accessibilityIdentifier("food-dining-visual-\(kind.rawValue)")
    }
}

private struct FoodDiningAccessibilityModifier: ViewModifier {
    let usage: FoodDiningVisualUsage
    let label: String

    func body(content: Content) -> some View {
        switch usage {
        case .decorative:
            content.accessibilityHidden(true)
        case .dataLinked:
            content.accessibilityLabel(label)
        }
    }
}
