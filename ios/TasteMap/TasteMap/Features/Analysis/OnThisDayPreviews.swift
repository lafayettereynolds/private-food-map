#if DEBUG
import SwiftUI

nonisolated enum OnThisDayPreviewFixtures {
    static let empty = report([])
    static let oneYear = report([memory(1, year: 2025)])
    static let multipleYears = report([
        memory(2, year: 2025), memory(3, year: 2024), memory(4, year: 2022),
    ])
    static let sameDayMultiple = report([
        memory(5, year: 2025, hour: 20, name: "晚餐小馆"),
        memory(6, year: 2025, hour: 12, name: "午餐面馆"),
    ])
    static let withPhoto = report([
        memory(7, year: 2025, image: .asset(FoodHeroTheme.chinese.assetName)),
    ])
    static let missingPhoto = report([
        memory(8, year: 2025, image: .photo(uuid(999))),
    ])
    static let nilRating = report([memory(9, year: 2025, rating: nil)])
    static let longName = report([
        memory(
            10,
            year: 2025,
            name: "一间名字特别特别长但每年今天仍然会想起来的湖畔季节料理餐厅"
        ),
    ])
    static let longNote = report([
        memory(
            11,
            year: 2025,
            note: "那天从午后一直坐到傍晚，窗外下着很轻的雨。菜一道一道慢慢上来，我们聊了很多后来仍会想起的事情，这是一段用于验证动态字体和长文本布局的真实长度备注。"
        ),
    ])
    static let leapDay: OnThisDayReport = {
        report([memory(12, year: 2024)], month: 2, day: 29, referenceYear: 2028)
    }()

    private static func report(
        _ memories: [OnThisDayMemory],
        month: Int = 8,
        day: Int = 29,
        referenceYear: Int = 2026
    ) -> OnThisDayReport {
        let groups = Dictionary(grouping: memories, by: \.year).map {
            OnThisDayYearGroup(year: $0.key, memories: $0.value)
        }.sorted { $0.year > $1.year }
        return OnThisDayReport(
            referenceDate: date(referenceYear, month, day, 12),
            month: month,
            day: day,
            groups: groups
        )
    }

    private static func memory(
        _ id: Int,
        year: Int,
        hour: Int = 19,
        name: String = "湖畔小馆",
        rating: Double? = 4.5,
        note: String? = "这一顿很值得记住。",
        image: AnalysisImageReference = .none
    ) -> OnThisDayMemory {
        OnThisDayMemory(
            id: uuid(id),
            restaurantID: uuid(100 + id),
            year: year,
            yearsAgo: 2026 - year,
            visitedAt: date(year, 8, 29, hour),
            restaurantName: name,
            city: "杭州",
            rating: rating,
            note: note,
            spend: 188,
            companions: ["小林"],
            recommendationSource: "朋友推荐",
            dishNames: ["龙井虾仁", "东坡肉"],
            imageReference: image
        )
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour)
        )!
    }

    private static func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}

private struct OnThisDayPreviewHost: View {
    let report: OnThisDayReport
    var body: some View {
        NavigationStack {
            OnThisDayAnalysisView(report: report, photosByID: [:], restaurantsByID: [:])
        }
    }
}

#Preview("Empty") { OnThisDayPreviewHost(report: OnThisDayPreviewFixtures.empty) }
#Preview("One previous year") { OnThisDayPreviewHost(report: OnThisDayPreviewFixtures.oneYear) }
#Preview("Multiple years") { OnThisDayPreviewHost(report: OnThisDayPreviewFixtures.multipleYears) }
#Preview("Same day multiple Visits") { OnThisDayPreviewHost(report: OnThisDayPreviewFixtures.sameDayMultiple) }
#Preview("With photo") { OnThisDayPreviewHost(report: OnThisDayPreviewFixtures.withPhoto) }
#Preview("Missing photo") { OnThisDayPreviewHost(report: OnThisDayPreviewFixtures.missingPhoto) }
#Preview("Nil rating") { OnThisDayPreviewHost(report: OnThisDayPreviewFixtures.nilRating) }
#Preview("Long Restaurant name") { OnThisDayPreviewHost(report: OnThisDayPreviewFixtures.longName) }
#Preview("Long note") { OnThisDayPreviewHost(report: OnThisDayPreviewFixtures.longNote) }
#Preview("Feb 29") { OnThisDayPreviewHost(report: OnThisDayPreviewFixtures.leapDay) }
#endif
