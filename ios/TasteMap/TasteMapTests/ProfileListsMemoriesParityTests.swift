import SwiftData
import SwiftUI
import Testing
@testable import TasteMap

@Suite("Task 05 Profile Lists and Memories Parity", .serialized)
@MainActor
struct ProfileListsMemoriesParityTests {
    @Test("Profile statistics and drill-down scope reject another authenticated owner")
    func profileOwnerSwitching() throws {
        let owned = try restaurant(name: "A 的餐厅", owner: "tm_a", index: 1)
        let other = try restaurant(name: "B 的餐厅", owner: "tm_b", index: 2)
        let ownVisit = Visit(ownerUserID: "tm_a", restaurantId: owned.id, rating: 4.5, myActualSpend: 88)
        let otherVisit = Visit(ownerUserID: "tm_b", restaurantId: other.id, rating: 1, myActualSpend: 999)

        let a = ProfileOwnedContentScope.capture(
            currentUserID: "tm_a",
            restaurants: [owned, other],
            visits: [ownVisit, otherVisit]
        )
        let b = ProfileOwnedContentScope.capture(
            currentUserID: "tm_b",
            restaurants: [owned, other],
            visits: [ownVisit, otherVisit]
        )
        let aStats = ProfileBasicStatistics(restaurants: a.restaurants, visits: a.visits)
        let bStats = ProfileBasicStatistics(restaurants: b.restaurants, visits: b.visits)

        #expect(a.restaurants.map(\.name) == ["A 的餐厅"])
        #expect(aStats.visitCount == 1)
        #expect(aStats.averageRating == 4.5)
        #expect(aStats.totalSpend == 88)
        #expect(b.restaurants.map(\.name) == ["B 的餐厅"])
        #expect(bStats.totalSpend == 999)
    }

    @Test("Social statistics follow every cursor and deduplicate users")
    func socialStatisticsPagination() async throws {
        let api = ProfileStatisticsSocialAPI()
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let result = await ProfileSocialStatisticsLoader.load(
            api: api,
            context: container.mainContext,
            currentUserID: "tm_a"
        )
        #expect(result.friendCount == 3)
        #expect(result.followingCount == 2)
        #expect(result.followerCount == 4)
        #expect(api.friendPageRequests == 2)
    }

    @Test("Custom list cover accepts only the owner's uploaded public restaurant photo")
    func safeCustomCover() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let ownedRestaurant = try restaurant(name: "Own", owner: "tm_a", index: 10)
        let otherRestaurant = try restaurant(name: "Other", owner: "tm_b", index: 11)
        let ownedPhoto = try photo(restaurant: ownedRestaurant, owner: "tm_a", index: 20)
        let otherPhoto = try photo(restaurant: otherRestaurant, owner: "tm_b", index: 21)
        context.insert(ownedRestaurant)
        context.insert(otherRestaurant)
        context.insert(ownedPhoto)
        context.insert(otherPhoto)
        let store = LocalRestaurantListStore(context: context)
        let list = try store.create(ownerUserID: "tm_a", title: "封面测试")

        try store.update(
            list, actorUserID: "tm_a", title: list.title, description: "",
            visibility: .public, isRanked: false, coverMode: .custom,
            customCoverPhotoID: ownedPhoto.remoteID
        )
        #expect(list.customCoverPhotoID == ownedPhoto.remoteID)
        #expect(throws: RestaurantListStoreError.invalidCoverPhoto) {
            try store.update(
                list, actorUserID: "tm_a", title: list.title, description: "",
                visibility: .public, isRanked: false, coverMode: .custom,
                customCoverPhotoID: otherPhoto.remoteID
            )
        }
    }

    @Test("On This Day poster is fixed light 1080 by 1920 output")
    func onThisDayPoster() throws {
        let memory = OnThisDayMemory(
            id: UUID(), restaurantID: UUID(), year: 2025, yearsAgo: 1,
            visitedAt: Date(timeIntervalSince1970: 1_756_473_600),
            restaurantName: "湖畔小馆", city: "杭州", rating: 4.5,
            note: "一顿值得记住的晚饭", spend: 268,
            companions: ["小林"], recommendationSource: "朋友推荐",
            dishNames: ["龙井虾仁"], imageReference: .none
        )
        let report = OnThisDayReport(
            referenceDate: Date(timeIntervalSince1970: 1_788_000_000),
            month: 8, day: 29,
            groups: [.init(year: 2025, memories: [memory])]
        )
        let light = try AnalysisPosterRenderer.render(
            content: OnThisDayPosterView(report: report, resolvedImages: [:]),
            canvasSize: OnThisDayPosterView.canvasSize
        )
        let darkHost = try AnalysisPosterRenderer.render(
            content: OnThisDayPosterView(report: report, resolvedImages: [:])
                .environment(\.colorScheme, .dark),
            canvasSize: OnThisDayPosterView.canvasSize
        )
        #expect(OnThisDayPosterView.canvasSize == CGSize(width: 1_080, height: 1_920))
        #expect(light.cgImage?.width == 1_080)
        #expect(light.cgImage?.height == 1_920)
        #expect(light.pngData() == darkHost.pngData())
        #expect(report.posterID.contains(memory.id.uuidString.lowercased()))
    }

    private func restaurant(name: String, owner: String, index: Int) throws -> Restaurant {
        let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!
        let timestamp = "2026-08-29T12:00:00.000Z"
        let contract = try RestaurantJSONContractV1(
            id: id.uuidString.lowercased(), userId: owner,
            placeIdentities: [try .init(
                provider: .manual, externalId: "manual-\(index)", isPrimary: true,
                createdAt: timestamp, updatedAt: timestamp
            )],
            name: name, address: "测试路", city: "杭州", latitude: 30, longitude: 120,
            status: .visited, preferenceLevel: .normal,
            overallRating: nil, foodRating: nil, environmentRating: nil,
            serviceRating: nil, valueRating: nil, tags: [], longTermNote: "",
            pricePerPerson: nil, phone: nil, openingHours: nil,
            markerType: .emoji, markerPhotoId: nil, merchantImageUrl: nil,
            markerEmoji: "🍽️", createdAt: timestamp, updatedAt: timestamp, deletedAt: nil
        )
        return Restaurant(
            id: id, ownerUserID: owner,
            name: name, address: "测试路", latitude: 30, longitude: 120,
            city: "杭州", status: .visited, remoteID: id.uuidString.lowercased(),
            syncStatus: .synced, remoteRecordData: try JSONEncoder().encode(contract)
        )
    }

    private func photo(restaurant: Restaurant, owner: String, index: Int) throws -> PhotoAsset {
        let id = UUID(uuidString: String(format: "00000000-0000-0000-0001-%012d", index))!
        let timestamp = "2026-08-29T12:00:00.000Z"
        let contract = try PhotoSyncContractV1(
            id: id.uuidString.lowercased(), userId: owner,
            restaurantId: restaurant.remoteID, visitId: nil, dishId: nil,
            kind: .restaurantMarker, storageProvider: .r2, storageKey: "photos/\(id)",
            providerAccountId: nil, thumbnailStorageKey: "thumbs/\(id)",
            fileName: "cover.jpg", mimeType: "image/jpeg", byteSize: 100,
            width: 1200, height: 900, sortOrder: 0, visibility: .public,
            createdAt: timestamp, updatedAt: timestamp, deletedAt: nil
        )
        return PhotoAsset(
            id: id, ownerUserID: owner,
            restaurantId: restaurant.id, kind: .restaurantMarker,
            storageProvider: .r2, storageKey: contract.storageKey,
            thumbnailStorageKey: contract.thumbnailStorageKey, fileName: contract.fileName,
            mimeType: contract.mimeType, byteSize: contract.byteSize,
            width: contract.width, height: contract.height, visibility: .public,
            uploadState: .uploaded, remoteID: contract.id, syncStatus: .synced,
            remoteRecordData: try JSONEncoder().encode(contract)
        )
    }
}

@MainActor
private final class ProfileStatisticsSocialAPI: SocialAPI {
    var friendPageRequests = 0

    func friendships(scope: FriendshipListScope, cursor: String?, limit: Int) async throws -> SocialPageV1<SocialUserResultV1> {
        friendPageRequests += 1
        if cursor == nil {
            return page([user("friend-1"), user("friend-2")], next: "friends-2")
        }
        return page([user("friend-2"), user("friend-3")], next: nil)
    }

    func follows(scope: FollowListScope, cursor: String?, limit: Int) async throws -> SocialPageV1<SocialUserResultV1> {
        switch scope {
        case .following: page([user("following-1"), user("following-2")], next: nil)
        case .followers: page((1...4).map { user("follower-\($0)") }, next: nil)
        }
    }

    func search(query: String, cursor: String?, limit: Int) async throws -> SocialPageV1<SocialUserResultV1> { page([], next: nil) }
    func profileContext(userID: String) async throws -> SocialProfileContextV1 { throw StubError.unused }
    func requestFriend(userID: String) async throws -> FriendshipMutationResponseV1 { throw StubError.unused }
    func mutateFriendship(id: String, action: FriendshipMutationAction) async throws -> FriendshipMutationResponseV1 { throw StubError.unused }
    func setFollowing(_ following: Bool, userID: String) async throws -> FollowMutationResponseV1 { throw StubError.unused }

    private func user(_ id: String) -> SocialUserResultV1 {
        .init(
            profile: .init(
                userId: id, displayName: id, bio: nil, city: nil,
                avatarPhotoId: nil, avatarPresetId: .otter
            ),
            friendshipId: nil, friendshipState: .friends, isFollowing: false
        )
    }

    private func page(_ users: [SocialUserResultV1], next: String?) -> SocialPageV1<SocialUserResultV1> {
        .init(apiVersion: 1, items: users, nextCursor: next)
    }

    private enum StubError: Error { case unused }
}
