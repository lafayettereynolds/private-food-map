import Foundation

#if !TASTEMAP_HYBRID_BRIDGE_CORE
/// Only authenticated, accepted city pages enter this in-memory authority.
/// Neither the canonical recommendation snapshot nor SwiftData is mutated.
@MainActor
struct TasteMapDiscoveryCitySource {
    let city: String
    let generatedAt: String
    var discoveryItems: [TasteMapHybridDiscoveryItemDTO] = []
    var activityItems: [TasteMapHybridActivityItemDTO] = []
    let nextCursor: String?
    var references: [String: TasteMapHybridResolvedRestaurantReference] = [:]
    var engagementKnown: Bool = false
    var dataSource: String = "remote"
    var evidenceAvailability: TasteMapDiscoveryEvidenceAvailabilityDTO? = nil
    var appliedQuery: TasteMapDiscoveryAppliedQuery? = nil
    var filterCapabilities: TasteMapDiscoveryFilterCapabilities? = nil
    var filterTaxonomy: TasteMapDiscoveryFilterTaxonomy? = nil
}

@MainActor
final class TasteMapDiscoveryCitySession {
    private struct Snapshot {
        let id: String
        let queryKey: String
        let source: TasteMapDiscoveryCitySource
        let acceptedAt: Date
    }
    private var owner: String?
    private var epoch = UUID()
    private var revision: [String: UUID] = [:]
    private var snapshots: [String: Snapshot] = [:]
    private var engagements: [String: CommunityEngagementSummaryV1] = [:]

    func reset() {
        epoch = UUID(); owner = nil; revision.removeAll(); snapshots.removeAll(); engagements.removeAll()
    }

    func page(ownerUserID: String, request: TasteMapHybridDiscoveryCityPageRequest,
              isCurrent: @escaping () -> Bool,
              load: (_ city: String, _ cursor: String?) async throws -> TasteMapDiscoveryCitySource) async throws -> TasteMapHybridDiscoveryCityPageDTO {
        let days = request.windowDays ?? 7
        let query = try TasteMapDiscoveryAppliedQuery.normalized(mode: request.mode, filters: request.filters, sort: request.sort, preferences: request.preferences)
        let city = request.city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ["following", "for_you", "similar_taste", "latest", "trending"].contains(request.mode),
              city.count <= 80, city.rangeOfCharacter(from: .controlCharacters) == nil,
              days == 7 || (days == 30 && request.mode == "trending"),
              (request.cursor == nil) == (request.snapshotID == nil),
              request.cursor.map({ !$0.isEmpty && $0.utf8.count <= 4096 }) ?? true,
              request.snapshotID.map({ !$0.isEmpty && $0.count <= 128 }) ?? true,
              request.forceRefresh != true || request.cursor == nil else { throw failure("invalid_discovery_query") }
        guard !ownerUserID.isEmpty, isCurrent() else { throw failure("auth_required") }
        if owner != ownerUserID { reset(); owner = ownerUserID }
        let key = "\(RestaurantCityFilterIdentity.key(city))|\(days)|\(query.fingerprint)"
        let previous = snapshots[request.mode].flatMap { $0.queryKey == key && Date().timeIntervalSince($0.acceptedAt) < 600 ? $0 : nil }
        if request.cursor != nil {
            guard let previous, previous.id == request.snapshotID, previous.source.nextCursor == request.cursor else {
                throw failure("discovery_cursor_scope_mismatch")
            }
        }
        // Switching a city immediately revokes the old city's overlay for this mode.
        snapshots[request.mode] = previous
        let capturedEpoch = epoch
        let token = UUID(); revision[request.mode] = token
        let current = { self.epoch == capturedEpoch && self.revision[request.mode] == token && isCurrent() }
        let attempted = ISO8601DateFormatter().string(from: .now)
        do {
            var source = try await load(request.cursor == nil ? city : previous!.source.city, request.cursor)
            guard current() else { throw failure("discovery_query_superseded") }
            try query.verify(source.appliedQuery, mode: request.mode)
            guard (city.isEmpty || RestaurantCityFilterIdentity.matches(source.city, city)), !source.generatedAt.isEmpty,
                  source.nextCursor == nil || (source.nextCursor != request.cursor && !source.nextCursor!.isEmpty),
                  source.discoveryItems.allSatisfy({ $0.mode == request.mode && !$0.id.isEmpty }),
                  source.activityItems.allSatisfy({ !$0.id.isEmpty }) else { throw failure("discovery_invalid_page") }
            if request.cursor != nil, let previous {
                // Discovery pins generatedAt; Community generatedAt is a response
                // timestamp, while its signed cursor binds the feed query.
                guard RestaurantCityFilterIdentity.matches(previous.source.city, source.city),
                      ["following", "latest"].contains(request.mode) || previous.source.generatedAt == source.generatedAt else {
                    throw failure("discovery_snapshot_mismatch")
                }
                var discoveryIDs = Set<String>(); var activityIDs = Set<String>()
                source.discoveryItems = (previous.source.discoveryItems + source.discoveryItems).filter { discoveryIDs.insert($0.id).inserted }
                source.activityItems = (previous.source.activityItems + source.activityItems).filter { activityIDs.insert($0.id).inserted }
                source.references = previous.source.references.merging(source.references) { _, new in new }
                source.engagementKnown = source.engagementKnown && previous.source.engagementKnown
                source.evidenceAvailability = source.evidenceAvailability ?? previous.source.evidenceAvailability
            }
            let accepted = Snapshot(id: request.cursor == nil ? UUID().uuidString : previous!.id,
                                    queryKey: key, source: source, acceptedAt: .now)
            snapshots[request.mode] = accepted
            return response(request, snapshot: accepted, attemptedAt: attempted)
        } catch {
            guard current() else { throw failure("discovery_query_superseded") }
            let status: Int?
            if case let SyncAPIError.server(code, _) = error { status = code }
            else { status = (error as? TasteMapDiscoveryHTTPError)?.status }
            let restricted = status == 401 || status == 403
            if restricted { epoch = UUID(); revision.removeAll(); snapshots.removeAll(); engagements.removeAll() }
            return response(request, snapshot: restricted ? nil : previous, attemptedAt: attempted,
                            error: (error as? TasteMapHybridBridgeErrorDTO) ?? tasteMapDiscoveryRefreshIssue(error), restricted: restricted)
        }
    }

    private func active(ownerUserID: String) -> [Snapshot] {
        guard owner == ownerUserID else { return [] }
        return snapshots.values.filter { Date().timeIntervalSince($0.acceptedAt) < 600 }
    }
    func reference(_ id: String, ownerUserID: String) -> TasteMapHybridResolvedRestaurantReference? {
        active(ownerUserID: ownerUserID).sorted { $0.acceptedAt > $1.acceptedAt }
            .compactMap { $0.source.references[id.lowercased()] }.first
    }
    func identityGroups(ownerUserID: String) -> [Set<String>] {
        active(ownerUserID: ownerUserID).flatMap { snapshot in
            snapshot.source.references.values.map { reference in
                Set(([reference.projection.globalKey] + reference.projection.placeIdentities.map {
                    "\($0.provider.rawValue):\($0.externalId)"
                }).map { $0.lowercased() })
            }
        }
    }
    func recommendationIntentMetadata(ownerUserID: String) -> [RestaurantRecommendationIntentMetadata] {
        active(ownerUserID: ownerUserID).flatMap { snapshot in
            snapshot.source.references.values.map { reference in
                let projection = reference.projection
                return RestaurantRecommendationIntentMetadata(
                    aliases: Set(([projection.globalKey] + projection.placeIdentities.map {
                        "\($0.provider.rawValue):\($0.externalId)"
                    }).map { $0.lowercased() }), name: projection.name, tags: projection.tags)
            }
        }
    }
    func permits(_ target: TasteMapHybridActivityInteractionDTO, ownerUserID: String) -> Bool {
        active(ownerUserID: ownerUserID).contains { snapshot in
            let targets = snapshot.source.discoveryItems.compactMap(\.interaction) + snapshot.source.activityItems.compactMap(\.interaction)
            return targets.contains { $0.visitID == target.visitID && $0.authorID == target.authorID && $0.restaurantID == target.restaurantID && $0.activityID == target.activityID }
        }
    }
    func permitsPhoto(_ id: String, ownerUserID: String) -> Bool {
        active(ownerUserID: ownerUserID).contains { snapshot in
            let descriptors = snapshot.source.discoveryItems.flatMap { [$0.restaurant.image] + ($0.activityImages ?? []) }
                + snapshot.source.activityItems.flatMap { [$0.restaurant.image] + ($0.activityImages ?? []) }
            let avatars = snapshot.source.activityItems.compactMap { $0.user.avatarPhotoID }
                + snapshot.source.discoveryItems.compactMap { $0.sourceUser?.avatarPhotoID }
            return descriptors.contains { $0.photoID?.caseInsensitiveCompare(id) == .orderedSame }
                || avatars.contains { $0.caseInsensitiveCompare(id) == .orderedSame }
        }
    }
    func engagement(_ visitID: String, ownerUserID: String) -> CommunityEngagementSummaryV1? {
        let items = active(ownerUserID: ownerUserID).flatMap { $0.source.activityItems }
        guard let item = items.first(where: { $0.visitID == visitID }) else { return nil }
        return engagements[visitID] ?? .init(likedByViewer: item.likedByViewer, likeCount: item.likeCount, commentCount: item.commentCount)
    }
    func setEngagement(_ value: CommunityEngagementSummaryV1, visitID: String, ownerUserID: String) {
        guard owner == ownerUserID else { return }; engagements[visitID] = value
    }
    private func response(_ request: TasteMapHybridDiscoveryCityPageRequest, snapshot: Snapshot?, attemptedAt: String,
                          error: TasteMapHybridBridgeErrorDTO? = nil, restricted: Bool = false) -> TasteMapHybridDiscoveryCityPageDTO {
        let source = snapshot?.source
        let state: TasteMapHybridDiscoveryFreshness = restricted ? .restricted : error == nil ? .fresh : snapshot == nil ? .unavailable : .cached
        return .init(dataSource: source?.dataSource ?? "remote", version: 1, mode: request.mode, requestedCity: request.city, resolvedCity: source?.city ?? request.city,
                     windowDays: request.windowDays ?? 7, snapshotID: snapshot?.id, generatedAt: source?.generatedAt,
                     discoveryItems: source?.discoveryItems ?? [], activityItems: source?.activityItems ?? [], nextCursor: source?.nextCursor,
                     pagination: snapshot == nil ? .unknown : source?.nextCursor == nil ? .complete : .more,
                     refreshStatus: .init(state: state, city: source?.city ?? request.city, windowDays: request.windowDays ?? 7,
                                          sourceGeneratedAt: source?.generatedAt, attemptedAt: attemptedAt, issue: error),
                     engagementState: source?.engagementKnown == true ? "known" : "unknown", interactionsAvailable: source?.engagementKnown == true,
                     evidenceAvailability: source?.evidenceAvailability, appliedQuery: source?.appliedQuery,
                     filterCapabilities: source?.filterCapabilities, filterTaxonomy: source?.filterTaxonomy)
    }
    private func failure(_ code: String) -> TasteMapHybridBridgeErrorDTO {
        .init(code: code, message: "城市查询已变化或暂时不可用，请重新加载。", recoverable: true, details: nil)
    }
}
#endif
