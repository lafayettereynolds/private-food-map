import Foundation

struct RatingSummary: Equatable, Identifiable, Sendable {
    let dimension: RatingDimension
    let average: Double
    let count: Int
    let latest: Double
    let latestAt: Date

    var id: RatingDimension { dimension }
}

@MainActor
enum RatingStatistics {
    static func summaries(for visits: [Visit]) -> [RatingSummary] {
        let active = visits.filter { $0.deletedAt == nil }
        return RatingDimension.allCases.compactMap { dimension in
            let samples = active.compactMap { visit -> (value: Double, date: Date)? in
                guard let value = dimension.value(in: visit), Visit.validatedRating(value) == value else {
                    return nil
                }
                return (value, visit.visitedAt)
            }
            guard !samples.isEmpty,
                  let latest = samples.max(by: { $0.date < $1.date }) else { return nil }
            return RatingSummary(
                dimension: dimension,
                average: samples.reduce(0) { $0 + $1.value } / Double(samples.count),
                count: samples.count,
                latest: latest.value,
                latestAt: latest.date
            )
        }
    }

    static func summary(for dimension: RatingDimension, visits: [Visit]) -> RatingSummary? {
        summaries(for: visits).first { $0.dimension == dimension }
    }
}
