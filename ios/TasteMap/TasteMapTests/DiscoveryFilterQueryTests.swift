import Foundation
import SwiftData
import Testing
@testable import TasteMap

@Suite(.serialized)
@MainActor
struct DiscoveryFilterQueryTests {
    @Test func personalPredictionAndMatchRemainDistinctThroughBridgeAndServerEcho() throws {
        let values = try filters(#"{"minimumPredictedLikingOutOfTen":8,"minimumTasteMatchPercent":90}"#)
        let query = try TasteMapDiscoveryAppliedQuery.normalized(mode: "for_you", filters: values, sort: "predicted_liking", preferences: nil)
        #expect(query.filters.minimumPredictedLikingOutOfTen == 8)
        #expect(query.filters.minimumTasteMatchPercent == 90)
        #expect(!query.isDefault(mode: "for_you"))
        let encoded = try JSONEncoder().encode(values)
        #expect(try JSONDecoder().decode(TasteMapDiscoveryFilters.self, from: encoded) == values)
        #expect(throws: TasteMapHybridBridgeErrorDTO.self) { try query.verify(nil, mode: "for_you") }
        #expect(throws: TasteMapHybridBridgeErrorDTO.self) {
            try TasteMapDiscoveryAppliedQuery.normalized(mode: "latest", filters: values, sort: nil, preferences: nil)
        }
        for raw in [#"{"minimumPredictedLikingOutOfTen":11}"#, #"{"minimumTasteMatchPercent":101}"#] {
            #expect(throws: TasteMapHybridBridgeErrorDTO.self) { try filters(raw) }
        }
    }

    @Test func explicitAllViewerStatesRemainDistinctFromUnspecifiedLegacyDefaults() throws {
        let all = try filters(#"{"viewerStates":[]}"#)
        let explicit = try TasteMapDiscoveryAppliedQuery.normalized(mode: "for_you", filters: all, sort: nil, preferences: nil)
        let legacy = try TasteMapDiscoveryAppliedQuery.normalized(mode: "for_you", filters: nil, sort: nil, preferences: nil)
        #expect(!explicit.isDefault(mode: "for_you"))
        #expect(explicit.fingerprint != legacy.fingerprint)
        let body = try #require(explicit.queryItems(mode: "for_you").first(where: { $0.name == "filters" })?.value)
        #expect((try JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])?["viewerStates"] is [String])
        #expect(throws: TasteMapHybridBridgeErrorDTO.self) { try explicit.verify(nil, mode: "for_you") }
        try explicit.verify(explicit, mode: "for_you")
    }

    @Test func deviceCoordinatesRequireNativeOwnerProofAndFreshFixWhileExplicitSelectedPointIsNotInvented() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let device = try filters(#"{"distance":{"maximumMeters":3000,"reference":{"latitude":30.251,"longitude":120.163,"source":"device_location"}}}"#)
        let query = try TasteMapDiscoveryAppliedQuery.normalized(mode: "for_you", filters: device, sort: "distance", preferences: nil)
        var proofs = TasteMapDiscoveryLocationProofs()
        do { try proofs.validate(query, owner: "tm_a", permissionAllowed: true, continuation: false, now: now); Issue.record("Unproven JS point accepted") } catch {}
        try proofs.register(try #require(device.distance?.reference), owner: "tm_a", timestamp: now, now: now)
        try proofs.validate(query, owner: "tm_a", permissionAllowed: true, continuation: false, now: now)
        for (owner, allowed, age, continuation) in [("tm_b", true, 0.0, false), ("tm_a", false, 0.0, false), ("tm_a", true, 301.0, false), ("tm_a", true, 601.0, true)] {
            do { try proofs.validate(query, owner: owner, permissionAllowed: allowed, continuation: continuation, now: now.addingTimeInterval(age)); Issue.record("Invalid proof accepted") } catch {}
        }
        try proofs.validate(query, owner: "tm_a", permissionAllowed: true, continuation: true, now: now.addingTimeInterval(60))
        try proofs.validate(query, owner: "tm_a", permissionAllowed: true, continuation: false, now: now.addingTimeInterval(300))
        proofs.reset()
        do { try proofs.validate(query, owner: "tm_a", permissionAllowed: true, continuation: true, now: now); Issue.record("Reset proof survived") } catch {}
        let selected = try filters(#"{"distance":{"maximumMeters":3000,"reference":{"latitude":31.12,"longitude":121.5,"source":"user_selected_point"}}}"#)
        let selectedQuery = try TasteMapDiscoveryAppliedQuery.normalized(mode: "for_you", filters: selected, sort: "distance", preferences: nil)
        try proofs.validate(selectedQuery, owner: "tm_a", permissionAllowed: false, continuation: false, now: now)
        #expect(selectedQuery.filters.distance?.reference.latitude == 31.12)
    }

    private func filters(_ text: String) throws -> TasteMapDiscoveryFilters {
        try JSONDecoder().decode(TasteMapDiscoveryFilters.self, from: Data(text.utf8))
    }
    private func preferences(_ text: String) throws -> TasteMapDiscoverySessionPreferences {
        try JSONDecoder().decode(TasteMapDiscoverySessionPreferences.self, from: Data(text.utf8))
    }

    @Test func strictFiltersNormalizeSetsPreserveZeroAndRejectUnknownUnprovenFacets() throws {
        let result = try filters(#"{"cuisines":["粤菜","川菜","粤菜"],"viewerStates":["visited","none","visited"],"minimumPublicScoreOutOfTen":0,"minimumPublicRatingUsers":0,"requireActualPhoto":true}"#)
        #expect(result.cuisines == ["川菜", "粤菜"])
        #expect(result.viewerStates == ["none", "visited"])
        #expect(result.minimumPublicScoreOutOfTen == 0 && result.minimumPublicRatingUsers == 0)
        for raw in [#"{"city":"杭州"}"#, #"{"region":"上城区"}"#, #"{"cuisines":["未注册菜系"]}"#,
                    #"{"types":["纽约"]}"#, #"{"minimumPublicRatingUsers":1.2}"#, #"{"minimumPublicScoreOutOfTen":11}"#,
                    #"{"requireActualPhoto":null}"#, #"{"distance":{"maximumMeters":1000,"reference":{"latitude":30,"longitude":120,"source":"city_center"}}}"#] {
            do { _ = try filters(raw); Issue.record("Invalid filter accepted: \(raw)") } catch { #expect(error is TasteMapHybridBridgeErrorDTO) }
        }
        let price = try filters(#"{"priceRange":{"minimum":0,"maximumExclusive":100,"basis":"reference_per_person","currency":"CNY"}}"#)
        let priceQuery = try TasteMapDiscoveryAppliedQuery.normalized(mode: "for_you", filters: price, sort: nil, preferences: nil)
        #expect(priceQuery.filters.priceRange?.currency == "CNY")
    }

    @Test func sortAndSessionPreferencesAreModeScopedAndDistanceRequiresExplicitReference() throws {
        let distance = try filters(#"{"distance":{"maximumMeters":3000,"reference":{"latitude":30.251,"longitude":120.163,"source":"user_selected_point"}}}"#)
        let pref = try preferences(#"{"exploration":"adventurous","budget":{"minimum":20,"maximumExclusive":null,"currency":"CNY"},"occasion":"two","nearby":true,"reference":{"latitude":30.251,"longitude":120.163,"source":"user_selected_point"}}"#)
        let query = try TasteMapDiscoveryAppliedQuery.normalized(mode: "for_you", filters: distance, sort: "distance", preferences: pref)
        #expect(query.references.count == 2)
        #expect(try TasteMapDiscoveryAppliedQuery.json(pref).contains("\"maximumExclusive\":null"))
        for mode in ["trending", "following", "latest"] {
            do { _ = try TasteMapDiscoveryAppliedQuery.normalized(mode: mode, filters: nil, sort: nil, preferences: pref); Issue.record("Wrong mode preferences accepted") }
            catch { #expect(error is TasteMapHybridBridgeErrorDTO) }
        }
        do { _ = try TasteMapDiscoveryAppliedQuery.normalized(mode: "for_you", filters: nil, sort: "distance", preferences: nil); Issue.record("Implicit location accepted") } catch {}
        do { _ = try TasteMapDiscoveryAppliedQuery.normalized(mode: "trending", filters: nil, sort: "taste", preferences: nil); Issue.record("Wrong mode sort accepted") } catch {}
        let legacy = try JSONDecoder().decode(TasteMapHybridDiscoveryPageRequest.self, from: Data(#"{"mode":"for_you","city":"","windowDays":7}"#.utf8))
        #expect(legacy.filters == nil && legacy.preferences == nil && legacy.sort == nil)
        #expect(try TasteMapDiscoveryAppliedQuery.normalized(mode: "for_you", filters: nil, sort: nil, preferences: nil).queryItems(mode: "for_you").isEmpty)
    }

    @Test func actualHTTPClientsSendFiltersSortPreferencesAndRejectOldServerIgnoringActiveQuery() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [DiscoveryFilterURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); DiscoveryFilterURLProtocol.handler = nil }
        let apiConfig = APIConfiguration(environment: .development, baseURL: URL(string: "https://filters.example.test")!)
        let discovery = URLSessionDiscoveryAPIClient(configuration: apiConfig, session: session)
        let community = URLSessionCommunityAPIClient(configuration: apiConfig, session: session)
        let hard = try filters(#"{"types":["咖啡"],"requireActualPhoto":true,"minimumPublicScoreOutOfTen":8}"#)
        var acknowledge = true
        for mode in ["for_you", "similar_taste", "trending", "latest", "following"] {
            let query = try TasteMapDiscoveryAppliedQuery.normalized(mode: mode, filters: hard, sort: nil, preferences: nil)
            DiscoveryFilterURLProtocol.handler = { request in
                let url = try #require(request.url)
                let values = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).compactMap { item in item.value.map { (item.name, $0) } })
                #expect(values["city"] == "杭州")
                #expect(values["sort"] == query.sort && values["limit"] == "20")
                #expect(try JSONDecoder().decode(TasteMapDiscoveryFilters.self, from: Data(try #require(values["filters"]).utf8)) == hard)
                #expect(try JSONDecoder().decode(TasteMapDiscoverySessionPreferences.self, from: Data(try #require(values["preferences"]).utf8)) == .init())
                #expect(values["ownerUserID"] == nil)
                let isCommunity = ["latest", "following"].contains(mode)
                var json: [String: Any] = ["apiVersion": 1, "city": "杭州", "generatedAt": "2026-09-07T00:00:00Z", "items": [], "nextCursor": NSNull()]
                if isCommunity { json["scope"] = mode } else { json["mode"] = mode; json["personalizationConfidence"] = "low" }
                if acknowledge { json["appliedQuery"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(query)) }
                return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, try JSONSerialization.data(withJSONObject: json))
            }
            for echoed in [true, false] {
                acknowledge = echoed
                do {
                    if let discoveryMode = DiscoveryModeV1(rawValue: mode) {
                        _ = try await discovery.page(mode: discoveryMode, city: "杭州", trendWindowDays: 7, cursor: nil, limit: 20, query: query)
                    } else {
                        _ = try await community.feed(scope: CommunityFeedScopeV1(rawValue: mode)!, city: "杭州", cursor: nil, limit: 20, query: query)
                    }
                    #expect(echoed)
                } catch { #expect(!echoed && (error as? TasteMapHybridBridgeErrorDTO)?.code == "unsupported_discovery_filter") }
            }
        }
    }

    @Test func queryChangesInvalidateCursorAndDoNotReuseCacheAcrossFiltersSortPreferencesOrOwners() async throws {
        let queryFilters = try filters(#"{"viewerStates":["none"]}"#)
        let query = try TasteMapDiscoveryAppliedQuery.normalized(mode: "for_you", filters: queryFilters, sort: "taste", preferences: nil)
        let coordinator = TasteMapDiscoveryPageCoordinator()
        let request = TasteMapHybridDiscoveryPageRequest(mode: .forYou, city: "", windowDays: 7, filters: queryFilters, sort: "taste")
        let first = try await coordinator.page(ownerUserID: "tm_owner", request: request, isCurrent: { true }) { _, _ in
            .init(mode: .forYou, city: "杭州", generatedAt: "snapshot", items: [], nextCursor: "next", appliedQuery: query)
        }
        #expect(first.appliedQuery == query && first.resolvedCity == "杭州")
        var changed = request; changed.cursor = first.nextCursor; changed.snapshotID = first.snapshotID; changed.sort = "recommended"
        do {
            _ = try await coordinator.page(ownerUserID: "tm_owner", request: changed, isCurrent: { true }) { _, _ in Issue.record("Foreign cursor reached API"); throw URLError(.badURL) }
            Issue.record("Cursor reused after query changed")
        } catch { #expect((error as? TasteMapHybridBridgeErrorDTO)?.code == "discovery_cursor_scope_mismatch") }
        changed.cursor = nil; changed.snapshotID = nil
        let unavailable = try await coordinator.page(ownerUserID: "tm_owner", request: changed, isCurrent: { true }) { _, _ in throw URLError(.notConnectedToInternet) }
        #expect(unavailable.refreshStatus.state == .unavailable && unavailable.appliedQuery == nil)
        let citySession = TasteMapDiscoveryCitySession()
        let cityRequest = TasteMapHybridDiscoveryCityPageRequest(mode: "for_you", city: "", filters: queryFilters, sort: "taste")
        let city = try await citySession.page(ownerUserID: "tm_owner", request: cityRequest, isCurrent: { true }) { _, _ in
            .init(city: "杭州", generatedAt: "snapshot", nextCursor: nil, appliedQuery: query)
        }
        #expect(city.appliedQuery == query && city.resolvedCity == "杭州")
        var preferenceRequest = cityRequest; preferenceRequest.preferences = try preferences(#"{"exploration":"familiar"}"#)
        let noStale = try await citySession.page(ownerUserID: "tm_owner", request: preferenceRequest, isCurrent: { true }) { _, _ in throw URLError(.notConnectedToInternet) }
        #expect(noStale.appliedQuery == nil && noStale.refreshStatus.state == .unavailable)
        let other = try await coordinator.page(ownerUserID: "tm_other", request: request, isCurrent: { true }) { _, _ in throw URLError(.notConnectedToInternet) }
        #expect(other.appliedQuery == nil)
    }
}

private final class DiscoveryFilterURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (response, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
