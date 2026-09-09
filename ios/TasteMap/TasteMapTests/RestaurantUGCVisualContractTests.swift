import Foundation
import Testing
@testable import TasteMap

@Suite("Restaurant UGC visual contract")
struct RestaurantUGCVisualContractTests {
    @Test("Category taxonomy is stable and evidence-based")
    func categories() {
        #expect(FoodCategoryVisualID.allCases.map(\.rawValue) == [
            "chinese", "japaneseKorean", "western", "hotpotBBQ", "noodles",
            "cafeBakery", "drinksDessert", "seafood", "fastFood", "vegetarianLight", "other",
        ])
        #expect(FoodCategoryVisualResolver.resolve(name: "牛New寿喜烧", tags: ["日料"]) == .japaneseKorean)
        #expect(FoodCategoryVisualResolver.resolve(name: "木屋烧烤") == .hotpotBBQ)
        #expect(FoodCategoryVisualResolver.resolve(name: "湖滨二十八号", tags: ["杭帮菜"]) == .chinese)
        #expect(FoodCategoryVisualResolver.resolve(name: "无分类餐厅") == .other)
    }

    @Test("Restaurant food emoji follows explicit choice, food evidence, then category fallback")
    func foodEmojiFallback() {
        #expect(FoodCategoryEmojiResolver.resolve(name: "街角咖啡") == "☕️")
        #expect(FoodCategoryEmojiResolver.resolve(name: "经典牛排馆") == "🥩")
        #expect(FoodCategoryEmojiResolver.resolve(name: "青岚寿司") == "🍣")
        #expect(FoodCategoryEmojiResolver.resolve(name: "春日泰味") == "🍛")
        #expect(FoodCategoryEmojiResolver.resolve(name: "湖滨粤菜") == "🥟")
        #expect(FoodCategoryEmojiResolver.resolve(name: "山岚咖啡", preferredEmoji: "🍽️") == "☕️")
        #expect(FoodCategoryEmojiResolver.resolve(name: "山岚咖啡", preferredEmoji: "🍴") == "☕️")
        #expect(FoodCategoryEmojiResolver.resolve(name: "山岚小馆", preferredEmoji: "🌮") == "🌮")
        #expect(FoodCategoryEmojiResolver.resolve(name: "无分类餐厅") == "🍽️")
    }

    @Test("Owner, activity and public eligibility preserve privacy and export boundaries")
    func pool() {
        let owner = record(id: "owner", owner: "tm_viewer", visibility: "private")
        let publicPhoto = record(id: "public", owner: "tm_author", visibility: "public")
        let friendPhoto = record(id: "friend", owner: "tm_friend", visibility: "friends")
        let deleted = record(id: "deleted", owner: "tm_author", visibility: "public", deletedAt: .now)
        let records = [publicPhoto, friendPhoto, deleted, owner]

        #expect(RestaurantUGCImagePool.currentOwnerPhoto(
            records: records, currentOwnerID: "tm_viewer", restaurantID: "restaurant"
        )?.record.photoID == "owner")
        #expect(RestaurantUGCImagePool.currentOwnerPhoto(
            records: records, currentOwnerID: "tm_viewer", restaurantID: "restaurant"
        )?.exportAllowed == true)
        #expect(RestaurantUGCImagePool.publicUGC(records: records, restaurantID: "restaurant")?.record.photoID == "public")
        #expect(RestaurantUGCImagePool.publicUGC(records: records, restaurantID: "restaurant")?.exportAllowed == false)
        #expect(RestaurantUGCImagePool.activityPhoto(
            records: records, visibleVisitID: "visit", currentOwnerID: "tm_viewer", canSeeFriends: false
        )?.record.photoID == "owner")

        let friendOnly = RestaurantUGCImagePool.activityPhoto(
            records: [friendPhoto], visibleVisitID: "visit", currentOwnerID: "tm_viewer", canSeeFriends: false
        )
        #expect(friendOnly == nil)
        #expect(RestaurantUGCImagePool.activityPhoto(
            records: [friendPhoto], visibleVisitID: "visit", currentOwnerID: "tm_viewer", canSeeFriends: true
        )?.record.photoID == "friend")
    }

    @Test("Every product surface uses the formal visual source matrix")
    func surfaceMatrix() {
        let owner = record(id: "owner", owner: "tm_viewer", visibility: "private")
        let activity = RestaurantUGCImageRecord(
            photoID: "activity", restaurantID: "restaurant", visitID: "activity-visit",
            ownerUserID: "tm_author", visibility: "public", visitVisibility: "public",
            profileVisibility: "public", moderationEligible: true, deletedAt: nil,
            binaryDeletedAt: nil, createdAt: .now, markerPreferred: false,
            resourceURL: "tastemap-resource://public-photo/activity/display"
        )
        let records = [owner, activity]
        for surface in [RestaurantVisualSurface.map, .search, .nearby, .detail, .forYou, .trending] {
            #expect(RestaurantUGCImagePool.resolve(
                surface: surface, records: records, currentOwnerID: "tm_viewer", restaurantID: "restaurant",
                activityVisitID: "activity-visit"
            )?.sourceType == .currentOwnerPhoto)
        }
        for surface in [RestaurantVisualSurface.following, .similarTaste, .latest] {
            #expect(RestaurantUGCImagePool.resolve(
                surface: surface, records: records, currentOwnerID: "tm_viewer", restaurantID: "restaurant",
                activityVisitID: "activity-visit"
            )?.sourceType == .activityAuthorPhoto)
        }
        #expect(RestaurantUGCImagePool.resolve(
            surface: .forYou, records: [], currentOwnerID: "tm_viewer", restaurantID: "restaurant"
        ) == nil)
    }

    @Test("Deleting owner photos exhausts Personal Map to category, never another user's public UGC")
    func deletedOwnerFallbackIsSurfaceScoped() {
        let first = record(id: "owner", owner: "tm_viewer", visibility: "private")
        let remaining = record(id: "remaining", owner: "tm_viewer", visibility: "private")
        let foreign = record(id: "public", owner: "tm_other", visibility: "public")
        let deletedFirst = record(id: "owner", owner: "tm_viewer", visibility: "private", deletedAt: .now)
        let deletedRemaining = record(id: "remaining", owner: "tm_viewer", visibility: "private", deletedAt: .now)
        let snapshots = [[first, remaining, foreign], [deletedFirst, remaining, foreign], [deletedFirst, deletedRemaining, foreign]]
        let expectedIDs: [String?] = ["owner", "remaining", nil]
        // Repeated reads represent Map/List/Detail return projections, not a device smoke claim.
        for (records, expectedID) in zip(snapshots, expectedIDs) {
            for _ in 0..<3 {
                let map = RestaurantUGCImagePool.resolve(surface: .map, records: records,
                    currentOwnerID: "tm_viewer", restaurantID: "restaurant")
                #expect(map?.record.photoID == expectedID)
                #expect(map?.record.ownerUserID != "tm_other")
            }
        }
        // A nil photo selection delegates to the established category renderer.
        for surface in [RestaurantVisualSurface.search, .nearby, .detail, .forYou, .trending] {
            let result = RestaurantUGCImagePool.resolve(surface: surface, records: snapshots[2],
                currentOwnerID: "tm_viewer", restaurantID: "restaurant")
            #expect(result?.record.photoID == "public")
            #expect(result?.exportAllowed == false)
        }
    }

    private func record(
        id: String, owner: String, visibility: String, deletedAt: Date? = nil
    ) -> RestaurantUGCImageRecord {
        .init(
            photoID: id, restaurantID: "restaurant", visitID: "visit",
            ownerUserID: owner, visibility: visibility, visitVisibility: visibility,
            profileVisibility: "public", moderationEligible: true,
            deletedAt: deletedAt, binaryDeletedAt: nil,
            createdAt: Date(timeIntervalSince1970: id == "owner" ? 4 : 2),
            markerPreferred: false, resourceURL: "tastemap-resource://photo/\(id)/display"
        )
    }
}
