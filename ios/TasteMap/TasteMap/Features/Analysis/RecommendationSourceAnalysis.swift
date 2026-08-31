import Foundation

nonisolated struct RecommendationSourceInput: Sendable {
    nonisolated struct SourceRecord: Sendable {
        let id: UUID
        let identifiers: [String]
        let displayName: String
        let sourceType: RecommendationSourceType
        let updatedAt: Date
        let deletedAt: Date?
    }

    nonisolated struct RestaurantRecord: Sendable {
        let id: UUID
        let name: String
        let city: String
        let status: RestaurantStatus
        var merchantImageURL: URL? = nil
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
        let recommendationSourceID: String?
        let recommendationSourceType: RecommendationSourceType?
        let recommendationSourceText: String?
        let updatedAt: Date
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

    let userDisplayName: String
    let sources: [SourceRecord]
    let restaurants: [RestaurantRecord]
    let visits: [VisitRecord]
    let photos: [PhotoRecord]

    @MainActor
    static func capture(
        sources: [RecommendationSource],
        restaurants: [Restaurant],
        visits: [Visit],
        photos: [PhotoAsset],
        profile: UserProfile?
    ) -> RecommendationSourceInput {
        let identity = AnalysisRestaurantIdentity.projection(for: restaurants)
        return RecommendationSourceInput(
            userDisplayName: profile?.displayName.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                ?? "Taste Map 用户",
            sources: sources.map {
                SourceRecord(
                    id: $0.id,
                    identifiers: [$0.id.uuidString.lowercased(), $0.remoteID]
                        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty },
                    displayName: $0.displayName,
                    sourceType: $0.sourceType,
                    updatedAt: $0.updatedAt,
                    deletedAt: $0.deletedAt
                )
            },
            restaurants: restaurants.filter { restaurant in
                restaurant.deletedAt != nil || identity.representativeIDs.contains(restaurant.id)
            }.map { restaurant in
                let contract = restaurant.remoteRecordData.flatMap {
                    try? JSONDecoder().decode(RestaurantJSONContractV1.self, from: $0)
                }
                return RestaurantRecord(
                    id: restaurant.id,
                    name: restaurant.name,
                    city: restaurant.city,
                    status: restaurant.status,
                    merchantImageURL: RestaurantImagePriorityPolicy.safeHTTPSURL(contract?.merchantImageUrl),
                    updatedAt: restaurant.updatedAt,
                    deletedAt: restaurant.deletedAt
                )
            },
            visits: visits.map {
                VisitRecord(
                    id: $0.id,
                    restaurantID: identity.canonicalID(for: $0.restaurantId),
                    visitedAt: $0.visitedAt,
                    rating: $0.rating,
                    valueRating: $0.valueRating,
                    environmentRating: $0.environmentRating,
                    serviceRating: $0.serviceRating,
                    recommendationSourceID: $0.recommendationSourceID,
                    recommendationSourceType: $0.recommendationSourceType,
                    recommendationSourceText: $0.recommendationSourceText,
                    updatedAt: $0.updatedAt,
                    deletedAt: $0.deletedAt
                )
            },
            photos: photos.map {
                PhotoRecord(
                    id: $0.id,
                    restaurantID: identity.canonicalID(for: $0.restaurantId),
                    visitID: $0.visitId,
                    dishID: $0.dishId,
                    kind: $0.kind,
                    sortOrder: $0.sortOrder,
                    updatedAt: $0.updatedAt,
                    deletedAt: $0.deletedAt
                )
            }
        )
    }
}

nonisolated enum RecommendationSourceRatingStability: String, Hashable, Sendable {
    case insufficient
    case stable
    case forming
    case volatile

    var title: String {
        switch self {
        case .insufficient: "样本不足"
        case .stable: "评分稳定"
        case .forming: "仍在观察"
        case .volatile: "表现起伏"
        }
    }
}

nonisolated enum RecommendationSourceTrend: String, Hashable, Sendable {
    case new
    case rising
    case steady
    case cooling
    case inactive

    var title: String {
        switch self {
        case .new: "近期新出现"
        case .rising: "近期更常用"
        case .steady: "使用稳定"
        case .cooling: "近期减少"
        case .inactive: "近期未使用"
        }
    }
}

nonisolated struct RecommendationSourceRestaurantEvidence: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let city: String
    let role: String
    let detail: String
    let averageRating: Double?
    let visitCount: Int
    let acquisitionDate: Date
    let imageReference: AnalysisImageReference
}

nonisolated struct RecommendationSourceAnalysis: Identifiable, Hashable, Sendable {
    let id: UUID
    let displayName: String
    let sourceType: RecommendationSourceType
    let usageCount: Int
    let restaurantCount: Int
    let ratedRestaurantCount: Int
    let newDiscoveryCount: Int
    let repeatedRestaurantCount: Int
    let averageRating: Double?
    let valueAverage: Double?
    let environmentAverage: Double?
    let serviceAverage: Double?
    let highRatingCount: Int
    let lowRatingCount: Int
    let highRatingRate: Double
    let lowRatingRate: Double
    let repeatConversionRate: Double
    let ratingStandardDeviation: Double?
    let ratingStability: RecommendationSourceRatingStability
    let trend: RecommendationSourceTrend
    let recentRestaurantCount: Int
    let previousRestaurantCount: Int
    let latestUsageAt: Date?
    let sufficiency: AnalysisDataSufficiency
    let reliabilityScore: Double?
    let pitfallScore: Double?
    let restaurants: [RecommendationSourceRestaurantEvidence]
    let updatedAt: Date

    var hasUsage: Bool { restaurantCount > 0 }
    var photoReferences: [AnalysisImageReference] { restaurants.map(\.imageReference) }
}

nonisolated struct RecommendationSourceConclusion: Hashable, Sendable {
    let sourceID: UUID
    let displayName: String
    let title: String
    let value: String
    let explanation: String
    let tone: AnalysisTone
    let symbol: String
}

nonisolated struct RecommendationSourceOverview: Identifiable, Hashable, Sendable {
    let id: String
    let kind: AnalysisReportKind
    let userDisplayName: String
    let sourceCount: Int
    let usedSourceCount: Int
    let attributedRestaurantCount: Int
    let ratedRestaurantCount: Int
    let overallRestaurantRating: Double?
    let sources: [RecommendationSourceAnalysis]
    let mostUsed: RecommendationSourceConclusion?
    let highestAverage: RecommendationSourceConclusion?
    let bestSource: RecommendationSourceConclusion?
    let worstSource: RecommendationSourceConclusion?
    let representativeRestaurants: [RecommendationSourceRestaurantEvidence]
    let dataNote: String
    let generatedAt: Date

    var photoReferences: [AnalysisImageReference] {
        representativeRestaurants.map(\.imageReference)
            + sources.flatMap(\.photoReferences)
    }

    func analysis(for sourceID: UUID) -> RecommendationSourceAnalysis? {
        sources.first(where: { $0.id == sourceID })
    }
}

private extension String {
    nonisolated var nonEmpty: String? { isEmpty ? nil : self }
}
