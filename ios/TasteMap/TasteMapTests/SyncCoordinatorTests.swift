import Foundation
import SwiftData
import Testing
@testable import TasteMap

@Suite("P1-D sync coordination", .serialized)
@MainActor
struct SyncCoordinatorTests {
    @Test("Review-only maintenance launch preserves uploading state and never runs startup or foreground sync")
    func reviewOnlyLaunchPreservesQueue() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let api = ControlledSyncAPI()
        let mutation = SyncMutation(entityType: .visitDish, entityID: "protected-startup",
            operation: .upsert, retryCount: 35, payload: Data("unchanged".utf8), baseVersion: 0,
            state: .uploading, nextRetryAt: .distantFuture, lastError: "retryable:http_500")
        context.insert(mutation)
        try context.save()
        let coordinator = SyncCoordinator(context: context, api: api, hasAuthenticatedSession: { true },
            networkRecoveryDelay: .zero, conflictReviewOnly: true)
        coordinator.start()
        await coordinator.sessionDidBecomeAvailable()
        _ = try coordinator.beginConflictReview()
        coordinator.endConflictReview()
        coordinator.handleAppBecameActive()
        coordinator.networkAvailabilityChanged(true)
        await coordinator.retryNow()
        await coordinator.synchronizeNow()
        await Task.yield()
        #expect(api.pushCount == 0 && api.pullCount == 0)
        #expect(mutation.state == .uploading && mutation.retryCount == 35 && mutation.baseVersion == 0)
        #expect(mutation.payload == Data("unchanged".utf8) && mutation.nextRetryAt == .distantFuture)
        #expect(mutation.resolution == nil)
        #expect(try context.fetchCount(FetchDescriptor<SyncMutation>()) == 1)
    }

    @Test("Conflict review does not retry, reset or upload the other four queued mutations")
    func conflictReviewLeavesOtherWorkUntouched() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let api = ControlledSyncAPI()
        let coordinator = coordinator(context: context, api: api)
        await coordinator.sessionDidBecomeAvailable()
        let pullCount = api.pullCount
        let conflict = SyncMutation(entityType: .restaurantList, entityID: "fixture-list",
            operation: .upsert, payload: Data(), baseVersion: 1, state: .conflicted)
        context.insert(conflict)
        var untouched: [SyncMutation] = []
        for index in 0..<4 {
            let mutation = SyncMutation(entityType: .visitDish, entityID: "protected-\(index)",
                operation: .upsert, retryCount: 35, payload: Data("unchanged".utf8), baseVersion: 0,
                state: index == 3 ? .uploading : .queued, nextRetryAt: .distantFuture, lastError: "retryable:http_500")
            context.insert(mutation); untouched.append(mutation)
        }
        try context.save()
        let review = try coordinator.beginConflictReview()
        #expect(review.map(\.id) == [conflict.mutationID])
        await coordinator.retryNow()
        await coordinator.synchronizeNow()
        coordinator.networkAvailabilityChanged(true)
        await Task.yield()
        #expect(api.pushCount == 0 && api.pullCount == pullCount)
        #expect(untouched.enumerated().allSatisfy { index, mutation in
            mutation.state == (index == 3 ? .uploading : .queued) && mutation.retryCount == 35 &&
            mutation.nextRetryAt == .distantFuture && mutation.payload == Data("unchanged".utf8)
        })
        coordinator.endConflictReview()
        #expect(api.pushCount == 0 && api.pullCount == pullCount)
    }

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
        #expect(SyncErrorClassifier.disposition(
            for: PhotoBinaryAPIError.server(status: 503, message: "secret")
        ) == .retryable)
        #expect(SyncErrorClassifier.disposition(
            for: PhotoBinaryAPIError.server(status: 401, message: "secret")
        ) == .authentication)
        #expect(SyncErrorClassifier.disposition(
            for: PhotoBinaryAPIError.server(status: 422, message: "secret")
        ) == .permanent)
        #expect(SyncErrorClassifier.disposition(for: PhotoImportError.invalidImage) == .permanent)
        #expect(SyncErrorClassifier.disposition(for: SyncStageFailure(
            stage: .pull,
            underlyingError: URLError(.timedOut)
        )) == .retryable)
        #expect(SyncErrorClassifier.disposition(for: SyncStageFailure(
            stage: .reconciliation,
            underlyingError: SyncEngineError.missingRestaurantMapping
        )) == .permanent)
    }

    @Test("Empty queue and successful pull finishes synced")
    func emptyQueueSuccessfulPullIsSynced() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let api = ControlledSyncAPI()
        let coordinator = coordinator(context: container.mainContext, api: api)

        await coordinator.sessionDidBecomeAvailable()

        #expect(api.pushCount == 0)
        #expect(api.pullCount == 1)
        #expect(coordinator.presentation.phase == .synced)
        #expect(coordinator.presentation.diagnostic == nil)
    }

    @Test("Per-user checkpoint resumes a paged incremental pull with an empty mutation queue")
    func perUserCheckpointResumesIncrementalPull() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        context.insert(SyncCheckpoint(ownerUserID: "tm_checkpoint_a", cursor: "3310"))
        context.insert(SyncCheckpoint(ownerUserID: "tm_checkpoint_b", cursor: "9000"))
        try context.save()
        let api = ControlledSyncAPI(pullPages: [
            (nextCursor: "3500", hasMore: true),
            (nextCursor: "3500", hasMore: false)
        ])
        let engine = SyncEngine(
            context: context,
            api: api,
            ownerUserID: "tm_checkpoint_a",
            retryBaseDelay: 0
        )

        try await engine.synchronize()

        #expect(api.pushCount == 0)
        #expect(api.receivedPullCursors == ["3310", "3500"])
        let checkpoints = try context.fetch(FetchDescriptor<SyncCheckpoint>())
        #expect(checkpoints.first(where: { $0.ownerUserID == "tm_checkpoint_a" })?.cursor == "3500")
        #expect(checkpoints.first(where: { $0.ownerUserID == "tm_checkpoint_b" })?.cursor == "9000")
    }

    @Test("Empty queue pull failure reports the pull stage and never remains syncing")
    func emptyQueuePullFailureHasActionableStatus() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let api = ControlledSyncAPI(
            pullFailures: [SyncAPIError.server(status: 503, message: "do-not-display")]
        )
        let coordinator = coordinator(
            context: container.mainContext,
            api: api,
            retryBaseDelay: 60
        )

        await coordinator.sessionDidBecomeAvailable()

        #expect(coordinator.presentation.phase == .failed)
        #expect(coordinator.presentation.pendingCount == 0)
        #expect(coordinator.presentation.diagnostic?.stage == .pull)
        #expect(coordinator.presentation.diagnostic?.requestCategory == "pull")
        #expect(coordinator.presentation.diagnostic?.category == .server)
        #expect(coordinator.presentation.diagnostic?.httpStatus == 503)
        #expect(coordinator.presentation.diagnostic?.finalDisposition == .retryable)
    }

    @Test("Acknowledged push is removed even if the following pull fails")
    func pushAcknowledgedThenPullFailureDoesNotRestoreMutation() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let restaurant = try LocalTasteMapStore(context: context).addToWantToGo(candidate: candidate(), among: [])
        let api = ControlledSyncAPI(pullFailures: [URLError(.networkConnectionLost)])
        let coordinator = coordinator(context: context, api: api, retryBaseDelay: 60)

        await coordinator.sessionDidBecomeAvailable()

        #expect(api.pushCount == 1)
        #expect(try context.fetch(FetchDescriptor<SyncMutation>()).isEmpty)
        #expect(restaurant.serverVersion == 1)
        #expect(restaurant.syncStatus == .synced)
        #expect(coordinator.presentation.phase == .failed)
        #expect(coordinator.presentation.pendingCount == 0)
        #expect(coordinator.presentation.diagnostic?.stage == .pull)
    }

    @Test("Manual retry clears a pull-only failure")
    func manualRetryClearsPullFailure() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let api = ControlledSyncAPI(
            pullFailures: [SyncAPIError.server(status: 503, message: "temporary")]
        )
        let coordinator = coordinator(context: container.mainContext, api: api, retryBaseDelay: 60)

        await coordinator.sessionDidBecomeAvailable()
        #expect(coordinator.presentation.phase == .failed)

        await coordinator.retryNow()

        #expect(api.pullCount == 2)
        #expect(coordinator.presentation.phase == .synced)
        #expect(coordinator.presentation.diagnostic == nil)
    }

    @Test("Photo binary failures participate in the unified sync status")
    func photoFailureParticipatesInSyncStatus() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        context.insert(PhotoAsset(
            kind: .visit,
            mimeType: "image/jpeg",
            byteSize: 10,
            uploadState: .failed,
            uploadLastError: "permanent:照片合同无效"
        ))
        try context.save()
        let coordinator = coordinator(context: context, api: ControlledSyncAPI())

        await coordinator.sessionDidBecomeAvailable()

        #expect(coordinator.presentation.phase == .failed)
        #expect(coordinator.presentation.pendingCount == 0)
        #expect(coordinator.presentation.pendingPhotoCount == 1)
        #expect(coordinator.presentation.failedPhotoCount == 1)
        #expect(coordinator.presentation.message.contains("1 张照片"))
        #expect(coordinator.presentation.allowsRetry)
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

    @Test("Foreground-style and manual requests never overlap")
    func automaticAndManualRequestsAreSingleFlight() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let api = ControlledSyncAPI(pullDelay: .milliseconds(80))
        let coordinator = coordinator(context: container.mainContext, api: api)

        async let automatic: Void = coordinator.sessionDidBecomeAvailable()
        try await Task.sleep(for: .milliseconds(10))
        async let manual: Void = coordinator.retryNow()
        _ = await (automatic, manual)

        #expect(api.maximumConcurrentRequests == 1)
        #expect(api.pullCount == 2)
        #expect(coordinator.presentation.phase == .synced)
    }

    @Test("Request timeout, pull budget, and automatic backoff are bounded")
    func retryPolicyIsBounded() {
        #expect(SyncRetryPolicy.requestTimeout == 15)
        #expect(SyncRetryPolicy.requestTimeout <= 30)
        #expect(SyncRetryPolicy.maximumBackoff == 60)
        #expect(SyncRetryPolicy.maximumPullPagesPerPass == 20)
    }

    @Test("Sync HTTP requests carry the bounded timeout")
    func syncRequestUsesBoundedTimeout() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Task02SyncURLProtocol.self]
        Task02SyncURLProtocol.handler = { request in
            #expect(request.timeoutInterval == SyncRetryPolicy.requestTimeout)
            let body = #"{"apiVersion":1,"schemaVersion":1,"restaurants":[],"visits":[],"dishes":[],"visitDishes":[],"photos":[],"companions":[],"recommendationSources":[],"profiles":[],"restaurantLists":[],"restaurantListItems":[],"tombstones":[],"nextCursor":"0","hasMore":false,"serverTime":"2026-08-30T08:00:00.000Z"}"#
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(body.utf8)
            )
        }
        defer { Task02SyncURLProtocol.handler = nil }
        let api = URLSessionSyncAPIClient(
            configuration: APIConfiguration(
                environment: .development,
                baseURL: URL(string: "https://sync.example.test")!
            ),
            session: URLSession(configuration: configuration)
        )

        _ = try await api.pull(cursor: "0", limit: 200)
    }

    @Test("Changing accounts clears the previous account failure state")
    func userSwitchClearsFailureState() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let api = ControlledSyncAPI(pullFailures: [URLError(.timedOut)])
        let coordinator = coordinator(context: container.mainContext, api: api, retryBaseDelay: 60)

        await coordinator.sessionDidBecomeAvailable(userID: "tm_task02_a")
        #expect(coordinator.presentation.phase == .failed)

        await coordinator.sessionDidBecomeAvailable(userID: "tm_task02_b")

        #expect(coordinator.presentation.phase == .synced)
        #expect(coordinator.presentation.diagnostic == nil)
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

        // An ordinary pass must not silently retry a permanently failed mutation.
        await coordinator.synchronizeNow()
        #expect(api.pushCount == 1)
        #expect(failed.mutationID.uuidString.lowercased() == api.receivedMutationIDs[0])
        #expect(failed.state == .failed)

        await coordinator.retryNow()
        #expect(api.pushCount == 2)
        #expect(api.receivedMutationIDs[0] == api.receivedMutationIDs[1])
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

    private func coordinator(
        context: ModelContext,
        api: any SyncAPI,
        retryBaseDelay: TimeInterval = 0.01
    ) -> SyncCoordinator {
        SyncCoordinator(
            context: context,
            api: api,
            hasAuthenticatedSession: { true },
            automaticSyncInterval: 0,
            networkRecoveryDelay: .zero,
            retryBaseDelay: retryBaseDelay
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
    private var pullFailures: [Error]
    private let pullDelay: Duration
    private var pullPages: [(nextCursor: String, hasMore: Bool)]
    private var revision: Int64 = 0
    private var concurrentRequests = 0
    private(set) var maximumConcurrentRequests = 0
    private(set) var pushCount = 0
    private(set) var pullCount = 0
    private(set) var receivedMutationIDs: [String] = []
    private(set) var receivedPullCursors: [String] = []

    init(
        pushFailures: [Error] = [],
        pullFailures: [Error] = [],
        pullDelay: Duration = .zero,
        pullPages: [(nextCursor: String, hasMore: Bool)] = []
    ) {
        self.pushFailures = pushFailures
        self.pullFailures = pullFailures
        self.pullDelay = pullDelay
        self.pullPages = pullPages
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
        receivedPullCursors.append(cursor)
        if pullDelay != .zero { try await Task.sleep(for: pullDelay) }
        if !pullFailures.isEmpty { throw pullFailures.removeFirst() }
        let page = pullPages.isEmpty
            ? (nextCursor: String(revision), hasMore: false)
            : pullPages.removeFirst()
        return SyncPullResponseV1(
            apiVersion: 1,
            schemaVersion: 1,
            restaurants: [],
            visits: [],
            tombstones: [],
            nextCursor: page.nextCursor,
            hasMore: page.hasMore,
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

private final class Task02SyncURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let handler = try Self.handler ?? { _ in throw URLError(.badServerResponse) }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
