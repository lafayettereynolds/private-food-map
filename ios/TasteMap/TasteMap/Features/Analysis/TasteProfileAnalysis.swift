import CryptoKit
import Foundation

nonisolated enum AnalysisReportKind: String, Hashable, Sendable {
    case tasteProfile
    case companion
    case recommendationSource
    case monthlyReview
    case annualReview
}

nonisolated enum AnalysisDataSufficiency: String, Hashable, Sendable {
    case insufficient
    case emerging
    case established

    var title: String {
        switch self {
        case .insufficient: "正在形成"
        case .emerging: "初步形成"
        case .established: "稳定画像"
        }
    }
}

nonisolated enum AnalysisSufficiencyPolicy {
    nonisolated static func level(
        sampleCount: Int,
        emergingAt: Int = 3,
        establishedAt: Int = 10
    ) -> AnalysisDataSufficiency {
        if sampleCount < emergingAt { return .insufficient }
        if sampleCount < establishedAt { return .emerging }
        return .established
    }
}

nonisolated enum AnalysisTone: String, Hashable, Sendable {
    case brand
    case ingredientRed
    case leafGreen
    case cream
    case caramel
}

nonisolated enum FoodHeroTheme: String, CaseIterable, Hashable, Sendable {
    case japanese
    case hotpotGrill
    case chinese
    case western
    case cafe
    case mixed

    nonisolated var assetName: String {
        switch self {
        case .japanese: "FoodHeroJapanese"
        case .hotpotGrill: "FoodHeroHotpotGrill"
        case .chinese: "FoodHeroChinese"
        case .western: "FoodHeroWestern"
        case .cafe: "FoodHeroCafe"
        case .mixed: "FoodHeroMixed"
        }
    }

    nonisolated var title: String {
        switch self {
        case .japanese: "日料拼盘"
        case .hotpotGrill: "火锅与烧烤"
        case .chinese: "中式家常味"
        case .western: "西式主菜"
        case .cafe: "咖啡与甜点"
        case .mixed: "多元口味拼盘"
        }
    }
}

nonisolated enum AnalysisImageReference: Hashable, Sendable {
    case photo(UUID)
    case provider(URL)
    case asset(String)
    case none

    /// Stable dictionary key shared by page and poster image resolution.
    /// Provider URLs use SHA-256 rather than Swift's randomized `Hasher`, so a
    /// render never changes identity between launches.
    nonisolated var resolutionKey: UUID? {
        switch self {
        case .photo(let id):
            return id
        case .provider(let url):
            let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
                .map { String(format: "%02x", $0) }
                .joined()
            let value = "\(digest.prefix(8))-\(digest.dropFirst(8).prefix(4))-\(digest.dropFirst(12).prefix(4))-\(digest.dropFirst(16).prefix(4))-\(digest.dropFirst(20).prefix(12))"
            return UUID(uuidString: value)
        case .asset, .none:
            return nil
        }
    }
}

nonisolated struct TasteProfileInput: Sendable {
    nonisolated struct RestaurantRecord: Sendable {
        let id: UUID
        let name: String
        let address: String
        let city: String
        let status: String
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
        let diningMode: String
        let diningOccasionLabels: [String]
        let diningOccasionText: String?
        let valueTags: [String]
        let environmentTags: [String]
        let serviceTags: [String]
        let noiseLevelLabel: String?
        let companionIDs: [String]
        let companionNames: [String]
        let recommendationSourceID: String?
        let recommendationSourceTypeLabel: String?
        let recommendationSourceText: String?
        let createdAt: Date
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
        let sortOrder: Int
        let deletedAt: Date?
    }

    nonisolated struct PhotoRecord: Sendable {
        let id: UUID
        let restaurantID: UUID?
        let visitID: UUID?
        let dishID: UUID?
        let kind: String
        let sortOrder: Int
        let updatedAt: Date
        let deletedAt: Date?
    }

    nonisolated struct DirectoryRecord: Sendable {
        let identifiers: [String]
        let displayName: String
        let deletedAt: Date?
    }

    let userDisplayName: String
    let restaurants: [RestaurantRecord]
    let visits: [VisitRecord]
    let dishes: [DishRecord]
    let visitDishes: [VisitDishRecord]
    let photos: [PhotoRecord]
    let companions: [DirectoryRecord]
    let recommendationSources: [DirectoryRecord]

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
    ) -> TasteProfileInput {
        let identity = AnalysisRestaurantIdentity.projection(for: restaurants)
        return TasteProfileInput(
            userDisplayName: profile?.displayName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "Taste Map 用户",
            restaurants: restaurants.filter { restaurant in
                restaurant.deletedAt != nil || identity.representativeIDs.contains(restaurant.id)
            }.map { restaurant in
                let contract = restaurant.remoteRecordData.flatMap {
                    try? JSONDecoder().decode(RestaurantJSONContractV1.self, from: $0)
                }
                return RestaurantRecord(
                    id: restaurant.id,
                    name: restaurant.name,
                    address: restaurant.address,
                    city: restaurant.city,
                    status: restaurant.status.rawValue,
                    tags: contract?.tags ?? [],
                    merchantImageURL: RestaurantImagePriorityPolicy.safeHTTPSURL(contract?.merchantImageUrl),
                    createdAt: restaurant.createdAt,
                    updatedAt: restaurant.updatedAt,
                    deletedAt: restaurant.deletedAt
                )
            },
            visits: visits.map { visit in
                VisitRecord(
                    id: visit.id,
                    restaurantID: identity.canonicalID(for: visit.restaurantId),
                    visitedAt: visit.visitedAt,
                    rating: visit.rating,
                    valueRating: visit.valueRating,
                    environmentRating: visit.environmentRating,
                    serviceRating: visit.serviceRating,
                    myActualSpend: visit.myActualSpend,
                    diningMode: visit.diningMode.rawValue,
                    diningOccasionLabels: visit.diningOccasionDisplayTitles,
                    diningOccasionText: visit.diningOccasionText,
                    valueTags: visit.valueTags,
                    environmentTags: visit.environmentTags,
                    serviceTags: visit.serviceTags,
                    noiseLevelLabel: visit.noiseLevel?.title,
                    companionIDs: visit.companionIDs,
                    companionNames: visit.companionNames,
                    recommendationSourceID: visit.recommendationSourceID,
                    recommendationSourceTypeLabel: visit.recommendationSourceType?.title,
                    recommendationSourceText: visit.recommendationSourceText,
                    createdAt: visit.createdAt,
                    updatedAt: visit.updatedAt,
                    deletedAt: visit.deletedAt
                )
            },
            dishes: dishes.map {
                DishRecord(
                    id: $0.id,
                    restaurantID: identity.canonicalID(for: $0.restaurantId),
                    originVisitID: $0.visitId,
                    name: $0.name,
                    taste: $0.taste,
                    rating: $0.rating,
                    updatedAt: $0.updatedAt,
                    deletedAt: $0.deletedAt
                )
            },
            visitDishes: visitDishes.map {
                VisitDishRecord(
                    visitID: $0.visitId,
                    dishID: $0.dishId,
                    sortOrder: $0.sortOrder,
                    deletedAt: $0.deletedAt
                )
            },
            photos: photos.map {
                PhotoRecord(
                    id: $0.id,
                    restaurantID: identity.canonicalID(for: $0.restaurantId),
                    visitID: $0.visitId,
                    dishID: $0.dishId,
                    kind: $0.kind.rawValue,
                    sortOrder: $0.sortOrder,
                    updatedAt: $0.updatedAt,
                    deletedAt: $0.deletedAt
                )
            },
            companions: companions.map {
                DirectoryRecord(
                    identifiers: [$0.id.uuidString.lowercased(), $0.remoteID].compactMap { $0 },
                    displayName: $0.displayName,
                    deletedAt: $0.deletedAt
                )
            },
            recommendationSources: recommendationSources.map {
                DirectoryRecord(
                    identifiers: [$0.id.uuidString.lowercased(), $0.remoteID].compactMap { $0 },
                    displayName: $0.displayName,
                    deletedAt: $0.deletedAt
                )
            }
        )
    }
}

nonisolated struct TastePreferenceRank: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let score: Double
    let visitCount: Int
    let restaurantCount: Int
    let repeatVisitCount: Int
    let averageRating: Double?
    let ratedVisitCount: Int
}

nonisolated struct AnalysisFrequencyItem: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let count: Int
    let share: Double
}

nonisolated struct SpendDistributionItem: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let count: Int
    let share: Double
}

nonisolated struct TasteProfileSpendAnalysis: Hashable, Sendable {
    let sampleCount: Int
    let median: Double?
    let lowerQuartile: Double?
    let upperQuartile: Double?
    let typicalBucket: String?
    let distribution: [SpendDistributionItem]
    let sufficiency: AnalysisDataSufficiency
}

nonisolated struct TasteProfileRatingStyle: Hashable, Sendable {
    let sampleCount: Int
    let average: Double?
    let median: Double?
    let standardDeviation: Double?
    let highRatingShare: Double
    let lowRatingShare: Double
    let label: String
    let detail: String
    let dimensionSummary: String?
    let sufficiency: AnalysisDataSufficiency
}

nonisolated struct TasteProfileRepeatAnalysis: Hashable, Sendable {
    let repeatedRestaurantCount: Int
    let visitedRestaurantCount: Int
    let rate: Double
    let label: String
    let detail: String
    let sufficiency: AnalysisDataSufficiency
}

nonisolated struct TasteProfileTimeAnalysis: Hashable, Sendable {
    let label: String?
    let sampleCount: Int
    let share: Double
    let detail: String
    let timeZoneNotice: String
    let sufficiency: AnalysisDataSufficiency
}

nonisolated struct FoodHeroPresentation: Hashable, Sendable {
    let theme: FoodHeroTheme
    let primaryTheme: String
    let secondaryThemes: [String]
    let labels: [String]
    let imageReferences: [AnalysisImageReference]
    let fallbackAssetName: String
    let tone: AnalysisTone
}

nonisolated struct AnalysisCallout: Identifiable, Hashable, Sendable {
    let id: String
    let icon: String
    let title: String
    let value: String
    let detail: String
    let tone: AnalysisTone
    let sufficiency: AnalysisDataSufficiency
}

nonisolated struct AnalysisInsight: Identifiable, Hashable, Sendable {
    let id: String
    let icon: String
    let title: String
    let value: String
    let detail: String
    let tone: AnalysisTone
    let sufficiency: AnalysisDataSufficiency

    var isAvailable: Bool { sufficiency != .insufficient }
}

nonisolated struct RepresentativeRestaurant: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let role: String
    let detail: String
    let averageRating: Double?
    let visitCount: Int
    let imageReference: AnalysisImageReference
}

nonisolated struct TasteProfileAnalysis: Identifiable, Hashable, Sendable {
    let id: String
    let kind: AnalysisReportKind
    let userDisplayName: String
    let title: String
    let eyebrow: String
    let subtitle: String
    let summary: String
    let generatedAt: Date
    let visitCount: Int
    let ratedVisitCount: Int
    let sufficiency: AnalysisDataSufficiency
    let favoriteStatement: String
    let cuisineRanking: [TastePreferenceRank]
    let spend: TasteProfileSpendAnalysis
    let diningScenes: [AnalysisFrequencyItem]
    let recommendationSources: [AnalysisFrequencyItem]
    let companions: [AnalysisFrequencyItem]
    let ratingStyle: TasteProfileRatingStyle
    let repeatAnalysis: TasteProfileRepeatAnalysis
    let diningTime: TasteProfileTimeAnalysis
    let keywords: [String]
    let hero: FoodHeroPresentation
    let callouts: [AnalysisCallout]
    let insights: [AnalysisInsight]
    let restaurants: [RepresentativeRestaurant]
    let dataNote: String
    let footer: String

    var hasAnyData: Bool { visitCount > 0 }
    var availableInsights: [AnalysisInsight] { insights.filter(\.isAvailable) }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
