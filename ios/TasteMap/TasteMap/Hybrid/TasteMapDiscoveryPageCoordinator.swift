import Foundation

/// Data already projected from the authenticated server response. No owner or
/// authorization is accepted from JavaScript, and no ranking is recomputed here.
struct TasteMapDiscoveryPageSource {
    let mode: TasteMapHybridDiscoveryMode
    let city: String
    let generatedAt: String
    let items: [TasteMapHybridDiscoveryItemDTO]
    let nextCursor: String?
    var evidenceAvailability: TasteMapDiscoveryEvidenceAvailabilityDTO? = nil
    var appliedQuery: TasteMapDiscoveryAppliedQuery? = nil
    var filterCapabilities: TasteMapDiscoveryFilterCapabilities? = nil
    var filterTaxonomy: TasteMapDiscoveryFilterTaxonomy? = nil
}

/// Session-only query cache. In particular friends-visible cards never enter
/// SwiftData via this new channel. The old content.snapshot cache is untouched.
@MainActor
final class TasteMapDiscoveryPageCoordinator {
    private struct Scope: Hashable {
        let owner: String
        let mode: String
        let requestedCityKey: String
        let windowDays: Int
        let queryFingerprint: String
    }
    private struct Snapshot {
        let id: String
        let resolvedCity: String
        let generatedAt: String
        let items: [TasteMapHybridDiscoveryItemDTO]
        let nextCursor: String?
        let evidenceAvailability: TasteMapDiscoveryEvidenceAvailabilityDTO?
        let appliedQuery: TasteMapDiscoveryAppliedQuery?
        let filterCapabilities: TasteMapDiscoveryFilterCapabilities?
        let filterTaxonomy: TasteMapDiscoveryFilterTaxonomy?
    }
    private struct Pending {
        let scope: Scope
        let cursor: String?
        let snapshotID: String?
        let task: Task<TasteMapHybridDiscoveryPageDTO, Error>
    }
    private var owner: String?
    private var epoch: UInt64 = 0
    private var revisions: [String: UInt64] = [:]
    private var snapshots: [Scope: Snapshot] = [:]
    private var pending: [String: Pending] = [:]
    private let now: () -> Date

    init(now: @escaping () -> Date = { .now }) { self.now = now }

    func reset() {
        epoch &+= 1
        pending.values.forEach { $0.task.cancel() }
        pending.removeAll(); snapshots.removeAll(); revisions.removeAll()
        owner = nil
    }

    func page(
        ownerUserID: String,
        request: TasteMapHybridDiscoveryPageRequest,
        isCurrent: @escaping () -> Bool,
        load: @escaping (_ city: String, _ cursor: String?) async throws -> TasteMapDiscoveryPageSource
    ) async throws -> TasteMapHybridDiscoveryPageDTO {
        try validate(request)
        let query = try TasteMapDiscoveryAppliedQuery.normalized(mode: request.mode.rawValue, filters: request.filters, sort: request.sort, preferences: request.preferences)
        guard !ownerUserID.isEmpty, isCurrent() else { throw issue("auth_required", recoverable: false) }
        if owner != ownerUserID { reset(); owner = ownerUserID }
        let mode = request.mode.rawValue
        let scope = Scope(owner: ownerUserID, mode: mode,
                          requestedCityKey: RestaurantCityFilterIdentity.key(request.city), windowDays: request.windowDays,
                          queryFingerprint: query.fingerprint)
        if request.forceRefresh != true, let running = pending[mode], running.scope == scope,
           running.cursor == request.cursor, running.snapshotID == request.snapshotID {
            return try await running.task.value
        }
        let previous = snapshots[scope]
        if let cursor = request.cursor {
            guard let previous, previous.id == request.snapshotID, previous.nextCursor == cursor else {
                throw issue("discovery_cursor_scope_mismatch", recoverable: false)
            }
        }
        let revision = (revisions[mode] ?? 0) &+ 1
        revisions[mode] = revision
        pending[mode]?.task.cancel()
        let currentEpoch = epoch
        let attemptedAt = ISO8601DateFormatter().string(from: now())
        let task = Task { @MainActor [self] () throws -> TasteMapHybridDiscoveryPageDTO in
            let canPublish = { self.epoch == currentEpoch && self.revisions[mode] == revision && isCurrent() }
            do {
                // Pin implicit city resolution on continuation. Sending an
                // empty city again could resolve differently after a profile edit.
                let source = try await load(request.cursor == nil ? request.city : previous!.resolvedCity, request.cursor)
                guard canPublish() else { throw issue("discovery_query_superseded", recoverable: false) }
                try query.verify(source.appliedQuery, mode: mode)
                guard source.mode == request.mode, !source.generatedAt.isEmpty,
                      source.items.allSatisfy({ $0.mode == mode && !$0.id.isEmpty }),
                      source.nextCursor == nil || (source.nextCursor != request.cursor && !source.nextCursor!.isEmpty),
                      request.city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || RestaurantCityFilterIdentity.matches(source.city, request.city) else {
                    throw issue("discovery_invalid_page", recoverable: true)
                }
                if request.cursor != nil {
                    guard let previous, source.generatedAt == previous.generatedAt,
                          RestaurantCityFilterIdentity.matches(source.city, previous.resolvedCity) else {
                        throw issue("discovery_snapshot_mismatch", recoverable: true)
                    }
                }
                var seen = Set<String>()
                let combined = (request.cursor == nil ? [] : previous!.items) + source.items
                let accepted = Snapshot(
                    id: request.cursor == nil ? UUID().uuidString : previous!.id,
                    resolvedCity: source.city, generatedAt: source.generatedAt,
                    items: combined.filter { seen.insert($0.id).inserted }, nextCursor: source.nextCursor,
                    evidenceAvailability: source.evidenceAvailability ?? (request.cursor == nil ? nil : previous?.evidenceAvailability),
                    appliedQuery: source.appliedQuery, filterCapabilities: source.filterCapabilities, filterTaxonomy: source.filterTaxonomy)
                snapshots[scope] = accepted
                return response(request, snapshot: accepted, attemptedAt: attemptedAt, error: nil)
            } catch {
                guard canPublish() else { throw issue("discovery_query_superseded", recoverable: false) }
                let restricted = (error as? TasteMapDiscoveryHTTPError).map { $0.status == 401 || $0.status == 403 } ?? false
                if restricted {
                    // A denial invalidates every cached city/window for this
                    // mode, not merely the currently visible first page.
                    snapshots = snapshots.filter { $0.key.owner != ownerUserID || $0.key.mode != mode }
                }
                let mapped = (error as? TasteMapHybridBridgeErrorDTO) ?? tasteMapDiscoveryRefreshIssue(error)
                return response(request, snapshot: restricted ? nil : previous,
                                attemptedAt: attemptedAt, error: mapped, restricted: restricted)
            }
        }
        pending[mode] = Pending(scope: scope, cursor: request.cursor, snapshotID: request.snapshotID, task: task)
        defer {
            if epoch == currentEpoch, revisions[mode] == revision { pending[mode] = nil }
        }
        return try await task.value
    }

    private func validate(_ request: TasteMapHybridDiscoveryPageRequest) throws {
        guard request.city.count <= 80, !request.city.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              request.windowDays == 7 || (request.mode == .trending && request.windowDays == 30),
              (request.cursor == nil) == (request.snapshotID == nil),
              request.cursor.map({ !$0.isEmpty && $0.utf8.count <= 4096 }) ?? true,
              request.snapshotID.map({ !$0.isEmpty && $0.count <= 128 }) ?? true,
              request.forceRefresh != true || request.cursor == nil else {
            throw issue("invalid_discovery_query", recoverable: false)
        }
    }

    private func response(_ request: TasteMapHybridDiscoveryPageRequest, snapshot: Snapshot?, attemptedAt: String,
                          error: TasteMapHybridBridgeErrorDTO?, restricted: Bool = false) -> TasteMapHybridDiscoveryPageDTO {
        let state: TasteMapHybridDiscoveryFreshness = restricted ? .restricted : error == nil ? .fresh : snapshot == nil ? .unavailable : .cached
        return .init(version: 1, mode: request.mode, requestedCity: request.city,
                     resolvedCity: snapshot?.resolvedCity ?? request.city, windowDays: request.windowDays,
                     snapshotID: snapshot?.id, generatedAt: snapshot?.generatedAt,
                     items: snapshot?.items ?? [], nextCursor: snapshot?.nextCursor,
                     pagination: snapshot == nil ? .unknown : snapshot?.nextCursor == nil ? .complete : .more,
                     refreshStatus: .init(state: state, city: snapshot?.resolvedCity ?? request.city,
                                          windowDays: request.windowDays, sourceGeneratedAt: snapshot?.generatedAt,
                                          attemptedAt: attemptedAt, issue: error),
                     engagementState: "unknown", interactionsAvailable: false,
                     evidenceAvailability: snapshot?.evidenceAvailability, appliedQuery: snapshot?.appliedQuery,
                     filterCapabilities: snapshot?.filterCapabilities, filterTaxonomy: snapshot?.filterTaxonomy)
    }

    private func issue(_ code: String, recoverable: Bool) -> TasteMapHybridBridgeErrorDTO {
        .init(code: code, message: "发现查询已变化或暂时无法继续，请重新加载当前查询。", recoverable: recoverable, details: nil)
    }
}
