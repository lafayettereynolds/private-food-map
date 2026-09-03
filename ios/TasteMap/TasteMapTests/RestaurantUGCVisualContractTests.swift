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
