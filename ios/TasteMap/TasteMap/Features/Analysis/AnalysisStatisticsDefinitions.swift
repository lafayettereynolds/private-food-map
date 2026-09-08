import Foundation

/// P4-wide statistical semantics. Analysis modules may present the values differently,
/// but they must all start from the same nullable fields and sample definitions.
nonisolated enum AnalysisStatisticsDefinitions {
    struct RecentComparison: Hashable, Sendable {
        let currentStart: Date
        let previousStart: Date
        let currentVisitCount: Int
        let previousVisitCount: Int
        let currentRatedRestaurantCount: Int
        let previousRatedRestaurantCount: Int
        let frequencyAvailable: Bool
        let scoreDeltaOutOfTen: Double?
    }

    static func recentComparison<T, ID: Hashable>(in values: [T], now: Date, calendar: Calendar,
                                                 visitedAt: (T) -> Date, restaurantID: (T) -> ID,
                                                 rating: (T) -> Double?) -> RecentComparison {
        let currentStart = calendar.date(byAdding: .day, value: -90, to: now) ?? now
        let previousStart = calendar.date(byAdding: .day, value: -90, to: currentStart) ?? currentStart
        let current = values.filter { visitedAt($0) >= currentStart && visitedAt($0) <= now }
        let previous = values.filter { visitedAt($0) >= previousStart && visitedAt($0) < currentStart }
        let currentRatings = representativeRatings(in: current, restaurantID: restaurantID, rating: rating)
        let previousRatings = representativeRatings(in: previous, restaurantID: restaurantID, rating: rating)
        let ratingAvailable = currentRatings.count >= AnalysisSufficiencyThresholds.comparisonRatedRestaurants
            && previousRatings.count >= AnalysisSufficiencyThresholds.comparisonRatedRestaurants
        let frequencyAvailable = current.count >= AnalysisSufficiencyThresholds.frequencyVisits
            && previous.count >= AnalysisSufficiencyThresholds.frequencyVisits
            && Set(current.map(restaurantID)).count >= AnalysisSufficiencyThresholds.frequencyRestaurants
            && Set(previous.map(restaurantID)).count >= AnalysisSufficiencyThresholds.frequencyRestaurants
        return RecentComparison(currentStart: currentStart, previousStart: previousStart,
            currentVisitCount: current.count, previousVisitCount: previous.count,
            currentRatedRestaurantCount: currentRatings.count, previousRatedRestaurantCount: previousRatings.count,
            frequencyAvailable: frequencyAvailable,
            scoreDeltaOutOfTen: ratingAvailable ? (mean(currentRatings)! - mean(previousRatings)!) * 2 : nil)
    }

    /// Each distinct restaurant contributes one mean, regardless of repeat meals.
    static func representativeRatings<T, ID: Hashable>(in values: [T], restaurantID: (T) -> ID, rating: (T) -> Double?) -> [Double] {
        Dictionary(grouping: values, by: restaurantID).values.compactMap { group in
            mean(group.compactMap(rating).filter { $0.isFinite && $0 >= 0.5 && $0 <= 5 })
        }.sorted()
    }

    static func comparableMonthEnds(period: MonthlyPeriod, now: Date) -> (current: Date, previous: Date) {
        guard period.contains(now) else { return (period.end, period.start) }
        let calendar = period.calendar
        let day = min(calendar.component(.day, from: now), calendar.range(of: .day, in: .month, for: period.previous.start)?.count ?? 28)
        return (calendar.date(byAdding: .day, value: day, to: period.start) ?? period.end,
                calendar.date(byAdding: .day, value: day, to: period.previous.start) ?? period.start)
    }
    /// Overall restaurant/visit rating. Dimension ratings and Dish.rating are never substituted.
    static func overallRatings<T>(in values: [T], rating: (T) -> Double?) -> [Double] {
        values.compactMap(rating)
    }

    /// User-entered Visit.myActualSpend values. Missing spend and Dish prices are never substituted.
    static func recordedSpendValues<T>(in values: [T], spend: (T) -> Decimal?) -> [Double] {
        values.compactMap { value in
            guard let decimal = spend(value) else { return nil }
            let result = NSDecimalNumber(decimal: decimal).doubleValue
            return result.isFinite && result >= 0 ? result : nil
        }
    }

    static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    static func median(_ values: [Double]) -> Double? {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }

    static func coverage(recordedCount: Int, totalCount: Int) -> Double {
        guard totalCount > 0 else { return 0 }
        return Double(recordedCount) / Double(totalCount)
    }
}

/// Thresholds are intentionally centralized while remaining analysis-specific.
/// A single Visit must not be promoted into a stable taste or relationship conclusion.
nonisolated enum AnalysisSufficiencyThresholds {
    static let frequencyVisits = 10
    static let frequencyRestaurants = 5
    static let frequencyShareChange = 0.15
    static let comparisonRatedRestaurants = 5
    static let tasteProfile = (emerging: 3, established: 10)
    static let companion = (emerging: 3, established: 6)
    static let companionSpend = (emerging: 2, established: 6)
    static let monthly = (emerging: 3, established: 8)
    static let annual = (emerging: 4, established: 16)
    static let recommendationSourceRankingRatedRestaurants = 5
    static let recommendationSourceAverageRatedRestaurants = 2
    static let recommendationSourceStableRatedRestaurants = 10
}

/// A read-only projection used only by P4 analytics. It does not alter SwiftData identity,
/// sync payloads, or provider identities. Connected identity tokens are folded into one
/// representative local Restaurant ID before an analysis snapshot is built.
nonisolated struct AnalysisRestaurantIdentityProjection: Sendable {
    let canonicalIDByLocalID: [UUID: UUID]
    let representativeIDs: Set<UUID>

    func canonicalID(for localID: UUID) -> UUID {
        canonicalIDByLocalID[localID] ?? localID
    }

    func canonicalID(for localID: UUID?) -> UUID? {
        localID.map(canonicalID(for:))
    }
}

nonisolated enum AnalysisRestaurantIdentity {
    struct Descriptor: Sendable {
        let localID: UUID
        let updatedAt: Date
        let deletedAt: Date?
        let tasteMapID: String?
        let remoteID: String?
        let appleMapItemIdentifier: String?
        let placeIdentities: [RestaurantPlaceIdentityContract]
    }

    @MainActor
    static func projection(for restaurants: [Restaurant]) -> AnalysisRestaurantIdentityProjection {
        projection(restaurants.map { restaurant in
            let contract = restaurant.remoteRecordData.flatMap {
                try? JSONDecoder().decode(RestaurantJSONContractV1.self, from: $0)
            }
            return Descriptor(
                localID: restaurant.id,
                updatedAt: restaurant.updatedAt,
                deletedAt: restaurant.deletedAt,
                tasteMapID: contract?.id,
                remoteID: restaurant.remoteID,
                appleMapItemIdentifier: restaurant.appleMapItemIdentifier,
                placeIdentities: contract?.placeIdentities ?? []
            )
        })
    }

    static func projection(_ descriptors: [Descriptor]) -> AnalysisRestaurantIdentityProjection {
        let active = descriptors.filter { $0.deletedAt == nil }
            .sorted { $0.localID.uuidString < $1.localID.uuidString }
        var parent = Dictionary(uniqueKeysWithValues: active.map { ($0.localID, $0.localID) })
        var ownerByIdentity = [String: UUID]()

        func root(_ id: UUID) -> UUID {
            var value = id
            while let next = parent[value], next != value { value = next }
            return value
        }

        func union(_ lhs: UUID, _ rhs: UUID) {
            let left = root(lhs)
            let right = root(rhs)
            guard left != right else { return }
            if left.uuidString < right.uuidString {
                parent[right] = left
            } else {
                parent[left] = right
            }
        }

        for descriptor in active {
            for key in identityKeys(for: descriptor) {
                if let owner = ownerByIdentity[key] {
                    union(descriptor.localID, owner)
                } else {
                    ownerByIdentity[key] = descriptor.localID
                }
            }
        }

        let groups = Dictionary(grouping: active) { root($0.localID) }
        var canonicalByLocalID = [UUID: UUID]()
        var representatives = Set<UUID>()
        for members in groups.values {
            let representative = members.sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
                return lhs.localID.uuidString < rhs.localID.uuidString
            }[0]
            representatives.insert(representative.localID)
            for member in members { canonicalByLocalID[member.localID] = representative.localID }
        }

        return AnalysisRestaurantIdentityProjection(
            canonicalIDByLocalID: canonicalByLocalID,
            representativeIDs: representatives
        )
    }

    private static func identityKeys(for descriptor: Descriptor) -> Set<String> {
        var keys = Set<String>()
        if let tasteMapID = normalized(descriptor.tasteMapID) {
            keys.insert("taste_map:\(tasteMapID)")
        }
        if let remoteID = normalized(descriptor.remoteID) {
            keys.insert("taste_map:\(remoteID)")
        }
        if let appleID = normalized(descriptor.appleMapItemIdentifier) {
            keys.insert("apple_maps:\(appleID)")
        }
        for identity in descriptor.placeIdentities {
            if let externalID = normalized(identity.externalId) {
                keys.insert("\(identity.provider.rawValue):\(externalID)")
            }
        }
        if keys.isEmpty { keys.insert("local:\(descriptor.localID.uuidString.lowercased())") }
        return keys
    }

    private static func normalized(_ value: String?) -> String? {
        // Provider IDs are opaque and may be case-sensitive. Trim transport
        // whitespace but never case-fold an Apple/AMap/other provider identity.
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }
}
