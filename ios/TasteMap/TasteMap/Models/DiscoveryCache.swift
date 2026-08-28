import Foundation
import SwiftData

@Model
final class CachedDiscoveryRestaurant {
    @Attribute(.unique) var cacheID: String
    var currentUserID: String
    var globalKey: String
    var projectionData: Data
    var fetchedAt: Date

    @MainActor
    init(currentUserID: String, projection: DiscoveryRestaurantProjectionV1, fetchedAt: Date) throws {
        cacheID = "\(currentUserID)|\(projection.globalKey)"
        self.currentUserID = currentUserID
        globalKey = projection.globalKey
        projectionData = try JSONEncoder().encode(projection)
        self.fetchedAt = fetchedAt
    }

    @MainActor var projection: DiscoveryRestaurantProjectionV1? {
        try? JSONDecoder().decode(DiscoveryRestaurantProjectionV1.self, from: projectionData)
    }
}

@Model
final class CachedDiscoveryPlacement {
    @Attribute(.unique) var cacheID: String
    var currentUserID: String
    var modeValue: String
    var city: String
    var trendWindowDays: Int
    var globalKey: String
    var contextData: Data
    var generatedAt: Date

    @MainActor
    init(
        currentUserID: String,
        city: String,
        trendWindowDays: Int,
        card: DiscoveryCardV1,
        generatedAt: Date
    ) throws {
        cacheID = Self.id(currentUserID: currentUserID, mode: card.mode, city: city,
                          trendWindowDays: trendWindowDays, globalKey: card.restaurant.globalKey)
        self.currentUserID = currentUserID
        modeValue = card.mode.rawValue
        self.city = city
        self.trendWindowDays = trendWindowDays
        globalKey = card.restaurant.globalKey
        contextData = try JSONEncoder().encode(DiscoveryCachedCardContext(card: card))
        self.generatedAt = generatedAt
    }

    var mode: DiscoveryModeV1? { DiscoveryModeV1(rawValue: modeValue) }
    @MainActor var context: DiscoveryCachedCardContext? {
        try? JSONDecoder().decode(DiscoveryCachedCardContext.self, from: contextData)
    }

    static func id(currentUserID: String, mode: DiscoveryModeV1, city: String,
                   trendWindowDays: Int, globalKey: String) -> String {
        "\(currentUserID)|\(mode.rawValue)|\(city)|\(trendWindowDays)|\(globalKey)"
    }
}
