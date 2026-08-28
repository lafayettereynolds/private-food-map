import CoreLocation
import Foundation
import SwiftData
import Testing
@testable import TasteMap

@Suite("Restaurant acquisition", .serialized)
@MainActor
struct RestaurantAcquisitionTests {
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
        #expect(viewModel.nearbyResults.first?.distanceMeters == 180)
        #expect(viewModel.detectedCity == "杭州")
        #expect(search.nearbyRadius == 3_000)
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
    var returnsNoResults = false
    var returnsNoNearbyResults = false

    func search(query: String) async throws -> [RestaurantCandidate] {
        try await search(query: query, scope: .init())
    }

    func search(query: String, scope: RestaurantSearchScope) async throws -> [RestaurantCandidate] {
        lastQuery = query
        lastScope = scope
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
    private let error: RestaurantLocationError?

    init(error: RestaurantLocationError? = nil) {
        self.error = error
        authorizationStatus = error == .permissionDenied ? .denied : .authorizedWhenInUse
    }

    func requestCurrentLocation() async throws -> CLLocation {
        if let error { throw error }
        return CLLocation(latitude: 30.2741, longitude: 120.1551)
    }
}

@MainActor
private final class AcquisitionLinkResolverStub: ExternalRestaurantLinkResolving {
    let useSearchFallback: Bool
    var receivedText: String?

    init(useSearchFallback: Bool = false) {
        self.useSearchFallback = useSearchFallback
    }

    func resolve(text: String, currentCity: String) async throws -> ExternalRestaurantLinkResponseV1 {
        receivedText = text
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
