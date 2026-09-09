import Foundation
import XCTest
@testable import TasteMapHybridBridge

@MainActor
final class DiscoveryRefreshCoordinatorTests: XCTestCase {
    func testTransportAndDecodeFailuresAreNotMisreportedAsOffline() {
        let decoding = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "invalid response"))
        XCTAssertEqual(tasteMapDiscoveryRefreshIssue(decoding).code, "discovery_response_invalid")
        XCTAssertEqual(tasteMapDiscoveryRefreshIssue(URLError(.timedOut)).code, "discovery_timeout")
        XCTAssertEqual(tasteMapDiscoveryRefreshIssue(URLError(.notConnectedToInternet)).code, "discovery_offline")
        XCTAssertEqual(tasteMapDiscoveryRefreshIssue(URLError(.secureConnectionFailed)).code, "discovery_transport_failed")
        XCTAssertFalse(tasteMapDiscoveryRefreshIssue(decoding).message.contains("网络"))
    }

    private let scope = TasteMapDiscoveryRefreshCoordinator.Scope(ownerUserID: "tm_a", mode: "for_you", city: "杭州", windowDays: 7)
    private let date = Date(timeIntervalSince1970: 1_788_600_000)
    private var capacity: TasteMapDiscoveryHTTPError {
        .decode(status: 503, data: Data(#"{"code":"DISCOVERY_AGGREGATE_CAPACITY","error":"capacity"}"#.utf8))
    }

    func testHTTPCodeAndModeIssueReachTheRealBridgeEnvelopeWithoutDroppingCachedCards() async throws {
        let coordinator = TasteMapDiscoveryRefreshCoordinator(now: { self.date })
        var saved = ["old"]
        let status = await coordinator.refresh(scope: scope, force: false, isCurrent: { true },
            load: { () async throws -> [String] in throw self.capacity }, save: { saved = $0 },
            generatedAt: { _ in "new" }, cachedGeneratedAt: { "2026-09-01T00:00:00Z" })
        XCTAssertEqual(saved, ["old"])
        XCTAssertEqual(status?.state, .cached)
        XCTAssertEqual(status?.issue?.code, "DISCOVERY_AGGREGATE_CAPACITY")
        XCTAssertEqual(status?.sourceGeneratedAt, "2026-09-01T00:00:00Z")
        let fixtureURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("fixtures/profile-restaurant-rich.json")
        let service = try TasteMapHybridDebugFixture.makeService(fixtureData: Data(contentsOf: fixtureURL))
        service.discoveryRefreshStatus = ["for_you": try XCTUnwrap(status)]
        let dispatcher = TasteMapHybridBridgeDispatcher(service: service, appVersion: "test", build: "test", dataSource: "local-test",
            authState: { .init(state: "authenticated", userID: service.ownerUserID, displayName: "Test") })
        let response = dispatcher.dispatch(.init(version: 1, requestId: "discovery-refresh-test", method: .contentSnapshot, payload: .object([:])))
        let data = try JSONEncoder().encode(response)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let result = try XCTUnwrap(json["result"] as? [String: Any])
        let discovery = try XCTUnwrap(result["discovery"] as? [String: Any])
        XCTAssertEqual((discovery["forYou"] as? [Any])?.count, 12)
        let statuses = try XCTUnwrap(discovery["refreshStatus"] as? [String: Any])
        let forYou = try XCTUnwrap(statuses["for_you"] as? [String: Any])
        XCTAssertEqual((forYou["issue"] as? [String: Any])?["code"] as? String, "DISCOVERY_AGGREGATE_CAPACITY")
        XCTAssertNil(json["error"])
    }

    func testImmediateFailureRetryAndExplicitForceBypassSuccessThrottle() async {
        let coordinator = TasteMapDiscoveryRefreshCoordinator(now: { self.date })
        var attempts = 0
        var fail = true
        func refresh(force: Bool = false) async -> TasteMapHybridDiscoveryRefreshStatusDTO? {
            await coordinator.refresh(scope: scope, force: force, isCurrent: { true }, load: {
                attempts += 1
                if fail { throw self.capacity }
                return [String]() // Genuine empty server page is a successful page.
            }, save: { _ in }, generatedAt: { _ in "server-time" }, cachedGeneratedAt: { nil })
        }
        let failed = await refresh()
        XCTAssertEqual(failed?.state, .unavailable)
        fail = false
        _ = await refresh()
        XCTAssertEqual(attempts, 1) // Automatic retry observes the failure cooldown.
        let retried = await refresh(force: true)
        XCTAssertEqual(retried?.state, .fresh)
        XCTAssertEqual(attempts, 2)
        _ = await refresh()
        XCTAssertEqual(attempts, 2)
        _ = await refresh(force: true)
        XCTAssertEqual(attempts, 3)
    }

    func testPermissionDenialNeverPresentsProtectedCacheAsFreshOrRetryable() async {
        let coordinator = TasteMapDiscoveryRefreshCoordinator()
        let restricted = await coordinator.refresh(scope: scope, force: false, isCurrent: { true },
            load: { () async throws -> String in throw TasteMapDiscoveryHTTPError(status: 403, code: nil, message: "Premium required") },
            save: { _ in XCTFail("Forbidden page must not be cached") }, generatedAt: { $0 }, cachedGeneratedAt: { "protected-old" })
        XCTAssertEqual(restricted?.state, .restricted)
        XCTAssertNil(restricted?.sourceGeneratedAt)
        XCTAssertEqual(restricted?.issue?.recoverable, false)
    }

    func testEmptyRequestedCityKeepsServerResolvedScopeOnSuccessAndFailure() async {
        let coordinator = TasteMapDiscoveryRefreshCoordinator()
        let automatic = TasteMapDiscoveryRefreshCoordinator.Scope(ownerUserID: "tm_a", mode: "for_you", city: "", windowDays: 7)
        let fresh = await coordinator.refresh(scope: automatic, force: true, isCurrent: { true },
            load: { "杭州" }, save: { _ in }, generatedAt: { _ in "server-time" }, resolvedCity: { $0 }, cachedGeneratedAt: { nil })
        XCTAssertEqual(fresh?.state, .fresh)
        XCTAssertEqual(fresh?.city, "杭州")
        var cacheQueryCity: String?
        let failed = await coordinator.refresh(scope: automatic, force: true, isCurrent: { true },
            load: { () async throws -> String in throw self.capacity }, save: { _ in XCTFail("Failure cannot write") },
            generatedAt: { $0 }, resolvedCity: { $0 }, cachedGeneratedAt: {
                cacheQueryCity = coordinator.snapshot(ownerUserID: "tm_a", city: "", windowDays: 7)["for_you"]?.city
                return cacheQueryCity == "杭州" ? "server-time" : nil
            })
        XCTAssertEqual(cacheQueryCity, "杭州")
        XCTAssertEqual(failed?.city, "杭州")
        XCTAssertEqual(failed?.state, .cached)
        XCTAssertEqual(failed?.issue?.code, "DISCOVERY_AGGREGATE_CAPACITY")
        XCTAssertTrue(coordinator.snapshot(ownerUserID: "tm_b", city: "", windowDays: 7).isEmpty)
    }

    func testCacheWriteFailureAndIndependentModesDoNotBecomeSuccess() async {
        let coordinator = TasteMapDiscoveryRefreshCoordinator()
        let cached = await coordinator.refresh(scope: scope, force: false, isCurrent: { true },
            load: { "new" }, save: { _ in throw CocoaError(.fileWriteOutOfSpace) },
            generatedAt: { $0 }, cachedGeneratedAt: { "old" })
        XCTAssertEqual(cached?.state, .cached)
        XCTAssertEqual(cached?.issue?.code, "discovery_cache_write_failed")
        let trending = TasteMapDiscoveryRefreshCoordinator.Scope(ownerUserID: "tm_a", mode: "trending", city: "杭州", windowDays: 7)
        _ = await coordinator.refresh(scope: trending, force: false, isCurrent: { true }, load: { "fresh" }, save: { _ in }, generatedAt: { $0 }, cachedGeneratedAt: { nil })
        let values = coordinator.snapshot(ownerUserID: "tm_a", city: "杭州", windowDays: 7)
        XCTAssertEqual(values["trending"]?.state, .fresh)
        XCTAssertEqual(values["for_you"]?.state, .cached)
        XCTAssertTrue(coordinator.snapshot(ownerUserID: "tm_b", city: "杭州", windowDays: 7).isEmpty)
    }

    func testNewForceRequestAndAccountResetRejectLateCompletionsBeforeCacheWrites() async {
        let coordinator = TasteMapDiscoveryRefreshCoordinator()
        var continuation: CheckedContinuation<String, Error>?
        var saved: [String] = []
        let old = Task { await coordinator.refresh(scope: self.scope, force: false, isCurrent: { true }, load: {
            try await withCheckedThrowingContinuation { continuation = $0 }
        }, save: { saved.append($0) }, generatedAt: { $0 }, cachedGeneratedAt: { nil }) }
        while continuation == nil { await Task.yield() }
        _ = await coordinator.refresh(scope: scope, force: true, isCurrent: { true }, load: { "fresh" }, save: { saved.append($0) }, generatedAt: { $0 }, cachedGeneratedAt: { nil })
        continuation?.resume(returning: "old")
        let oldResult = await old.value
        XCTAssertNil(oldResult)
        XCTAssertEqual(saved, ["fresh"])
        continuation = nil
        let beforeLogout = Task { await coordinator.refresh(scope: self.scope, force: true, isCurrent: { true }, load: {
            try await withCheckedThrowingContinuation { continuation = $0 }
        }, save: { saved.append($0) }, generatedAt: { $0 }, cachedGeneratedAt: { nil }) }
        while continuation == nil { await Task.yield() }
        coordinator.reset()
        continuation?.resume(returning: "previous-owner")
        let signedOutResult = await beforeLogout.value
        XCTAssertNil(signedOutResult)
        XCTAssertEqual(saved, ["fresh"])
        XCTAssertTrue(coordinator.snapshot(ownerUserID: "tm_a", city: "杭州", windowDays: 7).isEmpty)
    }

    func testLegacySnapshotAndRequestRemainDecodable() throws {
        let legacy = Data(#"{"generatedAt":"old","discovery":{"forYou":[],"similarTaste":[],"trending":[]},"community":{"following":[],"latest":[]},"lists":[]}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(TasteMapHybridContentSnapshotDTO.self, from: legacy).discovery.refreshStatus)
        XCTAssertNil(try JSONDecoder().decode(TasteMapHybridContentSnapshotRequest.self, from: Data("{}".utf8)).forceRefresh)
        XCTAssertEqual(try JSONDecoder().decode(TasteMapHybridContentSnapshotRequest.self, from: Data(#"{"forceRefresh":true}"#.utf8)).forceRefresh, true)
    }
}
