import SwiftUI

enum TasteMapRatingFilterOptions {
    nonisolated static let thresholdsOutOfTen = (1...10).map(Double.init)
    nonisolated static let discoveryThresholdsOutOfTen = (thresholdsOutOfTen + [7.5]).sorted()

    nonisolated static func label(for score: Double) -> String {
        let text = score.rounded() == score ? String(Int(score)) : String(format: "%.1f", score)
        return score == 10 ? "10 分" : "\(text) 分以上"
    }
}

struct TasteMapRatingInput: View {
    let dimension: RatingDimension
    @Binding var rating: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(dimension.title, systemImage: dimension.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            HalfStarRatingPicker(
                rating: $rating,
                accessibilityName: dimension.title,
                accessibilityIdentifier: "detailed-rating-\(dimension.rawValue)"
            )
        }
        .padding(.vertical, 6)
    }
}
