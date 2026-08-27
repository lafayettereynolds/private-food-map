import Foundation
import SwiftData
import Testing
@testable import TasteMap

@Suite("P1-D sync coordination", .serialized)
@MainActor
struct SyncCoordinatorTests {
    @Test("Transient, authentication, and permanent failures are classified safely")
    func errorClassification() {
        #expect(SyncErrorClassifier.disposition(for: URLError(.timedOut)) == .retryable)
        #expect(SyncErrorClassifier.disposition(for: SyncAPIError.server(status: 503, message: "secret")) == .retryable)
        #expect(SyncErrorClassifier.disposition(for: SyncAPIError.server(status: 401, message: "secret")) == .authentication)
        #expect(SyncErrorClassifier.disposition(for: SyncAPIError.server(status: 422, message: "secret")) == .permanent)
        #expect(SyncErrorClassifier.storedReason(
            for: SyncAPIError.server(status: 422, message: "do-not-store-this-body"),
            disposition: .permanent
        ) == "permanent:http_422")
    }

    @Test("Network recovery automatically drains the persistent queue")
    func networkRecoveryAutomaticallySyncs() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        _ = try LocalTasteMapStore(context: context).addToWantToGo(candidate: candidate(), among: [])
        let api = ControlledSyncAPI()
        let coordinator = coordinator(context: context, api: api)

        coordinator.networkAvailabilityChanged(false)
        await coordinator.sessionDidBecomeAvailable()
        #expect(api.pushCount == 0)
        #expect(coordinator.presentation.phase == .waitingForNetwork)

        coordinator.networkAvailabilityChanged(true)
        try await Task.sleep(for: .milliseconds(50))

        #expect(api.pushCount == 1)
        #expect(try context.fetch(FetchDescriptor<SyncMutation>()).isEmpty)
        #expect(coordinator.presentation.phase == .synced)
    }

    @Test("Concurrent app triggers share one in-flight sync pass")
    func concurrentTriggersAreSingleFlight() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let api = ControlledSyncAPI(pullDelay: .milliseconds(80))
        let coordinator = coordinator(context: container.mainContext, api: api)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask { await coordinator.sessionDidBecomeAvailable() }
            }
        }

        #expect(api.pullCount == 1)
        #expect(api.maximumConcurrentRequests == 1)
        #expect(coordinator.presentation.phase == .synced)
    }

    @Test("Permanent 4xx failure stops automatic retry and remains manually retryable")
    func permanentFailureDoesNotLoop() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        _ = try LocalTasteMapStore(context: context).addToWantToGo(candidate: candidate(), among: [])
        let api = ControlledSyncAPI(pushFailures: [SyncAPIError.server(status: 422, message: "invalid payload")])
        let coordinator = coordinator(context: context, api: api)

        await coordinator.sessionDidBecomeAvailable()
        try await Task.sleep(for: .milliseconds(100))

        let failed = try #require(context.fetch(FetchDescriptor<SyncMutation>()).first)
        #expect(failed.state == .failed)
        #expect(failed.nextRetryAt == nil)
        #expect(failed.lastError == "permanent:http_422")
        #expect(api.pushCount == 1)
        #expect(coordinator.presentation.phase == .failed)

        await coordinator.retryNow()
        #expect(api.pushCount == 2)
        #expect(try context.fetch(FetchDescriptor<SyncMutation>()).isEmpty)
        #expect(coordinator.presentation.phase == .synced)
    }

    @Test("Transient failure automatically retries the exact mutation without duplication")
    func transientFailureAutomaticallyRetriesWithoutDuplication() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        _ = try LocalTasteMapStore(context: context).addToWantToGo(candidate: candidate(), among: [])
        let originalMutationID = try #require(context.fetch(FetchDescriptor<SyncMutation>()).first?.mutationID)
        let api = ControlledSyncAPI(pushFailures: [URLError(.networkConnectionLost)])
        let coordinator = coordinator(context: context, api: api)

        await coordinator.sessionDidBecomeAvailable()
        try await Task.sleep(for: .milliseconds(100))
        #expect(api.receivedMutationIDs == [
            originalMutationID.uuidString.lowercased(),
            originalMutationID.uuidString.lowercased(),
        ])
        #expect(try context.fetch(FetchDescriptor<SyncMutation>()).isEmpty)
    }

    @Test("A session ending cancels sync and leaves local queue intact")
    func logoutPreservesLocalQueue() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        _ = try LocalTasteMapStore(context: context).addToWantToGo(candidate: candidate(), among: [])
        let coordinator = coordinator(
            context: context,
            api: ControlledSyncAPI(pullDelay: .seconds(1))
        )
        coordinator.networkAvailabilityChanged(false)
        await coordinator.sessionDidBecomeAvailable()

        coordinator.sessionDidEnd()

        #expect(coordinator.presentation.phase == .signedOut)
        #expect(try context.fetch(FetchDescriptor<Restaurant>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<SyncMutation>()).count == 1)
    }

    private func coordinator(context: ModelContext, api: any SyncAPI) -> SyncCoordinator {
        SyncCoordinator(
            context: context,
            api: api,
            hasAuthenticatedSession: { true },
            automaticSyncInterval: 0,
            networkRecoveryDelay: .zero
        )
    }

    private func candidate() -> RestaurantCandidate {
        RestaurantCandidate(
            name: "P1-D 离线餐厅",
            address: "Development local only",
            latitude: 30.25,
            longitude: 120.16,
            appleMapItemIdentifier: "apple-p1d-coordinator"
        )
    }
}

@MainActor
private final class ControlledSyncAPI: SyncAPI {
    private var pushFailures: [Error]
    private let pullDelay: Duration
    private var revision: Int64 = 0
    private var concurrentRequests = 0
    private(set) var maximumConcurrentRequests = 0
    private(set) var pushCount = 0
    private(set) var pullCount = 0
    private(set) var receivedMutationIDs: [String] = []

    init(pushFailures: [Error] = [], pullDelay: Duration = .zero) {
        self.pushFailures = pushFailures
        self.pullDelay = pullDelay
    }

    func push(_ request: SyncPushRequestV1) async throws -> SyncPushResponseV1 {
        beginRequest()
        defer { endRequest() }
        pushCount += 1
        let mutation = request.mutations[0]
        receivedMutationIDs.append(mutation.mutationId)
        if !pushFailures.isEmpty { throw pushFailures.removeFirst() }
        revision += 1
        return SyncPushResponseV1(
            apiVersion: 1,
            acknowledgements: [SyncMutationAcknowledgementV1(
                mutationId: mutation.mutationId,
                entityType: mutation.entityType,
                entityId: mutation.entityId,
                status: .applied,
                duplicate: receivedMutationIDs.dropLast().contains(mutation.mutationId),
                serverVersion: mutation.baseVersion + 1,
                revision: revision,
                conflictReason: nil
            )],
            serverTime: "2026-08-27T08:00:00.000Z"
        )
    }

    func pull(cursor: String, limit: Int) async throws -> SyncPullResponseV1 {
        beginRequest()
        defer { endRequest() }
        pullCount += 1
        if pullDelay != .zero { try await Task.sleep(for: pullDelay) }
        return SyncPullResponseV1(
            apiVersion: 1,
            schemaVersion: 1,
            restaurants: [],
            visits: [],
            tombstones: [],
            nextCursor: String(revision),
            hasMore: false,
            serverTime: "2026-08-27T08:00:00.000Z"
        )
    }

    private func beginRequest() {
        concurrentRequests += 1
        maximumConcurrentRequests = max(maximumConcurrentRequests, concurrentRequests)
    }

    private func endRequest() {
        concurrentRequests -= 1
    }
}
