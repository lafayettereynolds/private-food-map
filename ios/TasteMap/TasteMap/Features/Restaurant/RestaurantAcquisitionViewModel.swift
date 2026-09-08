import Combine
import CoreLocation
import Foundation

enum RestaurantAcquisitionLoadState: Equatable {
    case idle
    case loading
    case loaded
    case locationDenied
    case failed(String)
}

enum RestaurantAcquisitionLocationAccuracy: Equatable {
    case unknown
    case precise
    case reduced
}

@MainActor
final class RestaurantAcquisitionViewModel: ObservableObject {
    @Published private(set) var nearbyState: RestaurantAcquisitionLoadState = .idle
    @Published private(set) var locationAccuracy: RestaurantAcquisitionLocationAccuracy = .unknown
    @Published private(set) var nearbyResults: [RestaurantCandidate] = []
    @Published private(set) var nearbyVisibleCount = 12
    var visibleNearbyResults: ArraySlice<RestaurantCandidate> { nearbyResults.prefix(nearbyVisibleCount) }
    var hasMoreNearbyResults: Bool { nearbyVisibleCount < nearbyResults.count }
    @Published private(set) var searchResults: [RestaurantCandidate] = []
    @Published private(set) var hasSearched = false
    @Published private(set) var isSearching = false
    @Published private(set) var searchMessage: String?
    @Published private(set) var linkResults: [RestaurantCandidate] = []
    @Published private(set) var isResolvingLink = false
    @Published private(set) var linkMessage: String?
    @Published private(set) var currentCoordinate: RestaurantCoordinate?
    @Published private(set) var currentLocationLabel: String?
    @Published private(set) var detectedCity: String?

    private let searchService: any RestaurantSearching
    private let linkResolver: any ExternalRestaurantLinkResolving
    private let locationProvider: any RestaurantLocationProviding
    private let now: () -> Date
    private var acceptedLocation: CLLocation?
    private var searchGeneration = 0
    private var nearbyGeneration = 0

    init(
        searchService: any RestaurantSearching,
        linkResolver: any ExternalRestaurantLinkResolving,
        locationProvider: any RestaurantLocationProviding,
        now: @escaping () -> Date = { Date() }
    ) {
        self.searchService = searchService
        self.linkResolver = linkResolver
        self.locationProvider = locationProvider
        self.now = now
    }

    func loadNearby() async {
        invalidateNearby()
        let generation = nearbyGeneration
        nearbyState = .loading
        currentLocationLabel = nil
        currentCoordinate = nil
        acceptedLocation = nil
        locationAccuracy = .unknown
        do {
            let location = try await locationProvider.requestCurrentLocation()
            guard nearbyGeneration == generation, !Task.isCancelled else { return }
            let accuracyAuthorization = locationProvider.accuracyAuthorization
            guard accuracyAuthorization == .fullAccuracy else {
                locationAccuracy = .reduced
                throw RestaurantLocationError.preciseLocationRequired
            }
            guard RestaurantLocationFixPolicy.isUsable(
                location,
                accuracyAuthorization: accuracyAuthorization,
                now: now()
            ) else {
                throw RestaurantLocationError.staleOrInaccurate
            }
            let coordinate = RestaurantCoordinate(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                reference: .wgs84
            )
            currentCoordinate = coordinate
            acceptedLocation = location
            locationAccuracy = accuracyAuthorization == .reducedAccuracy ? .reduced : .precise
            async let contextTask: RestaurantLocationContext? = try? searchService.locationContext(for: coordinate)
            async let nearbyTask = searchService.nearby(center: coordinate, radiusMeters: 3_000)
            let locationContext = await contextTask
            let candidates = try await nearbyTask
            guard nearbyGeneration == generation, !Task.isCancelled else { return }
            if let locationContext {
                detectedCity = locationContext.city.nilIfBlank
                currentLocationLabel = locationContext.address.nilIfBlank
                    ?? [locationContext.city, locationContext.district]
                        .compactMap(\.nilIfBlank)
                        .joined(separator: " · ")
                        .nilIfBlank
            }
            nearbyResults = RestaurantDistanceOrdering.measuringAndSorting(candidates, from: coordinate)
                .filter { ($0.distanceMeters ?? .greatestFiniteMagnitude) <= 3_000 }
            nearbyState = .loaded
        } catch RestaurantLocationError.permissionDenied {
            guard nearbyGeneration == generation, !Task.isCancelled else { return }
            nearbyState = .locationDenied
        } catch RestaurantLocationError.preciseLocationRequired {
            guard nearbyGeneration == generation, !Task.isCancelled else { return }
            nearbyState = .failed("请在系统设置中为味图开启精确位置，再查找附近餐厅。城市搜索仍可使用。")
        } catch {
            guard nearbyGeneration == generation, !Task.isCancelled else { return }
            nearbyState = .failed("暂时无法读取附近餐厅，你仍可按城市搜索、粘贴链接或手动添加。")
        }
    }

    func loadMoreNearby() {
        guard nearbyState == .loaded else { return }
        nearbyVisibleCount = min(nearbyResults.count, nearbyVisibleCount + 12)
    }

    func invalidateNearby() {
        nearbyGeneration += 1
        nearbyResults = []
        nearbyVisibleCount = 12
        nearbyState = .idle
        acceptedLocation = nil
        currentCoordinate = nil
    }

    func refreshAfterForeground() async {
        await loadNearby()
    }

    func search(query: String, city: String) async {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            clearSearch()
            return
        }
        hasSearched = true
        searchGeneration += 1
        let generation = searchGeneration
        isSearching = true
        searchMessage = nil
        defer { if searchGeneration == generation { isSearching = false } }
        do {
            let searchCenter = await currentSearchCenter(city: city)
            guard searchGeneration == generation else { return }
            let values = RestaurantSearchRelevancePolicy.rankedMatches(
                try await searchService.search(
                    query: query,
                    scope: RestaurantSearchScope(city: city, center: searchCenter)
                ),
                query: query,
                scopeCity: city
            )
            guard searchGeneration == generation else { return }
            searchResults = searchCenter.map { RestaurantDistanceOrdering.measuringAndSorting(values, from: $0) } ?? values
            searchMessage = values.isEmpty ? "没有找到匹配的餐厅，请换一个名称、地址或城市。" : nil
        } catch is CancellationError {
            return
        } catch {
            guard searchGeneration == generation else { return }
            searchResults = []
            searchMessage = "搜索失败，请检查网络后重试。附近功能不可用时，仍可手动添加。"
        }
    }

    func clearSearch() {
        searchGeneration += 1
        isSearching = false
        searchResults = []
        searchMessage = nil
        hasSearched = false
    }

    private func currentSearchCenter(city: String) async -> RestaurantCoordinate? {
        guard let location = await RestaurantSearchLocationPolicy.location(
            accepted: acceptedLocation,
            authorizationStatus: locationProvider.authorizationStatus,
            accuracyAuthorization: locationProvider.accuracyAuthorization,
            now: now,
            refresh: { try await self.locationProvider.requestCurrentLocation() }
        ),
              locationProvider.accuracyAuthorization == .fullAccuracy else { return nil }
        let refreshed = acceptedLocation?.timestamp != location.timestamp
        if let previous = acceptedLocation,
           previous.coordinate.latitude != location.coordinate.latitude || previous.coordinate.longitude != location.coordinate.longitude {
            invalidateNearby()
            nearbyState = .failed("位置已变化，请重新查找附近餐厅。")
        }
        acceptedLocation = location
        currentCoordinate = RestaurantCoordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, reference: .wgs84)
        locationAccuracy = .precise
        if refreshed, let currentCoordinate {
            // A refreshed position may be in another city. Never reuse the old
            // detected city to authorize the new origin's location bias.
            detectedCity = try? await searchService.locationContext(for: currentCoordinate).city
        }
        let normalize = { (value: String) in value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "市", with: "").lowercased() }
        guard city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || detectedCity.map({ normalize($0) == normalize(city) }) == true else { return nil }
        return currentCoordinate
    }

    func clearLinkResolution() {
        linkResults = []
        linkMessage = nil
    }

    func resolveLink(_ text: String, city: String) async {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isResolvingLink = true
        linkResults = []
        linkMessage = nil
        defer { isResolvingLink = false }

        let parsed: ParsedExternalRestaurantLink?
        do {
            parsed = try ExternalRestaurantLinkParser.parse(text, currentCity: city)
        } catch ExternalRestaurantLinkParserError.insecureURL {
            linkMessage = "只支持安全的 HTTPS 餐厅链接。"
            return
        } catch {
            linkMessage = "这不是可识别的餐厅链接或分享文字。"
            return
        }
        if let direct = parsed?.candidate {
            linkResults = [direct]
            linkMessage = "已从链接提取餐厅，请确认门店后再添加。"
            return
        }

        do {
            let response = try await linkResolver.resolve(text: text, currentCity: city)
            var candidates = response.candidates.map(\.restaurantCandidate)
            if candidates.isEmpty, let fallback = response.searchFallback {
                let center: RestaurantCoordinate?
                if let latitude = fallback.latitude, let longitude = fallback.longitude {
                    center = RestaurantCoordinate(latitude: latitude, longitude: longitude)
                } else {
                    center = currentCoordinate
                }
                candidates = try await searchService.search(
                    query: fallback.keyword,
                    scope: RestaurantSearchScope(
                        city: fallback.city.nilIfBlank ?? city,
                        center: center
                    )
                )
            }
            if candidates.isEmpty, let parsed {
                candidates = try await fallbackCandidates(for: parsed, originalText: text, city: city)
            }
            linkResults = candidates
            linkMessage = candidates.isEmpty
                ? "已读取链接，但还不能确定具体门店。请改用名称搜索或手动添加。"
                : response.message
        } catch {
            if let parsed {
                do {
                    let candidates = try await fallbackCandidates(
                        for: parsed,
                        originalText: text,
                        city: city
                    )
                    linkResults = candidates
                    linkMessage = candidates.isEmpty
                        ? "链接服务暂时不可用，也没有找到匹配门店。可以手动添加。"
                        : "已从链接提取名称，请确认 Apple 地图搜索到的门店。"
                    return
                } catch {
                    // Fall through to the recoverable message below.
                }
            }
            linkMessage = "餐厅链接暂时无法解析。你仍可按名称搜索或手动添加。"
        }
    }

    private func fallbackCandidates(
        for parsed: ParsedExternalRestaurantLink,
        originalText: String,
        city: String
    ) async throws -> [RestaurantCandidate] {
        let semanticQuery = parsed.name.nilIfBlank ?? parsed.address.nilIfBlank
        if semanticQuery == nil, let coordinate = parsed.coordinate {
            return try await searchService.nearby(center: coordinate, radiusMeters: 3_000)
        }
        let query = semanticQuery
            ?? originalText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        if let query {
            return try await searchService.search(
                query: query,
                scope: RestaurantSearchScope(
                    city: parsed.city.nilIfBlank ?? city,
                    center: parsed.coordinate ?? currentCoordinate,
                    radiusMeters: parsed.coordinate == nil ? 20_000 : 3_000
                )
            )
        }
        if let coordinate = parsed.coordinate {
            return try await searchService.nearby(center: coordinate, radiusMeters: 3_000)
        }
        return []
    }

    func resolveManualCoordinate(address: String, city: String) async throws -> RestaurantCoordinate {
        try await searchService.coordinate(for: address, city: city)
    }

    func requestCurrentCoordinate() async throws -> (RestaurantCoordinate, RestaurantLocationContext?) {
        let location = try await locationProvider.requestCurrentLocation()
        let accuracyAuthorization = locationProvider.accuracyAuthorization
        guard accuracyAuthorization == .fullAccuracy else { throw RestaurantLocationError.preciseLocationRequired }
        guard RestaurantLocationFixPolicy.isUsable(
            location,
            accuracyAuthorization: accuracyAuthorization
        ) else {
            throw RestaurantLocationError.staleOrInaccurate
        }
        let coordinate = RestaurantCoordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        currentCoordinate = coordinate
        acceptedLocation = location
        locationAccuracy = accuracyAuthorization == .reducedAccuracy ? .reduced : .precise
        return (coordinate, try? await searchService.locationContext(for: coordinate))
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
