import SwiftUI

#if DEBUG
private struct AnnualRecapPreviewHost: View {
    let report: AnnualRecapAnalysis
    var body: some View {
        NavigationStack {
            AnnualRecapAnalysisView(
                report: report,
                availablePeriods: [AnnualRecapPreviewFixtures.currentPeriod, AnnualRecapPreviewFixtures.previousPeriod],
                photosByID: [:], restaurantsByID: [:], onSelectPeriod: { _ in }
            )
        }
    }
}

#Preview("1 · 当前年丰富数据") { AnnualRecapPreviewHost(report: AnnualRecapPreviewFixtures.withAssetImages) }
#Preview("2 · 当前年部分数据") { AnnualRecapPreviewHost(report: AnnualRecapPreviewFixtures.partial) }
#Preview("3 · 完整历史年") { AnnualRecapPreviewHost(report: AnnualRecapPreviewFixtures.past) }
#Preview("4 · 少数据年") { AnnualRecapPreviewHost(report: AnnualRecapPreviewFixtures.sparse) }
#Preview("5 · 空年份") { AnnualRecapPreviewHost(report: AnnualRecapPreviewFixtures.empty) }
#Preview("6 · 高探索年") { AnnualRecapPreviewHost(report: AnnualRecapPreviewFixtures.highExploration) }
#Preview("7 · 高 repeat 年") { AnnualRecapPreviewHost(report: AnnualRecapPreviewFixtures.highRepeat) }
#Preview("8 · 多 cuisine 变化") { AnnualRecapPreviewHost(report: AnnualRecapPreviewFixtures.multiCuisine) }
#Preview("9 · 单一 cuisine") { AnnualRecapPreviewHost(report: AnnualRecapPreviewFixtures.singleCuisine) }
#Preview("10 · 多 Companion") { AnnualRecapPreviewHost(report: AnnualRecapPreviewFixtures.rich) }
#Preview("11 · 无 Companion") { AnnualRecapPreviewHost(report: AnnualRecapPreviewFixtures.noCompanion) }
#Preview("12 · 多 RecommendationSource") { AnnualRecapPreviewHost(report: AnnualRecapPreviewFixtures.rich) }
#Preview("13 · 有最坑来源") { AnnualRecapPreviewHost(report: AnnualRecapPreviewFixtures.rich) }
#Preview("14 · 无法排名来源") { AnnualRecapPreviewHost(report: AnnualRecapPreviewFixtures.insufficientSources) }
#Preview("15 · 高消费覆盖") { AnnualRecapPreviewHost(report: AnnualRecapPreviewFixtures.rich) }
#Preview("16 · 低消费覆盖") { AnnualRecapPreviewHost(report: AnnualRecapPreviewFixtures.lowSpendCoverage) }
#Preview("17 · 多 Photo") { AnnualRecapPreviewHost(report: AnnualRecapPreviewFixtures.withAssetImages) }
#Preview("18 · 无 Photo") { AnnualRecapPreviewHost(report: AnnualRecapPreviewFixtures.noPhoto) }
#Preview("19 · Long Restaurant names") { AnnualRecapPreviewHost(report: AnnualRecapPreviewFixtures.longNames) }
#Preview("20 · Poster rich") {
    AnnualRecapPosterView(report: AnnualRecapPreviewFixtures.withAssetImages, resolvedImages: [:]).scaledToFit()
}
#Preview("21 · Poster sparse") {
    AnnualRecapPosterView(report: AnnualRecapPreviewFixtures.sparse, resolvedImages: [:]).scaledToFit()
}
#Preview("22 · 小屏") {
    AnnualRecapPreviewHost(report: AnnualRecapPreviewFixtures.sparse).frame(width: 320, height: 700)
}
#Preview("23 · 大字体") {
    AnnualRecapPreviewHost(report: AnnualRecapPreviewFixtures.withAssetImages)
        .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
