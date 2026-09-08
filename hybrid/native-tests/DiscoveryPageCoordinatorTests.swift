import Foundation
import XCTest
@testable import TasteMapHybridBridge

@MainActor
final class DiscoveryPageCoordinatorTests: XCTestCase {
    private let date = "2026-09-06T00:00:00.000Z"
    private let query = TasteMapHybridDiscoveryPageRequest(mode: .trending, city: "杭州", windowDays: 30)

    private func cards(_ range: Range<Int>, mode: String = "trending") throws -> [TasteMapHybridDiscoveryItemDTO] {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("fixtures/profile-restaurant-rich.json")
        let template = try TasteMapHybridDebugFixture.makeService(fixtureData: Data(contentsOf: fixture)).contentSnapshot().discovery.forYou[0]
        var value = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(template)) as? [String: Any])
        return try range.map { index in
            value["id"] = "card-\(index)"; value["mode"] = mode; value["rank"] = index + 1
            return try JSONDecoder().decode(TasteMapHybridDiscoveryItemDTO.self, from: JSONSerialization.data(withJSONObject: value))
        }
    }

    private func source(_ range: Range<Int> = 0..<0, city: String = "杭州", mode: TasteMapHybridDiscoveryMode = .trending,
                        next: String? = nil, generatedAt: String? = nil) throws -> TasteMapDiscoveryPageSource {
        .init(mode: mode, city: city, generatedAt: generatedAt ?? date, items: try cards(range, mode: mode.rawValue), nextCursor: next)
    }

    private func next(_ page: TasteMapHybridDiscoveryPageDTO) -> TasteMapHybridDiscoveryPageRequest {
        .init(mode: page.mode, city: page.requestedCity, windowDays: page.windowDays,
              cursor: page.nextCursor, snapshotID: page.snapshotID)
    }

    private func expectError(_ code: String, _ action: () async throws -> TasteMapHybridDiscoveryPageDTO) async {
        do { _ = try await action(); XCTFail("Expected \(code)") }
        catch { XCTAssertEqual((error as? TasteMapHybridBridgeErrorDTO)?.code, code) }
    }

    func testRealContinuationAccumulatesBeyondTwentyAndPreservesServerOrderWithoutDuplicateIDs() async throws {
        let coordinator = TasteMapDiscoveryPageCoordinator()
        let first = try await coordinator.page(ownerUserID: "a", request: query, isCurrent: { true }) { city, cursor in
            XCTAssertEqual(city, "杭州"); XCTAssertNil(cursor)
            return try self.source(0..<20, next: "opaque-page-2")
        }
        let second = try await coordinator.page(ownerUserID: "a", request: next(first), isCurrent: { true }) { city, cursor in
            XCTAssertEqual(city, "杭州"); XCTAssertEqual(cursor, "opaque-page-2")
            return try self.source(19..<40)
        }
        XCTAssertEqual(second.items.map(\.id), (0..<40).map { "card-\($0)" })
        XCTAssertEqual(second.items.map(\.rank), Array(1...40))
        XCTAssertEqual(second.snapshotID, first.snapshotID)
        XCTAssertEqual(second.generatedAt, date)
        XCTAssertEqual(second.pagination, .complete)
        XCTAssertEqual(second.refreshStatus.state, .fresh)
        XCTAssertFalse(second.interactionsAvailable)
        XCTAssertEqual(second.engagementState, "unknown")
        await expectError("discovery_cursor_scope_mismatch") {
            try await coordinator.page(ownerUserID: "a", request: self.next(first), isCurrent: { true }) { _, _ in XCTFail(); return try self.source() }
        }
    }

    func testAutomaticCityIsResolvedOnceAndPinnedForContinuationAndFailureCache() async throws {
        let coordinator = TasteMapDiscoveryPageCoordinator()
        let automatic = TasteMapHybridDiscoveryPageRequest(mode: .trending, city: "", windowDays: 7)
        let first = try await coordinator.page(ownerUserID: "a", request: automatic, isCurrent: { true }) { city, _ in
            XCTAssertEqual(city, ""); return try self.source(0..<1, city: "杭州市", next: "next")
        }
        let failed = try await coordinator.page(ownerUserID: "a", request: next(first), isCurrent: { true }) { city, _ in
            XCTAssertEqual(city, "杭州市"); throw URLError(.notConnectedToInternet)
        }
        XCTAssertEqual(failed.requestedCity, "")
        XCTAssertEqual(failed.resolvedCity, "杭州市")
        XCTAssertEqual(failed.refreshStatus.city, "杭州市")
        XCTAssertEqual(failed.snapshotID, first.snapshotID)
        XCTAssertEqual(failed.nextCursor, "next")
        XCTAssertEqual(failed.refreshStatus.state, .cached)
    }

    func testCursorCannotCrossOwnerModeRequestedCityWindowOrSnapshot() async throws {
        for variation in 0..<5 {
            let coordinator = TasteMapDiscoveryPageCoordinator()
            let first = try await coordinator.page(ownerUserID: "a", request: query, isCurrent: { true }) { _, _ in try self.source(next: "cursor") }
            let request = TasteMapHybridDiscoveryPageRequest(
                mode: variation == 1 ? .forYou : .trending, city: variation == 2 ? "上海" : "杭州",
                windowDays: variation == 1 || variation == 3 ? 7 : 30,
                cursor: "cursor", snapshotID: variation == 4 ? "wrong" : first.snapshotID)
            await expectError("discovery_cursor_scope_mismatch") {
                try await coordinator.page(ownerUserID: variation == 0 ? "b" : "a", request: request, isCurrent: { true }) { _, _ in
                    XCTFail("Cross-scope cursor reached network"); return try self.source()
                }
            }
        }
    }

    func testEquivalentChineseCityLabelsShareScopeWithoutTruncatingRealCityNames() async throws {
        let coordinator = TasteMapDiscoveryPageCoordinator()
        let first = try await coordinator.page(ownerUserID: "a", request: query, isCurrent: { true }) { _, _ in try self.source(next: "next") }
        var request = next(first)
        request = .init(mode: request.mode, city: "杭州市", windowDays: request.windowDays, cursor: request.cursor, snapshotID: request.snapshotID)
        let result = try await coordinator.page(ownerUserID: "a", request: request, isCurrent: { true }) { city, _ in
            XCTAssertEqual(city, "杭州"); return try self.source()
        }
        XCTAssertEqual(result.pagination, .complete)
        XCTAssertNotEqual(RestaurantCityFilterIdentity.key("杭州"), "杭")
    }

    func testInvalidInputsAreRejectedBeforeNetwork() async throws {
        let coordinator = TasteMapDiscoveryPageCoordinator()
        let invalid: [TasteMapHybridDiscoveryPageRequest] = [
            .init(mode: .forYou, city: "杭州", windowDays: 30), .init(mode: .trending, city: "杭州", windowDays: 14),
            .init(mode: .trending, city: String(repeating: "杭", count: 81), windowDays: 7),
            .init(mode: .trending, city: "杭\n州", windowDays: 7),
            .init(mode: .trending, city: "杭州", windowDays: 7, cursor: "cursor"),
            .init(mode: .trending, city: "杭州", windowDays: 7, snapshotID: "snapshot"),
            .init(mode: .trending, city: "杭州", windowDays: 7, cursor: "", snapshotID: "snapshot"),
            .init(mode: .trending, city: "杭州", windowDays: 7, cursor: "cursor", snapshotID: "snapshot", forceRefresh: true),
        ]
        for request in invalid {
            await expectError("invalid_discovery_query") {
                try await coordinator.page(ownerUserID: "a", request: request, isCurrent: { true }) { _, _ in XCTFail(); return try self.source() }
            }
        }
    }

    func testWrongSourceCityModeSnapshotAndNonAdvancingCursorNeverAppend() async throws {
        for variation in 0..<4 {
            let coordinator = TasteMapDiscoveryPageCoordinator()
            let first = try await coordinator.page(ownerUserID: "a", request: query, isCurrent: { true }) { _, _ in try self.source(0..<20, next: "next") }
            let rejected = try await coordinator.page(ownerUserID: "a", request: next(first), isCurrent: { true }) { _, _ in
                try self.source(20..<40, city: variation == 0 ? "上海" : "杭州", mode: variation == 1 ? .forYou : .trending,
                                next: variation == 3 ? "next" : nil, generatedAt: variation == 2 ? "changed-snapshot" : self.date)
            }
            XCTAssertEqual(rejected.items.count, 20)
            XCTAssertEqual(rejected.nextCursor, "next")
            XCTAssertEqual(rejected.refreshStatus.state, .cached)
            XCTAssertEqual(rejected.refreshStatus.issue?.code, variation == 2 ? "discovery_snapshot_mismatch" : "discovery_invalid_page")
        }
    }

    func testCapacityFailurePreservesScopedPageAndImmediateRetryUsesSameRealCursor() async throws {
        let coordinator = TasteMapDiscoveryPageCoordinator()
        let first = try await coordinator.page(ownerUserID: "a", request: query, isCurrent: { true }) { _, _ in try self.source(0..<20, next: "next") }
        let failed = try await coordinator.page(ownerUserID: "a", request: next(first), isCurrent: { true }) { _, _ in
            throw TasteMapDiscoveryHTTPError.decode(status: 503, data: Data(#"{"code":"DISCOVERY_AGGREGATE_CAPACITY","error":"capacity"}"#.utf8))
        }
        XCTAssertEqual(failed.items.count, 20)
        XCTAssertEqual(failed.refreshStatus.issue?.code, "DISCOVERY_AGGREGATE_CAPACITY")
        XCTAssertEqual(failed.pagination, .more)
        var attempts = 0
        let retry = try await coordinator.page(ownerUserID: "a", request: next(failed), isCurrent: { true }) { _, cursor in
            attempts += 1; XCTAssertEqual(cursor, "next"); return try self.source(20..<25)
        }
        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(retry.items.count, 25)
    }

    func testLegitimateEmptySuccessIsCompleteWhileUnavailableHasUnknownPagination() async throws {
        let coordinator = TasteMapDiscoveryPageCoordinator()
        let failed = try await coordinator.page(ownerUserID: "a", request: query, isCurrent: { true }) { _, _ in throw URLError(.timedOut) }
        XCTAssertEqual(failed.pagination, .unknown)
        XCTAssertEqual(failed.refreshStatus.state, .unavailable)
        XCTAssertNil(failed.snapshotID)
        let empty = try await coordinator.page(ownerUserID: "a", request: query, isCurrent: { true }) { _, _ in try self.source() }
        XCTAssertTrue(empty.items.isEmpty)
        XCTAssertEqual(empty.pagination, .complete)
        XCTAssertEqual(empty.refreshStatus.state, .fresh)
        XCTAssertNotNil(empty.snapshotID)
    }

    func testPermissionDenialClearsEveryScopeOfAffectedModeAndCannotResurrectOnOfflineRetry() async throws {
        for status in [401, 403] {
            let coordinator = TasteMapDiscoveryPageCoordinator()
            _ = try await coordinator.page(ownerUserID: "a", request: query, isCurrent: { true }) { _, _ in try self.source(0..<20, next: "next") }
            let other = TasteMapHybridDiscoveryPageRequest(mode: .trending, city: "上海", windowDays: 7)
            let denied = try await coordinator.page(ownerUserID: "a", request: other, isCurrent: { true }) { _, _ in
                throw TasteMapDiscoveryHTTPError(status: status, code: nil, message: "denied")
            }
            XCTAssertEqual(denied.refreshStatus.state, .restricted)
            XCTAssertTrue(denied.items.isEmpty)
            XCTAssertNil(denied.snapshotID)
            let offline = try await coordinator.page(ownerUserID: "a", request: query, isCurrent: { true }) { _, _ in throw URLError(.notConnectedToInternet) }
            XCTAssertTrue(offline.items.isEmpty)
            XCTAssertEqual(offline.pagination, .unknown)
        }
    }

    func testLateCityResponseAndOwnerABAResetCannotPublish() async throws {
        for ownerChange in [false, true] {
            let coordinator = TasteMapDiscoveryPageCoordinator()
            let gate = PageGate()
            let old = Task { try await coordinator.page(ownerUserID: "a", request: query, isCurrent: { true }) { _, _ in await gate.load() } }
            await gate.started()
            if ownerChange { coordinator.reset() }
            let current = TasteMapHybridDiscoveryPageRequest(mode: .trending, city: ownerChange ? "杭州" : "上海", windowDays: 30)
            let latest = try await coordinator.page(ownerUserID: "a", request: current, isCurrent: { true }) { _, _ in try self.source(30..<31, city: current.city) }
            gate.finish(try source(0..<20, next: "old-next"))
            await expectError("discovery_query_superseded") { try await old.value }
            let offline = try await coordinator.page(ownerUserID: "a", request: current, isCurrent: { true }) { _, _ in throw URLError(.timedOut) }
            XCTAssertEqual(offline.items.map(\.id), latest.items.map(\.id))
        }
    }

    func testConcurrentContinuationCoalescesButFirstPageRefreshInvalidatesLateAppend() async throws {
        let coordinator = TasteMapDiscoveryPageCoordinator()
        let first = try await coordinator.page(ownerUserID: "a", request: query, isCurrent: { true }) { _, _ in try self.source(0..<20, next: "next") }
        let gate = PageGate()
        let appendRequest = next(first)
        let append = Task { try await coordinator.page(ownerUserID: "a", request: appendRequest, isCurrent: { true }) { _, _ in await gate.load() } }
        await gate.started()
        let joined = expectation(description: "Duplicate continuation entered the MainActor coordinator")
        let coalesced = Task {
            joined.fulfill()
            return try await coordinator.page(ownerUserID: "a", request: appendRequest, isCurrent: { true }) { _, _ in XCTFail("Duplicate append request"); return try self.source() }
        }
        await fulfillment(of: [joined], timeout: 1)
        var refresh = query; refresh.forceRefresh = true
        let replaced = try await coordinator.page(ownerUserID: "a", request: refresh, isCurrent: { true }) { _, cursor in
            XCTAssertNil(cursor); return try self.source(100..<102)
        }
        gate.finish(try source(20..<40))
        await expectError("discovery_query_superseded") { try await append.value }
        await expectError("discovery_query_superseded") { try await coalesced.value }
        XCTAssertEqual(replaced.items.map(\.id), ["card-100", "card-101"])
        XCTAssertNotEqual(replaced.snapshotID, first.snapshotID)
    }

    func testDispatcherNegotiatesCapabilityAuthAndRealStructuredResultEnvelope() async throws {
        let request = TasteMapHybridBridgeRequest(version: 1, requestId: "discovery-page-test", method: .discoveryPage,
            payload: try JSONDecoder().decode(TasteMapHybridJSONValue.self, from: JSONEncoder().encode(query)))
        let unavailable = TasteMapHybridBridgeDispatcher(service: nil, appVersion: "test", build: "test", dataSource: "test",
            authState: { .init(state: "authenticated", userID: "a", displayName: nil) })
        let unsupportedResponse = await unavailable.dispatchAsync(request)
        XCTAssertEqual(unsupportedResponse.error?.code, "capability_unavailable")
        let signedOut = TasteMapHybridBridgeDispatcher(service: nil, appVersion: "test", build: "test", dataSource: "test",
            authState: { .init(state: "signedOut", userID: nil, displayName: nil) }, capabilityOverrides: [.discoveryPage: true])
        let authResponse = await signedOut.dispatchAsync(request)
        XCTAssertEqual(authResponse.error?.code, "auth_required")
        let coordinator = TasteMapDiscoveryPageCoordinator()
        let dispatcher = TasteMapHybridBridgeDispatcher(service: nil, appVersion: "test", build: "test", dataSource: "test",
            authState: { .init(state: "authenticated", userID: "a", displayName: nil) }, capabilityOverrides: [.discoveryPage: true],
            asynchronousAction: { method, payload in
                XCTAssertEqual(method, .discoveryPage)
                let query = try JSONDecoder().decode(TasteMapHybridDiscoveryPageRequest.self, from: JSONEncoder().encode(payload))
                let page = try await coordinator.page(ownerUserID: "a", request: query, isCurrent: { true }) { _, _ in
                    throw TasteMapDiscoveryHTTPError(status: 503, code: "DISCOVERY_AGGREGATE_CAPACITY", message: "capacity")
                }
                return try JSONDecoder().decode(TasteMapHybridJSONValue.self, from: JSONEncoder().encode(page))
            })
        let data = try await dispatcher.responseDataAsync(for: JSONEncoder().encode(request))
        let envelope = try JSONDecoder().decode(TasteMapHybridBridgeResponse.self, from: data)
        XCTAssertNil(envelope.error)
        let result = try JSONDecoder().decode(TasteMapHybridDiscoveryPageDTO.self, from: JSONEncoder().encode(envelope.result))
        XCTAssertEqual(result.refreshStatus.issue?.code, "DISCOVERY_AGGREGATE_CAPACITY")
        XCTAssertEqual(result.pagination, .unknown)
    }
}

@MainActor
private final class PageGate {
    private var continuation: CheckedContinuation<TasteMapDiscoveryPageSource, Never>?
    private var startWaiter: CheckedContinuation<Void, Never>?
    func load() async -> TasteMapDiscoveryPageSource {
        await withCheckedContinuation { continuation in
            self.continuation = continuation; startWaiter?.resume(); startWaiter = nil
        }
    }
    func started() async {
        if continuation != nil { return }
        await withCheckedContinuation { startWaiter = $0 }
    }
    func finish(_ source: TasteMapDiscoveryPageSource) { continuation?.resume(returning: source); continuation = nil }
}
