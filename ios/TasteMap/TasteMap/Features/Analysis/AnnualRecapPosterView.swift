import SwiftUI
import UIKit

struct AnnualRecapPosterView: View {
    static let canvasSize = CGSize(width: 1_080, height: 1_920)
    // An incomplete timeline is a state, not evidence of a particular food
    // preference. Keep its illustration in the shared decorative vocabulary.
    static let emptyJourneyVisualKind: FoodDiningVisualKind = .trend

    let report: AnnualRecapAnalysis
    let resolvedImages: [UUID: UIImage]
    var brandConfiguration = SharePosterBrandConfiguration.current()

    var body: some View {
        ZStack {
            TasteMapAnalysisTheme.canvas
            Circle().fill(TasteMapAnalysisTheme.brandSoft.opacity(0.9))
                .frame(width: 720, height: 720).offset(x: 430, y: -720)
            Circle().fill(TasteMapAnalysisTheme.leafGreenSoft.opacity(0.72))
                .frame(width: 500, height: 500).offset(x: -470, y: 710)
            VStack(spacing: 0) {
                posterHeader.frame(height: 190)
                annualHero.frame(height: 600).padding(.horizontal, 54)
                metricPassport.frame(height: 250).padding(.horizontal, 54).offset(y: -28)
                journeyBand.frame(height: 310).padding(.horizontal, 54).offset(y: -20)
                restaurantStrip.frame(height: 340).padding(.horizontal, 54).offset(y: -8)
                SharePosterBrandFooter(
                    supportingText: footerSupportingText,
                    tagline: "这一年的每一口，都算数",
                    configuration: brandConfiguration
                )
                .frame(height: 110)
                .padding(.horizontal, 54)
            }
        }
        .frame(width: Self.canvasSize.width, height: Self.canvasSize.height)
        .environment(\.colorScheme, .light)
    }

    private var posterHeader: some View {
        HStack(alignment: .center, spacing: 22) {
            ZStack {
                RoundedRectangle(cornerRadius: 24).fill(TasteMapAnalysisTheme.brand)
                Text("TM").font(.system(size: 34, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            }.frame(width: 76, height: 76)
            VStack(alignment: .leading, spacing: 7) {
                Text("TASTE MAP · ANNUAL TASTE JOURNEY")
                    .font(.system(size: 19, weight: .bold)).tracking(2.4).foregroundStyle(TasteMapAnalysisTheme.brand)
                Text(report.periodLabel)
                    .font(.system(size: 40, weight: .heavy, design: .rounded)).foregroundStyle(TasteMapAnalysisTheme.ink)
                    .lineLimit(1).minimumScaleFactor(0.72)
            }
            Spacer()
            Text(report.userDisplayName).font(.system(size: 19, weight: .semibold))
                .foregroundStyle(TasteMapAnalysisTheme.secondaryInk).lineLimit(1).frame(maxWidth: 240, alignment: .trailing)
        }.padding(.horizontal, 54)
    }

    private var annualHero: some View {
        ZStack(alignment: .bottomLeading) {
            posterCollage
            LinearGradient(colors: [.clear, TasteMapAnalysisTheme.ink.opacity(0.88)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 13) {
                Text(report.isCurrentPeriod ? "这一年仍在继续" : "这一年的味觉地图")
                    .font(.system(size: 23, weight: .bold)).opacity(0.88)
                Text("\(report.visitCount) 次 · \(report.restaurantCount) 家餐厅")
                    .font(.system(size: 54, weight: .heavy, design: .rounded)).lineLimit(1).minimumScaleFactor(0.72)
                Text(heroStory).font(.system(size: 25, weight: .semibold)).lineLimit(2).minimumScaleFactor(0.72)
            }.foregroundStyle(.white).padding(42)
        }.clipShape(RoundedRectangle(cornerRadius: 40))
    }

    private var heroStory: String {
        if let favorite = report.favoriteRestaurant, let most = report.mostVisitedRestaurant {
            if favorite.id == most.id {
                return "年度最喜欢 / 最常去：\(favorite.name)"
            }
            return "年度最喜欢：\(favorite.name) · 最常去：\(most.name)"
        }
        if let favorite = report.favoriteRestaurant { return "年度最喜欢：\(favorite.name)" }
        if let most = report.mostVisitedRestaurant { return "年度最常去：\(most.name)" }
        return report.tasteJourney.changeSummaries.first
            ?? "每一次真实到访，都组成了这一年的味觉旅程。"
    }

    private var posterCollage: some View {
        GeometryReader { proxy in
            let stories = report.representativeRestaurants
            if stories.count >= 3 {
                HStack(spacing: 7) {
                    posterImage(stories[0].imageReference).frame(width: proxy.size.width * 0.59).clipped()
                    VStack(spacing: 7) {
                        posterImage(stories[1].imageReference)
                        posterImage(stories[2].imageReference)
                    }.clipped()
                }
            } else if let first = stories.first {
                posterImage(first.imageReference)
            } else { posterFallback }
        }
    }

    private var metricPassport: some View {
        HStack(spacing: 0) {
            posterMetric("去过", "\(report.visitCount)", "次")
            divider
            posterMetric("餐厅", "\(report.restaurantCount)", "家")
            divider
            posterMetric("年度新店", "\(report.newRestaurantCount)", "家")
            if showsSpend {
                divider
                posterMetric(report.spend.displayState == .complete ? "全年消费" : "已记录消费",
                             "¥\(Int((report.spend.recordedTotal ?? 0).rounded()))", "")
            } else {
                divider
                posterMetric("探索倾向", "\(Int((report.explorationRate * 100).rounded()))", "%")
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 30)
        .background(.white, in: AnnualReceiptShape())
        .shadow(color: TasteMapAnalysisTheme.brandDeep.opacity(0.10), radius: 18, y: 9)
    }
    private var divider: some View { Rectangle().fill(TasteMapAnalysisTheme.secondaryInk.opacity(0.16)).frame(width: 1, height: 86) }
    private var showsSpend: Bool {
        report.spend.recordedTotal != nil && report.spend.displayState != .lowCoverage && report.spend.displayState != .none
    }

    private var journeyBand: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("YEAR IN FLAVORS").font(.system(size: 16, weight: .bold)).tracking(2).foregroundStyle(TasteMapAnalysisTheme.brand)
                    Text("年度味觉轨迹").font(.system(size: 32, weight: .heavy, design: .rounded)).foregroundStyle(TasteMapAnalysisTheme.ink)
                }
                Spacer()
                Text(report.tasteJourney.granularity.title).font(.system(size: 18, weight: .bold))
                    .foregroundStyle(TasteMapAnalysisTheme.brandDeep)
            }
            if report.tasteJourney.milestones.isEmpty {
                HStack(spacing: 18) {
                    FoodDiningVisualIcon(
                        kind: Self.emptyJourneyVisualKind,
                        usage: .decorative,
                        size: 48,
                        foregroundColor: TasteMapAnalysisTheme.leafGreen,
                        backgroundColor: TasteMapAnalysisTheme.leafGreenSoft
                    )
                    VStack(alignment: .leading, spacing: 6) {
                        Text("味觉轨迹正在形成").font(.system(size: 25, weight: .heavy)).foregroundStyle(TasteMapAnalysisTheme.ink)
                        Text(keywordLine).font(.system(size: 19, weight: .semibold)).foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 12) {
                    ForEach(Array(report.tasteJourney.milestones.prefix(5))) { milestone in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(milestone.periodLabel).font(.system(size: 16, weight: .bold)).foregroundStyle(TasteMapAnalysisTheme.brand)
                            Text(milestone.title).font(.system(size: 21, weight: .heavy)).foregroundStyle(TasteMapAnalysisTheme.ink)
                                .lineLimit(2).minimumScaleFactor(0.68)
                            Text("\(milestone.visitCount) 次").font(.system(size: 16, weight: .semibold)).foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
                        }
                        .padding(17).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(TasteMapAnalysisTheme.brandSoft.opacity(0.58), in: RoundedRectangle(cornerRadius: 23))
                    }
                }
            }
        }
    }

    private var restaurantStrip: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("这一年的餐桌名片").font(.system(size: 33, weight: .heavy, design: .rounded)).foregroundStyle(TasteMapAnalysisTheme.ink)
                Spacer()
                Text(keywordLine).font(.system(size: 19, weight: .bold)).foregroundStyle(TasteMapAnalysisTheme.brandDeep)
                    .lineLimit(1).minimumScaleFactor(0.58).frame(maxWidth: 430, alignment: .trailing)
            }
            HStack(spacing: 18) {
                ForEach(Array(report.representativeRestaurants.prefix(3))) { item in
                    VStack(alignment: .leading, spacing: 0) {
                        posterImage(item.imageReference).frame(height: 210).clipped()
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.role).font(.system(size: 17, weight: .bold)).foregroundStyle(TasteMapAnalysisTheme.brand)
                            Text(item.name).font(.system(size: 25, weight: .heavy)).foregroundStyle(TasteMapAnalysisTheme.ink)
                                .lineLimit(2).minimumScaleFactor(0.66)
                            Text(item.detail).font(.system(size: 17, weight: .medium)).foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
                                .lineLimit(1).minimumScaleFactor(0.68)
                        }.padding(17)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(.white, in: RoundedRectangle(cornerRadius: 28)).clipShape(RoundedRectangle(cornerRadius: 28))
                }
            }
        }
    }

    private var posterSource: AnnualSourceConclusion? {
        report.recommendationSummary.best ?? report.recommendationSummary.worst ?? report.recommendationSummary.mostUsed
    }
    private var keywordLine: String {
        report.keywords.isEmpty ? "真实记录生成" : report.keywords.prefix(4).joined(separator: " · ")
    }
    private var footerSupportingText: String {
        let companion = report.topCompanion.map { "年度饭搭子 · \($0.displayName)" }
        let source = posterSource.map { "\($0.title) · \($0.displayName)" }
        return [companion, source, keywordLine].compactMap { $0 }.joined(separator: " · ")
    }

    private func posterMetric(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(spacing: 8) {
            Text(label).font(.system(size: 18, weight: .bold)).foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.system(size: value.count > 5 ? 32 : 42, weight: .heavy, design: .rounded))
                Text(unit).font(.system(size: 18, weight: .bold))
            }
            .foregroundStyle(TasteMapAnalysisTheme.ink).lineLimit(1).minimumScaleFactor(0.5)
        }.frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func posterImage(_ reference: AnalysisImageReference) -> some View {
        switch reference {
        case .photo(let id, _):
            if let image = resolvedImages[id] { Image(uiImage: image).resizable().scaledToFill() }
            else { posterFallback }
        case .provider:
            if let key = reference.resolutionKey, let image = resolvedImages[key] {
                Image(uiImage: image).resizable().scaledToFill()
            } else { posterFallback }
        case .asset(let name): Image(name).resizable().scaledToFill()
        case .none: posterFallback
        }
    }
    private var posterFallback: some View {
        ZStack {
            LinearGradient(colors: [TasteMapAnalysisTheme.creamSoft, TasteMapAnalysisTheme.brandSoft], startPoint: .topLeading, endPoint: .bottomTrailing)
            FoodDiningVisualIcon(
                kind: .genericDining,
                usage: .decorative,
                size: 94,
                foregroundColor: TasteMapAnalysisTheme.brandDeep,
                backgroundColor: .white.opacity(0.72)
            )
        }
    }
}

private struct AnnualReceiptShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(); let tooth: CGFloat = 18
        path.move(to: CGPoint(x: 0, y: tooth / 2))
        for x in stride(from: 0, through: rect.width, by: tooth) {
            path.addLine(to: CGPoint(x: x + tooth / 2, y: 0)); path.addLine(to: CGPoint(x: x + tooth, y: tooth / 2))
        }
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - tooth / 2))
        for x in stride(from: rect.width, through: 0, by: -tooth) {
            path.addLine(to: CGPoint(x: x - tooth / 2, y: rect.height)); path.addLine(to: CGPoint(x: x - tooth, y: rect.height - tooth / 2))
        }
        path.closeSubpath(); return path
    }
}

struct AnnualRecapPosterSheet: View {
    let report: AnnualRecapAnalysis
    let photosByID: [UUID: PhotoAsset]
    var body: some View {
        AnalysisPosterExportSheet(
            posterID: report.id, requiredFeature: .annualRecap,
            progressMessage: "正在把这一年的味觉旅程排成海报…",
            references: report.photoReferences, photosByID: photosByID,
            render: { images in
                try AnalysisPosterRenderer.render(
                    content: AnnualRecapPosterView(report: report, resolvedImages: images),
                    canvasSize: AnnualRecapPosterView.canvasSize
                )
            }
        )
    }
}
