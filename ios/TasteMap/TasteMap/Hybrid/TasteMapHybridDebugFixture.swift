#if DEBUG
import Foundation
import SwiftData

public enum TasteMapHybridDebugFixture {
    public static let ownerUserID = "tm_hybrid_debug"

    @MainActor
    public static func makeService(fixtureData: Data) throws -> TasteMapHybridBridgeService {
        let fixture = try Self.decoder.decode(DebugRoot.self, from: fixtureData)
        let schema = Schema([Restaurant.self, Visit.self, UserProfile.self, CachedFollow.self])
        let configuration = ModelConfiguration(
            "TasteMapHybridDebug",
            schema: schema,
            isStoredInMemoryOnly: true,
            groupContainer: .none,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let profile = UserProfile(
            tasteMapUserID: ownerUserID,
            displayName: fixture.profile.user.nickname,
            bio: fixture.profile.user.bio,
            city: fixture.profile.user.city,
            avatarPhotoID: fixture.profile.user.avatarPhotoId,
            avatarPreset: ProfileAvatarPreset(rawValue: fixture.profile.user.avatarPresetId) ?? .otter,
            visibility: ProfileVisibility(rawValue: fixture.profile.user.mapVisibility) ?? .private,
            createdAt: fixture.profile.user.createdAt,
            updatedAt: fixture.profile.user.updatedAt,
            syncStatus: .synced
        )
        context.insert(profile)

        var metadata: [UUID: TasteMapHybridRestaurantMetadata] = [:]
        for item in fixture.restaurants {
            guard let restaurantID = UUID(uuidString: item.id) else { continue }
            let restaurant = Restaurant(
                id: restaurantID,
                ownerUserID: ownerUserID,
                name: item.name,
                address: item.address,
                latitude: item.latitude,
                longitude: item.longitude,
                city: item.city,
                status: RestaurantStatus(rawValue: item.status) ?? .visited,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt,
                remoteID: item.id,
                serverVersion: 1,
                lastSyncedAt: .now,
                syncStatus: .synced
            )
            context.insert(restaurant)
            metadata[restaurantID] = TasteMapHybridRestaurantMetadata(
                tags: item.tags,
                phone: item.phone,
                openingHours: item.openingHours,
                referencePrice: item.averagePricePerPerson,
                providerMerchantImageURL: item.merchantImageUrl
            )

            for itemVisit in item.visits {
                guard let visitID = UUID(uuidString: itemVisit.id) else { continue }
                context.insert(Visit(
                    id: visitID,
                    ownerUserID: ownerUserID,
                    restaurantId: restaurantID,
                    visitedAt: itemVisit.visitedAt,
                    rating: itemVisit.rating,
                    valueRating: itemVisit.valueRating,
                    environmentRating: itemVisit.environmentRating,
                    serviceRating: itemVisit.serviceRating,
                    note: itemVisit.note,
                    myActualSpend: itemVisit.myActualSpend.map { Decimal($0) },
                    totalPrice: itemVisit.totalPrice.map { Decimal($0) },
                    pricePerPerson: itemVisit.pricePerPerson.map { Decimal($0) },
                    diningMode: DiningMode(rawValue: itemVisit.diningMode) ?? .dineIn,
                    visibility: VisitVisibility(rawValue: itemVisit.visibility) ?? .private,
                    paymentMode: itemVisit.paymentMode.flatMap(VisitPaymentMode.init(rawValue:)),
                    queueDuration: itemVisit.queueDuration.flatMap(VisitQueueDuration.init(rawValue:)),
                    diningOccasions: itemVisit.diningOccasions.compactMap(VisitDiningOccasion.init(rawValue:)),
                    diningOccasionText: itemVisit.diningOccasionText,
                    valueTags: itemVisit.valueTags,
                    environmentTags: itemVisit.environmentTags,
                    serviceTags: itemVisit.serviceTags,
                    companionIDs: itemVisit.companionIds,
                    companionNames: itemVisit.companions,
                    recommendationSourceText: itemVisit.recommendationSourceText,
                    partySize: itemVisit.partySize,
                    createdAt: itemVisit.createdAt,
                    updatedAt: itemVisit.updatedAt,
                    remoteID: itemVisit.id,
                    serverVersion: 1,
                    lastSyncedAt: .now,
                    syncStatus: .synced
                ))
            }
        }

        for index in 0..<fixture.profile.followingCount {
            context.insert(CachedFollow(
                relationshipID: "hybrid-following-\(index)",
                currentUserID: ownerUserID,
                followerUserID: ownerUserID,
                followedUserID: "tm_followed_\(index)",
                serverVersion: 1
            ))
        }
        for index in 0..<fixture.profile.followerCount {
            context.insert(CachedFollow(
                relationshipID: "hybrid-follower-\(index)",
                currentUserID: ownerUserID,
                followerUserID: "tm_follower_\(index)",
                followedUserID: ownerUserID,
                serverVersion: 1
            ))
        }
        try context.save()
        return try TasteMapHybridBridgeService(
            container: container,
            ownerUserID: ownerUserID,
            membershipTier: "member",
            mapSharingEnabled: true,
            metadataByRestaurantID: metadata
        )
    }

    private struct DebugRoot: Decodable {
        let profile: DebugProfile
        let restaurants: [DebugRestaurant]
    }

    private struct DebugProfile: Decodable {
        let user: DebugUser
        let followerCount: Int
        let followingCount: Int
    }

    private struct DebugUser: Decodable {
        let nickname: String
        let bio: String
        let city: String
        let avatarPhotoId: String?
        let avatarPresetId: String
        let mapVisibility: String
        let createdAt: Date
        let updatedAt: Date
    }

    private struct DebugRestaurant: Decodable {
        let id: String
        let name: String
        let address: String
        let city: String
        let latitude: Double
        let longitude: Double
        let status: String
        let tags: [String]
        let phone: String?
        let openingHours: String?
        let averagePricePerPerson: Double?
        let merchantImageUrl: String?
        let createdAt: Date
        let updatedAt: Date
        let visits: [DebugVisit]
    }

    private struct DebugVisit: Decodable {
        let id: String
        let visitedAt: Date
        let rating: Double?
        let valueRating: Double?
        let environmentRating: Double?
        let serviceRating: Double?
        let myActualSpend: Double?
        let totalPrice: Double?
        let pricePerPerson: Double?
        let diningMode: String
        let visibility: String
        let paymentMode: String?
        let queueDuration: String?
        let diningOccasions: [String]
        let diningOccasionText: String
        let valueTags: [String]
        let environmentTags: [String]
        let serviceTags: [String]
        let companions: [String]
        let companionIds: [String]
        let recommendationSourceText: String
        let partySize: Int?
        let note: String
        let createdAt: Date
        let updatedAt: Date
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
#endif
