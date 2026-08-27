import Foundation
import SwiftData
import Testing
@testable import TasteMap

@Suite("P0-B1 offline Sync Engine", .serialized)
@MainActor
struct SyncEngineTests {
    @Test("Local Restaurant and Visit push then pull with their relationship intact")
    func localCreatePushPullRoundTrip() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let store = LocalTasteMapStore(context: context)
        let restaurant = try store.restaurant(for: appleCandidate(), among: [])
        let visit = try store.createVisit(restaurantId: restaurant.id, rating: nil, note: "真实记录")
        let api = EchoSyncAPI()

        try await SyncEngine(context: context, api: api).synchronize()

        #expect(try context.fetch(FetchDescriptor<SyncMutation>()).isEmpty)
        #expect(restaurant.serverVersion == 1)
        #expect(visit.serverVersion == 1)
        #expect(api.restaurantRecords.first?.placeIdentities.first?.provider == .appleMaps)
        #expect(api.restaurantRecords.first?.amapPoiId == nil)
        #expect(api.visitRecords.first?.restaurantId == restaurant.remoteID)
        #expect(api.visitRecords.first?.rating == nil)
    }

    @Test("Offline queue survives process restart and interrupted upload")
    func persistentQueueSurvivesRestart() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TasteMapSyncTests-(UUID().uuidString)")
            .appendingPathExtension("store")
        defer { removeStoreFiles(at: url) }

        do {
            let container = try persistentContainer(at: url)
            let context = container.mainContext
            let restaurant = try LocalTasteMapStore(context: context).restaurant(for: appleCandidate(), among: [])
            _ = try LocalTasteMapStore(context: context).createVisit(restaurantId: restaurant.id)
            let mutations = try context.fetch(FetchDescriptor<SyncMutation>())
            #expect(mutations.count == 2)
            mutations.first?.state = .uploading
            try context.save()
        }

        let reopened = try persistentContainer(at: url)
        let context = reopened.mainContext
        #expect(try context.fetch(FetchDescriptor<SyncMutation>()).count == 2)
        try await SyncEngine(context: context, api: EchoSyncAPI()).synchronize()
        #expect(try context.fetch(FetchDescriptor<SyncMutation>()).isEmpty)
    }

    @Test("Lost push response retries the exact same mutation ID")
    func lostResponseKeepsMutationIdentity() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let restaurant = try LocalTasteMapStore(context: context).restaurant(for: appleCandidate(), among: [])
        _ = try LocalTasteMapStore(context: context).createVisit(restaurantId: restaurant.id)
        let api = ResponseLostOnceAPI()
        let firstAttempt = Date(timeIntervalSince1970: 1_800_000_000)

        await #expect(throws: ResponseLostOnceAPI.ExpectedFailure.self) {
            try await SyncEngine(context: context, api: api, now: { firstAttempt }).synchronize()
        }
        let retainedID = try #require(
            context.fetch(FetchDescriptor<SyncMutation>()).first(where: { $0.retryCount == 1 })?.mutationID
        )
        try await SyncEngine(
            context: context,
            api: api,
            now: { firstAttempt.addingTimeInterval(10) }
        ).synchronize()

        #expect(api.firstMutationID == retainedID.uuidString.lowercased())
        #expect(api.retriedMutationID == api.firstMutationID)
        #expect(try context.fetch(FetchDescriptor<SyncMutation>()).isEmpty)
    }

    @Test("Server tombstone deletes locally without hard deleting history")
    func serverTombstoneAppliesLocally() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let restaurant = syncedRestaurant()
        context.insert(restaurant)
        try context.save()
        let api = EchoSyncAPI(tombstones: [SyncTombstoneV1(
            entityType: .restaurant,
            entityId: restaurant.remoteID!,
            serverVersion: 2,
            deletedAt: "2026-08-27T08:00:00.000Z"
        )])

        try await SyncEngine(context: context, api: api).synchronize()

        #expect(restaurant.deletedAt != nil)
        #expect(restaurant.serverVersion == 2)
        #expect(try context.fetch(FetchDescriptor<Restaurant>()).count == 1)
    }

    @Test("Stale local update conflicts and cannot resurrect a server deletion")
    func staleUpdateCannotResurrectDeletion() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let restaurant = syncedRestaurant()
        context.insert(restaurant)
        try LocalTasteMapStore(context: context).update(
            restaurant,
            name: "离线旧设备改名",
            address: restaurant.address,
            latitude: restaurant.latitude,
            longitude: restaurant.longitude
        )
        let api = ConflictThenTombstoneAPI(tombstone: SyncTombstoneV1(
            entityType: .restaurant,
            entityId: restaurant.remoteID!,
            serverVersion: 2,
            deletedAt: "2026-08-27T08:00:00.000Z"
        ))

        try await SyncEngine(context: context, api: api).synchronize()

        #expect(restaurant.deletedAt != nil)
        #expect(restaurant.serverVersion == 2)
        #expect(try context.fetch(FetchDescriptor<SyncMutation>()).first?.state == .conflicted)
    }

    private func appleCandidate() -> RestaurantCandidate {
        RestaurantCandidate(
            name: "Apple 地图真实餐厅",
            address: "中山路 1 号",
            latitude: 30.25,
            longitude: 120.16,
            appleMapItemIdentifier: "apple-place-only"
        )
    }

    private func syncedRestaurant() -> Restaurant {
        Restaurant(
            name: "已同步餐厅",
            address: "同步地址",
            latitude: 30,
            longitude: 120,
            appleMapItemIdentifier: "apple-synced",
            remoteID: "remote-restaurant",
            serverVersion: 1,
            lastSyncedAt: .now,
            syncStatus: .synced
        )
    }

    private func persistentContainer(at url: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "TasteMapSyncTests",
            schema: TasteMapPersistence.schema,
            url: url,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: TasteMapPersistence.schema, configurations: [configuration])
    }

    private func removeStoreFiles(at url: URL) {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(atPath: url.path + "-shm")
        try? FileManager.default.removeItem(atPath: url.path + "-wal")
    }
}

@MainActor
private final class EchoSyncAPI: SyncAPI {
    private(set) var restaurantRecords: [RestaurantJSONContractV1]
    private(set) var visitRecords: [VisitSyncContractV1]
    private var tombstones: [SyncTombstoneV1]
    private var revision: Int64 = 0

    init(
        restaurantRecords: [RestaurantJSONContractV1] = [],
        visitRecords: [VisitSyncContractV1] = [],
        tombstones: [SyncTombstoneV1] = []
    ) {
        self.restaurantRecords = restaurantRecords
        self.visitRecords = visitRecords
        self.tombstones = tombstones
    }

    func push(_ request: SyncPushRequestV1) async throws -> SyncPushResponseV1 {
        let acknowledgements = request.mutations.map { mutation in
            revision += 1
            if case .restaurant(let record) = mutation.payload {
                restaurantRecords.removeAll { $0.id == record.id }
                restaurantRecords.append(record)
            }
            if case .visit(let record) = mutation.payload {
                visitRecords.removeAll { $0.id == record.id }
                visitRecords.append(record)
            }
            return SyncMutationAcknowledgementV1(
                mutationId: mutation.mutationId,
                entityType: mutation.entityType,
                entityId: mutation.entityId,
                status: .applied,
                duplicate: false,
                serverVersion: mutation.baseVersion + 1,
                revision: revision,
                conflictReason: nil
            )
        }
        return SyncPushResponseV1(apiVersion: 1, acknowledgements: acknowledgements, serverTime: "2026-08-27T08:00:00.000Z")
    }

    func pull(cursor: String, limit: Int) async throws -> SyncPullResponseV1 {
        let restaurantEnvelopes = restaurantRecords.map { RestaurantSyncRecordEnvelopeV1(serverVersion: 1, record: $0) }
        let visitEnvelopes = visitRecords.map { VisitSyncRecordEnvelopeV1(serverVersion: 1, record: $0) }
        return SyncPullResponseV1(
            apiVersion: 1,
            schemaVersion: 1,
            restaurants: restaurantEnvelopes,
            visits: visitEnvelopes,
            tombstones: tombstones,
            nextCursor: String(max(revision, Int64(tombstones.count))),
            hasMore: false,
            serverTime: "2026-08-27T08:00:00.000Z"
        )
    }
}

@MainActor
private final class ConflictThenTombstoneAPI: SyncAPI {
    let tombstone: SyncTombstoneV1

    init(tombstone: SyncTombstoneV1) {
        self.tombstone = tombstone
    }

    func push(_ request: SyncPushRequestV1) async throws -> SyncPushResponseV1 {
        let mutation = request.mutations[0]
        return SyncPushResponseV1(
            apiVersion: 1,
            acknowledgements: [SyncMutationAcknowledgementV1(
                mutationId: mutation.mutationId,
                entityType: mutation.entityType,
                entityId: mutation.entityId,
                status: .conflict,
                duplicate: false,
                serverVersion: tombstone.serverVersion,
                revision: nil,
                conflictReason: "server_version_mismatch"
            )],
            serverTime: tombstone.deletedAt
        )
    }

    func pull(cursor: String, limit: Int) async throws -> SyncPullResponseV1 {
        SyncPullResponseV1(
            apiVersion: 1, schemaVersion: 1, restaurants: [], visits: [],
            tombstones: [tombstone], nextCursor: "2", hasMore: false, serverTime: tombstone.deletedAt
        )
    }
}

@MainActor
private final class ResponseLostOnceAPI: SyncAPI {
    struct ExpectedFailure: Error {}

    private(set) var firstMutationID: String?
    private(set) var retriedMutationID: String?
    private var shouldLoseResponse = true

    func push(_ request: SyncPushRequestV1) async throws -> SyncPushResponseV1 {
        let mutation = request.mutations[0]
        if shouldLoseResponse {
            shouldLoseResponse = false
            firstMutationID = mutation.mutationId
            throw ExpectedFailure()
        }
        if mutation.mutationId == firstMutationID { retriedMutationID = mutation.mutationId }
        return SyncPushResponseV1(
            apiVersion: 1,
            acknowledgements: [SyncMutationAcknowledgementV1(
                mutationId: mutation.mutationId,
                entityType: mutation.entityType,
                entityId: mutation.entityId,
                status: .applied,
                duplicate: mutation.mutationId == firstMutationID,
                serverVersion: mutation.baseVersion + 1,
                revision: 1,
                conflictReason: nil
            )],
            serverTime: "2027-01-15T08:00:00.000Z"
        )
    }

    func pull(cursor: String, limit: Int) async throws -> SyncPullResponseV1 {
        SyncPullResponseV1(
            apiVersion: 1, schemaVersion: 1, restaurants: [], visits: [], tombstones: [],
            nextCursor: cursor, hasMore: false, serverTime: "2027-01-15T08:00:00.000Z"
        )
    }
}
