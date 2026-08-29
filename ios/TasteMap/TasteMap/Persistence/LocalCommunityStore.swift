import Foundation
import SwiftData

@MainActor
struct LocalCommunityStore {
    let context: ModelContext

    static func feedRoute(_ scope: CommunityFeedScopeV1) -> String { "feed:\(scope.rawValue)" }
    static func profileRoute(userID: String, section: PublicContentSectionV1) -> String {
        "profile:\(userID):\(section.rawValue)"
    }

    /// A first-page refresh replaces the authorized cache for this route. This
    /// makes tombstones and visibility changes disappear instead of surviving forever.
    func replace(items: [PublicContentItemV1], currentUserID: String, routeKey: String, fetchedAt: Date) throws {
        for cached in try context.fetch(FetchDescriptor<CachedCommunityContent>())
        where cached.currentUserID == currentUserID && cached.routeKey == routeKey {
            context.delete(cached)
        }
        try append(items: items, currentUserID: currentUserID, routeKey: routeKey, fetchedAt: fetchedAt)
    }

    func append(items: [PublicContentItemV1], currentUserID: String, routeKey: String, fetchedAt: Date) throws {
        let existing = try context.fetch(FetchDescriptor<CachedCommunityContent>())
        // Authorization-sensitive friend content is memory-only. Public content
        // remains useful offline without retaining revoked friendship data.
        for item in items where item.cacheScope == .public {
            let id = CachedCommunityContent.id(currentUserID: currentUserID, routeKey: routeKey, contentID: item.id)
            if let value = existing.first(where: { $0.cacheID == id }) {
                value.payload = try JSONEncoder().encode(item)
                value.eventAt = CachedCommunityContent.date(item.eventAt) ?? fetchedAt
                value.fetchedAt = fetchedAt
            } else {
                context.insert(try CachedCommunityContent(
                    currentUserID: currentUserID, routeKey: routeKey, item: item, fetchedAt: fetchedAt
                ))
            }
        }
        try context.save()
    }

    func cached(currentUserID: String, routeKey: String) throws -> (items: [PublicContentItemV1], fetchedAt: Date)? {
        let values = try context.fetch(FetchDescriptor<CachedCommunityContent>())
            .filter { $0.currentUserID == currentUserID && $0.routeKey == routeKey }
            .sorted { $0.eventAt > $1.eventAt || ($0.eventAt == $1.eventAt && $0.contentID < $1.contentID) }
        let items = values.compactMap(\.item)
        guard !items.isEmpty else { return nil }
        return (items, values.map(\.fetchedAt).max() ?? .now)
    }

    func invalidateOwner(_ ownerUserID: String, currentUserID: String) throws {
        for cached in try context.fetch(FetchDescriptor<CachedCommunityContent>())
        where cached.currentUserID == currentUserID && cached.ownerUserID == ownerUserID {
            context.delete(cached)
        }
        try context.save()
    }

    /// Keeps an explicit viewer action visible in every cached public feed while
    /// retaining the original author's read-only projection.
    func updateViewerState(
        globalKey: String,
        currentUserID: String,
        state: DiscoveryViewerRestaurantStateV1
    ) throws {
        for cached in try context.fetch(FetchDescriptor<CachedCommunityContent>())
        where cached.currentUserID == currentUserID {
            guard var item = cached.item, item.restaurant.globalKey == globalKey else { continue }
            item.viewerState = state
            cached.payload = try JSONEncoder().encode(item)
        }
        try context.save()
    }
}
