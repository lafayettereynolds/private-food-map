import Foundation
import SwiftData
import Testing
@testable import TasteMap

@Suite(.serialized)
@MainActor
struct DiscoveryPageIntegrationTests {
    @Test func successfulEvidenceSurvivesPageBridgeAndBothSessionsButNotDeniedOrDifferentOwner() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true, configurationName: "EvidencePages")
        let service = try TasteMapHybridBridgeService(container: container, ownerUserID: "tm_evidence_owner")
        let evidence = TasteMapDiscoveryEvidenceAvailabilityDTO(personalRatedRestaurantCount: 5,
            personalScoreStandardDeviationOutOfTen: 1, personalEvidence: "eligible", localDirectRestaurantCount: 0)
        let page = DiscoveryPageV1(apiVersion: 1, mode: .similarTaste, city: "杭州", personalizationConfidence: .low,
            generatedAt: "2026-09-07T00:00:00Z", items: [], nextCursor: nil, evidenceAvailability: evidence)
        let coordinator = TasteMapDiscoveryPageCoordinator()
        let request = TasteMapHybridDiscoveryPageRequest(mode: .similarTaste, city: "杭州", windowDays: 7)
        let result = try await coordinator.page(ownerUserID: "tm_evidence_owner", request: request, isCurrent: { true }) { _, _ in
            try service.discoveryPageSource(page)
        }
        #expect(result.evidenceAvailability == evidence)
        let session = TasteMapDiscoveryCitySession()
        let cityRequest = TasteMapHybridDiscoveryCityPageRequest(mode: "similar_taste", city: "杭州")
        let city = try await session.page(ownerUserID: "tm_evidence_owner", request: cityRequest, isCurrent: { true }) { _, _ in
            try service.discoveryCitySource(page)
        }
        #expect(city.evidenceAvailability == evidence)
        let denied = try await session.page(ownerUserID: "tm_evidence_owner", request: cityRequest, isCurrent: { true }) { _, _ in
            throw TasteMapDiscoveryHTTPError(status: 403, code: nil, message: "denied")
        }
        #expect(denied.evidenceAvailability == nil && denied.refreshStatus.state == .restricted)
        let other = try await coordinator.page(ownerUserID: "other", request: request, isCurrent: { true }) { _, _ in
            throw URLError(.notConnectedToInternet)
        }
        #expect(other.evidenceAvailability == nil && other.refreshStatus.state == .unavailable)
        service.discoveryEvidenceAvailability = ["similar_taste": evidence]
        #expect(try service.contentSnapshot().discovery.evidenceAvailability?["similar_taste"] == evidence)
    }

#if DEBUG
    @Test func qaCityFiltersWholeDatasetBeforePaginationAndNeverFabricatesMissingFacts() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true, configurationName: "QACityFilters")
        let service = try TasteMapHybridBridgeService(container: container, ownerUserID: "tm_qa")
        var filters = TasteMapDiscoveryFilters()
        filters.viewerStates = ["none"]
        filters.minimumPublicScoreOutOfTen = 8
        filters.minimumPublicRatingUsers = 8
        for mode in ["following", "for_you", "similar_taste", "latest", "trending"] {
            let query = try TasteMapDiscoveryAppliedQuery.normalized(mode: mode, filters: filters, sort: nil, preferences: nil)
            let first = try service.debugCitySource(mode: mode, city: "上海", cursor: nil, windowDays: 7, query: query)
            let second = try service.debugCitySource(mode: mode, city: "上海", cursor: #require(first.nextCursor), windowDays: 7, query: query)
            #expect(first.discoveryItems.count + first.activityItems.count == 20)
            #expect(second.discoveryItems.count + second.activityItems.count == 16)
            #expect(second.nextCursor == nil && first.appliedQuery == query)
            #expect(first.dataSource == "debug_city_fixture" && first.filterCapabilities?.publicScore == true)
        }
        filters.minimumPublicScoreOutOfTen = 9
        var query = try TasteMapDiscoveryAppliedQuery.normalized(mode: "for_you", filters: filters, sort: nil, preferences: nil)
        #expect(try service.debugCitySource(mode: "for_you", city: "上海", cursor: nil, windowDays: 7, query: query).discoveryItems.isEmpty)
        filters.minimumPublicScoreOutOfTen = nil
        filters.requireActualPhoto = true
        query = try .normalized(mode: "for_you", filters: filters, sort: nil, preferences: nil)
        #expect(try service.debugCitySource(mode: "for_you", city: "上海", cursor: nil, windowDays: 7, query: query).discoveryItems.isEmpty)
        filters.requireActualPhoto = false
        filters.distance = .init(maximumMeters: 100, reference: .init(latitude: 31.2304 + 0.0035, longitude: 121.4737, source: "user_selected_point"))
        query = try .normalized(mode: "for_you", filters: filters, sort: "distance", preferences: nil)
        let nearby = try service.debugCitySource(mode: "for_you", city: "上海", cursor: nil, windowDays: 7, query: query)
        #expect(nearby.discoveryItems.first?.restaurant.id == "qa-city:上海:35")
        #expect(nearby.discoveryItems.count < 20 && nearby.nextCursor == nil)
        var preferences = TasteMapDiscoverySessionPreferences(); preferences.exploration = "adventurous"
        query = try .normalized(mode: "for_you", filters: nil, sort: nil, preferences: preferences)
        #expect(throws: TasteMapHybridBridgeErrorDTO.self) {
            try service.debugCitySource(mode: "for_you", city: "上海", cursor: nil, windowDays: 7, query: query)
        }
    }

    @Test func explicitQACityDatasetCoversFiveModesCompletePaginationAndAuthorization() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true, configurationName: "QACityPages")
        let service = try TasteMapHybridBridgeService(container: container, ownerUserID: "tm_qa")
        let session = TasteMapDiscoveryCitySession()
        for mode in ["following", "for_you", "similar_taste", "latest", "trending"] {
            let first = try await session.page(ownerUserID: "tm_qa", request: .init(mode: mode, city: "上海", windowDays: 7), isCurrent: { true }) { city, cursor in
                try service.debugCitySource(mode: mode, city: city, cursor: cursor, windowDays: 7)
            }
            #expect(first.dataSource == "debug_city_fixture")
            #expect(first.discoveryItems.count + first.activityItems.count == 20)
            #expect(first.pagination == .more)
            let second = try await session.page(ownerUserID: "tm_qa", request: .init(mode: mode, city: "上海", windowDays: 7,
                cursor: first.nextCursor, snapshotID: first.snapshotID), isCurrent: { true }) { city, cursor in
                try service.debugCitySource(mode: mode, city: city, cursor: cursor, windowDays: 7)
            }
            #expect(second.discoveryItems.count + second.activityItems.count == 36)
            #expect(second.pagination == .complete)
            #expect(second.snapshotID == first.snapshotID)
            let targets = second.discoveryItems.compactMap(\.interaction) + second.activityItems.compactMap(\.interaction)
            for target in targets {
                #expect(session.permits(target, ownerUserID: "tm_qa"))
                #expect(!session.permits(target, ownerUserID: "other"))
                let forged = TasteMapHybridActivityInteractionDTO(activityID: target.activityID, visitID: target.visitID,
                    authorID: "another-author", restaurantID: target.restaurantID)
                #expect(!session.permits(forged, ownerUserID: "tm_qa"))
            }
        }
        let empty = try service.debugCitySource(mode: "latest", city: "未定义的模拟城市", cursor: nil, windowDays: 7)
        #expect(empty.activityItems.isEmpty && empty.nextCursor == nil)
        #expect(try ModelContext(container).fetch(FetchDescriptor<CachedDiscoveryPlacement>()).isEmpty)
        #expect(try ModelContext(container).fetch(FetchDescriptor<CachedCommunityContent>()).isEmpty)
    }
#endif
    @Test func selectedCitySessionAuthorizesDetailWithoutChangingCanonicalMapCache() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true, configurationName: "CitySessionDetail")
        let service = try TasteMapHybridBridgeService(container: container, ownerUserID: "tm_city")
        let session = TasteMapDiscoveryCitySession()
        service.sessionRestaurantReference = { session.reference($0, ownerUserID: "tm_city") }
        let canonical = try service.contentSnapshot()
        let first = try await session.page(ownerUserID: "tm_city", request: .init(mode: "trending", city: "杭州", windowDays: 30), isCurrent: { true }) { city, cursor in
            #expect(city == "杭州" && cursor == nil)
            return try service.discoveryCitySource(page(0..<20, cursor: "city-next"))
        }
        #expect(first.discoveryItems.count == 20 && first.activityItems.isEmpty)
        #expect(!first.interactionsAvailable && first.engagementState == "unknown")
        let detail = try service.restaurantDetail(id: "place:page-0")
        #expect(detail.restaurant.name == "分页餐厅 0")
        #expect(detail.socialStats?.overallUserRating == 8)
        #expect(session.reference("place:page-0", ownerUserID: "other") == nil)
        #expect(!session.permitsPhoto("guessed-photo", ownerUserID: "tm_city"))
        let second = try await session.page(ownerUserID: "tm_city", request: .init(mode: "trending", city: "杭州", windowDays: 30,
            cursor: first.nextCursor, snapshotID: first.snapshotID), isCurrent: { true }) { city, cursor in
            #expect(city == "杭州市" && cursor == "city-next")
            return try service.discoveryCitySource(page(19..<40, cursor: nil))
        }
        #expect(second.discoveryItems.count == 40 && second.snapshotID == first.snapshotID)
        #expect(second.pagination == .complete)
        #expect(try ModelContext(container).fetch(FetchDescriptor<CachedDiscoveryPlacement>()).isEmpty)
        #expect(try ModelContext(container).fetch(FetchDescriptor<CachedDiscoveryRestaurant>()).isEmpty)
        #expect(try service.contentSnapshot().discovery.forYou.count == canonical.discovery.forYou.count)
        let denied = try await session.page(ownerUserID: "tm_city", request: .init(mode: "trending", city: "杭州", windowDays: 30), isCurrent: { true }) { _, _ in
            throw SyncAPIError.server(status: 403, message: "revoked")
        }
        #expect(denied.refreshStatus.state == .restricted && denied.discoveryItems.isEmpty)
        #expect(session.reference("place:page-0", ownerUserID: "tm_city") == nil)
    }

    @Test func citySessionRejectsForeignCursorAndLateOwnerOrCityResponses() async throws {
        let session = TasteMapDiscoveryCitySession()
        let request = TasteMapHybridDiscoveryCityPageRequest(mode: "latest", city: "杭州")
        let first = try await session.page(ownerUserID: "owner", request: request, isCurrent: { true }) { _, _ in
            .init(city: "杭州", generatedAt: "first", nextCursor: "next", engagementKnown: true)
        }
        #expect(first.interactionsAvailable)
        do {
            _ = try await session.page(ownerUserID: "owner", request: .init(mode: "latest", city: "上海", cursor: "next", snapshotID: first.snapshotID), isCurrent: { true }) { _, _ in
                Issue.record("Foreign cursor reached provider")
                return .init(city: "上海", generatedAt: "second", nextCursor: nil)
            }
            Issue.record("Foreign cursor accepted")
        } catch { #expect((error as? TasteMapHybridBridgeErrorDTO)?.code == "discovery_cursor_scope_mismatch") }
        let wrongCity = try await session.page(ownerUserID: "owner", request: request, isCurrent: { true }) { _, _ in
            .init(city: "上海", generatedAt: "wrong", nextCursor: nil)
        }
        #expect(wrongCity.refreshStatus.state == .cached)
        #expect(wrongCity.resolvedCity == "杭州")
        var release: CheckedContinuation<TasteMapDiscoveryCitySource, Never>?
        let pending = Task { @MainActor in
            try await session.page(ownerUserID: "owner", request: request, isCurrent: { true }) { _, _ in
                await withCheckedContinuation { release = $0 }
            }
        }
        while release == nil { await Task.yield() }
        session.reset()
        release?.resume(returning: .init(city: "杭州", generatedAt: "late", nextCursor: nil))
        do { _ = try await pending.value; Issue.record("Late owner page accepted") }
        catch { #expect((error as? TasteMapHybridBridgeErrorDTO)?.code == "discovery_query_superseded") }
    }

    @Test func cityPreferenceUsesOnlyAcceptedOwnerScopedIdentitiesWithoutPersistentPlacement() async throws {
        let owner = "tm_city_preference_\(UUID().uuidString)"
        let container = try TasteMapPersistence.makeContainer(inMemory: true, configurationName: "CityPreference")
        let service = try TasteMapHybridBridgeService(container: container, ownerUserID: owner)
        let session = TasteMapDiscoveryCitySession()
        defer { UserDefaults.standard.removeObject(forKey: "tastemap.recommendation-exclusions.v1.\(owner)") }
        _ = try await session.page(ownerUserID: owner, request: .init(mode: "trending", city: "杭州"), isCurrent: { true }) { _, _ in
            try service.discoveryCitySource(page(0..<1, cursor: nil))
        }
        let groups = session.identityGroups(ownerUserID: owner)
        #expect(!groups.isEmpty && session.identityGroups(ownerUserID: "other").isEmpty)
        let excluded = try RestaurantRecommendationPreferences.excludedIDs(ownerID: owner, context: container.mainContext,
            adding: "place:page-0", authorizedSessionIdentityGroups: groups)
        #expect(excluded == ["place:page-0"])
        do {
            _ = try RestaurantRecommendationPreferences.excludedIDs(ownerID: owner, context: container.mainContext,
                adding: "guessed-private-place", authorizedSessionIdentityGroups: groups)
            Issue.record("Arbitrary restaurant identifier accepted")
        } catch { #expect(error is TasteMapHybridServiceError) }
        #expect(try ModelContext(container).fetch(FetchDescriptor<CachedDiscoveryRestaurant>()).isEmpty)
        #expect(try ModelContext(container).fetch(FetchDescriptor<Restaurant>()).isEmpty)
    }

    @Test func actualURLSessionPagesFlowThroughProjectionCoordinatorAndBridgeWithoutWritingLegacyCache() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true, configurationName: "DiscoveryScopedPages")
        let service = try TasteMapHybridBridgeService(container: container, ownerUserID: "tm_page_test")
        let coordinator = TasteMapDiscoveryPageCoordinator()
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [DiscoveryPageURLProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)
        defer { session.invalidateAndCancel(); DiscoveryPageURLProtocol.handler = nil }
        let api = URLSessionDiscoveryAPIClient(
            configuration: APIConfiguration(environment: .development, baseURL: URL(string: "https://discovery.example.test")!),
            authorization: DiscoveryPageTestAuthorization(), session: session)
        let firstData = try JSONEncoder().encode(page(0..<20, cursor: "opaque-next"))
        let secondData = try JSONEncoder().encode(page(19..<40, cursor: nil))
        DiscoveryPageURLProtocol.handler = { request in
            let url = try #require(request.url)
            #expect(url.path == "/api/v1/discovery/trending")
            let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
            let query = Dictionary(uniqueKeysWithValues: items.compactMap { item in item.value.map { (item.name, $0) } })
            #expect(query["city"] == "杭州市")
            #expect(query["window"] == "30")
            #expect(query["limit"] == "20")
            #expect(query["ownerUserID"] == nil)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer scoped-test-only")
            let data: Data
            if let cursor = query["cursor"] { #expect(cursor == "opaque-next"); data = secondData }
            else { data = firstData }
            return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        let dispatcher = TasteMapHybridBridgeDispatcher(service: service, appVersion: "test", build: "test", dataSource: "test",
            authState: { .init(state: "authenticated", userID: "tm_page_test", displayName: nil) },
            capabilityOverrides: [.discoveryPage: true], asynchronousAction: { method, payload in
                #expect(method == .discoveryPage)
                let request = try JSONDecoder().decode(TasteMapHybridDiscoveryPageRequest.self, from: JSONEncoder().encode(payload))
                let response = try await coordinator.page(ownerUserID: "tm_page_test", request: request, isCurrent: { true }) { city, cursor in
                    try service.discoveryPageSource(await api.page(mode: .trending, city: city, trendWindowDays: request.windowDays, cursor: cursor, limit: 20))
                }
                return try JSONDecoder().decode(TasteMapHybridJSONValue.self, from: JSONEncoder().encode(response))
            })
        func invoke(_ query: TasteMapHybridDiscoveryPageRequest) async throws -> TasteMapHybridDiscoveryPageDTO {
            let payload = try JSONDecoder().decode(TasteMapHybridJSONValue.self, from: JSONEncoder().encode(query))
            let envelope = await dispatcher.dispatchAsync(.init(version: 1, requestId: UUID().uuidString, method: .discoveryPage, payload: payload))
            #expect(envelope.error == nil)
            return try JSONDecoder().decode(TasteMapHybridDiscoveryPageDTO.self, from: JSONEncoder().encode(envelope.result))
        }
        let first = try await invoke(.init(mode: .trending, city: "杭州市", windowDays: 30))
        let second = try await invoke(.init(mode: .trending, city: "杭州市", windowDays: 30, cursor: first.nextCursor, snapshotID: first.snapshotID))
        #expect(second.items.count == 40)
        #expect(second.items.map(\.rank) == Array(1...40))
        #expect(second.items[0].communityRating.sampleCount == 4)
        #expect(second.items[0].reasons.first?.text == "真实测试理由")
        #expect(second.snapshotID == first.snapshotID)
        #expect(second.pagination == .complete)
        #expect(!second.interactionsAvailable && second.engagementState == "unknown")
        #expect(try ModelContext(container).fetch(FetchDescriptor<CachedDiscoveryPlacement>()).isEmpty)
        #expect(try ModelContext(container).fetch(FetchDescriptor<CachedDiscoveryRestaurant>()).isEmpty)
    }

    @Test func transportObservationPreservesFailureAndDoesNotRetry() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DiscoveryPageURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); DiscoveryPageURLProtocol.handler = nil }
        let api = URLSessionDiscoveryAPIClient(
            configuration: .init(environment: .development, baseURL: URL(string: "https://discovery.example.test")!),
            authorization: DiscoveryPageTestAuthorization(), session: session)
        var count = 0
        DiscoveryPageURLProtocol.handler = { request in
            count += 1
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer scoped-test-only")
            #expect(request.url?.path == "/api/v1/discovery/for-you")
            throw URLError(.networkConnectionLost)
        }
        do {
            _ = try await api.page(mode: .forYou, city: "杭州", trendWindowDays: 7, cursor: nil, limit: 20)
            Issue.record("Expected original transport failure")
        } catch {
            #expect((error as? URLError)?.code == .networkConnectionLost)
        }
        #expect(count == 1)
    }

    @Test func realAPIPathsKeepModesSevenOrThirtyDayWindowsAndStructuredCapacityError() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DiscoveryPageURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); DiscoveryPageURLProtocol.handler = nil }
        let api = URLSessionDiscoveryAPIClient(
            configuration: .init(environment: .development, baseURL: URL(string: "https://discovery.example.test")!), session: session)
        for (mode, days, path) in [(DiscoveryModeV1.forYou, 7, "for-you"), (.similarTaste, 7, "similar-taste"), (.trending, 7, "trending"), (.trending, 30, "trending")] {
            DiscoveryPageURLProtocol.handler = { request in
                let url = try #require(request.url)
                #expect(url.path == "/api/v1/discovery/\(path)")
                let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                #expect(items.first(where: { $0.name == "city" })?.value == "Kansas City")
                #expect(items.first(where: { $0.name == "window" })?.value == (mode == .trending ? String(days) : nil))
                return (HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil)!,
                        Data(#"{"code":"DISCOVERY_AGGREGATE_CAPACITY","error":"capacity"}"#.utf8))
            }
            do { _ = try await api.page(mode: mode, city: "Kansas City", trendWindowDays: days, cursor: nil, limit: 20); Issue.record("Expected capacity error") }
            catch let error as TasteMapDiscoveryHTTPError { #expect(error.status == 503 && error.code == "DISCOVERY_AGGREGATE_CAPACITY") }
        }
    }

    private func page(_ range: Range<Int>, cursor: String?) -> DiscoveryPageV1 {
        let cards = range.map { index in
            let restaurant = DiscoveryRestaurantProjectionV1(globalKey: "place:page-\(index)", placeIdentities: [],
                name: "分页餐厅 \(index)", address: "杭州", city: "杭州市", latitude: 30.2, longitude: 120.1,
                tags: [], pricePerPerson: nil, merchantImageUrl: nil, markerEmoji: "", photo: nil)
            let rating = DiscoveryRatingProjectionV1(value: 4, sampleCount: 4)
            return DiscoveryCardV1(id: "page-\(index)", mode: .trending, restaurant: restaurant, viewerState: .none,
                ratings: .init(mine: rating, community: rating, friends: rating, similarTaste: rating),
                reasons: [.init(code: "test_evidence", text: "真实测试理由")], sourceUser: nil, similarity: nil, trend: nil,
                cacheScope: index == 0 ? .friends : .public, rank: index + 1, score: Double(100 - index))
        }
        return .init(apiVersion: 1, mode: .trending, city: "杭州市", personalizationConfidence: .insufficient,
                     generatedAt: "2026-09-06T00:00:00.000Z", items: cards, nextCursor: cursor)
    }
}

private struct DiscoveryPageTestAuthorization: SyncAuthorizationProviding {
    func headers() async throws -> [String: String] { ["Authorization": "Bearer scoped-test-only"] }
}

private final class DiscoveryPageURLProtocol: URLProtocol, @unchecked Sendable {
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
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
