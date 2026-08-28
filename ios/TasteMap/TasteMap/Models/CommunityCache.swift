import Foundation
import SwiftData

@Model
final class CachedCommunityContent {
    @Attribute(.unique) var cacheID: String
    var currentUserID: String
    var routeKey: String
    var contentID: String
    var ownerUserID: String
    var eventAt: Date
    var fetchedAt: Date
    var payload: Data

    init(currentUserID: String, routeKey: String, item: PublicContentItemV1, fetchedAt: Date) throws {
        cacheID = Self.id(currentUserID: currentUserID, routeKey: routeKey, contentID: item.id)
        self.currentUserID = currentUserID
        self.routeKey = routeKey
        contentID = item.id
        ownerUserID = item.user.userId
        eventAt = Self.date(item.eventAt) ?? fetchedAt
        self.fetchedAt = fetchedAt
        payload = try JSONEncoder().encode(item)
    }

    var item: PublicContentItemV1? { try? JSONDecoder().decode(PublicContentItemV1.self, from: payload) }

    static func id(currentUserID: String, routeKey: String, contentID: String) -> String {
        "\(currentUserID)|\(routeKey)|\(contentID)"
    }

    static func date(_ value: String) -> Date? {
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return precise.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
