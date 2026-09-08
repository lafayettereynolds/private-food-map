import CoreLocation
import Foundation
import MapKit
import SwiftData
import Testing
@testable import TasteMap

private final class AcquisitionWorldwideURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.badServerResponse) }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@Suite("Restaurant acquisition", .serialized)
@MainActor
struct RestaurantAcquisitionTests {
    @Test("Live provider accepts the user's original full restaurant name", .enabled(if: ProcessInfo.processInfo.environment["TASTEMAP_LIVE_SEARCH"] == "1"))
    func liveFullForeignRestaurantName() async throws {
        // Explicit opt-in integration test: never introduce public-network
        // availability into the deterministic regression suite.
        let fallback = AcquisitionSearchSpy()
        let values = try await WorldwideRestaurantSearchService(mapKit: fallback)
            .search(query: "Da Andrea Greenwich Village", scope: .init(city: "纽约"))
        #expect(fallback.lastQuery == nil)
        #expect(values.first?.placeIdentities.first?.externalID == "osm:n:2569050392")
        #expect(values.first?.address.contains("35 West 13th Street") == true)
        #expect(values.first?.address.contains("Union Square") == true)
        #expect(values.first?.resolvedSearchQuery == "Da Andrea Greenwich Village")
        print("LIVE_SEARCH_RESULT \(values.map { "\($0.name) | \($0.address)" }.joined(separator: " ; "))")
    }

    @Test("Qualified fallback rejects wrong-city or non-place anchors and other-city businesses")
    func qualifiedFallbackRequiresCityAndPlaceEvidence() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AcquisitionWorldwideURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); AcquisitionWorldwideURLProtocol.handler = nil }
        let city = RestaurantResolvedCity(displayName: "New York", countryCode: "US", region: MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.71427, longitude: -74.00597), latitudinalMeters: 120_000, longitudinalMeters: 120_000))
        for (anchorKey, anchorCity, businessCity) in [("place", "Jersey City", "New York"), ("amenity", "New York", "New York"), ("place", "New York", "Jersey City")] {
            AcquisitionWorldwideURLProtocol.handler = { request in
                let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value
                let body: String
                if query == "Greenwich Village" {
                    body = "{\"features\":[{\"properties\":{\"osm_type\":\"N\",\"osm_id\":1,\"osm_key\":\"\(anchorKey)\",\"osm_value\":\"neighbourhood\",\"name\":\"Greenwich Village\",\"city\":\"\(anchorCity)\"},\"geometry\":{\"coordinates\":[-73.9965658,40.7319802]}}]}"
                } else if query == "Da Andrea" {
                    body = "{\"features\":[{\"properties\":{\"osm_type\":\"N\",\"osm_id\":2,\"osm_key\":\"amenity\",\"osm_value\":\"restaurant\",\"name\":\"Da Andrea\",\"city\":\"\(businessCity)\"},\"geometry\":{\"coordinates\":[-73.995801,40.7361321]}}]}"
                } else { body = #"{"features":[]}"# }
                #expect(request.timeoutInterval <= 10)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
            }
            let values = try await PhotonRestaurantSearchService(session: session).searchQualifiedName(
                query: "Da Andrea Greenwich Village", scopeCity: "纽约", resolvedCity: city)
            #expect(values.isEmpty)
        }
    }

    @Test("A provider timeout uses independent fallback; cancellation does not start another search")
    func qualifiedFallbackTimeoutAndCancellation() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AcquisitionWorldwideURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); AcquisitionWorldwideURLProtocol.handler = nil }
        for code in [URLError.timedOut, URLError.cancelled] {
            AcquisitionWorldwideURLProtocol.handler = { request in
                if request.url?.host == "geocoding-api.open-meteo.com" {
                    let body = #"{"results":[{"name":"New York","latitude":40.71427,"longitude":-74.00597,"feature_code":"PPL","country_code":"US"}]}"#
                    return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
                }
                throw URLError(code)
            }
            let fallback = AcquisitionSearchSpy()
            do {
                _ = try await WorldwideRestaurantSearchService(session: session, mapKit: fallback)
                    .search(query: "Da Andrea Greenwich Village", scope: .init(city: "纽约"))
                #expect(code == .timedOut)
                #expect(fallback.lastQuery == "Da Andrea Greenwich Village")
            } catch {
                #expect(code == .cancelled)
                #expect((error as? URLError)?.code == .cancelled)
                #expect(fallback.lastQuery == nil)
            }
        }
    }

    @Test("Full name plus neighbourhood automatically retrieves real branches despite provider locality mismatch")
    func fullForeignNameWithProviderLocalityMismatch() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AcquisitionWorldwideURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); AcquisitionWorldwideURLProtocol.handler = nil }
        AcquisitionWorldwideURLProtocol.handler = { request in
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value
            let body: String
            if request.url?.host == "geocoding-api.open-meteo.com" {
                body = #"{"results":[{"name":"New York","latitude":40.71427,"longitude":-74.00597,"feature_code":"PPL","country_code":"US"}]}"#
            } else if query == "Greenwich Village" {
                body = #"{"features":[{"properties":{"osm_type":"N","osm_id":158861717,"osm_key":"place","osm_value":"neighbourhood","name":"Greenwich Village","city":"New York"},"geometry":{"coordinates":[-73.9965658,40.7319802]}}]}"#
            } else if query == "Da Andrea" {
                // Both real branches; provider calls the desired branch Union Square.
                body = #"{"features":[{"properties":{"osm_type":"N","osm_id":2377128176,"osm_key":"amenity","osm_value":"restaurant","name":"Da Andrea","city":"New York","locality":"Chelsea District","street":"8th Avenue","housenumber":"160"},"geometry":{"coordinates":[-74.0006,40.742]}},{"properties":{"osm_type":"N","osm_id":2569050392,"osm_key":"amenity","osm_value":"restaurant","name":"Da Andrea","city":"New York","locality":"Union Square","street":"West 13th Street","housenumber":"35"},"geometry":{"coordinates":[-73.995801,40.7361321]}}]}"#
            } else { body = #"{"features":[]}"# }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        let values = try await WorldwideRestaurantSearchService(session: session, mapKit: AcquisitionSearchSpy())
            .search(query: "Da Andrea Greenwich Village", scope: .init(city: "纽约"))
        #expect(values.count == 2)
        #expect(values.first?.address.contains("35 West 13th Street") == true)
        #expect(values.first?.address.contains("Union Square") == true)
        #expect(RestaurantSearchRelevancePolicy.rankedMatches(values, query: "Da Andrea Greenwich Village").count == 2)
        #expect(RestaurantSearchRelevancePolicy.rankedMatches(values, query: "unrelated restaurant name").isEmpty)
    }
    @Test("Lanzhou shorthand retains the actual beef-noodle branch and excludes unrelated shops")
    func lanzhouShorthand() {
        let candidates = ["兰州牛肉拉面（凯旋门商业中心店）", "兰州拉面（另一分店）", "杭州牛肉拉面", "兰州烧烤", "兰州某个很长很长很长的商城拉面"].map {
            RestaurantCandidate(name: $0, address: "", city: "杭州", latitude: 30.27, longitude: 120.15)
        }
        #expect(RestaurantSearchRelevancePolicy.rankedMatches(candidates, query: "兰州拉面").map(\.name) == ["兰州拉面（另一分店）", "兰州牛肉拉面（凯旋门商业中心店）"])
        #expect(RestaurantSearchRelevancePolicy.queryVariants("兰州拉面") == ["兰州拉面", "兰州牛肉拉面"])
        #expect(RestaurantSearchRelevancePolicy.queryVariants("陌生小馆") == ["陌生小馆"])
    }
    @Test("Search relevance removes unrelated provider suggestions and handles mixed CJK/Latin input")
    func searchRelevance() {
        let values = [
            RestaurantCandidate(name: "青岚寿司", address: "杭州市美食街 1 号", city: "杭州", latitude: 30.27, longitude: 120.15),
            RestaurantCandidate(name: "牛 New 寿喜烧", address: "杭州市延安路 88 号", city: "杭州", latitude: 30.28, longitude: 120.16),
            RestaurantCandidate(name: "山茶烘焙", address: "杭州市美食街 81 号", city: "杭州", latitude: 30.29, longitude: 120.17),
        ]

        #expect(RestaurantSearchRelevancePolicy.rankedMatches(values, query: "牛new").map(\.name) == ["牛 New 寿喜烧"])
        #expect(RestaurantSearchRelevancePolicy.rankedMatches(values, query: "延安路 88").map(\.name) == ["牛 New 寿喜烧"])
        #expect(RestaurantSearchRelevancePolicy.rankedMatches(values, query: "完全不存在").isEmpty)
    }

    @Test("Worldwide city and dining-intent searches remain relevant across scripts")
    func worldwideCitySearchRelevance() {
        let shanghai = RestaurantCandidate(
            name: "南翔馒头店", address: "上海市黄浦区豫园路", city: "上海",
            latitude: 31.227, longitude: 121.492,
            categoryHints: [MKPointOfInterestCategory.restaurant.rawValue]
        )
        let newYork = RestaurantCandidate(
            name: "Katz's Delicatessen", address: "205 E Houston St", city: "New York",
            latitude: 40.722, longitude: -73.987,
            categoryHints: [MKPointOfInterestCategory.restaurant.rawValue]
        )

        #expect(RestaurantSearchRelevancePolicy.rankedMatches(
            [shanghai], query: "上海餐厅"
        ).map(\.name) == ["南翔馒头店"])
        #expect(RestaurantSearchRelevancePolicy.rankedMatches(
            [newYork], query: "New York restaurant"
        ).map(\.name) == ["Katz's Delicatessen"])
        #expect(RestaurantSearchRelevancePolicy.rankedMatches(
            [newYork], query: "餐厅", scopeCity: "纽约"
        ).map(\.name) == ["Katz's Delicatessen"])
    }

    @Test("Worldwide city aliases preserve common Chinese and compact spellings")
    func worldwideCityAliases() {
        #expect(WorldwideCityResolver.canonicalQuery(for: "纽约") == "New York")
        #expect(WorldwideCityResolver.canonicalQuery(for: "NewYork") == "New York")
        #expect(WorldwideCityResolver.canonicalQuery(for: " new york ") == "New York")
        #expect(WorldwideCityResolver.canonicalQuery(for: "东京") == "Tokyo")
        #expect(WorldwideCityResolver.canonicalQuery(for: "上海市") == "Shanghai")
        #expect(WorldwideCityResolver.canonicalQuery(for: " Reykjavík ") == "Reykjavík")
    }

    @Test("Unrelated foreign-provider dining suggestions cannot suppress the independent fallback")
    func worldwideIrrelevantDiningFallsBack() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AcquisitionWorldwideURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); AcquisitionWorldwideURLProtocol.handler = nil }
        AcquisitionWorldwideURLProtocol.handler = { request in
            let body: String
            if request.url?.host == "geocoding-api.open-meteo.com" {
                let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
                #expect(query?.first(where: { $0.name == "name" })?.value == "New York")
                body = #"{"results":[{"name":"New York","latitude":40.71427,"longitude":-74.00597,"feature_code":"PPL","country_code":"US","population":8804190}]}"#
            } else {
                // This is the actual failure shape: the full query returned a
                // restaurant matching only "Greenwich", not the requested name.
                body = #"{"features":[{"properties":{"osm_type":"N","osm_id":6053253585,"osm_key":"amenity","osm_value":"restaurant","name":"Top Thai Greenwich","city":"New York","district":"Manhattan"},"geometry":{"coordinates":[-73.9994469,40.7297907]}}]}"#
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        let fallback = AcquisitionSearchSpy()
        fallback.searchOverride = [RestaurantCandidate(name: "Da Andrea", address: "35 W 13th St",
            city: "New York", district: "Greenwich Village, Manhattan", latitude: 40.7361321, longitude: -73.995801)]
        let values = try await WorldwideRestaurantSearchService(session: session, mapKit: fallback)
            .search(query: "Da Andrea Greenwich Village", scope: .init(city: "new york"))
        #expect(values.map(\.name) == ["Da Andrea"])
        #expect(fallback.lastQuery == "Da Andrea Greenwich Village")
        #expect(fallback.lastScope?.city == "new york")
        #expect(fallback.lastScope?.center == nil)
    }

    @Test("A genuine foreign-provider match does not trigger an unnecessary fallback")
    func worldwideRelevantDiningReturns() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AcquisitionWorldwideURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); AcquisitionWorldwideURLProtocol.handler = nil }
        AcquisitionWorldwideURLProtocol.handler = { request in
            let body = request.url?.host == "geocoding-api.open-meteo.com"
                ? #"{"results":[{"name":"New York","latitude":40.71427,"longitude":-74.00597,"feature_code":"PPL","country_code":"US","population":8804190}]}"#
                : #"{"features":[{"properties":{"osm_type":"N","osm_id":2569050392,"osm_key":"amenity","osm_value":"restaurant","name":"Da Andrea","city":"New York","district":"Manhattan","street":"West 13th Street","housenumber":"35"},"geometry":{"coordinates":[-73.995801,40.7361321]}}]}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        let fallback = AcquisitionSearchSpy()
        let values = try await WorldwideRestaurantSearchService(session: session, mapKit: fallback)
            .search(query: "Da Andrea", scope: .init(city: "new york"))
        #expect(values.map(\.name) == ["Da Andrea"])
        #expect(values.first?.address.contains("35 West 13th Street") == true)
        #expect(fallback.lastQuery == nil)
    }

    @Test("Name plus neighbourhood does not admit another branch or an unrelated neighbourhood restaurant")
    func qualifiedForeignRestaurantName() {
        let values = [
            RestaurantCandidate(name: "Da Andrea", address: "160 8th Ave", city: "New York", district: "Chelsea", latitude: 40.742, longitude: -74.0006),
            RestaurantCandidate(name: "Top Thai Greenwich", address: "235 Sullivan St", city: "New York", district: "Greenwich Village", latitude: 40.7298, longitude: -73.9994),
            RestaurantCandidate(name: "Da Andrea", address: "35 W 13th St", city: "New York", district: "Greenwich Village", latitude: 40.7361, longitude: -73.9958),
        ]
        #expect(RestaurantSearchRelevancePolicy.rankedMatches(values, query: "Da Andrea Greenwich Village")
            .map(\.address) == ["35 W 13th St"])
    }

    @Test("Nearby uses current location, keeps distance, and detects the city")
    func nearbySuccess() async throws {
        let search = AcquisitionSearchSpy()
        let viewModel = RestaurantAcquisitionViewModel(
            searchService: search,
            linkResolver: AcquisitionLinkResolverStub(),
            locationProvider: AcquisitionLocationStub()
        )

        await viewModel.loadNearby()

        #expect(viewModel.nearbyState == .loaded)
        #expect(viewModel.nearbyResults.map(\.name) == ["附近小馆"])
        #expect(abs((viewModel.nearbyResults.first?.distanceMeters ?? 0) - 110.9) < 1)
        #expect(viewModel.detectedCity == "杭州")
        #expect(search.nearbyRadius == 3_000)
        #expect(search.nearbyCenters == [RestaurantCoordinate(latitude: 30.2741, longitude: 120.1551, reference: .wgs84)])
        #expect(viewModel.locationAccuracy == .precise)
    }

    @Test("Nearby expands the complete accepted snapshot without another GPS or provider request")
    func nearbyCompleteSnapshotLocalContinuation() async {
        let search = AcquisitionSearchSpy()
        let location = AcquisitionLocationStub()
        let origin = RestaurantCoordinate(latitude: 30.2741, longitude: 120.1551)
        let candidates = (0..<29).map { index in
            RestaurantCandidate(name: "批次测试 \(index)", address: "测试地址", city: "测试城市",
                latitude: origin.latitude + Double(index + 1) / 10_000, longitude: origin.longitude,
                appleMapItemIdentifier: "nearby-batch-\(index)")
        }
        search.nearbyOverride = Array(candidates.reversed()) + [RestaurantCandidate(name: "半径外测试", address: "测试地址", city: "测试城市",
            latitude: origin.latitude + 0.1, longitude: origin.longitude, appleMapItemIdentifier: "outside")]
        let model = RestaurantAcquisitionViewModel(searchService: search, linkResolver: AcquisitionLinkResolverStub(), locationProvider: location)
        await model.loadNearby()
        #expect(model.nearbyResults.count == 29)
        #expect(model.visibleNearbyResults.count == 12)
        model.loadMoreNearby()
        #expect(model.visibleNearbyResults.count == 24)
        model.loadMoreNearby()
        model.loadMoreNearby()
        #expect(model.visibleNearbyResults.map(\.id) == candidates.map(\.id))
        #expect(!model.hasMoreNearbyResults)
        #expect(location.requestCount == 1)
        #expect(search.nearbyCenters.count == 1)
        await model.loadNearby()
        #expect(model.visibleNearbyResults.count == 12)
        #expect(location.requestCount == 2)
        #expect(search.nearbyCenters.count == 2)
    }

    @Test("A superseded Nearby batch cannot reappear after owner or lifecycle invalidation")
    func nearbyInvalidationRejectsLateBatch() async {
        let search = AcquisitionSearchSpy()
        search.nearbyDelay = .milliseconds(40)
        let model = RestaurantAcquisitionViewModel(searchService: search, linkResolver: AcquisitionLinkResolverStub(), locationProvider: AcquisitionLocationStub())
        let pending = Task { await model.loadNearby() }
        for _ in 0..<1_000 {
            if !search.nearbyCenters.isEmpty { break }
            await Task.yield()
        }
        #expect(!search.nearbyCenters.isEmpty)
        model.invalidateNearby()
        model.loadMoreNearby()
        await pending.value
        #expect(model.nearbyState == .idle)
        #expect(model.nearbyResults.isEmpty)
        #expect(!model.hasMoreNearbyResults)
        search.nearbyDelay = nil
        await model.loadNearby()
        #expect(model.nearbyState == .loaded)
        #expect(model.nearbyResults.count == 1)
    }

    @Test("Fresh CLLocation is accepted and a stale cached CLLocation is rejected")
    func freshAndStaleLocationPolicy() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let fresh = acquisitionLocation(timestamp: now.addingTimeInterval(-2), horizontalAccuracy: 12)
        let stale = acquisitionLocation(timestamp: now.addingTimeInterval(-120), horizontalAccuracy: 12)

        #expect(RestaurantLocationFixPolicy.isUsable(fresh, accuracyAuthorization: .fullAccuracy, now: now))
        #expect(!RestaurantLocationFixPolicy.isUsable(stale, accuracyAuthorization: .fullAccuracy, now: now))
    }

    @Test("A new Nearby request rejects a replayed recent fix even when text search could reuse it")
    func freshRequestRejectsRecentCachedFix() {
        let startedAt = Date(timeIntervalSince1970: 2_000_000_000)
        let cached = acquisitionLocation(timestamp: startedAt.addingTimeInterval(-12), horizontalAccuracy: 8)
        let current = acquisitionLocation(timestamp: startedAt.addingTimeInterval(1), horizontalAccuracy: 15)
        #expect(RestaurantLocationFixPolicy.isUsable(cached, accuracyAuthorization: .fullAccuracy, now: startedAt))
        #expect(!RestaurantLocationFixPolicy.belongsToRequest(cached, startedAt: startedAt))
        #expect(RestaurantLocationFixPolicy.belongsToRequest(current, startedAt: startedAt))
        #expect(RestaurantLocationFixPolicy.belongsToRequest(
            acquisitionLocation(timestamp: startedAt.addingTimeInterval(-0.5), horizontalAccuracy: 12), startedAt: startedAt
        ))
    }

    @Test("Map and Nearby share the active sensor request but the next request is fresh")
    func concurrentFreshRequests() async throws {
        let coordinator = RestaurantLocationRequestCoordinator()
        var requestCount = 0
        let acquire: @MainActor () async throws -> CLLocation = {
            requestCount += 1
            try await Task.sleep(for: .milliseconds(30))
            return acquisitionLocation(horizontalAccuracy: 12)
        }
        async let mapFix = coordinator.request(acquire)
        async let nearbyFix = coordinator.request(acquire)
        let (map, nearby) = try await (mapFix, nearbyFix)
        #expect(requestCount == 1)
        #expect(map.timestamp == nearby.timestamp)
        _ = try await coordinator.request(acquire)
        #expect(requestCount == 2)
    }

    @Test("A failed shared sensor request does not poison retry")
    func failedFreshRequestCanRetry() async throws {
        let coordinator = RestaurantLocationRequestCoordinator()
        do {
            _ = try await coordinator.request { throw RestaurantLocationError.unavailable }
            Issue.record("Expected the sensor failure to propagate")
        } catch RestaurantLocationError.unavailable { }
        let fix = try await coordinator.request { acquisitionLocation(horizontalAccuracy: 14) }
        #expect(fix.horizontalAccuracy == 14)
    }

    @Test("Nearby does not accept the first coarse full-accuracy fix")
    func preciseLocationPolicyWaitsForAnAccurateFix() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let coarse = acquisitionLocation(
            latitude: 30.281,
            longitude: 120.161,
            timestamp: now,
            horizontalAccuracy: 450
        )
        let acceptable = acquisitionLocation(
            latitude: 30.2744,
            longitude: 120.1554,
            timestamp: now.addingTimeInterval(1),
            horizontalAccuracy: 82
        )
        let preferred = acquisitionLocation(
            latitude: 30.2741,
            longitude: 120.1551,
            timestamp: now.addingTimeInterval(2),
            horizontalAccuracy: 18
        )

        #expect(!RestaurantLocationFixPolicy.isUsable(
            coarse,
            accuracyAuthorization: .fullAccuracy,
            now: now
        ))
        #expect(RestaurantLocationFixPolicy.isUsable(
            acceptable,
            accuracyAuthorization: .fullAccuracy,
            now: now.addingTimeInterval(1)
        ))
        #expect(!RestaurantLocationFixPolicy.isPreferred(
            acceptable,
            accuracyAuthorization: .fullAccuracy,
            now: now.addingTimeInterval(1)
        ))
        #expect(RestaurantLocationFixPolicy.isPreferred(
            preferred,
            accuracyAuthorization: .fullAccuracy,
            now: now.addingTimeInterval(2)
        ))

        let selected = try #require(RestaurantLocationFixPolicy.bestUsableLocation(
            in: [coarse, acceptable, preferred],
            comparedWith: nil,
            accuracyAuthorization: .fullAccuracy,
            now: now.addingTimeInterval(2)
        ))
        #expect(selected.horizontalAccuracy == 18)
        #expect(selected.coordinate.latitude == preferred.coordinate.latitude)
        #expect(selected.coordinate.longitude == preferred.coordinate.longitude)
    }

    @Test("Reduced Accuracy remains usable but is never presented as meter-level precision")
    func reducedLocationPolicyRemainsHonest() {
        let location = acquisitionLocation(horizontalAccuracy: 3_000)

        #expect(!RestaurantLocationFixPolicy.isUsable(
            location,
            accuracyAuthorization: .fullAccuracy
        ))
        #expect(RestaurantLocationFixPolicy.isPreferred(
            location,
            accuracyAuthorization: .reducedAccuracy
        ))
    }

    @Test("Delayed first fix remains locating and does not search from a fallback center")
    func delayedFirstFix() async {
        let search = AcquisitionSearchSpy()
        let location = AcquisitionLocationStub(delay: .milliseconds(80))
        let viewModel = RestaurantAcquisitionViewModel(
            searchService: search,
            linkResolver: AcquisitionLinkResolverStub(),
            locationProvider: location
        )

        let task = Task { await viewModel.loadNearby() }
        try? await Task.sleep(for: .milliseconds(10))

        #expect(viewModel.nearbyState == .loading)
        #expect(search.nearbyCenters.isEmpty)

        await task.value
        #expect(viewModel.nearbyState == .loaded)
        #expect(search.nearbyCenters.count == 1)
    }

    @Test("Stale provider result never reaches Nearby search")
    func staleLocationDoesNotSearch() async {
        let search = AcquisitionSearchSpy()
        let stale = acquisitionLocation(timestamp: Date().addingTimeInterval(-300), horizontalAccuracy: 10)
        let viewModel = RestaurantAcquisitionViewModel(
            searchService: search,
            linkResolver: AcquisitionLinkResolverStub(),
            locationProvider: AcquisitionLocationStub(locations: [stale])
        )

        await viewModel.loadNearby()

        guard case .failed = viewModel.nearbyState else {
            Issue.record("Expected stale location to leave Nearby in a recoverable failed state")
            return
        }
        #expect(search.nearbyCenters.isEmpty)
        #expect(viewModel.currentCoordinate == nil)
    }

    @Test("Reduced accuracy cannot impersonate a precise Nearby origin")
    func reducedAccuracy() async {
        let search = AcquisitionSearchSpy()
        let location = acquisitionLocation(horizontalAccuracy: 3_000)
        let viewModel = RestaurantAcquisitionViewModel(
            searchService: search,
            linkResolver: AcquisitionLinkResolverStub(),
            locationProvider: AcquisitionLocationStub(
                accuracyAuthorization: .reducedAccuracy,
                locations: [location]
            )
        )

        await viewModel.loadNearby()

        guard case .failed(let message) = viewModel.nearbyState else { Issue.record("Expected precision guidance"); return }
        #expect(message.contains("精确位置"))
        #expect(viewModel.locationAccuracy == .reduced)
        #expect(search.nearbyCenters.isEmpty)
        #expect(viewModel.currentCoordinate == nil)
    }

    @Test("Movement update replaces the GPS query center and distance origin")
    func movementUpdate() async {
        let search = AcquisitionSearchSpy()
        let first = acquisitionLocation(latitude: 30.2741, longitude: 120.1551)
        let second = acquisitionLocation(latitude: 30.2841, longitude: 120.1651)
        let location = AcquisitionLocationStub(locations: [first, second])
        let viewModel = RestaurantAcquisitionViewModel(
            searchService: search,
            linkResolver: AcquisitionLinkResolverStub(),
            locationProvider: location
        )

        await viewModel.loadNearby()
        await viewModel.loadNearby()

        #expect(search.nearbyCenters == [
            RestaurantCoordinate(latitude: 30.2741, longitude: 120.1551, reference: .wgs84),
            RestaurantCoordinate(latitude: 30.2841, longitude: 120.1651, reference: .wgs84),
        ])
        #expect(viewModel.currentCoordinate == RestaurantCoordinate(latitude: 30.2841, longitude: 120.1651, reference: .wgs84))
    }

    @Test("Foreground refresh requests a new fix instead of reusing the prior center")
    func foregroundRefresh() async {
        let search = AcquisitionSearchSpy()
        let location = AcquisitionLocationStub(locations: [
            acquisitionLocation(latitude: 30.2741, longitude: 120.1551),
            acquisitionLocation(latitude: 30.2941, longitude: 120.1751),
        ])
        let viewModel = RestaurantAcquisitionViewModel(
            searchService: search,
            linkResolver: AcquisitionLinkResolverStub(),
            locationProvider: location
        )

        await viewModel.loadNearby()
        await viewModel.refreshAfterForeground()

        #expect(location.requestCount == 2)
        #expect(search.nearbyCenters.last == RestaurantCoordinate(latitude: 30.2941, longitude: 120.1751, reference: .wgs84))
    }

    @Test("Shared fixed coordinate sorts a 40m restaurant before farther results")
    func fixedCoordinateDistanceSorting() throws {
        let fixture = try loadNearbyLocationFixture()
        let origin = RestaurantCoordinate(latitude: fixture.latitude, longitude: fixture.longitude)
        let candidates = fixture.candidates.reversed().map { value in
            RestaurantCandidate(
                name: value.name,
                address: "fixture",
                latitude: value.latitude,
                longitude: value.longitude
            )
        }

        let sorted = RestaurantDistanceOrdering.measuringAndSorting(candidates, from: origin)

        #expect(sorted.map(\.name) == ["fixture-40m", "fixture-420m", "fixture-2km"])
        #expect((sorted[0].distanceMeters ?? 0) > 39)
        #expect((sorted[0].distanceMeters ?? 0) < 41)
        #expect((sorted[1].distanceMeters ?? 0) > 419)
    }

    @Test("Nearby combines coordinate-first food POIs with broad local queries and merges provider duplicates")
    func nearbyQueryCoverageAndMerge() {
        let origin = RestaurantCoordinate(latitude: 30.2741, longitude: 120.1551)
        let sharedIdentity = "apple-shared-nearby"
        let far = RestaurantCandidate(
            name: "较远餐厅",
            address: "远路 8 号",
            latitude: 30.2841,
            longitude: 120.1551,
            appleMapItemIdentifier: "apple-far-nearby"
        )
        let close = RestaurantCandidate(
            name: "最近餐厅",
            address: "近路 1 号",
            latitude: 30.27446,
            longitude: 120.1551,
            appleMapItemIdentifier: sharedIdentity
        )
        let duplicate = RestaurantCandidate(
            name: "最近餐厅（重复结果）",
            address: "近路 1 号",
            latitude: 30.27446,
            longitude: 120.1551,
            appleMapItemIdentifier: sharedIdentity
        )
        let outOfRange = RestaurantCandidate(
            name: "范围外餐厅",
            address: "远郊",
            latitude: 30.32,
            longitude: 120.1551,
            appleMapItemIdentifier: "apple-outside-nearby"
        )

        let merged = RestaurantNearbySearchPolicy.merge(
            [[far, close], [duplicate], [outOfRange]],
            from: origin,
            radiusMeters: 3_000
        )

        #expect(RestaurantNearbySearchPolicy.keywords == ["餐厅", "美食", "饭店", "小吃"])
        #expect(RestaurantNearbySearchPolicy.fallbackKeywords == ["餐饮", "餐馆", "咖啡馆", "烘焙店"])
        #expect(RestaurantNearbySearchPolicy.fallbackProviderRadius(for: 3_000) == 12_000)
        #expect(RestaurantNearbySearchPolicy.fallbackProviderRadius(for: 5_000) == 20_000)
        #expect(RestaurantNearbySearchPolicy.pointOfInterestCategories == [
            .restaurant,
            .cafe,
            .bakery,
            .foodMarket,
        ])
        #expect(merged.map(\.name) == ["最近餐厅", "较远餐厅"])
        #expect(merged.first?.distanceMeters != nil)
    }

    @Test("Nearby no-result is a completed empty state with manual fallback available")
    func nearbyNoResults() async {
        let search = AcquisitionSearchSpy()
        search.returnsNoNearbyResults = true
        let viewModel = RestaurantAcquisitionViewModel(
            searchService: search,
            linkResolver: AcquisitionLinkResolverStub(),
            locationProvider: AcquisitionLocationStub()
        )

        await viewModel.loadNearby()

        #expect(viewModel.nearbyState == .loaded)
        #expect(viewModel.nearbyResults.isEmpty)
    }

    @Test("Location denial leaves city search, links, and manual acquisition usable")
    func locationDenialIsNonBlocking() async {
        let search = AcquisitionSearchSpy()
        let viewModel = RestaurantAcquisitionViewModel(
            searchService: search,
            linkResolver: AcquisitionLinkResolverStub(),
            locationProvider: AcquisitionLocationStub(error: .permissionDenied)
        )

        await viewModel.loadNearby()
        await viewModel.search(query: "面馆", city: "上海")
        await viewModel.resolveLink("https://example.com/restaurants/noodle", city: "上海")

        #expect(viewModel.nearbyState == .locationDenied)
        #expect(viewModel.searchResults.first?.city == "上海")

        await viewModel.search(query: "南京西路 88 号", city: "上海")
        #expect(search.lastQuery == "南京西路 88 号")
        #expect(viewModel.searchResults.first?.address.contains("测试路") == true)
        #expect(viewModel.linkResults.first?.name == "链接餐厅")
    }

    @Test("Search passes an explicit city scope and represents no-result without endless loading")
    func cityScopedSearchAndNoResults() async {
        let search = AcquisitionSearchSpy()
        let viewModel = RestaurantAcquisitionViewModel(
            searchService: search,
            linkResolver: AcquisitionLinkResolverStub(),
            locationProvider: AcquisitionLocationStub()
        )

        await viewModel.search(query: "外滩餐厅", city: "上海")
        #expect(search.lastQuery == "外滩餐厅")
        #expect(search.lastScope?.city == "上海")
        #expect(viewModel.searchResults.first?.city == "上海")

        search.returnsNoResults = true
        await viewModel.search(query: "不存在的店", city: "东京")
        #expect(viewModel.isSearching == false)
        #expect(viewModel.searchResults.isEmpty)
        #expect(viewModel.searchMessage?.contains("没有找到") == true)
    }

    @Test("A fresh Hangzhou fix biases Hangzhou search but never the manually selected Shanghai scope")
    func sameCityGPSBiasOnly() async {
        let search = AcquisitionSearchSpy()
        let viewModel = RestaurantAcquisitionViewModel(searchService: search,
            linkResolver: AcquisitionLinkResolverStub(), locationProvider: AcquisitionLocationStub())
        await viewModel.loadNearby()
        await viewModel.search(query: "兰州拉面", city: "上海")
        #expect(search.lastScope?.city == "上海")
        #expect(search.lastScope?.center == nil)
        await viewModel.search(query: "兰州拉面", city: "杭州市")
        #expect(search.lastScope?.center == RestaurantCoordinate(latitude: 30.2741, longitude: 120.1551, reference: .wgs84))
    }

    @Test("After typing for 30 seconds search refreshes an accepted origin and sends the new GPS coordinate")
    func staleAcceptedSearchFixRefreshes() async {
        var clock = Date(timeIntervalSince1970: 2_000_000_000)
        let initial = acquisitionLocation(timestamp: clock)
        let refreshed = acquisitionLocation(latitude: 30.281, longitude: 120.162, timestamp: clock.addingTimeInterval(30))
        let location = AcquisitionLocationStub(locations: [initial, refreshed])
        let search = AcquisitionSearchSpy()
        let viewModel = RestaurantAcquisitionViewModel(searchService: search,
            linkResolver: AcquisitionLinkResolverStub(), locationProvider: location, now: { clock })
        await viewModel.loadNearby()
        #expect(location.requestCount == 1)
        clock = clock.addingTimeInterval(30)
        await viewModel.search(query: "兰州拉面", city: "杭州")
        #expect(location.requestCount == 2)
        #expect(search.lastScope?.center == RestaurantCoordinate(latitude: 30.281, longitude: 120.162, reference: .wgs84))
        #expect(!viewModel.searchResults.isEmpty)
    }

    @Test("Shared Hybrid/rollback search location policy falls back on failure and never requests first-time permission")
    func searchLocationRefreshFailureIsNonBlocking() async {
        let clock = Date(timeIntervalSince1970: 2_000_000_000)
        let expired = acquisitionLocation(timestamp: clock.addingTimeInterval(-30))
        var requests = 0
        let failed = await RestaurantSearchLocationPolicy.location(accepted: expired,
            authorizationStatus: .authorizedWhenInUse, accuracyAuthorization: .fullAccuracy, now: { clock }) {
                requests += 1
                throw RestaurantLocationError.unavailable
            }
        #expect(failed == nil)
        #expect(requests == 1)
        let missing = await RestaurantSearchLocationPolicy.location(accepted: nil,
            authorizationStatus: .notDetermined, accuracyAuthorization: .fullAccuracy, now: { clock }) {
                requests += 1
                return acquisitionLocation(timestamp: clock)
            }
        #expect(missing == nil)
        #expect(requests == 1)
    }

    @Test("Browsing nearby, search, and link candidates never creates a Restaurant")
    func browsingDoesNotAutoCreate() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let viewModel = RestaurantAcquisitionViewModel(
            searchService: AcquisitionSearchSpy(),
            linkResolver: AcquisitionLinkResolverStub(),
            locationProvider: AcquisitionLocationStub()
        )

        await viewModel.loadNearby()
        await viewModel.search(query: "寿司", city: "杭州")
        await viewModel.resolveLink("https://example.com/restaurants/sushi", city: "杭州")

        #expect(try container.mainContext.fetch(FetchDescriptor<Restaurant>()).isEmpty)
        #expect(try container.mainContext.fetch(FetchDescriptor<SyncMutation>()).isEmpty)
    }

    @Test("Apple Maps URL preserves name, coordinates, and external identity")
    func appleMapsLinkParsing() throws {
        let value = try #require(try ExternalRestaurantLinkParser.parse(
            "https://maps.apple.com/?q=Din%20Tai%20Fung&address=Broadway&ll=40.758,-73.9855&place-id=apple-nyc-42",
            currentCity: "New York"
        ))

        #expect(value.source == .appleMaps)
        #expect(value.candidate?.name == "Din Tai Fung")
        #expect(value.candidate?.appleMapItemIdentifier == "apple-nyc-42")
        #expect(value.candidate?.placeIdentities.first?.provider == .appleMaps)
    }

    @Test("Amap marker URL keeps longitude/latitude order and Amap identity")
    func amapLinkParsing() throws {
        let value = try #require(try ExternalRestaurantLinkParser.parse(
            "https://uri.amap.com/marker?position=120.1551,30.2741&name=%E6%A1%82%E8%AF%AD%E5%B1%B1%E6%88%BF&address=%E6%BB%A1%E8%A7%89%E9%99%87%E8%B7%AF&poiid=B0AMAP12345",
            currentCity: "杭州"
        ))

        #expect(value.source == .amap)
        #expect(value.candidate?.latitude == 30.2741)
        #expect(value.candidate?.longitude == 120.1551)
        #expect(value.candidate?.appleMapItemIdentifier == nil)
        #expect(value.candidate?.placeIdentities.first?.provider == .amap)
    }

    @Test("Generic HTTPS restaurant URLs are accepted as evidence but HTTP is rejected")
    func genericAndInvalidLinks() throws {
        let generic = try #require(try ExternalRestaurantLinkParser.parse(
            "看看这家 https://guide.example/restaurants/42?name=Little%20Table&ll=51.5,-0.12&id=place-42",
            currentCity: "London"
        ))
        #expect(generic.source == .genericURL)
        #expect(generic.name == "Little Table")
        #expect(generic.identity?.provider == .other)
        #expect(throws: ExternalRestaurantLinkParserError.insecureURL) {
            try ExternalRestaurantLinkParser.parse("http://example.com/restaurant")
        }
    }

    @Test("Address-only and coordinate-only shares remain useful without a URL")
    func plainShareEvidence() async throws {
        let address = try #require(try ExternalRestaurantLinkParser.parse(
            "杭州市西湖区满觉陇路 2 号",
            currentCity: "杭州"
        ))
        #expect(address.source == .sharedText)
        #expect(address.address == "杭州市西湖区满觉陇路 2 号")
        #expect(address.city == "杭州")

        let coordinate = try #require(try ExternalRestaurantLinkParser.parse(
            "30.2741,120.1551",
            currentCity: "杭州"
        ))
        #expect(coordinate.source == .sharedText)
        #expect(coordinate.coordinate == RestaurantCoordinate(latitude: 30.2741, longitude: 120.1551))

        let search = AcquisitionSearchSpy()
        let viewModel = RestaurantAcquisitionViewModel(
            searchService: search,
            linkResolver: AcquisitionLinkResolverStub(throwsError: true),
            locationProvider: AcquisitionLocationStub()
        )
        await viewModel.resolveLink("杭州市西湖区满觉陇路 2 号", city: "杭州")
        #expect(search.lastQuery == "杭州市西湖区满觉陇路 2 号")
        #expect(viewModel.linkResults.isEmpty == false)

        await viewModel.resolveLink("30.2741,120.1551", city: "杭州")
        #expect(search.nearbyCenters.last == RestaurantCoordinate(latitude: 30.2741, longitude: 120.1551))
    }

    @Test("Partial shared link falls back to authenticated resolver then MapKit candidates")
    func partialLinkFallback() async {
        let search = AcquisitionSearchSpy()
        let resolver = AcquisitionLinkResolverStub(useSearchFallback: true)
        let viewModel = RestaurantAcquisitionViewModel(
            searchService: search,
            linkResolver: resolver,
            locationProvider: AcquisitionLocationStub()
        )

        await viewModel.resolveLink("今晚吃这家 https://example.com/r/short", city: "东京")

        #expect(resolver.receivedText?.contains("example.com") == true)
        #expect(search.lastQuery == "链接里的店")
        #expect(search.lastScope?.city == "东京")
        #expect(viewModel.linkResults.first?.name == "东京 · 链接里的店")
    }

    @Test("Manual restaurant has a stable Taste Map identity and does not require Apple Maps")
    func manualIdentity() {
        let id = UUID(uuidString: "4a78b01c-7791-4e2e-a005-621288c40b65")!
        let candidate = RestaurantCandidate.manual(
            id: id,
            name: "阿婆夜宵摊",
            city: "杭州",
            address: "",
            coordinate: .init(latitude: 30.2741, longitude: 120.1551)
        )

        #expect(candidate.appleMapItemIdentifier == nil)
        #expect(candidate.address.isEmpty)
        #expect(candidate.placeIdentities == [
            RestaurantCandidatePlaceIdentity(
                provider: .manual,
                externalID: "tastemap:4a78b01c-7791-4e2e-a005-621288c40b65",
                isPrimary: true
            ),
        ])
    }

    @Test("Explicit WantToGo creates one offline Restaurant and a persistent mutation")
    func explicitWantToGoPersistsOffline() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TasteMapAcquisition-\(UUID().uuidString).store")
        defer { removeStoreFiles(at: storeURL) }
        let candidate = RestaurantCandidate.manual(
            name: "离线小店",
            city: "杭州",
            address: "",
            coordinate: .init(latitude: 30.27, longitude: 120.16)
        )

        do {
            let container = try persistentContainer(at: storeURL)
            _ = try LocalTasteMapStore(context: container.mainContext).addToWantToGo(
                candidate: candidate,
                among: []
            )
        }
        let reopened = try persistentContainer(at: storeURL)
        let restaurant = try #require(reopened.mainContext.fetch(FetchDescriptor<Restaurant>()).first)
        let mutation = try #require(reopened.mainContext.fetch(FetchDescriptor<SyncMutation>()).first)
        let payload = try JSONDecoder().decode(RestaurantJSONContractV1.self, from: try #require(mutation.payload))

        #expect(restaurant.status == .wantToGo)
        #expect(restaurant.syncStatus == .pending)
        #expect(payload.placeIdentities.first?.provider == .manual)
        #expect(try reopened.mainContext.fetch(FetchDescriptor<Visit>()).isEmpty)
    }

    @Test("Exact provider identity deduplicates even if the display data differs")
    func providerIdentityDeduplication() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let store = LocalTasteMapStore(context: container.mainContext)
        let first = amapCandidate(name: "山房", externalID: "B0SAMEPLACE", latitude: 30.27)
        let saved = try store.addToWantToGo(candidate: first, among: [])
        let renamed = amapCandidate(name: "桂语山房·新名", externalID: "B0SAMEPLACE", latitude: 31.23)

        let result = try store.addToWantToGo(candidate: renamed, among: [saved])

        #expect(result.id == saved.id)
        #expect(try container.mainContext.fetch(FetchDescriptor<Restaurant>()).count == 1)
    }

    @Test("MapKit Provider facts persist without inventing unavailable detail fields")
    func providerFactsPersistWithoutFabrication() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let store = LocalTasteMapStore(context: container.mainContext)
        let candidate = RestaurantCandidate(
            name: "Provider 真餐厅",
            address: "1 Infinite Loop",
            city: "Cupertino",
            latitude: 37.3317,
            longitude: -122.0301,
            appleMapItemIdentifier: "apple-provider-facts",
            phone: "+1 408 555 0100",
            websiteURL: URL(string: "https://restaurant.example/menu"),
            categoryHints: [MKPointOfInterestCategory.restaurant.rawValue]
        )

        let saved = try store.addToWantToGo(candidate: candidate, among: [])
        let record = try JSONDecoder().decode(
            RestaurantJSONContractV1.self,
            from: try #require(saved.remoteRecordData)
        )

        #expect(saved.name == candidate.name)
        #expect(saved.address == candidate.address)
        #expect(saved.city == candidate.city)
        #expect(saved.latitude == candidate.latitude)
        #expect(saved.longitude == candidate.longitude)
        #expect(record.phone == "+1 408 555 0100")
        #expect(record.websiteUrl == "https://restaurant.example/menu")
        #expect(record.tags == [MKPointOfInterestCategory.restaurant.rawValue])
        #expect(record.openingHours == nil)
        #expect(record.pricePerPerson == nil)
        #expect(record.merchantImageUrl == nil)
        #expect(record.overallRating == nil)
    }

    @Test("A later Provider result refreshes the same Restaurant instead of leaving stale facts")
    func providerFactsRefreshExistingRestaurant() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let store = LocalTasteMapStore(context: container.mainContext)
        let initial = RestaurantCandidate(
            name: "旧名称", address: "旧地址", city: "上海",
            latitude: 31.20, longitude: 121.40,
            appleMapItemIdentifier: "apple-provider-refresh",
            phone: "+86 21 5555 0000",
            websiteURL: URL(string: "https://old.example")
        )
        let saved = try store.addToWantToGo(candidate: initial, among: [])
        let refreshed = RestaurantCandidate(
            name: "真实新名称", address: "真实新地址", city: "上海",
            latitude: 31.21, longitude: 121.41,
            appleMapItemIdentifier: "apple-provider-refresh",
            phone: "+86 21 5555 1111",
            websiteURL: URL(string: "https://new.example"),
            categoryHints: [MKPointOfInterestCategory.cafe.rawValue]
        )

        let result = try store.addToWantToGo(candidate: refreshed, among: [saved])
        let record = try JSONDecoder().decode(
            RestaurantJSONContractV1.self,
            from: try #require(result.remoteRecordData)
        )

        #expect(result.id == saved.id)
        #expect(result.name == "真实新名称")
        #expect(result.address == "真实新地址")
        #expect(result.latitude == 31.21)
        #expect(result.longitude == 121.41)
        #expect(record.phone == "+86 21 5555 1111")
        #expect(record.websiteUrl == "https://new.example")
        #expect(record.tags == [MKPointOfInterestCategory.cafe.rawValue])
        #expect(record.openingHours == nil)
        #expect(try container.mainContext.fetch(FetchDescriptor<Restaurant>()).count == 1)
    }

    @Test("Cross-provider fuzzy match merges external identities without duplicating Restaurant")
    func crossProviderIdentityMerge() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let store = LocalTasteMapStore(context: container.mainContext)
        let apple = RestaurantCandidate(
            name: "桂语山房",
            address: "满觉陇路 2 号",
            city: "杭州",
            latitude: 30.245,
            longitude: 120.126,
            appleMapItemIdentifier: "apple-guiyu"
        )
        let saved = try store.addToWantToGo(candidate: apple, among: [])
        let amap = RestaurantCandidate(
            name: "桂语山房",
            address: "满觉陇路 2 号",
            city: "杭州市",
            latitude: 30.2451,
            longitude: 120.1261,
            placeIdentities: [.init(provider: .amap, externalID: "B0GUIYU", isPrimary: true)]
        )

        let result = try store.addToWantToGo(candidate: amap, among: [saved])
        let record = try SyncRecordMapper.restaurantRecord(result)

        #expect(result.id == saved.id)
        #expect(Set(record.placeIdentities.map(\.provider)) == [.appleMaps, .amap])
        #expect(try container.mainContext.fetch(FetchDescriptor<Restaurant>()).count == 1)
    }

    @Test("Dedupe classifies exact provider matches separately from probable cross-provider matches")
    func dedupeClassification() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let store = LocalTasteMapStore(context: container.mainContext)
        let apple = RestaurantCandidate(
            name: "桂语山房",
            address: "满觉陇路 2 号",
            city: "杭州",
            latitude: 30.245,
            longitude: 120.126,
            appleMapItemIdentifier: "apple-guiyu"
        )
        let saved = try store.addToWantToGo(candidate: apple, among: [])
        let exact = RestaurantDeduplicator.classifiedMatch(for: apple, in: [saved])
        #expect(exact?.kind == .exactProviderIdentity)

        let amap = RestaurantCandidate(
            name: "桂语山房",
            address: "满觉陇路 2 号",
            city: "杭州市",
            latitude: 30.2451,
            longitude: 120.1261,
            placeIdentities: [.init(provider: .amap, externalID: "B0GUIYU", isPrimary: true)]
        )
        let probable = RestaurantDeduplicator.classifiedMatch(for: amap, in: [saved])
        #expect(probable?.kind == .probableCrossProvider)
    }

    @Test("Amap-only and manual Restaurants encode provider-neutral sync contracts")
    func providerNeutralSyncPayloads() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let store = LocalTasteMapStore(context: container.mainContext)
        let amap = try store.addToWantToGo(
            candidate: amapCandidate(name: "高德餐厅", externalID: "B0ONLYAMAP", latitude: 30.28),
            among: []
        )
        let manual = try store.addToWantToGo(
            candidate: .manual(
                name: "无地图小摊",
                city: "杭州",
                address: "",
                coordinate: .init(latitude: 30.29, longitude: 120.17)
            ),
            among: [amap]
        )

        let amapRecord = try SyncRecordMapper.restaurantRecord(amap)
        let manualRecord = try SyncRecordMapper.restaurantRecord(manual)
        #expect(amapRecord.placeIdentities.first?.provider == .amap)
        #expect(amapRecord.amapPoiId == "B0ONLYAMAP")
        #expect(amap.appleMapItemIdentifier == nil)
        #expect(manualRecord.placeIdentities.first?.provider == .manual)
        #expect(manualRecord.amapPoiId == nil)
        #expect(manualRecord.address == "")
    }

    private func amapCandidate(name: String, externalID: String, latitude: Double) -> RestaurantCandidate {
        RestaurantCandidate(
            name: name,
            address: "满觉陇路 2 号",
            city: "杭州",
            latitude: latitude,
            longitude: 120.126,
            placeIdentities: [.init(provider: .amap, externalID: externalID, isPrimary: true)]
        )
    }

    private func persistentContainer(at url: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "RestaurantAcquisitionTests",
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
private final class AcquisitionSearchSpy: RestaurantSearching, @unchecked Sendable {
    var lastQuery: String?
    var lastScope: RestaurantSearchScope?
    var nearbyRadius: Double?
    var nearbyCenters: [RestaurantCoordinate] = []
    var returnsNoResults = false
    var returnsNoNearbyResults = false
    var nearbyOverride: [RestaurantCandidate]?
    var nearbyDelay: Duration?
    var searchOverride: [RestaurantCandidate]?

    func search(query: String) async throws -> [RestaurantCandidate] {
        try await search(query: query, scope: .init())
    }

    func search(query: String, scope: RestaurantSearchScope) async throws -> [RestaurantCandidate] {
        lastQuery = query
        lastScope = scope
        if let searchOverride { return searchOverride }
        if returnsNoResults { return [] }
        let city = scope.city.isEmpty ? "杭州" : scope.city
        return [RestaurantCandidate(
            name: "\(city) · \(query)",
            address: "\(city)测试路 1 号",
            city: city,
            latitude: 30.27,
            longitude: 120.16,
            appleMapItemIdentifier: "apple-search-spy"
        )]
    }

    func nearby(center: RestaurantCoordinate, radiusMeters: Double) async throws -> [RestaurantCandidate] {
        nearbyRadius = radiusMeters
        nearbyCenters.append(center)
        if let nearbyDelay { try await Task.sleep(for: nearbyDelay) }
        if let nearbyOverride { return nearbyOverride }
        if returnsNoNearbyResults { return [] }
        return [RestaurantCandidate(
            name: "附近小馆",
            address: "附近路 3 号",
            city: "杭州",
            latitude: center.latitude + 0.001,
            longitude: center.longitude,
            appleMapItemIdentifier: "apple-nearby-spy",
            distanceMeters: 180
        )]
    }

    func locationContext(for coordinate: RestaurantCoordinate) async throws -> RestaurantLocationContext {
        .init(city: "杭州", district: "西湖区", address: "杭州 · 西湖区")
    }

    func coordinate(for address: String, city: String) async throws -> RestaurantCoordinate {
        .init(latitude: 30.27, longitude: 120.16)
    }
}

@MainActor
private final class AcquisitionLocationStub: RestaurantLocationProviding {
    let authorizationStatus: CLAuthorizationStatus
    let accuracyAuthorization: CLAccuracyAuthorization
    private let error: RestaurantLocationError?
    private let locations: [CLLocation]
    private let delay: Duration?
    private(set) var requestCount = 0

    init(
        error: RestaurantLocationError? = nil,
        accuracyAuthorization: CLAccuracyAuthorization = .fullAccuracy,
        locations: [CLLocation] = [acquisitionLocation()],
        delay: Duration? = nil
    ) {
        self.error = error
        self.accuracyAuthorization = accuracyAuthorization
        self.locations = locations
        self.delay = delay
        authorizationStatus = error == .permissionDenied ? .denied : .authorizedWhenInUse
    }

    func requestCurrentLocation() async throws -> CLLocation {
        if let error { throw error }
        if let delay { try? await Task.sleep(for: delay) }
        let index = min(requestCount, locations.count - 1)
        requestCount += 1
        return locations[index]
    }
}

private struct NearbyLocationFixture: Decodable {
    struct Candidate: Decodable {
        let name: String
        let latitude: Double
        let longitude: Double
    }

    let latitude: Double
    let longitude: Double
    let candidates: [Candidate]
}

private func loadNearbyLocationFixture() throws -> NearbyLocationFixture {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let url = repositoryRoot.appendingPathComponent("contracts/fixtures/nearby-location.v1.json")
    return try JSONDecoder().decode(NearbyLocationFixture.self, from: Data(contentsOf: url))
}

private func acquisitionLocation(
    latitude: Double = 30.2741,
    longitude: Double = 120.1551,
    timestamp: Date = Date(),
    horizontalAccuracy: CLLocationAccuracy = 8
) -> CLLocation {
    CLLocation(
        coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
        altitude: 0,
        horizontalAccuracy: horizontalAccuracy,
        verticalAccuracy: 10,
        timestamp: timestamp
    )
}

@MainActor
private final class AcquisitionLinkResolverStub: ExternalRestaurantLinkResolving {
    let useSearchFallback: Bool
    let throwsError: Bool
    var receivedText: String?

    init(useSearchFallback: Bool = false, throwsError: Bool = false) {
        self.useSearchFallback = useSearchFallback
        self.throwsError = throwsError
    }

    func resolve(text: String, currentCity: String) async throws -> ExternalRestaurantLinkResponseV1 {
        receivedText = text
        if throwsError { throw URLError(.cannotConnectToHost) }
        return ExternalRestaurantLinkResponseV1(
            apiVersion: 1,
            sourceType: .genericURL,
            sourceHost: "example.com",
            confidence: useSearchFallback ? .low : .high,
            matchType: useSearchFallback ? "search_fallback" : "single",
            candidates: useSearchFallback ? [] : [ExternalRestaurantCandidateV1(
                restaurantId: nil,
                amapPoiId: nil,
                name: "链接餐厅",
                address: "链接路 8 号",
                city: currentCity,
                latitude: 30.27,
                longitude: 120.16,
                merchantImageUrl: nil,
                phone: nil,
                openingHours: nil,
                placeIdentities: [.init(provider: .other, externalId: "example:restaurant", isPrimary: true)]
            )],
            searchFallback: useSearchFallback ? .init(
                keyword: "链接里的店",
                city: currentCity,
                addressHint: "",
                latitude: nil,
                longitude: nil
            ) : nil,
            sourceSuggestion: "网页",
            message: "已识别，请确认。"
        )
    }
}
