import Foundation

nonisolated struct MonthlyPeriod: Identifiable, Hashable, Sendable {
    let year: Int
    let month: Int
    let calendar: Calendar

    var id: String { "\(year)-\(String(format: "%02d", month))-\(calendar.timeZone.identifier)" }

    var start: Date {
        calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? .distantPast
    }

    var end: Date {
        calendar.date(byAdding: .month, value: 1, to: start) ?? .distantFuture
    }

    var previous: MonthlyPeriod {
        MonthlyPeriod(date: calendar.date(byAdding: .month, value: -1, to: start) ?? start, calendar: calendar)
    }

    var next: MonthlyPeriod {
        MonthlyPeriod(date: calendar.date(byAdding: .month, value: 1, to: start) ?? start, calendar: calendar)
    }

    var title: String { "\(year) 年 \(month) 月" }

    init(year: Int, month: Int, calendar: Calendar = .current) {
        var normalizedCalendar = calendar
        normalizedCalendar.locale = calendar.locale ?? .current
        let anchor = normalizedCalendar.date(from: DateComponents(year: year, month: month, day: 15)) ?? .now
        let components = normalizedCalendar.dateComponents([.year, .month], from: anchor)
        self.year = components.year ?? year
        self.month = components.month ?? month
        self.calendar = normalizedCalendar
    }

    init(date: Date, calendar: Calendar = .current) {
        var normalizedCalendar = calendar
        normalizedCalendar.locale = calendar.locale ?? .current
        let components = normalizedCalendar.dateComponents([.year, .month], from: date)
        self.year = components.year ?? 1970
        self.month = components.month ?? 1
        self.calendar = normalizedCalendar
    }

    static func current(now: Date = .now, calendar: Calendar = .current) -> MonthlyPeriod {
        MonthlyPeriod(date: now, calendar: calendar)
    }

    func contains(_ date: Date) -> Bool { date >= start && date < end }

    func isCurrent(now: Date = .now) -> Bool {
        MonthlyPeriod.current(now: now, calendar: calendar).year == year
            && MonthlyPeriod.current(now: now, calendar: calendar).month == month
    }

    func posterLabel(now: Date = .now) -> String {
        guard isCurrent(now: now) else { return title }
        let day = calendar.component(.day, from: now)
        return "\(title) · 截至 \(month) 月 \(day) 日"
    }
}

nonisolated struct MonthlyRecapInput: Sendable {
    nonisolated struct RestaurantRecord: Sendable {
        let id: UUID
        let name: String
        let city: String
        let status: RestaurantStatus
        let tags: [String]
        var merchantImageURL: URL? = nil
        let createdAt: Date
        let updatedAt: Date
        let deletedAt: Date?
    }

    nonisolated struct VisitRecord: Sendable {
        let id: UUID
        let restaurantID: UUID
        let visitedAt: Date
        let rating: Double?
        let valueRating: Double?
        let environmentRating: Double?
        let serviceRating: Double?
        let myActualSpend: Decimal?
        let note: String?
        let diningOccasionLabels: [String]
        let companionIDs: [String]
        let companionNames: [String]
        let recommendationSourceID: String?
        let recommendationSourceType: RecommendationSourceType?
        let recommendationSourceText: String?
        let updatedAt: Date
        let deletedAt: Date?
    }

    nonisolated struct DishRecord: Sendable {
        let id: UUID
        let restaurantID: UUID
        let originVisitID: UUID
        let name: String
        let taste: String
        let rating: Double?
        let updatedAt: Date
        let deletedAt: Date?
    }

    nonisolated struct VisitDishRecord: Sendable {
        let visitID: UUID
        let dishID: UUID
        let deletedAt: Date?
    }

    nonisolated struct PhotoRecord: Sendable {
        let id: UUID
        let restaurantID: UUID?
        let visitID: UUID?
        let dishID: UUID?
        let kind: PhotoAssetKind
        let sortOrder: Int
        let updatedAt: Date
        let deletedAt: Date?
    }

    nonisolated struct CompanionRecord: Sendable {
        let id: UUID
        let identifiers: [String]
        let displayName: String
        let updatedAt: Date
        let deletedAt: Date?
    }

    nonisolated struct SourceRecord: Sendable {
        let id: UUID
        let identifiers: [String]
        let displayName: String
        let sourceType: RecommendationSourceType
        let updatedAt: Date
        let deletedAt: Date?
    }

    let userDisplayName: String
    let restaurants: [RestaurantRecord]
    let visits: [VisitRecord]
    let dishes: [DishRecord]
    let visitDishes: [VisitDishRecord]
    let photos: [PhotoRecord]
    let companions: [CompanionRecord]
    let recommendationSources: [SourceRecord]

    @MainActor
    static func capture(
        restaurants: [Restaurant],
        visits: [Visit],
        dishes: [Dish],
        visitDishes: [VisitDish],
        photos: [PhotoAsset],
        companions: [DiningCompanion],
        recommendationSources: [RecommendationSource],
        profile: UserProfile?
    ) -> MonthlyRecapInput {
        let identity = AnalysisRestaurantIdentity.projection(for: restaurants)
        return MonthlyRecapInput(
            userDisplayName: profile?.displayName.trimmingCharacters(in: .whitespacesAndNewlines).monthlyNonEmpty
                ?? "Taste Map 用户",
            restaurants: restaurants.filter { restaurant in
                restaurant.deletedAt != nil || identity.representativeIDs.contains(restaurant.id)
            }.map { restaurant in
                let contract = restaurant.remoteRecordData.flatMap {
                    try? JSONDecoder().decode(RestaurantJSONContractV1.self, from: $0)
                }
                return RestaurantRecord(
                    id: restaurant.id, name: restaurant.name, city: restaurant.city,
                    status: restaurant.status, tags: contract?.tags ?? [],
                    merchantImageURL: RestaurantImagePriorityPolicy.safeHTTPSURL(contract?.merchantImageUrl),
                    createdAt: restaurant.createdAt, updatedAt: restaurant.updatedAt,
                    deletedAt: restaurant.deletedAt
                )
            },
            visits: visits.map {
                VisitRecord(
                    id: $0.id, restaurantID: identity.canonicalID(for: $0.restaurantId), visitedAt: $0.visitedAt,
                    rating: $0.rating, valueRating: $0.valueRating,
                    environmentRating: $0.environmentRating, serviceRating: $0.serviceRating,
                    myActualSpend: $0.resolvedActualSpend, note: $0.note,
                    diningOccasionLabels: $0.diningOccasionDisplayTitles,
                    companionIDs: $0.companionIDs, companionNames: $0.companionNames,
                    recommendationSourceID: $0.recommendationSourceID,
                    recommendationSourceType: $0.recommendationSourceType,
                    recommendationSourceText: $0.recommendationSourceText,
                    updatedAt: $0.updatedAt, deletedAt: $0.deletedAt
                )
            },
            dishes: dishes.map {
                DishRecord(
                    id: $0.id, restaurantID: identity.canonicalID(for: $0.restaurantId), originVisitID: $0.visitId,
                    name: $0.name, taste: $0.taste, rating: $0.rating,
                    updatedAt: $0.updatedAt, deletedAt: $0.deletedAt
                )
            },
            visitDishes: visitDishes.map {
                VisitDishRecord(visitID: $0.visitId, dishID: $0.dishId, deletedAt: $0.deletedAt)
            },
            photos: photos.map {
                PhotoRecord(
                    id: $0.id, restaurantID: identity.canonicalID(for: $0.restaurantId), visitID: $0.visitId,
                    dishID: $0.dishId, kind: $0.kind, sortOrder: $0.sortOrder,
                    updatedAt: $0.updatedAt, deletedAt: $0.deletedAt
                )
            },
            companions: companions.map {
                CompanionRecord(
                    id: $0.id,
                    identifiers: [$0.id.uuidString.lowercased(), $0.remoteID].compactMap { $0 },
                    displayName: $0.displayName, updatedAt: $0.updatedAt, deletedAt: $0.deletedAt
                )
            },
            recommendationSources: recommendationSources.map {
                SourceRecord(
                    id: $0.id,
                    identifiers: [$0.id.uuidString.lowercased(), $0.remoteID].compactMap { $0 },
                    displayName: $0.displayName, sourceType: $0.sourceType,
                    updatedAt: $0.updatedAt, deletedAt: $0.deletedAt
                )
            }
        )
    }
}

nonisolated enum MonthlySpendDisplayState: String, Hashable, Sendable {
    case none
    case lowCoverage
    case recorded
    case complete

    var label: String {
        switch self {
        case .none: "未记录消费"
        case .lowCoverage, .recorded: "本月已记录消费"
        case .complete: "本月消费"
        }
    }
}

nonisolated struct MonthlySpendSummary: Hashable, Sendable {
    let recordedTotal: Double?
    let median: Double?
    let recordedVisitCount: Int
    let visitCount: Int
    let coverage: Double
    let displayState: MonthlySpendDisplayState
    let sufficiency: AnalysisDataSufficiency
}

nonisolated struct MonthlyRestaurantStory: Identifiable, Hashable, Sendable {
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

nonisolated struct MonthlyCompanionStory: Hashable, Sendable {
    let id: UUID
    let displayName: String
    let sharedVisitCount: Int
    let restaurantCount: Int
    let representativeRestaurant: MonthlyRestaurantStory?
    let sufficiency: AnalysisDataSufficiency
}

nonisolated struct MonthlyRecommendationStory: Hashable, Sendable {
    let sourceID: UUID
    let displayName: String
    let sourceType: RecommendationSourceType
    let restaurantCount: Int
    let ratedRestaurantCount: Int
    let highRatedRestaurantCount: Int
    let averageRating: Double?
    let statement: String
    let representativeRestaurant: MonthlyRestaurantStory?
    let sufficiency: AnalysisDataSufficiency
}

nonisolated enum MonthlyTasteChangeKind: String, Hashable, Sendable {
    case cuisineIncrease
    case cuisineDecrease
    case explorationIncrease
    case repeatIncrease
}

nonisolated struct MonthlyTasteChange: Hashable, Sendable {
    let kind: MonthlyTasteChangeKind
    let title: String
    let statement: String
    let magnitude: Double
    let sufficiency: AnalysisDataSufficiency
}

nonisolated struct MonthlyRecapAnalysis: Identifiable, Hashable, Sendable {
    let id: String
    let kind: AnalysisReportKind
    let userDisplayName: String
    let period: MonthlyPeriod
    let comparisonPeriod: MonthlyPeriod
    let isCurrentPeriod: Bool
    let periodLabel: String
    let visitCount: Int
    let restaurantCount: Int
    let newRestaurantCount: Int
    let repeatRestaurantCount: Int
    let spend: MonthlySpendSummary
    let favoriteRestaurant: MonthlyRestaurantStory?
    let mostVisitedRestaurant: MonthlyRestaurantStory?
    let newRestaurants: [MonthlyRestaurantStory]
    let topCompanion: MonthlyCompanionStory?
    let recommendationStory: MonthlyRecommendationStory?
    let tasteChange: MonthlyTasteChange?
    let keywords: [String]
    let highlight: MonthlyRestaurantStory?
    let representativeRestaurants: [MonthlyRestaurantStory]
    let sufficiency: AnalysisDataSufficiency
    let tasteChangeSufficiency: AnalysisDataSufficiency
    let dataNote: String
    let generatedAt: Date

    var hasData: Bool { visitCount > 0 }
    var photoReferences: [AnalysisImageReference] { representativeRestaurants.map(\.imageReference) }
}

private extension String {
    nonisolated var monthlyNonEmpty: String? { isEmpty ? nil : self }
}
