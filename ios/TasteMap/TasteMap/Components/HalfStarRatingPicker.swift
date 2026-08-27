import SwiftUI

struct HalfStarRatingPicker: View {
    @Binding var rating: Double?
    var accessibilityName: String? = nil
    var accessibilityIdentifier = "visit-overall-rating"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                ForEach(1...5, id: \.self) { starIndex in
                    star(for: starIndex)
                }
            }

            HStack {
                Text(rating.map { String(format: "%.1f", $0) } ?? "未评分")
                    .foregroundStyle(rating == nil ? .secondary : .primary)
                Spacer()
                if rating != nil {
                    Button("清除评分") { rating = nil }
                        .font(.subheadline)
                        .accessibilityLabel(accessibilityName.map { "清除\($0)评分" } ?? "清除评分")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func star(for index: Int) -> some View {
        let value = rating ?? 0
        let symbolName: String
        if value >= Double(index) {
            symbolName = "star.fill"
        } else if value >= Double(index) - 0.5 {
            symbolName = "star.leadinghalf.filled"
        } else {
            symbolName = "star"
        }

        return ZStack {
            Image(systemName: symbolName)
                .font(.title2)
                .foregroundStyle(.orange)
                .frame(width: 44, height: 44)

            HStack(spacing: 0) {
                Button {
                    rating = Double(index) - 0.5
                } label: {
                    Color.clear
                        .frame(width: 22, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    accessibilityLabel(for: Double(index) - 0.5)
                )

                Button {
                    rating = Double(index)
                } label: {
                    Color.clear
                        .frame(width: 22, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel(for: Double(index)))
            }
        }
        .frame(width: 44, height: 44)
    }

    private func accessibilityLabel(for value: Double) -> String {
        let ratingText = "\(String(format: "%.1f", value)) 星"
        return accessibilityName.map { "\($0) \(ratingText)" } ?? ratingText
    }
}
