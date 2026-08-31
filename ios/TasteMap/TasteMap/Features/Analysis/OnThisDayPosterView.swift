import SwiftUI
import UIKit

/// A fixed, export-only 1080 × 1920 canvas. It deliberately owns its light
/// palette so device appearance never changes the generated social image.
struct OnThisDayPosterView: View {
    static let canvasSize = CGSize(width: 1_080, height: 1_920)

    let report: OnThisDayReport
    let resolvedImages: [UUID: UIImage]

    private let ink = Color(red: 0.10, green: 0.17, blue: 0.22)
    private let secondary = Color(red: 0.35, green: 0.43, blue: 0.47)
    private let brand = Color(red: 0.17, green: 0.42, blue: 0.56)
    private let canvas = Color(red: 0.985, green: 0.978, blue: 0.955)
    private let cream = Color(red: 0.96, green: 0.91, blue: 0.79)
    private let leaf = Color(red: 0.79, green: 0.88, blue: 0.77)

    var body: some View {
        ZStack {
            canvas
            Circle().fill(cream.opacity(0.72)).frame(width: 520, height: 520)
                .offset(x: 420, y: -730)
            Circle().fill(leaf.opacity(0.45)).frame(width: 440, height: 440)
                .offset(x: -480, y: 760)
            VStack(alignment: .leading, spacing: 42) {
                header
                hero
                memoryStrip
                footer
            }
            .padding(.horizontal, 72)
            .padding(.vertical, 76)
        }
        .frame(width: Self.canvasSize.width, height: Self.canvasSize.height)
        .environment(\.colorScheme, .light)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("TASTE MAP · ON THIS DAY")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .tracking(4)
                    .foregroundStyle(brand)
                Spacer()
                Text("\(report.month) 月 \(report.day) 日")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(brand)
            }
            Text("往年的今天，\n我吃过这些。")
                .font(.system(size: 76, weight: .heavy, design: .rounded))
                .foregroundStyle(ink)
                .lineSpacing(6)
            Text("\(report.groups.count) 个年份 · \(report.memories.count) 次真实到访")
                .font(.system(size: 30, weight: .medium, design: .rounded))
                .foregroundStyle(secondary)
        }
    }

    private var hero: some View {
        let first = report.memories.first
        return ZStack(alignment: .bottomLeading) {
            posterImage(reference: first?.imageReference ?? .none)
                .frame(height: 470)
                .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
            LinearGradient(
                colors: [.clear, ink.opacity(0.84)],
                startPoint: .center,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
            VStack(alignment: .leading, spacing: 10) {
                Text(first.map { "\($0.yearsAgo) 年前" } ?? "味觉回忆")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(cream)
                Text(first?.restaurantName ?? "那年今日")
                    .font(.system(size: 48, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let first, !first.dishNames.isEmpty {
                    Text(first.dishNames.prefix(3).joined(separator: " · "))
                        .font(.system(size: 27, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                }
            }
            .padding(42)
        }
        .frame(height: 470)
    }

    private var memoryStrip: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("记忆切片")
                .font(.system(size: 35, weight: .heavy, design: .rounded))
                .foregroundStyle(ink)
            HStack(alignment: .top, spacing: 20) {
                ForEach(Array(report.memories.prefix(3))) { memory in
                    VStack(alignment: .leading, spacing: 14) {
                        posterImage(reference: memory.imageReference)
                            .frame(height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        Text(String(memory.year))
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(brand)
                        Text(memory.restaurantName)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(ink)
                            .lineLimit(2)
                        Text(memoryCaption(memory))
                            .font(.system(size: 20, weight: .medium, design: .rounded))
                            .foregroundStyle(secondary)
                            .lineLimit(2)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, minHeight: 365, alignment: .topLeading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                }
            }
        }
    }

    private var footer: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text(report.memories.count > 3 ? "还有 \(report.memories.count - 3) 段记忆，留在 Taste Map 里。" : "每一次认真记录，都会成为未来的味觉坐标。")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(secondary)
                Text("仅来自我的私密到访记录")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundStyle(secondary.opacity(0.8))
            }
            Spacer()
            HStack(spacing: 14) {
                Image(systemName: "mappin.and.ellipse")
                Text("Taste Map")
            }
            .font(.system(size: 30, weight: .heavy, design: .rounded))
            .foregroundStyle(brand)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func posterImage(reference: AnalysisImageReference) -> some View {
        if case .photo(let id) = reference, let image = resolvedImages[id] {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            LinearGradient(
                colors: [cream, leaf.opacity(0.9)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay {
                VStack(spacing: 12) {
                    FoodDiningVisualIcon(
                        kind: .genericDining,
                        usage: .decorative,
                        size: 104,
                        foregroundColor: ink,
                        backgroundColor: .white.opacity(0.55)
                    )
                    Text("一顿值得记住的饭")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(ink.opacity(0.68))
                }
            }
        }
    }

    private func memoryCaption(_ memory: OnThisDayMemory) -> String {
        if !memory.dishNames.isEmpty { return memory.dishNames.prefix(2).joined(separator: " · ") }
        if let rating = memory.rating { return "我的评分 \(String(format: "%.1f", rating))" }
        if !memory.city.isEmpty { return memory.city }
        return "一次真实到访"
    }
}

struct OnThisDayPosterSheet: View {
    let report: OnThisDayReport
    let photosByID: [UUID: PhotoAsset]

    var body: some View {
        AnalysisPosterExportSheet(
            posterID: report.posterID,
            requiredFeature: nil,
            progressMessage: "正在把往年的今天排成海报…",
            references: report.memories.map(\.imageReference),
            photosByID: photosByID,
            render: { images in
                try AnalysisPosterRenderer.render(
                    content: OnThisDayPosterView(report: report, resolvedImages: images),
                    canvasSize: OnThisDayPosterView.canvasSize
                )
            }
        )
    }
}

extension OnThisDayReport {
    var posterID: String {
        let ids = memories.map { $0.id.uuidString.lowercased() }.joined(separator: "-")
        return "on-this-day-\(month)-\(day)-\(ids)"
    }
}
