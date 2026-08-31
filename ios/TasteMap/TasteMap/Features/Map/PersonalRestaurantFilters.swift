import CoreLocation
import Foundation

enum PersonalRestaurantStatusFilter: String, CaseIterable, Identifiable {
    case visited
    case wantToGo
    case all

    var id: Self { self }

    var title: String {
        switch self {
        case .visited: "去过"
        case .wantToGo: "想吃"
        case .all: "全部"
        }
    }
}

enum PersonalRestaurantSort: String, CaseIterable, Identifiable {
    case comprehensive
    case recent
    case rating

    var id: Self { self }

    var title: String {
        switch self {
        case .comprehensive: "综合"
        case .recent: "最近"
        case .rating: "评分"
        }
    }
}

enum PersonalVisitCountFilter: Int, CaseIterable, Identifiable {
    case one = 1
    case two = 2
    case three = 3
    case five = 5
    case ten = 10

    var id: Self { self }
    var title: String { "\(rawValue)+" }
}

enum PersonalRatingBand: Int, CaseIterable, Identifiable {
    case one = 1
    case two = 2
    case three = 3
    case four = 4
    case five = 5

    var id: Self { self }

    var title: String {
        switch self {
        case .five: "9.0–10.0 分"
        case .four: "7.0–8.9 分"
        case .three: "5.0–6.9 分"
        case .two: "3.0–4.9 分"
        case .one: "1.0–2.9 分"
        }
    }

    static func band(for averageRating: Double?) -> Self? {
        guard let averageRating, averageRating.isFinite else { return nil }
        let score = averageRating * 2
        if score >= 9 { return .five }
        if score >= 7 { return .four }
        if score >= 5 { return .three }
        if score >= 3 { return .two }
        return .one
    }
}

enum PersonalPriceRange: String, CaseIterable, Identifiable {
    case under100
    case from100To200
    case over200

    var id: Self { self }

    var title: String {
        switch self {
        case .under100: "¥100 以下"
        case .from100To200: "¥100–200"
        case .over200: "¥200 以上"
        }
    }

    func contains(_ value: Double?) -> Bool {
        guard let value, value.isFinite else { return false }
        return switch self {
        case .under100: value < 100
        case .from100To200: value >= 100 && value <= 200
        case .over200: value > 200
        }
    }
}

enum PersonalQueueFilter: Hashable {
    case recorded(VisitQueueDuration)
    case unrecorded

    var id: String {
        switch self {
        case let .recorded(value): value.rawValue
        case .unrecorded: "unrecorded"
        }
    }

    var title: String {
        switch self {
        case let .recorded(value): value.title
        case .unrecorded: "未记录"
        }
    }
}

enum PersonalVisitPeriod: Int, CaseIterable, Identifiable {
    case sixMonths = 6
    case oneYear = 12

    var id: Self { self }
    var title: String { self == .sixMonths ? "最近半年" : "最近一年" }
}

enum PersonalDistanceFilter: Int, CaseIterable, Identifiable {
    case one = 1
    case three = 3
    case five = 5
    case ten = 10

    var id: Self { self }
    var title: String { "\(rawValue) km 内" }
}

struct PersonalFilterOption: Identifiable, Hashable {
    let id: String
    let title: String
}

struct PersonalVisitFilterFacet {
    let visitedAt: Date
    let rating: Double?
    let pricePerPerson: Double?
    let diningMode: DiningMode
    let queueDuration: VisitQueueDuration?
    let occasionRawValues: Set<String>
    let companionOptions: Set<PersonalFilterOption>
    let sourceOptions: Set<PersonalFilterOption>
}

struct PersonalRestaurantFilterOptions {
    let cities: [String]
    let cuisines: [String]
    let companions: [PersonalFilterOption]
    let sources: [PersonalFilterOption]

    static let empty = PersonalRestaurantFilterOptions(
        cities: [], cuisines: [], companions: [], sources: []
    )
}

struct PersonalRestaurantFilterState: Equatable {
    var status: PersonalRestaurantStatusFilter = .visited
    var diningMode: DiningMode?
    var visitCount: PersonalVisitCountFilter?
    var ratingBands: Set<PersonalRatingBand> = []
    var priceRange: PersonalPriceRange?
    var queue: PersonalQueueFilter?
    var diningOccasions: Set<VisitDiningOccasion> = []
    var sourceID: String?
    var visitPeriod: PersonalVisitPeriod?
    var companionID: String?
    var city: String?
    var cuisine: String?
    var distance: PersonalDistanceFilter?
    var sort: PersonalRestaurantSort = .comprehensive

    var appliesVisitScopedFilters: Bool { status != .wantToGo }

    var activeFilterCount: Int {
        (ratingBands.isEmpty ? 0 : 1)
            + (city == nil ? 0 : 1)
            + (cuisine == nil ? 0 : 1)
            + (distance == nil ? 0 : 1)
            + (appliesVisitScopedFilters && diningMode != nil ? 1 : 0)
            + (appliesVisitScopedFilters && visitCount != nil ? 1 : 0)
            + (appliesVisitScopedFilters && priceRange != nil ? 1 : 0)
            + (appliesVisitScopedFilters && queue != nil ? 1 : 0)
            + (appliesVisitScopedFilters && !diningOccasions.isEmpty ? 1 : 0)
            + (appliesVisitScopedFilters && sourceID != nil ? 1 : 0)
            + (appliesVisitScopedFilters && visitPeriod != nil ? 1 : 0)
            + (appliesVisitScopedFilters && companionID != nil ? 1 : 0)
    }

    mutating func resetKeepingStatus() {
        let currentStatus = status
        self = PersonalRestaurantFilterState(status: currentStatus)
    }
}

struct PersonalRestaurantFilterResult {
    let items: [RestaurantBrowseItem]
    let activeFilterCount: Int
}

enum PersonalRestaurantFilterEngine {
    static func resolve(
        snapshot: RestaurantBrowseSnapshot,
        state: PersonalRestaurantFilterState,
        currentLocation: CLLocation? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> PersonalRestaurantFilterResult {
        let source: [RestaurantBrowseItem]
        switch state.status {
        case .visited: source = snapshot.visited
        case .wantToGo: source = snapshot.wantToGo
        case .all: source = snapshot.visited + snapshot.wantToGo
        }

        let cutoff = state.visitPeriod.flatMap {
            calendar.date(byAdding: .month, value: -$0.rawValue, to: now)
        }
        let filtered = source.filter { item in
            if !state.ratingBands.isEmpty {
                guard let band = PersonalRatingBand.band(for: item.averageRating),
                      state.ratingBands.contains(band) else { return false }
            }
            if let city = state.city, item.restaurant.city != city { return false }
            if let cuisine = state.cuisine,
               !restaurantTags(item.restaurant).contains(cuisine) { return false }
            if let distance = state.distance {
                guard let currentLocation,
                      let restaurantLocation = validLocation(for: item.restaurant),
                      currentLocation.distance(from: restaurantLocation) <= Double(distance.rawValue) * 1_000 else {
                    return false
                }
            }
            guard state.appliesVisitScopedFilters else { return true }
            if let visitCount = state.visitCount, item.visitCount < visitCount.rawValue { return false }

            let hasFacetFilter = state.diningMode != nil
                || state.priceRange != nil
                || state.queue != nil
                || !state.diningOccasions.isEmpty
                || state.sourceID != nil
                || state.visitPeriod != nil
                || state.companionID != nil
            guard hasFacetFilter else { return true }
            return item.visitFacets.contains { facet in
                if let diningMode = state.diningMode, facet.diningMode != diningMode { return false }
                if let priceRange = state.priceRange,
                   !priceRange.contains(facet.pricePerPerson) { return false }
                if let queue = state.queue {
                    switch queue {
                    case let .recorded(value):
                        if facet.queueDuration != value { return false }
                    case .unrecorded:
                        if facet.queueDuration != nil { return false }
                    }
                }
                if !state.diningOccasions.isEmpty,
                   facet.occasionRawValues.isDisjoint(with: state.diningOccasions.map(\.rawValue)) {
                    return false
                }
                if let sourceID = state.sourceID,
                   !facet.sourceOptions.contains(where: { $0.id == sourceID }) { return false }
                if let cutoff, facet.visitedAt < cutoff { return false }
                if let companionID = state.companionID,
                   !facet.companionOptions.contains(where: { $0.id == companionID }) { return false }
                return true
            }
        }

        return PersonalRestaurantFilterResult(
            items: filtered.sorted { ordered($0, before: $1, by: state.sort) },
            activeFilterCount: state.activeFilterCount
        )
    }

    static func ordered(
        _ left: RestaurantBrowseItem,
        before right: RestaurantBrowseItem,
        by sort: PersonalRestaurantSort
    ) -> Bool {
        switch sort {
        case .comprehensive:
            return comprehensiveOrder(left, right)
        case .recent:
            let leftDate = left.latestVisitAt ?? left.restaurant.createdAt
            let rightDate = right.latestVisitAt ?? right.restaurant.createdAt
            if leftDate != rightDate { return leftDate > rightDate }
            return stableOrder(left, right)
        case .rating:
            switch (left.averageRating, right.averageRating) {
            case let (left?, right?) where left != right: return left > right
            case (_?, nil): return true
            case (nil, _?): return false
            default: return comprehensiveOrder(left, right)
            }
        }
    }

    private static func comprehensiveOrder(
        _ left: RestaurantBrowseItem,
        _ right: RestaurantBrowseItem
    ) -> Bool {
        // Exact Web personal-list order: 10-point score, visit count,
        // latest visit, then creation date. No recommendation signal is used.
        let leftScore = left.averageRating.map { $0 * 2 } ?? -1
        let rightScore = right.averageRating.map { $0 * 2 } ?? -1
        if leftScore != rightScore { return leftScore > rightScore }
        if left.visitCount != right.visitCount { return left.visitCount > right.visitCount }
        if left.latestVisitAt != right.latestVisitAt {
            return (left.latestVisitAt ?? .distantPast) > (right.latestVisitAt ?? .distantPast)
        }
        if left.restaurant.createdAt != right.restaurant.createdAt {
            return left.restaurant.createdAt > right.restaurant.createdAt
        }
        return stableOrder(left, right)
    }

    private static func stableOrder(_ left: RestaurantBrowseItem, _ right: RestaurantBrowseItem) -> Bool {
        let nameOrder = left.restaurant.name.localizedStandardCompare(right.restaurant.name)
        if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
        return left.id.uuidString < right.id.uuidString
    }

    private static func validLocation(for restaurant: Restaurant) -> CLLocation? {
        let latitude = restaurant.latitude
        let longitude = restaurant.longitude
        guard latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude),
              !(latitude == 0 && longitude == 0) else { return nil }
        return CLLocation(latitude: latitude, longitude: longitude)
    }

    private static func restaurantTags(_ restaurant: Restaurant) -> Set<String> {
        guard let data = restaurant.remoteRecordData,
              let record = try? JSONDecoder().decode(RestaurantJSONContractV1.self, from: data) else {
            return []
        }
        return Set(record.tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    }
}

enum PersonalRestaurantFilterProjection {
    static func options(from items: [RestaurantBrowseItem]) -> PersonalRestaurantFilterOptions {
        let cities = Set(items.map(\.restaurant.city).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        let cuisines = Set(items.flatMap { item -> [String] in
            guard let data = item.restaurant.remoteRecordData,
                  let record = try? JSONDecoder().decode(RestaurantJSONContractV1.self, from: data) else {
                return []
            }
            return record.tags
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        })
        let facets = items.flatMap(\.visitFacets)
        return PersonalRestaurantFilterOptions(
            cities: cities.sorted { $0.localizedStandardCompare($1) == .orderedAscending },
            cuisines: cuisines.sorted { $0.localizedStandardCompare($1) == .orderedAscending },
            companions: stableOptions(facets.flatMap(\.companionOptions)),
            sources: stableOptions(facets.flatMap(\.sourceOptions))
        )
    }

    static func optionID(prefix: String, title: String) -> String {
        let normalized = title.precomposedStringWithCompatibilityMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return "\(prefix):\(normalized)"
    }

    private static func stableOptions(_ values: [PersonalFilterOption]) -> [PersonalFilterOption] {
        var byID: [String: PersonalFilterOption] = [:]
        for value in values where byID[value.id] == nil { byID[value.id] = value }
        return byID.values.sorted {
            let order = $0.title.localizedStandardCompare($1.title)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }
}
