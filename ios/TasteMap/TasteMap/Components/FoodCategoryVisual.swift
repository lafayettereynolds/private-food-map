import Foundation
#if !TASTEMAP_HYBRID_BRIDGE_CORE
import SwiftUI
import UIKit
#endif

/// Stable product taxonomy for Restaurant fallback visuals.
/// Raw values are a bridge contract; keep them in sync with FoodCategoryVisual.tsx.
enum FoodCategoryVisualID: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case chinese
    case japaneseKorean
    case western
    case hotpotBBQ
    case noodles
    case cafeBakery
    case drinksDessert
    case seafood
    case fastFood
    case vegetarianLight
    case other
}

enum FoodCategoryVisualResolver {
    private static let matchers: [(FoodCategoryVisualID, [String])] = [
        (.hotpotBBQ, ["火锅", "锅物", "涮", "烧肉", "烤肉", "烧烤", "串烧", "烤串", "bbq", "barbecue", "hotpot"]),
        (.noodles, ["面馆", "面食", "拉面", "拌面", "米线", "米粉", "河粉", "粉店", "饺子", "馄饨", "noodle", "ramen"]),
        (.cafeBakery, ["咖啡", "coffee", "cafe", "烘焙", "面包", "bakery", "brunch", "早午餐"]),
        (.drinksDessert, ["甜品", "甜点", "蛋糕", "冰淇淋", "冰激凌", "奶茶", "茶饮", "饮品", "糖水", "dessert", "boba", "tea shop"]),
        (.seafood, ["海鲜", "鱼生", "生蚝", "龙虾", "螃蟹", "水产", "seafood", "oyster"]),
        (.japaneseKorean, ["日料", "日本料理", "寿司", "刺身", "居酒屋", "韩餐", "韩国料理", "韩式", "石锅", "sushi", "japanese", "korean"]),
        (.western, ["西餐", "意大利", "法餐", "牛排", "披萨", "pizza", "pasta", "steak", "bistro", "western", "italian", "french"]),
        (.fastFood, ["快餐", "汉堡", "炸鸡", "小吃", "简餐", "便当", "burger", "fried chicken", "fast food"]),
        (.vegetarianLight, ["素食", "轻食", "沙拉", "健康餐", "低卡", "vegetarian", "vegan", "salad", "healthy"]),
        (.chinese, ["中餐", "中国菜", "杭帮菜", "江浙菜", "本帮菜", "粤菜", "川菜", "湘菜", "鲁菜", "徽菜", "闽菜", "京菜", "东北菜", "云南菜", "贵州菜", "新疆菜", "火锅店", "餐馆", "chinese"]),
    ]

    static func resolve(name: String, tags: [String] = [], providerCategory: String? = nil) -> FoodCategoryVisualID {
        let value = ([name] + tags + [providerCategory ?? ""])
            .joined(separator: "|")
            .precomposedStringWithCompatibilityMapping
            .lowercased()
        return matchers.first { _, needles in needles.contains { value.contains($0) } }?.0 ?? .other
    }
}

/// Native Apple Color Emoji fallback for Restaurant avatars and Map markers.
/// Explicit non-generic user choices remain authoritative; otherwise the
/// closest name/tag theme wins before the broad category fallback.
enum FoodCategoryEmojiResolver {
    private static let matchers: [(String, [String])] = [
        ("☕️", ["咖啡", "coffee", "cafe", "咖啡馆", "咖啡店"]),
        ("🥩", ["牛排", "steak", "扒房", "烤牛肉"]),
        ("🍕", ["披萨", "pizza", "披萨店"]),
        ("🍝", ["意大利面", "意面", "pasta", "意大利餐"]),
        ("🍣", ["寿司", "刺身", "日料", "日本料理", "sushi", "japanese"]),
        ("🫕", ["火锅", "锅物", "涮锅", "hotpot"]),
        ("🍢", ["烧烤", "烤串", "串烧", "烧鸟", "barbecue", "bbq", "yakitori"]),
        ("🥟", ["饺子", "馄饨", "包子", "小笼", "点心", "早茶", "粤菜", "dim sum", "dumpling"]),
        ("🍜", ["面馆", "面食", "拉面", "拌面", "米线", "米粉", "河粉", "粉店", "ramen", "noodle", "越南菜", "越南粉", "pho"]),
        ("🍛", ["泰国菜", "泰餐", "泰味", "东南亚", "咖喱", "curry", "thai"]),
        ("🦞", ["龙虾", "lobster"]),
        ("🦀", ["螃蟹", "蟹宴", "crab"]),
        ("🦐", ["海鲜", "生蚝", "水产", "seafood", "oyster"]),
        ("🍰", ["甜品", "甜点", "蛋糕", "糖水", "dessert", "cake"]),
        ("🍨", ["冰淇淋", "冰激凌", "gelato", "ice cream"]),
        ("🧋", ["奶茶", "茶饮", "珍珠", "boba", "bubble tea"]),
        ("🥐", ["烘焙", "面包", "bakery", "可颂", "brunch", "早午餐"]),
        ("🍔", ["汉堡", "burger", "快餐"]),
        ("🍗", ["炸鸡", "烤鸡", "鸡排", "fried chicken"]),
        ("🥗", ["素食", "轻食", "沙拉", "健康餐", "低卡", "vegetarian", "vegan", "salad", "healthy"]),
        ("🍳", ["早餐", "早饭", "breakfast"]),
        ("🍵", ["茶馆", "茶室", "茶楼", "抹茶", "tea house", "matcha"]),
        ("🍷", ["酒吧", "红酒", "葡萄酒", "wine", "bistro"]),
        ("🍺", ["啤酒", "精酿", "beer", "taproom"]),
        ("🌶️", ["川菜", "湘菜", "麻辣", "香辣", "川味", "辣子"]),
        ("🍲", ["韩餐", "韩国料理", "韩式", "石锅", "中餐", "中国菜", "杭帮菜", "江浙菜", "本帮菜", "鲁菜", "徽菜", "闽菜", "京菜", "东北菜", "云南菜", "贵州菜", "新疆菜"]),
    ]
    private static let generic: Set<String> = ["🍽️", "🍴"]
    private static let supported = Set(matchers.map(\.0) + ["🌮", "🥘", "🍤", "☕"])

    static func resolve(
        name: String,
        tags: [String] = [],
        providerCategory: String? = nil,
        preferredEmoji: String? = nil,
        fallbackCategory: FoodCategoryVisualID? = nil
    ) -> String {
        let preferred = preferredEmoji?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let preferred, !generic.contains(preferred), supported.contains(preferred) { return preferred }
        let value = ([name] + tags + [providerCategory ?? ""])
            .joined(separator: "|")
            .precomposedStringWithCompatibilityMapping
            .lowercased()
        if let matched = matchers.first(where: { _, needles in needles.contains { value.contains($0) } })?.0 {
            return matched
        }
        return defaultEmoji(for: fallbackCategory ?? FoodCategoryVisualResolver.resolve(
            name: name,
            tags: tags,
            providerCategory: providerCategory
        ))
    }

    static func sanitized(_ value: String, restaurantName: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return supported.contains(trimmed) ? trimmed : resolve(name: restaurantName)
    }

    private static func defaultEmoji(for category: FoodCategoryVisualID) -> String {
        switch category {
        case .chinese: "🍲"
        case .japaneseKorean: "🍣"
        case .western: "🥩"
        case .hotpotBBQ: "🫕"
        case .noodles: "🍜"
        case .cafeBakery: "☕️"
        case .drinksDessert: "🍰"
        case .seafood: "🦐"
        case .fastFood: "🍔"
        case .vegetarianLight: "🥗"
        case .other: "🍽️"
        }
    }
}

#if !TASTEMAP_HYBRID_BRIDGE_CORE
struct FoodCategoryVisual: View {
    let id: FoodCategoryVisualID
    var accessibilityLabel: String = "餐饮分类图示"

    var body: some View {
        GeometryReader { proxy in
            Image(uiImage: FoodCategoryVisualRenderer.image(id: id, size: proxy.size))
                .resizable()
                .interpolation(.high)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("food-category-visual-\(id.rawValue)")
    }
}

enum FoodCategoryVisualRenderer {
    static func image(id: FoodCategoryVisualID, size: CGSize) -> UIImage {
        let target = CGSize(width: max(1, size.width), height: max(1, size.height))
        return UIGraphicsImageRenderer(size: target).image { context in
            let scale = min(target.width, target.height) / 96
            context.cgContext.saveGState()
            context.cgContext.scaleBy(x: scale, y: scale)
            let palette = palette(for: id)
            palette.background.setFill()
            UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 96, height: 96), cornerRadius: 22).fill()
            UIColor.white.withAlphaComponent(0.55).setFill()
            UIBezierPath(ovalIn: CGRect(x: 24, y: 15, width: 15, height: 15)).fill()
            context.cgContext.setStrokeColor(palette.ink.cgColor)
            context.cgContext.setFillColor(palette.accent.withAlphaComponent(0.16).cgColor)
            context.cgContext.setLineWidth(4.2)
            context.cgContext.setLineCap(.round)
            context.cgContext.setLineJoin(.round)
            draw(id, in: context.cgContext)
            context.cgContext.restoreGState()
        }
    }

    private static func draw(_ id: FoodCategoryVisualID, in context: CGContext) {
        func stroke(_ points: [CGPoint], close: Bool = false, fill: Bool = false) {
            guard let first = points.first else { return }
            context.beginPath(); context.move(to: first)
            points.dropFirst().forEach { context.addLine(to: $0) }
            if close { context.closePath() }
            fill ? context.drawPath(using: .fillStroke) : context.strokePath()
        }
        switch id {
        case .chinese:
            stroke([.init(x: 22, y: 38), .init(x: 74, y: 38), .init(x: 69, y: 67), .init(x: 27, y: 67)], close: true, fill: true)
            stroke([.init(x: 31, y: 32), .init(x: 39, y: 27), .init(x: 57, y: 27), .init(x: 65, y: 32)])
            stroke([.init(x: 36, y: 48), .init(x: 60, y: 48)]); stroke([.init(x: 48, y: 25), .init(x: 48, y: 60)])
        case .japaneseKorean:
            context.fillEllipse(in: CGRect(x: 35, y: 40, width: 9, height: 9)); context.strokeEllipse(in: CGRect(x: 35, y: 40, width: 9, height: 9))
            context.fillEllipse(in: CGRect(x: 50, y: 34, width: 11, height: 11)); context.strokeEllipse(in: CGRect(x: 50, y: 34, width: 11, height: 11))
            stroke([.init(x: 20, y: 58), .init(x: 76, y: 58), .init(x: 68, y: 71), .init(x: 48, y: 76), .init(x: 28, y: 71)], close: true, fill: true)
        case .western:
            stroke([.init(x: 29, y: 60), .init(x: 67, y: 60), .init(x: 59, y: 32), .init(x: 37, y: 32)], close: true, fill: true)
            stroke([.init(x: 24, y: 67), .init(x: 72, y: 67)]); stroke([.init(x: 34, y: 44), .init(x: 62, y: 44)])
        case .hotpotBBQ:
            stroke([.init(x: 20, y: 47), .init(x: 76, y: 47), .init(x: 70, y: 66), .init(x: 48, y: 75), .init(x: 26, y: 66)], close: true, fill: true)
            stroke([.init(x: 36, y: 40), .init(x: 34, y: 34), .init(x: 38, y: 29)]); stroke([.init(x: 49, y: 40), .init(x: 46, y: 33), .init(x: 51, y: 25)]); stroke([.init(x: 62, y: 40), .init(x: 60, y: 34), .init(x: 64, y: 29)])
        case .noodles:
            stroke([.init(x: 19, y: 52), .init(x: 77, y: 52), .init(x: 68, y: 69), .init(x: 48, y: 76), .init(x: 28, y: 69)], close: true, fill: true)
            stroke([.init(x: 29, y: 43), .init(x: 38, y: 36), .init(x: 47, y: 42), .init(x: 58, y: 33), .init(x: 68, y: 38)])
        case .cafeBakery:
            stroke([.init(x: 24, y: 34), .init(x: 66, y: 34), .init(x: 66, y: 60), .init(x: 58, y: 73), .init(x: 35, y: 73), .init(x: 24, y: 60)], close: true, fill: true)
            stroke([.init(x: 66, y: 41), .init(x: 76, y: 43), .init(x: 76, y: 53), .init(x: 66, y: 56)])
        case .drinksDessert:
            stroke([.init(x: 31, y: 34), .init(x: 65, y: 34), .init(x: 60, y: 76), .init(x: 36, y: 76)], close: true, fill: true)
            stroke([.init(x: 35, y: 46), .init(x: 61, y: 46)]); stroke([.init(x: 52, y: 34), .init(x: 61, y: 20)])
        case .seafood:
            stroke([.init(x: 21, y: 49), .init(x: 38, y: 36), .init(x: 58, y: 36), .init(x: 70, y: 41), .init(x: 78, y: 32), .init(x: 78, y: 58), .init(x: 70, y: 50), .init(x: 58, y: 62), .init(x: 36, y: 62)], close: true, fill: true)
            context.fillEllipse(in: CGRect(x: 35, y: 42, width: 5, height: 5))
        case .fastFood:
            stroke([.init(x: 27, y: 42), .init(x: 32, y: 31), .init(x: 48, y: 24), .init(x: 64, y: 31), .init(x: 69, y: 42)], close: true, fill: true)
            stroke([.init(x: 22, y: 49), .init(x: 74, y: 49)]); stroke([.init(x: 25, y: 57), .init(x: 71, y: 57), .init(x: 66, y: 74), .init(x: 30, y: 74)], close: true, fill: true)
        case .vegetarianLight:
            context.beginPath(); context.move(to: .init(x: 23, y: 68)); context.addCurve(to: .init(x: 74, y: 26), control1: .init(x: 25, y: 40), control2: .init(x: 48, y: 25)); context.addCurve(to: .init(x: 29, y: 73), control1: .init(x: 72, y: 57), control2: .init(x: 55, y: 74)); context.closePath(); context.drawPath(using: .fillStroke)
            stroke([.init(x: 29, y: 69), .init(x: 67, y: 37)])
        case .other:
            context.fillEllipse(in: CGRect(x: 21, y: 21, width: 54, height: 54)); context.strokeEllipse(in: CGRect(x: 21, y: 21, width: 54, height: 54))
            stroke([.init(x: 34, y: 38), .init(x: 62, y: 38)]); stroke([.init(x: 30, y: 49), .init(x: 66, y: 49)]); stroke([.init(x: 37, y: 60), .init(x: 59, y: 60)])
        }
    }

    private static func palette(for id: FoodCategoryVisualID) -> (background: UIColor, accent: UIColor, ink: UIColor) {
        switch id {
        case .chinese: (hex("FFF0E8"), hex("E85C4A"), hex("8D2F2A"))
        case .japaneseKorean: (hex("FDECEF"), hex("E34D6D"), hex("842641"))
        case .western: (hex("F3EDFF"), hex("7A5BD6"), hex("49328E"))
        case .hotpotBBQ: (hex("FFF0DC"), hex("F07B32"), hex("984619"))
        case .noodles: (hex("FFF4C9"), hex("E5A62B"), hex("845B10"))
        case .cafeBakery: (hex("F4E8DD"), hex("A96F49"), hex("603C28"))
        case .drinksDessert: (hex("FCE9F5"), hex("D85DA5"), hex("853263"))
        case .seafood: (hex("E5F5FA"), hex("329BC0"), hex("16617D"))
        case .fastFood: (hex("FFF0D9"), hex("ED8F2D"), hex("944B11"))
        case .vegetarianLight: (hex("E8F5E4"), hex("61A64E"), hex("356B2A"))
        case .other: (hex("E9F1F4"), hex("588397"), hex("315565"))
        }
    }

    private static func hex(_ value: String) -> UIColor {
        let number = UInt64(value, radix: 16) ?? 0
        return UIColor(red: CGFloat((number >> 16) & 255) / 255, green: CGFloat((number >> 8) & 255) / 255, blue: CGFloat(number & 255) / 255, alpha: 1)
    }
}
#endif
