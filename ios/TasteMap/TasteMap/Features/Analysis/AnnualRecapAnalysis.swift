import Foundation

nonisolated struct AnnualPeriod: Identifiable, Hashable, Sendable {
    let year: Int
    let calendar: Calendar

    var id: String { "\(year)-\(calendar.timeZone.identifier)" }
    var start: Date {
        calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? .distantPast
    }
    var end: Date {
        calendar.date(byAdding: .year, value: 1, to: start) ?? .distantFuture
    }
    var previous: AnnualPeriod { AnnualPeriod(year: year - 1, calendar: calendar) }
    var next: AnnualPeriod { AnnualPeriod(year: year + 1, calendar: calendar) }
    var title: String { "\(year) 年" }

    init(year: Int, calendar: Calendar = .current) {
        var value = calendar
        value.locale = calendar.locale ?? .current
        self.year = year
        self.calendar = value
    }

    init(date: Date, calendar: Calendar = .current) {
        var value = calendar
        value.locale = calendar.locale ?? .current
        self.year = value.component(.year, from: date)
        self.calendar = value
    }

    static func current(now: Date = .now, calendar: Calendar = .current) -> AnnualPeriod {
        AnnualPeriod(date: now, calendar: calendar)
    }

    func contains(_ date: Date) -> Bool { date >= start && date < end }
    func isCurrent(now: Date = .now) -> Bool {
        AnnualPeriod.current(now: now, calendar: calendar).year == year
    }
    func month(_ value: Int) -> MonthlyPeriod {
        MonthlyPeriod(year: year, month: value, calendar: calendar)
    }
    func posterLabel(now: Date = .now) -> String {
        guard isCurrent(now: now) else { return "\(year) 年度回顾" }
        let month = calendar.component(.month, from: now)
        let day = calendar.component(.day, from: now)
        return "\(year) · 截至 \(month) 月 \(day) 日"
    }
}

nonisolated enum AnnualSpendDisplayState: String, Hashable, Sendable {
    case none
    case lowCoverage
    case recorded
    case complete

    var label: String {
        switch self {
        case .none: "未记录消费"
        case .lowCoverage, .recorded: "全年已记录消费"
        case .complete: "全年消费"
        }
    }
}

nonisolated struct AnnualMonthlySpend: Identifiable, Hashable, Sendable {
    let month: Int
    let recordedTotal: Double?
    let recordedVisitCount: Int
    let visitCount: Int
    let coverage: Double
    var id: Int { month }
}

nonisolated struct AnnualSpendSummary: Hashable, Sendable {
    let recordedTotal: Double?
    let median: Double?
    let recordedVisitCount: Int
    let visitCount: Int
    let coverage: Double
    let displayState: AnnualSpendDisplayState
    let monthlyDistribution: [AnnualMonthlySpend]
    let sufficiency: AnalysisDataSufficiency
}

nonisolated struct AnnualRestaurantStory: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let city: String
    let role: String
    let detail: String
    let visitCount: Int
    let averageRating: Double?
    let latestVisitAt: Date
    let isNew: Bool
    let imageReference: AnalysisImageReference
}

nonisolated struct AnnualCompanionStory: Hashable, Sendable {
    let id: UUID
    let displayName: String
    let sharedVisitCount: Int
    let restaurantCount: Int
    let representativeRestaurant: AnnualRestaurantStory?
    let sufficiency: AnalysisDataSufficiency
}

nonisolated struct AnnualSourceConclusion: Identifiable, Hashable, Sendable {
    let sourceID: UUID
    let displayName: String
    let sourceType: RecommendationSourceType
    let title: String
    let statement: String
    let restaurantCount: Int
    let ratedRestaurantCount: Int
    let averageRating: Double?
    let score: Double?
    let representativeRestaurant: AnnualRestaurantStory?
    let sufficiency: AnalysisDataSufficiency
    var id: String { "\(title):\(sourceID.uuidString)" }
}

nonisolated struct AnnualRecommendationSummary: Hashable, Sendable {
    let mostUsed: AnnualSourceConclusion?
    let best: AnnualSourceConclusion?
    let worst: AnnualSourceConclusion?
    let usedSourceCount: Int
    let attributedRestaurantCount: Int
    let rankingSufficiency: AnalysisDataSufficiency
}

nonisolated enum AnnualTasteJourneyGranularity: String, Hashable, Sendable {
    case monthly
    case quarterly
    case insufficient

    var title: String {
        switch self {
        case .monthly: "按月轨迹"
        case .quarterly: "按季度轨迹"
        case .insufficient: "轨迹正在形成"
        }
    }
}

nonisolated struct AnnualTasteMilestone: Identifiable, Hashable, Sendable {
    let id: String
    let periodLabel: String
    let title: String
    let detail: String
    let month: Int
    let visitCount: Int
    let restaurantID: UUID?
    let imageReference: AnalysisImageReference
}

nonisolated struct AnnualTasteJourney: Hashable, Sendable {
    let granularity: AnnualTasteJourneyGranularity
    let milestones: [AnnualTasteMilestone]
    let changeSummaries: [String]
    let sufficiency: AnalysisDataSufficiency
}

nonisolated enum AnnualHighlightKind: String, Hashable, Sendable {
    case busiest
    case exploration
    case rating
    case spend
}

nonisolated struct AnnualMonthHighlight: Identifiable, Hashable, Sendable {
    let kind: AnnualHighlightKind
    let month: Int
    let title: String
    let value: String
    let detail: String
    var id: String { "\(kind.rawValue):\(month)" }
}

nonisolated struct AnnualMonthSnapshot: Identifiable, Hashable, Sendable {
    let month: Int
    let visitCount: Int
    let restaurantCount: Int
    let newRestaurantCount: Int
    let dominantCuisine: String?
    let explorationRate: Double
    let repeatRate: Double
    var id: Int { month }
}

nonisolated struct AnnualRecapAnalysis: Identifiable, Hashable, Sendable {
    let id: String
    let kind: AnalysisReportKind
    let userDisplayName: String
    let period: AnnualPeriod
    let isCurrentPeriod: Bool
    let periodLabel: String
    let visitCount: Int
    let restaurantCount: Int
    let newRestaurantCount: Int
    let repeatRestaurantCount: Int
    let explorationRate: Double
    let spend: AnnualSpendSummary
    let favoriteRestaurant: AnnualRestaurantStory?
    let mostVisitedRestaurant: AnnualRestaurantStory?
    let topRestaurants: [AnnualRestaurantStory]
    let topCompanion: AnnualCompanionStory?
    let recommendationSummary: AnnualRecommendationSummary
    let tasteJourney: AnnualTasteJourney
    let monthlySnapshots: [AnnualMonthSnapshot]
    let monthlyHighlights: [AnnualMonthHighlight]
    let keywords: [String]
    let representativeRestaurants: [AnnualRestaurantStory]
    let sufficiency: AnalysisDataSufficiency
    let dataNote: String
    let generatedAt: Date

    var hasData: Bool { visitCount > 0 }
    var photoReferences: [AnalysisImageReference] {
        let restaurantReferences = representativeRestaurants.map(\.imageReference)
        let journeyReferences = tasteJourney.milestones.map(\.imageReference)
        var seen = Set<AnalysisImageReference>()
        return (restaurantReferences + journeyReferences).filter { seen.insert($0).inserted }
    }
}
