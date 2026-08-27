import SwiftData
import SwiftUI

struct ProfileView: View {
    @Query private var restaurants: [Restaurant]
    @Query private var visits: [Visit]

    private var visitedRestaurantCount: Int {
        Set(visits.map(\.restaurantId)).count
    }

    private var averageRating: Double? {
        let ratings = visits.compactMap(\.rating)
        guard !ratings.isEmpty else { return nil }
        return ratings.reduce(0, +) / Double(ratings.count)
    }

    private var totalSpend: Decimal? {
        let values = visits.compactMap(\.myActualSpend)
        guard !values.isEmpty else { return nil }
        return values.reduce(Decimal.zero, +)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("我的记录") {
                    LabeledContent("去过的餐厅", value: "\(visitedRestaurantCount)")
                    LabeledContent("到访记录", value: "\(visits.count)")
                    LabeledContent(
                        "我的平均评分",
                        value: averageRating.map { String(format: "%.1f", $0) } ?? "未评分"
                    )
                    if let totalSpend {
                        LabeledContent("累计实际消费", value: Self.currencyString(totalSpend))
                    }
                }

                if restaurants.isEmpty {
                    Section {
                        Text("保存第一次到访后，你的真实记录会显示在这里。")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("我的")
        }
    }

    private static func currencyString(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = .current
        return formatter.string(from: NSDecimalNumber(decimal: value))
            ?? NSDecimalNumber(decimal: value).stringValue
    }
}
