import Foundation

/// Same-owner personal Restaurant aggregate, not community or Activity rating.
/// Eligibility stays with the caller; raw Visit half-star values stay unchanged.
enum PersonalRestaurantRating {
    static func project(_ ratings: [Double]) -> (averageRating: Double?, scoreOutOfTen: Double?) {
        guard !ratings.isEmpty else { return (nil, nil) }
        let sum = ratings.reduce(0, +)
        let average = sum / Double(ratings.count)
        // Match the project's Decimal .plain (positive half-up) convention.
        // Sum of contract half-stars is exact; never round the five-star mean.
        var score = Decimal(sum) * 2 / Decimal(ratings.count)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &score, 1, .plain)
        return (average, NSDecimalNumber(decimal: rounded).doubleValue)
    }
}
