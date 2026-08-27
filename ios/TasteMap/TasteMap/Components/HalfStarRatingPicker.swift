import SwiftUI

struct HalfStarRatingPicker: View {
    @Binding var rating: Double?

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
                }
            }
        }
        .accessibilityElement(children: .contain)
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
                .frame(width: 40, height: 40)

            HStack(spacing: 0) {
                Button {
                    rating = Double(index) - 0.5
                } label: {
                    Color.clear
                }
                .accessibilityLabel(
                    "\(String(format: "%.1f", Double(index) - 0.5)) 星"
                )

                Button {
                    rating = Double(index)
                } label: {
                    Color.clear
                }
                .accessibilityLabel("\(index) 星")
            }
        }
        .frame(width: 40, height: 40)
    }
}
