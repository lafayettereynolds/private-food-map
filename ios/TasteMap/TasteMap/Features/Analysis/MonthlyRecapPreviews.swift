import SwiftUI

#if DEBUG
private struct MonthlyRecapPreviewHost: View {
    let report: MonthlyRecapAnalysis

    var body: some View {
        NavigationStack {
            MonthlyRecapAnalysisView(
                report: report,
                availablePeriods: [MonthlyRecapPreviewFixtures.currentPeriod, MonthlyRecapPreviewFixtures.previousPeriod],
                photosByID: [:], restaurantsByID: [:], onSelectPeriod: { _ in }
            )
        }
    }
}

#Preview("1 · 当前月丰富数据") { MonthlyRecapPreviewHost(report: MonthlyRecapPreviewFixtures.withAssetImages) }
#Preview("2 · 当前月少量数据") { MonthlyRecapPreviewHost(report: MonthlyRecapPreviewFixtures.sparse) }
#Preview("3 · 空月") { MonthlyRecapPreviewHost(report: MonthlyRecapPreviewFixtures.empty) }
#Preview("4 · 过去完整月") { MonthlyRecapPreviewHost(report: MonthlyRecapPreviewFixtures.past) }
#Preview("5 · 有新店") { MonthlyRecapPreviewHost(report: MonthlyRecapPreviewFixtures.rich) }
#Preview("6 · 无新店") { MonthlyRecapPreviewHost(report: MonthlyRecapPreviewFixtures.noNew) }
#Preview("7 · 高 repeat") { MonthlyRecapPreviewHost(report: MonthlyRecapPreviewFixtures.highRepeat) }
#Preview("8 · 多 Companion") { MonthlyRecapPreviewHost(report: MonthlyRecapPreviewFixtures.rich) }
#Preview("9 · 无 Companion") { MonthlyRecapPreviewHost(report: MonthlyRecapPreviewFixtures.noCompanion) }
#Preview("10 · 有 Source") { MonthlyRecapPreviewHost(report: MonthlyRecapPreviewFixtures.rich) }
#Preview("11 · 无 Source") { MonthlyRecapPreviewHost(report: MonthlyRecapPreviewFixtures.noSource) }
#Preview("12 · 有消费") { MonthlyRecapPreviewHost(report: MonthlyRecapPreviewFixtures.rich) }
#Preview("13 · 消费覆盖低") { MonthlyRecapPreviewHost(report: MonthlyRecapPreviewFixtures.lowSpendCoverage) }
#Preview("14 · 有 Taste Change") { MonthlyRecapPreviewHost(report: MonthlyRecapPreviewFixtures.rich) }
#Preview("15 · 无法比较") { MonthlyRecapPreviewHost(report: MonthlyRecapPreviewFixtures.noComparison) }
#Preview("16 · 多 Photo") { MonthlyRecapPreviewHost(report: MonthlyRecapPreviewFixtures.withAssetImages) }
#Preview("17 · 无 Photo") { MonthlyRecapPreviewHost(report: MonthlyRecapPreviewFixtures.noPhoto) }
#Preview("18 · 长 Restaurant 名") { MonthlyRecapPreviewHost(report: MonthlyRecapPreviewFixtures.longNames) }
#Preview("19 · Poster rich") {
    MonthlyRecapPosterView(report: MonthlyRecapPreviewFixtures.withAssetImages, resolvedImages: [:])
        .scaledToFit()
}
#Preview("20 · Poster sparse") {
    MonthlyRecapPosterView(report: MonthlyRecapPreviewFixtures.sparse, resolvedImages: [:])
        .scaledToFit()
}
#Preview("21 · 小屏") {
    MonthlyRecapPreviewHost(report: MonthlyRecapPreviewFixtures.sparse)
        .frame(width: 320, height: 700)
}
#Preview("22 · 大字体") {
    MonthlyRecapPreviewHost(report: MonthlyRecapPreviewFixtures.withAssetImages)
        .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
