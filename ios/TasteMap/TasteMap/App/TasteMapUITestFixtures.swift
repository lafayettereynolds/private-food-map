#if DEBUG
import Foundation
import SwiftData

@MainActor
enum TasteMapUITestFixtures {
    static let detailRestaurantID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    static let detailLaunchArgument = "-p1b-restaurant-detail-fixture"

    static func insertRestaurantDetailFixture(into container: ModelContainer) throws {
        let restaurant = Restaurant(
            id: detailRestaurantID,
            name: "P1-B 想吃餐厅",
            address: "杭州市上城区湖滨路 18 号",
            latitude: 30.259,
            longitude: 120.168,
            appleMapItemIdentifier: "apple-ui-test-p1b",
            city: "杭州",
            status: .wantToGo,
            syncStatus: .synced
        )
        container.mainContext.insert(restaurant)
        try container.mainContext.save()
    }
}
#endif
