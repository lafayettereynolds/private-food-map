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

@MainActor
final class RestaurantAcquisitionViewModel: ObservableObject {
    @Published private(set) var nearbyState: RestaurantAcquisitionLoadState = .idle
    @Published private(set) var nearbyResults: [RestaurantCandidate] = []
    @Published private(set) var searchResults: [RestaurantCandidate] = []
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

    init(
        searchService: any RestaurantSearching,
        linkResolver: any ExternalRestaurantLinkResolving,
        locationProvider: any RestaurantLocationProviding
    ) {
        self.searchService = searchService
        self.linkResolver = linkResolver
        self.locationProvider = locationProvider
    }

    func loadNearby() async {
        nearbyState = .loading
        nearbyResults = []
        do {
            let location = try await locationProvider.requestCurrentLocation()
            let coordinate = RestaurantCoordinate(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
            currentCoordinate = coordinate
            async let contextTask: RestaurantLocationContext? = try? searchService.locationContext(for: coordinate)
            async let nearbyTask = searchService.nearby(center: coordinate, radiusMeters: 3_000)
            let locationContext = await contextTask
            let candidates = try await nearbyTask
            if let locationContext {
                detectedCity = locationContext.city.nilIfBlank
                currentLocationLabel = locationContext.address.nilIfBlank
                    ?? [locationContext.city, locationContext.district]
                        .compactMap(\.nilIfBlank)
                        .joined(separator: " · ")
                        .nilIfBlank
            }
            nearbyResults = Array(candidates.prefix(8))
            nearbyState = .loaded
        } catch RestaurantLocationError.permissionDenied {
            nearbyState = .locationDenied
        } catch {
            nearbyState = .failed("暂时无法读取附近餐厅，你仍可按城市搜索、粘贴链接或手动添加。")
        }
    }

    func search(query: String, city: String) async {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            searchMessage = nil
            return
        }
        isSearching = true
        searchMessage = nil
        defer { isSearching = false }
        do {
            let values = try await searchService.search(
                query: query,
                scope: RestaurantSearchScope(city: city, center: currentCoordinate)
            )
            searchResults = values
            searchMessage = values.isEmpty ? "没有找到匹配的餐厅，请换一个名称、地址或城市。" : nil
        } catch is CancellationError {
            return
        } catch {
            searchResults = []
            searchMessage = "搜索失败，请检查网络后重试。附近功能不可用时，仍可手动添加。"
        }
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
            linkResults = candidates
            linkMessage = candidates.isEmpty
                ? "已读取链接，但还不能确定具体门店。请改用名称搜索或手动添加。"
                : response.message
        } catch {
            if let parsed, !parsed.name.isEmpty {
                do {
                    let candidates = try await searchService.search(
                        query: parsed.name,
                        scope: RestaurantSearchScope(
                            city: parsed.city.nilIfBlank ?? city,
                            center: parsed.coordinate ?? currentCoordinate
                        )
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

    func resolveManualCoordinate(address: String, city: String) async throws -> RestaurantCoordinate {
        try await searchService.coordinate(for: address, city: city)
    }

    func requestCurrentCoordinate() async throws -> (RestaurantCoordinate, RestaurantLocationContext?) {
        let location = try await locationProvider.requestCurrentLocation()
        let coordinate = RestaurantCoordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        currentCoordinate = coordinate
        return (coordinate, try? await searchService.locationContext(for: coordinate))
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
