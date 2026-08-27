import Foundation

struct RestaurantDetailPresentation {
    let activeVisits: [Visit]

    init(restaurantID: UUID, visits: [Visit]) {
        activeVisits = visits
            .filter { $0.restaurantId == restaurantID && $0.deletedAt == nil }
            .sorted { left, right in
                if left.visitedAt == right.visitedAt {
                    return left.createdAt > right.createdAt
                }
                return left.visitedAt > right.visitedAt
            }
    }

    var visitCount: Int { activeVisits.count }

    var averageRating: Double? {
        let ratings = activeVisits.compactMap(\.rating)
        guard !ratings.isEmpty else { return nil }
        return ratings.reduce(0, +) / Double(ratings.count)
    }

    var latestVisit: Visit? { activeVisits.first }

    var totalSpend: Decimal? {
        let values = activeVisits.compactMap(\.myActualSpend)
        guard !values.isEmpty else { return nil }
        return values.reduce(.zero, +)
    }

    var averageSpend: Decimal? {
        let values = activeVisits.compactMap(\.myActualSpend)
        guard !values.isEmpty else { return nil }
        return values.reduce(.zero, +) / Decimal(values.count)
    }
}

enum RestaurantDetailFormatting {
    nonisolated static func currency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = .current
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: value))
            ?? NSDecimalNumber(decimal: value).stringValue
    }

    nonisolated static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.year().month().day())
    }
}
