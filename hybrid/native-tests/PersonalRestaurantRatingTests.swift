import Foundation
import SwiftData
import XCTest
@testable import TasteMapHybridBridge

@MainActor
final class PersonalRestaurantRatingTests: XCTestCase {
    struct Case: Decodable { let name: String; let ratings: [Double]; let expected: Double? }
    func testSharedBrowserCasesThroughActualNativeBridgeAndDiskReload() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("fixtures/personal-rating-precision.json")
        let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: url))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema([Restaurant.self, Visit.self, UserProfile.self, CachedFollow.self])
        let config = ModelConfiguration("RatingPrecision", schema: schema, url: directory.appendingPathComponent("local.store"), cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        let owner = "tm_rating_owner"
        context.insert(UserProfile(tasteMapUserID: owner, displayName: "Rating test"))
        for c in cases {
            let restaurant = Restaurant(ownerUserID: owner, name: c.name, address: "", latitude: 30, longitude: 120)
            context.insert(restaurant)
            for rating in c.ratings { context.insert(Visit(ownerUserID: owner, restaurantId: restaurant.id, rating: rating)) }
            context.insert(Visit(ownerUserID: owner, restaurantId: restaurant.id, rating: nil))
            context.insert(Visit(ownerUserID: owner, restaurantId: restaurant.id, rating: 1, deletedAt: .now))
            context.insert(Visit(ownerUserID: "tm_other_owner", restaurantId: restaurant.id, rating: 1))
        }
        try context.save()
        func check(_ store: ModelContainer) throws {
            let service = try TasteMapHybridBridgeService(container: store, ownerUserID: owner)
            let actual = try service.profileDashboard().restaurants
            for c in cases {
                let result = try XCTUnwrap(actual.first { $0.name == c.name })
                XCTAssertEqual(result.scoreOutOfTen, c.expected, c.name)
                XCTAssertEqual(result.averageRating, c.ratings.isEmpty ? nil : c.ratings.reduce(0,+)/Double(c.ratings.count), c.name)
                XCTAssertEqual(result.visitCount, c.ratings.count + 1)
                XCTAssertEqual(PersonalRestaurantRating.project(c.ratings).scoreOutOfTen,c.expected)
            }
        }
        try check(container)
        // A new container and service must reconstruct from raw persisted Visits,
        // rather than retaining a rounded DTO or a screenshot-specific override.
        let reopened = try ModelContainer(for: schema, configurations: [config])
        try check(reopened)
        XCTAssertEqual(try ModelContext(reopened).fetch(FetchDescriptor<Visit>()).count, cases.reduce(0) { $0+$1.ratings.count+3 })
    }
}
