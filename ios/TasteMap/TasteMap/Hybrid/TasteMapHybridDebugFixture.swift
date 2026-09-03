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

        guard !fixture.restaurants.isEmpty,
              let seedVisit = fixture.restaurants.flatMap(\.visits).first else {
            throw TasteMapHybridServiceError.invalidRequest
        }
        let visitedRestaurantCount = 90
        let wantToGoRestaurantCount = 25
        let restaurantCount = visitedRestaurantCount + wantToGoRestaurantCount
        let anchors: [(Double, Double)] = [
            (30.2741, 120.1551), (30.2676, 120.1474), (30.2819, 120.1628),
            (30.2558, 120.1692), (30.2912, 120.1398), (30.2449, 120.1825),
        ]
        var metadata: [UUID: TasteMapHybridRestaurantMetadata] = [:]
        for index in 0..<restaurantCount {
            let item = fixture.restaurants[index % fixture.restaurants.count]
            let restaurantID = index < fixture.restaurants.count
                ? (UUID(uuidString: item.id) ?? fixtureUUID(10_000 + index))
                : fixtureUUID(10_000 + index)
            let isVisited = index < visitedRestaurantCount
            let anchor = anchors[index % anchors.count]
            let ring = Double((index / anchors.count) % 7)
            let angle = Double(index * 137) * .pi / 180
            let latitude = anchor.0 + sin(angle) * (0.00018 + ring * 0.00008)
            let longitude = anchor.1 + cos(angle) * (0.00018 + ring * 0.00009)
            let restaurantCreatedAt = item.createdAt.addingTimeInterval(Double(-index) * 43_200)
            let restaurantUpdatedAt = item.updatedAt.addingTimeInterval(Double(index % 9) * -3_600)
            let restaurant = Restaurant(
                id: restaurantID,
                ownerUserID: ownerUserID,
                name: index < fixture.restaurants.count ? item.name : "\(item.name) · \(index + 1)",
                address: item.address,
                latitude: latitude,
                longitude: longitude,
                city: item.city,
                status: isVisited ? .visited : .wantToGo,
                createdAt: restaurantCreatedAt,
                updatedAt: restaurantUpdatedAt,
                remoteID: restaurantID.uuidString.lowercased(),
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

            let visitCount = isVisited ? (index < 5 ? 4 : 3) : 0
            for visitIndex in 0..<visitCount {
                let itemVisit = item.visits.first ?? seedVisit
                let visitID = fixtureUUID(100_000 + index * 10 + visitIndex)
                let visitedAt = itemVisit.visitedAt.addingTimeInterval(Double(-(index * 4 + visitIndex)) * 86_400)
                let rating = ((index + visitIndex) % 7 == 0) ? nil : 3.4 + Double((index + visitIndex) % 8) * 0.2
                context.insert(Visit(
                    id: visitID,
                    ownerUserID: ownerUserID,
                    restaurantId: restaurantID,
                    visitedAt: visitedAt,
                    rating: rating,
                    valueRating: rating.map { max(1, min(5, $0 - 0.1)) },
                    environmentRating: rating.map { max(1, min(5, $0 + 0.1)) },
                    serviceRating: rating,
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
                    createdAt: visitedAt,
                    updatedAt: visitedAt,
                    remoteID: visitID.uuidString.lowercased(),
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

    private static func fixtureUUID(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", value))!
    }
}
#endif
