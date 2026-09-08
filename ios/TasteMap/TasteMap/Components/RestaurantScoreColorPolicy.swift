import Foundation

/// The canonical Restaurant score color contract recovered from the approved
/// Legacy Web presentation. Taste Map stores ratings on a five-point scale;
/// the historical visual language used a ten-point scale, so callers should
/// use `color(forFivePointRating:)` unless their value is already out of ten.
nonisolated struct TasteMapRGBColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    init(hex: UInt32) {
        red = Double((hex >> 16) & 0xff) / 255
        green = Double((hex >> 8) & 0xff) / 255
        blue = Double(hex & 0xff) / 255
    }

    fileprivate init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

nonisolated enum RestaurantScoreColorPolicy {
    static let unrated = TasteMapRGBColor(hex: 0x9ea3a0)

    static func score(forFivePointRating rating: Double?) -> Double? {
        guard let rating, rating.isFinite else { return nil }
        return (rating * 20).rounded() / 10
    }

    static func color(forFivePointRating rating: Double?) -> TasteMapRGBColor {
        color(forTenPointScore: score(forFivePointRating: rating))
    }

    static func color(forTenPointScore score: Double?) -> TasteMapRGBColor {
        guard let score, score.isFinite else { return unrated }
        let range: (minimum: Double, maximum: Double, light: UInt32, deep: UInt32, reverse: Bool)
        switch score {
        case 9...:
            range = (9, 10, 0x46a47b, 0x176f49, false)
        case 7..<9:
            range = (7, 8.9, 0x6594d3, 0x2b5ca9, false)
        case 5..<7:
            range = (5, 6.9, 0x9178bd, 0x644b9f, false)
        case 3..<5:
            range = (3, 4.9, 0xdfa04d, 0xb9650e, false)
        default:
            range = (1, 2.9, 0xcb4650, 0x851522, true)
        }
        let rawProgress = (score - range.minimum) / (range.maximum - range.minimum)
        let clamped = min(1, max(0, rawProgress))
        return mix(
            TasteMapRGBColor(hex: range.light),
            TasteMapRGBColor(hex: range.deep),
            amount: range.reverse ? 1 - clamped : clamped
        )
    }

    private static func mix(
        _ start: TasteMapRGBColor,
        _ end: TasteMapRGBColor,
        amount: Double
    ) -> TasteMapRGBColor {
        if amount <= 0 { return start }
        if amount >= 1 { return end }
        return TasteMapRGBColor(
            red: start.red + (end.red - start.red) * amount,
            green: start.green + (end.green - start.green) * amount,
            blue: start.blue + (end.blue - start.blue) * amount
        )
    }
}
