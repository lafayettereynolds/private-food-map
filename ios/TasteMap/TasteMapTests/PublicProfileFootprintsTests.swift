import Foundation
import SwiftData
import Testing
@testable import TasteMap

@MainActor
struct PublicProfileFootprintsTests {
    @Test func galleryRetainsEveryAuthorizedPhotoAndDoesNotGrantExport() {
        let photos = [photo("00000000-0000-4000-8000-000000000001"), photo("00000000-0000-4000-8000-000000000002")]
        let presentation = PublicContentMediaPresentation(item: item(photos: photos, selected: photos[1]))
        #expect(presentation.galleryPhotos == photos)
        #expect(presentation.galleryPhotos.allSatisfy { $0.exportAllowed == false })
        #expect(presentation.resolution.sources == [
            .publicOrCachedPhoto(photos[0].photoId),
            .publicOrCachedPhoto(photos[1].photoId),
        ])
    }

    @Test func activityAlbumLayoutAndProvenanceAreSharedWithoutBorrowedRestaurantImages() throws {
        #expect([1, 2, 3, 4, 5, 6, 7, 12].map { PublicContentMediaPresentation.columnCount(photoCount: $0) } == [1, 2, 3, 2, 3, 3, 3, 3])
        let photos = (0..<12).map { photo("photo-\($0)") }
        var otherVisit = photo("wrong-visit"); otherVisit.visitId = "different-visit"
        var otherAuthor = photo("wrong-author"); otherAuthor.ownerUserId = "different-author"
        let album = photos + [photos[0], otherVisit, otherAuthor]
        let community = PublicContentMediaPresentation(item: item(photos: album, selected: otherVisit))
        let discovery = PublicContentMediaPresentation(card: discoveryCard(photos: album.map(\.discoveryProjection)))
        #expect(community.galleryPhotos == photos)
        #expect(discovery.galleryPhotos == photos)
        #expect(community.resolution.sources == photos.map { .publicOrCachedPhoto($0.photoId) })
        #expect(discovery.resolution.sources == community.resolution.sources)
        let legacy = try JSONDecoder().decode(DiscoveryActivityProjectionV1.self,
            from: Data(#"{"visitId":"visit","visitedAt":"2026-09-01T12:00:00Z","rating":4.5}"#.utf8))
        #expect(legacy.photos == nil)
    }

    @Test func realCachedAlbumsAndPageProjectionReachHybridWithoutMixingOwnersOrGrantingExport() throws {
        let ownerID = "tm_album_viewer"
        let container = try TasteMapPersistence.makeContainer(inMemory: true, configurationName: "ActivityAlbumProjection")
        // Only public projections are persistable. Friends-only albums remain
        // session data and must not be used to assert a durable-cache round trip.
        let photos = (0..<12).map { photo("photo-\($0)", visibility: "public") }
        let remoteCard = discoveryCard(photos: photos.map(\.discoveryProjection), cacheScope: .public)
        let decoded = try JSONDecoder().decode(DiscoveryCardV1.self, from: JSONEncoder().encode(remoteCard))
        let page = DiscoveryPageV1(apiVersion: 1, mode: .similarTaste, city: "杭州", personalizationConfidence: .high,
                                   generatedAt: "2026-09-06T00:00:00Z", items: [decoded], nextCursor: nil)
        let context = ModelContext(container)
        try LocalDiscoveryStore(context: context).replaceCache(page: page, currentUserID: ownerID, trendWindowDays: 7)
        try LocalCommunityStore(context: context).replace(items: [item(photos: photos, rating: 4.5, visibility: .public)],
            currentUserID: ownerID, routeKey: LocalCommunityStore.feedRoute(.latest), fetchedAt: .now)
        let service = try TasteMapHybridBridgeService(container: container, ownerUserID: ownerID)
        let snapshot = try service.contentSnapshot()
        let similar = try #require(snapshot.discovery.similarTaste.first)
        let latest = try #require(snapshot.community.latest.first)
        #expect(similar.activityImages?.map(\.photoID) == photos.map { Optional($0.photoId) })
        #expect(latest.activityImages?.map(\.photoID) == similar.activityImages?.map(\.photoID))
        #expect(similar.activityImages?.allSatisfy { $0.visitID == "visit" && $0.sourceOwnerID == "owner" && $0.exportAllowed == false } == true)
        #expect(try service.discoveryPageSource(page).items.first?.activityImages?.count == 12)
        let foreign = try TasteMapHybridBridgeService(container: container, ownerUserID: "tm_other_viewer").contentSnapshot()
        #expect(foreign.discovery.similarTaste.isEmpty && foreign.community.latest.isEmpty)

        let friends = (0..<12).map { photo("friend-photo-\($0)") }
        let friendPage = DiscoveryPageV1(apiVersion: 1, mode: .similarTaste, city: "杭州", personalizationConfidence: .high,
            generatedAt: page.generatedAt, items: [discoveryCard(photos: friends.map(\.discoveryProjection))], nextCursor: nil)
        try LocalDiscoveryStore(context: context).replaceCache(page: friendPage, currentUserID: ownerID, trendWindowDays: 7)
        try LocalCommunityStore(context: context).replace(items: [item(photos: friends, rating: 4.5)],
            currentUserID: ownerID, routeKey: LocalCommunityStore.feedRoute(.latest), fetchedAt: .now)
        #expect(try ModelContext(container).fetch(FetchDescriptor<CachedDiscoveryPlacement>()).isEmpty)
        #expect(try ModelContext(container).fetch(FetchDescriptor<CachedCommunityContent>()).isEmpty)
        // The DTO can carry authorized session photos without persisting them.
        #expect(try service.discoveryPageSource(friendPage).items.first?.activityImages?.count == 12)
    }

    @Test func missingPhotosUseCanonicalMerchantThenHonestFallback() {
        let withMerchant = PublicContentMediaPresentation(item: item(photos: []))
        #expect(withMerchant.galleryPhotos.isEmpty)
        #expect(withMerchant.resolution.preferredSource == .providerMerchantImage(URL(string: "https://example.com/merchant.jpg")!))
        let missing = PublicContentMediaPresentation(item: item(photos: [], merchantURL: "http://unsafe.example/photo.jpg"))
        #expect(missing.resolution.isFallbackOnly)
    }

    @Test func followsAreDirectionalAndFriendshipNeverSubstitutesForAnEdge() {
        #expect(PublicProfileFollowDirection.label(isFollowing: false, followedByOwner: false) == "关注")
        #expect(PublicProfileFollowDirection.label(isFollowing: false, followedByOwner: true) == "关注")
        #expect(PublicProfileFollowDirection.label(isFollowing: true, followedByOwner: false) == "已关注")
        #expect(PublicProfileFollowDirection.label(isFollowing: true, followedByOwner: true) == "互相关注")
        #expect(PublicProfileFollowDirection.label(isFollowing: true, followedByOwner: nil) != "互相关注")
    }

    @Test func reverseFollowOnALaterPageIsFoundWithoutTreatingFirstPageAbsenceAsFalse() async throws {
        let api = FollowAPI(pages: [page(["other"], cursor: "second"), page(["owner"], cursor: nil)])
        #expect(try await PublicProfileFollowDirection.load(ownerUserID: "owner", api: api))
        #expect(api.cursors == [nil, "second"])
        #expect(api.scopes == [.followers, .followers])
    }

    @Test func onlyExhaustionProvesNoReverseFollow() async throws {
        let api = FollowAPI(pages: [page(["other"], cursor: "second"), page([], cursor: nil)])
        #expect(try await PublicProfileFollowDirection.load(ownerUserID: "owner", api: api) == false)
        #expect(api.cursors.count == 2)
    }

    @Test func repeatedCursorAndCapacityAreErrorsNotFalse() async {
        let repeated = FollowAPI(pages: [page([], cursor: "again"), page([], cursor: "again")])
        await #expect(throws: PublicProfileFollowDirection.ReadError.self) {
            try await PublicProfileFollowDirection.load(ownerUserID: "owner", api: repeated)
        }
        let limited = FollowAPI(pages: [page([], cursor: "more")])
        await #expect(throws: PublicProfileFollowDirection.ReadError.self) {
            try await PublicProfileFollowDirection.load(ownerUserID: "owner", api: limited, maximumPages: 1)
        }
    }

    @Test func networkFailureDoesNotInventAReverseRelationship() async {
        let api = FollowAPI(pages: [])
        await #expect(throws: URLError.self) {
            try await PublicProfileFollowDirection.load(ownerUserID: "owner", api: api)
        }
    }

    private func photo(_ id: String, visibility: String = "friends") -> PublicContentPhotoV1 {
        .init(photoId: id, variant: .thumbnail, sourceType: "activityAuthorPhoto", visitId: "visit", ownerUserId: "owner", visibility: visibility, exportAllowed: false)
    }

    private func item(photos: [PublicContentPhotoV1], selected: PublicContentPhotoV1? = nil, merchantURL: String? = "https://example.com/merchant.jpg", rating: Double? = nil, visibility: ProfileVisibility = .friends) -> PublicContentItemV1 {
        .init(
            id: "visit:visit", kind: .visit, eventAt: "2026-09-01T12:00:00Z", updatedAt: "2026-09-01T12:00:00Z",
            user: .init(userId: "owner", displayName: "公开用户", bio: nil, city: "杭州", avatarPhotoId: nil, avatarPresetId: .otter, friendshipId: "friend", friendshipState: .friends, isFollowing: false),
            restaurant: .init(globalKey: "place", placeIdentities: [], name: "真实餐厅", address: "", city: "杭州", latitude: 30.2, longitude: 120.1, tags: [], pricePerPerson: nil, merchantImageUrl: merchantURL, markerEmoji: "", photo: selected),
            visit: .init(id: "visit", ownerUserId: "owner", restaurantGlobalKey: "place", visitedAt: "2026-09-01T12:00:00Z", rating: rating, note: nil, visibility: visibility, photos: photos, updatedAt: "2026-09-01T12:00:00Z"),
            viewerState: .none, cacheScope: visibility == .public ? .public : .friends
        )
    }

    private func discoveryCard(photos: [DiscoveryPhotoProjectionV1], cacheScope: DiscoveryCacheScopeV1 = .friends) -> DiscoveryCardV1 {
        let value = item(photos: [])
        let rating = DiscoveryRatingProjectionV1(value: 4.5, sampleCount: 1)
        return .init(id: "similar:visit", mode: .similarTaste, restaurant: value.restaurant.discoveryProjection,
            viewerState: .none, ratings: .init(mine: rating, community: rating, friends: rating, similarTaste: rating),
            reasons: [], sourceUser: .init(userId: "owner", displayName: "真实作者", bio: nil, city: "杭州", avatarPhotoId: nil,
                                           avatarPresetId: .otter, friendshipId: "friend", friendshipState: .friends, isFollowing: false),
            activity: .init(visitId: "visit", visitedAt: "2026-09-01T12:00:00Z", rating: 4.5, photos: photos),
            similarity: .init(percent: 80, sharedRestaurantCount: 3), trend: nil, cacheScope: cacheScope, rank: 1, score: 1)
    }

    private func page(_ ids: [String], cursor: String?) -> SocialPageV1<SocialUserResultV1> {
        .init(apiVersion: 1, items: ids.map { .init(profile: .init(userId: $0, displayName: $0, bio: nil, city: nil, avatarPhotoId: nil, avatarPresetId: .otter), friendshipId: nil, friendshipState: .none, isFollowing: false) }, nextCursor: cursor)
    }
}

@MainActor
private final class FollowAPI: SocialAPI {
    var pages: [SocialPageV1<SocialUserResultV1>]
    var cursors: [String?] = []
    var scopes: [FollowListScope] = []
    init(pages: [SocialPageV1<SocialUserResultV1>]) { self.pages = pages }
    func follows(scope: FollowListScope, cursor: String?, limit: Int) async throws -> SocialPageV1<SocialUserResultV1> {
        cursors.append(cursor); scopes.append(scope)
        guard !pages.isEmpty else { throw URLError(.notConnectedToInternet) }
        return pages.removeFirst()
    }
    func search(query: String, cursor: String?, limit: Int) async throws -> SocialPageV1<SocialUserResultV1> { throw URLError(.unsupportedURL) }
    func friendships(scope: FriendshipListScope, cursor: String?, limit: Int) async throws -> SocialPageV1<SocialUserResultV1> { throw URLError(.unsupportedURL) }
    func profileContext(userID: String) async throws -> SocialProfileContextV1 { throw URLError(.unsupportedURL) }
    func requestFriend(userID: String) async throws -> FriendshipMutationResponseV1 { throw URLError(.unsupportedURL) }
    func mutateFriendship(id: String, action: FriendshipMutationAction) async throws -> FriendshipMutationResponseV1 { throw URLError(.unsupportedURL) }
    func setFollowing(_ following: Bool, userID: String) async throws -> FollowMutationResponseV1 { throw URLError(.unsupportedURL) }
}
