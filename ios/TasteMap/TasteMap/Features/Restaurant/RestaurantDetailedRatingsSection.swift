import SwiftUI

struct RestaurantDetailedRatingsSection: View {
    let summaries: [RatingSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("我的详细评分", systemImage: "star.bubble.fill")
                    .font(.title3.bold())
                Spacer()
                if !summaries.isEmpty {
                    Text("按真实到访统计")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if summaries.isEmpty {
                Label("还没有记录详细评分", systemImage: "fork.knife.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                ForEach(Array(summaries.enumerated()), id: \.element.id) { index, summary in
                    if index > 0 { Divider() }
                    HStack(spacing: 12) {
                        Image(systemName: summary.dimension.systemImage)
                            .foregroundStyle(.tint)
                            .frame(width: 30, height: 30)
                            .background(Color.accentColor.opacity(0.1), in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(summary.dimension.title)
                                .font(.subheadline.weight(.semibold))
                            Text("\(summary.count) 次有效评分 · 最近 \(summary.latest, format: .number.precision(.fractionLength(1)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(summary.average, format: .number.precision(.fractionLength(1)))
                            .font(.title3.bold())
                            .foregroundStyle(.orange)
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "\(summary.dimension.title)平均 \(String(format: "%.1f", summary.average)) 星，\(summary.count) 次有效评分"
                    )
                    .accessibilityIdentifier("restaurant-detailed-rating-\(summary.dimension.rawValue)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 22))
    }
}
