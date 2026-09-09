import Foundation

enum DiscoveryContentAccessPolicy {
    /// A refresh error or a populated cache cannot grant access to protected cards.
    static func blocksCards(mode: DiscoveryModeV1, access: PremiumAccessDecision) -> Bool {
        mode == .similarTaste && access != .allowed
    }
}

enum DiscoveryBrowseSort: String, CaseIterable, Identifiable, Sendable {
    case recommended
    case nearest
    case predictedLiking
    case tasteMatch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recommended: "综合推荐"
        case .nearest: "距离最近"
        case .predictedLiking: "预计喜欢度优先"
        case .tasteMatch: "口味匹配优先"
        }
    }
}

struct DiscoveryBrowseFilters: Equatable, Sendable {
    var sort: DiscoveryBrowseSort = .recommended
    var maximumDistanceKilometers: Double?
    var minimumPredictedLikingOutOfTen: Double?
    var minimumTasteMatchPercent: Double?

    nonisolated var activeCount: Int {
        (sort == .recommended ? 0 : 1) +
            (maximumDistanceKilometers == nil ? 0 : 1) +
            (minimumPredictedLikingOutOfTen == nil ? 0 : 1) +
            (minimumTasteMatchPercent == nil ? 0 : 1)
    }

    nonisolated var needsDistanceAnchor: Bool {
        sort == .nearest || maximumDistanceKilometers != nil
    }

    mutating func reset() { self = DiscoveryBrowseFilters() }
}

struct DiscoveryBrowseCoordinate: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
}

enum DiscoveryBrowseEmptyReason: Equatable, Sendable {
    case locationUnavailable
    case filtersTooStrict
}

struct DiscoveryBrowseResolution: Sendable {
    let cards: [DiscoveryCardV1]
    let emptyReason: DiscoveryBrowseEmptyReason?
}

enum DiscoveryBrowseResolver {
    nonisolated static func resolve(
        cards: [DiscoveryCardV1],
        filters: DiscoveryBrowseFilters,
        anchor: DiscoveryBrowseCoordinate?
    ) -> DiscoveryBrowseResolution {
        guard !filters.needsDistanceAnchor || anchor != nil else {
            return DiscoveryBrowseResolution(cards: [], emptyReason: .locationUnavailable)
        }

        let filtered = cards.filter { card in
            if let minimum = filters.minimumPredictedLikingOutOfTen,
               (card.displayablePredictedLiking ?? -1) < minimum {
                return false
            }
            if let minimum = filters.minimumTasteMatchPercent,
               Double(card.personalTastePercent ?? -1) < minimum {
                return false
            }
            if let maximumDistance = filters.maximumDistanceKilometers,
               let anchor,
               distanceKilometers(from: anchor, to: card.restaurant) > maximumDistance {
                return false
            }
            return true
        }

        let sorted: [DiscoveryCardV1]
        switch filters.sort {
        case .recommended:
            sorted = filtered.sorted(by: serverRank)
        case .predictedLiking:
            sorted = filtered.sorted { left, right in
                let leftRating = left.displayablePredictedLiking ?? -1
                let rightRating = right.displayablePredictedLiking ?? -1
                return leftRating == rightRating ? serverRank(left, right) : leftRating > rightRating
            }
        case .tasteMatch:
            sorted = filtered.sorted { left, right in
                let lhs = left.personalTastePercent ?? -1
                let rhs = right.personalTastePercent ?? -1
                return lhs == rhs ? serverRank(left, right) : lhs > rhs
            }
        case .nearest:
            guard let anchor else {
                return DiscoveryBrowseResolution(cards: [], emptyReason: .locationUnavailable)
            }
            sorted = filtered.sorted { left, right in
                let leftDistance = distanceKilometers(from: anchor, to: left.restaurant)
                let rightDistance = distanceKilometers(from: anchor, to: right.restaurant)
                return leftDistance == rightDistance ? serverRank(left, right) : leftDistance < rightDistance
            }
        }

        return DiscoveryBrowseResolution(
            cards: sorted,
            emptyReason: sorted.isEmpty && !cards.isEmpty && filters.activeCount > 0
                ? .filtersTooStrict
                : nil
        )
    }

    nonisolated static func centroid(of cards: [DiscoveryCardV1]) -> DiscoveryBrowseCoordinate? {
        guard !cards.isEmpty else { return nil }
        return DiscoveryBrowseCoordinate(
            latitude: cards.reduce(0) { $0 + $1.restaurant.latitude } / Double(cards.count),
            longitude: cards.reduce(0) { $0 + $1.restaurant.longitude } / Double(cards.count)
        )
    }

    nonisolated static func distanceKilometers(
        from origin: DiscoveryBrowseCoordinate,
        to restaurant: DiscoveryRestaurantProjectionV1
    ) -> Double {
        let radians = { (degrees: Double) in degrees * .pi / 180 }
        let latitudeDelta = radians(restaurant.latitude - origin.latitude)
        let longitudeDelta = radians(restaurant.longitude - origin.longitude)
        let startLatitude = radians(origin.latitude)
        let endLatitude = radians(restaurant.latitude)
        let value = pow(sin(latitudeDelta / 2), 2) +
            cos(startLatitude) * cos(endLatitude) * pow(sin(longitudeDelta / 2), 2)
        return 6_371 * 2 * atan2(sqrt(value), sqrt(max(0, 1 - value)))
    }

    nonisolated private static func serverRank(_ left: DiscoveryCardV1, _ right: DiscoveryCardV1) -> Bool {
        left.rank == right.rank ? left.score > right.score : left.rank < right.rank
    }
}

extension DiscoveryCardV1 {
    nonisolated var displayablePredictedLiking: Double? {
        guard let prediction = predictedLiking,
              prediction.method == "owner_history_weighted_rating_v1",
              prediction.ratedRestaurantCount > 0,
              let score = prediction.scoreOutOfTen, score.isFinite,
              (0...10).contains(score) else { return nil }
        return score
    }

    var displayableSimilarity: DiscoverySimilarityContextV1? {
        guard let similarity, similarity.sharedRestaurantCount >= 3 else { return nil }
        return similarity
    }
}
