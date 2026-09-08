import Foundation
import SwiftData
import XCTest
@testable import TasteMapHybridBridge

@MainActor
final class BridgeSharedProjectionBoundaryTests: XCTestCase {
    func testPackageUsesCanonicalVisitPrecedenceAndPlaceIdentityWithoutPersistenceWrites() throws {
        let owner = "tm_package_projection"
        let schema = Schema([Restaurant.self, Visit.self, UserProfile.self, CachedFollow.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(
            "SharedProjection", schema: schema, isStoredInMemoryOnly: true, groupContainer: .none, cloudKitDatabase: .none
        )])
        let context = ModelContext(container)
        let visited = Restaurant(ownerUserID: owner, name: "Coffee", address: "A", latitude: 31, longitude: 121,
            appleMapItemIdentifier: "same-actual-provider-id", city: "上海")
        let duplicate = Restaurant(ownerUserID: owner, name: "Imported alias", address: "B", latitude: 31, longitude: 121,
            appleMapItemIdentifier: "same-actual-provider-id", city: "上海市", status: .wantToGo)
        let promoted = Restaurant(ownerUserID: owner, name: "Ramen", address: "C", latitude: 30, longitude: 120,
            city: "杭州", status: .wantToGo)
        let wanted = Restaurant(ownerUserID: owner, name: "Still wanted", address: "D", latitude: 35, longitude: 139,
            city: "东京", status: .wantToGo)
        context.insert(UserProfile(tasteMapUserID: owner, displayName: "Owner"))
        [visited, duplicate, promoted, wanted].forEach { context.insert($0) }
        context.insert(Visit(ownerUserID: owner, restaurantId: promoted.id, rating: nil))
        context.insert(Visit(ownerUserID: owner, restaurantId: wanted.id, rating: 4, deletedAt: .now))
        try context.save()
        let service = try TasteMapHybridBridgeService(container: container, ownerUserID: owner)
        let profile = try service.profileDashboard()
        XCTAssertEqual(Set(profile.restaurants.filter { $0.status == "visited" }.map(\.name)), Set(["Coffee", "Ramen"]))
        XCTAssertEqual(profile.restaurants.filter { $0.status == "wantToGo" }.map(\.name), ["Still wanted"])
        XCTAssertFalse(profile.restaurants.contains { $0.name == "Imported alias" })
        // The Package is a projection facade, not the App's repair/sync writer.
        let persisted = try ModelContext(container).fetch(FetchDescriptor<Restaurant>())
        XCTAssertEqual(persisted.first { $0.id == promoted.id }?.status, .wantToGo)
        XCTAssertEqual(persisted.first { $0.id == duplicate.id }?.status, .wantToGo)
    }

    func testPackageUsesRealSharedFoodTaxonomyAndPreservesOwnerEmoji() throws {
        XCTAssertEqual(FoodCategoryVisualResolver.resolve(name: "Coffee"), .cafeBakery)
        XCTAssertEqual(FoodCategoryVisualResolver.resolve(name: "Ramen"), .noodles)
        XCTAssertEqual(FoodCategoryVisualResolver.resolve(name: "店", tags: ["粤菜"]), .chinese)
        let owner = "tm_package_visual"
        let schema = Schema([Restaurant.self, Visit.self, UserProfile.self, CachedFollow.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(
            "SharedVisual", schema: schema, isStoredInMemoryOnly: true, groupContainer: .none, cloudKitDatabase: .none
        )])
        let context = ModelContext(container)
        let restaurant = Restaurant(ownerUserID: owner, name: "Coffee", address: "A", latitude: 31, longitude: 121)
        context.insert(UserProfile(tasteMapUserID: owner, displayName: "Owner"))
        context.insert(restaurant)
        try context.save()
        let service = try TasteMapHybridBridgeService(container: container, ownerUserID: owner,
            metadataByRestaurantID: [restaurant.id: TasteMapHybridRestaurantMetadata(markerType: "emoji", markerEmoji: "🍜")])
        let image = try XCTUnwrap(service.profileDashboard().restaurants.first?.image)
        XCTAssertEqual(image.kind, .foodCategoryVisual)
        XCTAssertEqual(image.categoryVisualID, "cafeBakery")
        XCTAssertEqual(image.preferredEmoji, "🍜")
        XCTAssertNil(image.resourceURL)
    }
}
