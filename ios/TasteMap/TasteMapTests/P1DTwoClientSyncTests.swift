import Foundation
import SwiftData
import Testing
@testable import TasteMap

@Suite("P1-D two-client offline reconciliation", .serialized)
@MainActor
struct P1DTwoClientSyncTests {
    @Test("Two clients converge without duplicate records or stale resurrection")
    func twoClientConflictAndTombstoneFlow() async throws {
        let server = VersionedMemorySyncAPI()
        let containerA = try TasteMapPersistence.makeContainer(inMemory: true)
        let containerB = try TasteMapPersistence.makeContainer(inMemory: true)
        let contextA = containerA.mainContext
        let contextB = containerB.mainContext
        let storeA = LocalTasteMapStore(context: contextA)

        let restaurantA = try storeA.addToWantToGo(
            candidate: RestaurantCandidate(
                name: "P1-D 双端餐厅",
                address: "Apple Maps only",
                latitude: 30.25,
                longitude: 120.16,
                appleMapItemIdentifier: "apple-p1d-two-client"
            ),
            among: []
        )
        try await SyncEngine(context: contextA, api: server).synchronize()
        #expect(restaurantA.status == .wantToGo)
        #expect(server.restaurantCount == 1)

        try await SyncEngine(context: contextB, api: server).synchronize()
        let restaurantB = try #require(contextB.fetch(FetchDescriptor<Restaurant>()).first)
        #expect(restaurantB.status == .wantToGo)
        #expect(restaurantB.appleMapItemIdentifier == "apple-p1d-two-client")

        let visitA = try storeA.createVisit(
            restaurantId: restaurantA.id,
            draft: VisitDraft(rating: nil, note: "设备 A 首次到访")
        )
        try await SyncEngine(context: contextA, api: server).synchronize()
        #expect(restaurantA.status == .visited)
        #expect(visitA.serverVersion == 1)

        try await SyncEngine(context: contextB, api: server).synchronize()
        let visitB = try #require(contextB.fetch(FetchDescriptor<Visit>()).first)
        #expect(restaurantB.status == .visited)
        #expect(visitB.restaurantId == restaurantB.id)
        #expect(visitB.note == "设备 A 首次到访")

        try storeA.update(visitA, draft: VisitDraft(rating: 4.5, note: "设备 A 云端编辑"))
        try await SyncEngine(context: contextA, api: server).synchronize()
        #expect(visitA.serverVersion == 2)

        try LocalTasteMapStore(context: contextB).update(
            visitB,
            draft: VisitDraft(diningMode: .takeout, rating: 5, note: "设备 B 离线编辑")
        )
        try await SyncEngine(context: contextB, api: server).synchronize()

        let conflict = try #require(contextB.fetch(FetchDescriptor<SyncMutation>()).first)
        #expect(conflict.entityType == .visit)
        #expect(conflict.state == .conflicted)
        #expect(visitB.note == "设备 B 离线编辑")
        #expect(visitB.rating == 5)
        #expect(server.visitNote == "设备 A 云端编辑")

        try storeA.delete(visitA)
        try await SyncEngine(context: contextA, api: server).synchronize()
        try await SyncEngine(context: contextB, api: server).synchronize()

        #expect(visitB.deletedAt != nil)
        #expect(visitB.serverVersion == 3)
        #expect(try contextB.fetch(FetchDescriptor<SyncMutation>()).first?.state == .conflicted)
        #expect(server.visitCount == 0)
        #expect(server.visitTombstoneCount == 1)

        try await SyncEngine(context: contextB, api: server).synchronize()
        #expect(try contextB.fetch(FetchDescriptor<Restaurant>()).count == 1)
        #expect(try contextB.fetch(FetchDescriptor<Visit>()).count == 1)
        #expect(server.visitCount == 0)

        try storeA.delete(restaurantA)
        try await SyncEngine(context: contextA, api: server).synchronize()
        try await SyncEngine(context: contextB, api: server).synchronize()
        #expect(restaurantB.deletedAt != nil)
        #expect(server.restaurantCount == 0)
        #expect(server.restaurantTombstoneCount == 1)
    }
}

@MainActor
private final class VersionedMemorySyncAPI: SyncAPI {
    private struct RestaurantState {
        var record: RestaurantJSONContractV1
        var version: Int64
        var revision: Int64
    }

    private struct VisitState {
        var record: VisitSyncContractV1
        var version: Int64
        var revision: Int64
    }

    private struct TombstoneState {
        var tombstone: SyncTombstoneV1
        var revision: Int64
    }

    private var restaurants: [String: RestaurantState] = [:]
    private var visits: [String: VisitState] = [:]
    private var tombstones: [String: TombstoneState] = [:]
    private var acknowledgements: [String: SyncMutationAcknowledgementV1] = [:]
    private var revision: Int64 = 0

    var restaurantCount: Int { restaurants.count }
    var visitCount: Int { visits.count }
    var visitNote: String? { visits.values.first?.record.note }
    var visitTombstoneCount: Int { tombstones.values.filter { $0.tombstone.entityType == .visit }.count }
    var restaurantTombstoneCount: Int { tombstones.values.filter { $0.tombstone.entityType == .restaurant }.count }

    func push(_ request: SyncPushRequestV1) async throws -> SyncPushResponseV1 {
        var results: [SyncMutationAcknowledgementV1] = []
        for mutation in request.mutations {
            if let previous = acknowledgements[mutation.mutationId] {
                results.append(SyncMutationAcknowledgementV1(
                    mutationId: previous.mutationId,
                    entityType: previous.entityType,
                    entityId: previous.entityId,
                    status: previous.status,
                    duplicate: true,
                    serverVersion: previous.serverVersion,
                    revision: previous.revision,
                    conflictReason: previous.conflictReason
                ))
                continue
            }

            let currentVersion = version(type: mutation.entityType, id: mutation.entityId)
            guard mutation.baseVersion == currentVersion else {
                let conflict = SyncMutationAcknowledgementV1(
                    mutationId: mutation.mutationId,
                    entityType: mutation.entityType,
                    entityId: mutation.entityId,
                    status: .conflict,
                    duplicate: false,
                    serverVersion: currentVersion,
                    revision: nil,
                    conflictReason: "server_version_mismatch"
                )
                acknowledgements[mutation.mutationId] = conflict
                results.append(conflict)
                continue
            }

            revision += 1
            let nextVersion = currentVersion + 1
            switch (mutation.operation, mutation.payload) {
            case (.upsert, .restaurant(let record)):
                restaurants[mutation.entityId] = RestaurantState(
                    record: record,
                    version: nextVersion,
                    revision: revision
                )
                tombstones.removeValue(forKey: key(type: .restaurant, id: mutation.entityId))
            case (.upsert, .visit(let record)):
                visits[mutation.entityId] = VisitState(
                    record: record,
                    version: nextVersion,
                    revision: revision
                )
                tombstones.removeValue(forKey: key(type: .visit, id: mutation.entityId))
            case (.delete, _):
                if mutation.entityType == .restaurant {
                    restaurants.removeValue(forKey: mutation.entityId)
                } else {
                    visits.removeValue(forKey: mutation.entityId)
                }
                tombstones[key(type: mutation.entityType, id: mutation.entityId)] = TombstoneState(
                    tombstone: SyncTombstoneV1(
                        entityType: mutation.entityType,
                        entityId: mutation.entityId,
                        serverVersion: nextVersion,
                        deletedAt: "2026-08-27T08:00:00.000Z"
                    ),
                    revision: revision
                )
            default:
                break
            }
            let applied = SyncMutationAcknowledgementV1(
                mutationId: mutation.mutationId,
                entityType: mutation.entityType,
                entityId: mutation.entityId,
                status: .applied,
                duplicate: false,
                serverVersion: nextVersion,
                revision: revision,
                conflictReason: nil
            )
            acknowledgements[mutation.mutationId] = applied
            results.append(applied)
        }
        return SyncPushResponseV1(
            apiVersion: 1,
            acknowledgements: results,
            serverTime: "2026-08-27T08:00:00.000Z"
        )
    }

    func pull(cursor: String, limit: Int) async throws -> SyncPullResponseV1 {
        let since = Int64(cursor) ?? 0
        return SyncPullResponseV1(
            apiVersion: 1,
            schemaVersion: 1,
            restaurants: restaurants.values
                .filter { $0.revision > since }
                .sorted { $0.revision < $1.revision }
                .map { RestaurantSyncRecordEnvelopeV1(serverVersion: $0.version, record: $0.record) },
            visits: visits.values
                .filter { $0.revision > since }
                .sorted { $0.revision < $1.revision }
                .map { VisitSyncRecordEnvelopeV1(serverVersion: $0.version, record: $0.record) },
            tombstones: tombstones.values
                .filter { $0.revision > since }
                .sorted { $0.revision < $1.revision }
                .map(\.tombstone),
            nextCursor: String(revision),
            hasMore: false,
            serverTime: "2026-08-27T08:00:00.000Z"
        )
    }

    private func version(type: SyncEntityType, id: String) -> Int64 {
        if let tombstone = tombstones[key(type: type, id: id)] {
            return tombstone.tombstone.serverVersion
        }
        switch type {
        case .restaurant: return restaurants[id]?.version ?? 0
        case .visit: return visits[id]?.version ?? 0
        case .dish, .photo: return 0
        }
    }

    private func key(type: SyncEntityType, id: String) -> String {
        "\(type.rawValue):\(id)"
    }
}
