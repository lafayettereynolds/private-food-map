import SwiftUI

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
