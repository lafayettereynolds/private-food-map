import Foundation

nonisolated enum DiningCompanionAvatarPresentation: Hashable, Sendable {
    case initial(String, AnalysisTone)
    case preset(ProfileAvatarPreset)
}

nonisolated enum CompanionFoodSource: String, Hashable, Sendable {
    case dish
    case cuisine
}

nonisolated struct DiningCompanionInput: Sendable {
    nonisolated struct CompanionRecord: Sendable {
        let id: UUID
        let identifiers: [String]
        let displayName: String
        let linkedTasteMapUserID: String?
        let permittedLinkedAvatarPreset: ProfileAvatarPreset?
        let updatedAt: Date
        let deletedAt: Date?
    }

    nonisolated struct RestaurantRecord: Sendable {
        let id: UUID
        let name: String
        let address: String
        let city: String
        let status: RestaurantStatus
        let preference: RestaurantJSONContractV1.RestaurantPreferenceContract
        let tags: [String]
        var merchantImageURL: URL? = nil
        let updatedAt: Date
        let deletedAt: Date?
        let isAccessible: Bool
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
        let diningMode: DiningMode
        let diningOccasionLabels: [String]
        let environmentTags: [String]
        let noiseLevelLabel: String?
        let companionIDs: [String]
        let companionNames: [String]
        let hasPrivateNote: Bool
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
        let visibility: PhotoVisibility
        let sortOrder: Int
        let updatedAt: Date
        let deletedAt: Date?
    }

    let userDisplayName: String
    let userCity: String
    let companions: [CompanionRecord]
    let restaurants: [RestaurantRecord]
    let visits: [VisitRecord]
    let dishes: [DishRecord]
    let visitDishes: [VisitDishRecord]
    let photos: [PhotoRecord]

    @MainActor
    static func capture(
        restaurants: [Restaurant],
        visits: [Visit],
        dishes: [Dish],
        visitDishes: [VisitDish],
        photos: [PhotoAsset],
        companions: [DiningCompanion],
        profiles: [UserProfile],
        socialProfiles: [CachedSocialProfile],
        friendships: [CachedFriendship]
    ) -> DiningCompanionInput {
        let profile = profiles.first(where: { $0.deletedAt == nil })
        let currentUserID = profile?.tasteMapUserID
        let permittedLinkedUserIDs = Set(friendships.compactMap { friendship -> String? in
            guard friendship.deletedAt == nil,
                  friendship.perspectiveState == .friends,
                  friendship.currentUserID == currentUserID else { return nil }
            return friendship.otherUserID
        })
        let socialProfileByID = Dictionary(
            uniqueKeysWithValues: socialProfiles.map { ($0.tasteMapUserID, $0) }
        )
        let identity = AnalysisRestaurantIdentity.projection(for: restaurants)

        return DiningCompanionInput(
            userDisplayName: profile?.displayName.trimmedForAnalysis.nilIfEmpty ?? "Taste Map 用户",
            userCity: profile?.city.trimmedForAnalysis ?? "",
            companions: companions.map { companion in
                let linked = companion.linkedTasteMapUserId
                let linkedPreset = linked.flatMap { linkedID in
                    permittedLinkedUserIDs.contains(linkedID) ? socialProfileByID[linkedID]?.avatarPreset : nil
                }
                return CompanionRecord(
                    id: companion.id,
                    identifiers: [companion.id.uuidString.lowercased(), companion.remoteID]
                        .compactMap { $0?.trimmedForAnalysis.nilIfEmpty },
                    displayName: companion.displayName,
                    linkedTasteMapUserID: linked,
                    permittedLinkedAvatarPreset: linkedPreset,
                    updatedAt: companion.updatedAt,
                    deletedAt: companion.deletedAt
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
                    address: restaurant.address,
                    city: restaurant.city,
                    status: restaurant.status,
                    preference: contract?.preferenceLevel ?? .normal,
                    tags: contract?.tags ?? [],
                    merchantImageURL: RestaurantImagePriorityPolicy.safeHTTPSURL(contract?.merchantImageUrl),
                    updatedAt: restaurant.updatedAt,
                    deletedAt: restaurant.deletedAt,
                    isAccessible: true
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
                    myActualSpend: visit.resolvedActualSpend,
                    diningMode: visit.diningMode,
                    diningOccasionLabels: visit.diningOccasionDisplayTitles,
                    environmentTags: visit.environmentTags,
                    noiseLevelLabel: visit.noiseLevel?.title,
                    companionIDs: visit.companionIDs,
                    companionNames: visit.companionNames,
                    hasPrivateNote: visit.note?.trimmedForAnalysis.nilIfEmpty != nil,
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
                VisitDishRecord(visitID: $0.visitId, dishID: $0.dishId, deletedAt: $0.deletedAt)
            },
            photos: photos.map {
                PhotoRecord(
                    id: $0.id,
                    restaurantID: identity.canonicalID(for: $0.restaurantId),
                    visitID: $0.visitId,
                    dishID: $0.dishId,
                    kind: $0.kind,
                    visibility: $0.visibility,
                    sortOrder: $0.sortOrder,
                    updatedAt: $0.updatedAt,
                    deletedAt: $0.deletedAt
                )
            }
        )
    }
}

nonisolated struct DiningCompanionFoodRank: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let source: CompanionFoodSource
    let sharedVisitCount: Int
    let share: Double
    let averageRating: Double?
}

nonisolated struct DiningCompanionRestaurantRank: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let sharedVisitCount: Int
    let latestVisit: Date
    let averageRating: Double?
    let imageReference: AnalysisImageReference
}

nonisolated struct DiningCompanionRatingSummary: Hashable, Sendable {
    let sampleCount: Int
    let sharedAverage: Double?
    let overallAverage: Double?
    let differenceFromOverall: Double?
    let valueAverage: Double?
    let environmentAverage: Double?
    let serviceAverage: Double?
    let summary: String
    let sufficiency: AnalysisDataSufficiency
}

nonisolated struct DiningCompanionSpendSummary: Hashable, Sendable {
    let sampleCount: Int
    let median: Double?
    let totalRecorded: Double?
    let summary: String
    let sufficiency: AnalysisDataSufficiency
}

nonisolated struct DiningCompanionRecommendation: Identifiable, Hashable, Sendable {
    let id: String
    let localRestaurantID: UUID?
    let name: String
    let city: String
    let reason: String
    let score: Double
    let imageReference: AnalysisImageReference
}

nonisolated struct DiningCompanionSummary: Identifiable, Hashable, Sendable {
    let id: UUID
    let displayName: String
    let avatar: DiningCompanionAvatarPresentation
    let sharedVisitCount: Int
    let restaurantCount: Int
    let latestVisit: Date?
    let topFood: String?
    let summary: String
    let sufficiency: AnalysisDataSufficiency
}

nonisolated struct DiningCompanionAnalysis: Identifiable, Hashable, Sendable {
    let id: String
    let kind: AnalysisReportKind
    let companionID: UUID
    let userDisplayName: String
    let companionDisplayName: String
    let avatar: DiningCompanionAvatarPresentation
    let sufficiency: AnalysisDataSufficiency
    let sharedVisitCount: Int
    let restaurantCount: Int
    let firstVisit: Date?
    let latestVisit: Date?
    let topFoods: [DiningCompanionFoodRank]
    let topRestaurants: [DiningCompanionRestaurantRank]
    let diningContexts: [AnalysisFrequencyItem]
    let rating: DiningCompanionRatingSummary
    let spend: DiningCompanionSpendSummary
    let repeatRestaurantRate: Double
    let weekendShare: Double
    let lateMealShare: Double
    let keywords: [String]
    let behavioralPortrait: String
    let summary: String
    let hero: FoodHeroPresentation
    let callouts: [AnalysisCallout]
    let representativeRestaurants: [RepresentativeRestaurant]
    let recommendations: [DiningCompanionRecommendation]
    let geographicScope: String?
    let dataNote: String
    let generatedAt: Date

    var hasSharedVisits: Bool { sharedVisitCount > 0 }
    var photoReferences: [AnalysisImageReference] {
        hero.imageReferences
            + topRestaurants.map(\.imageReference)
            + representativeRestaurants.map(\.imageReference)
            + recommendations.map(\.imageReference)
    }
}

nonisolated struct DiningCompanionOverview: Identifiable, Hashable, Sendable {
    let id: String
    let userDisplayName: String
    let companionCount: Int
    let companionsWithVisitsCount: Int
    let summaries: [DiningCompanionSummary]
    let analyses: [DiningCompanionAnalysis]
    let generatedAt: Date

    var lead: DiningCompanionAnalysis? { analyses.first(where: { $0.sharedVisitCount > 0 }) }
    func analysis(for companionID: UUID) -> DiningCompanionAnalysis? {
        analyses.first(where: { $0.companionID == companionID })
    }
}

private extension String {
    nonisolated var trimmedForAnalysis: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated var nilIfEmpty: String? { isEmpty ? nil : self }
}
