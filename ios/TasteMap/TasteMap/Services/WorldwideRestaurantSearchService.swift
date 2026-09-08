import Foundation
import MapKit

struct RestaurantResolvedCity: Sendable {
    let displayName: String
    let countryCode: String
    let region: MKCoordinateRegion
}

struct WorldwideCityResolver: Sendable {
    private let session: URLSession

    nonisolated init(session: URLSession = .shared) {
        self.session = session
    }

    func resolve(_ rawCity: String) async throws -> RestaurantResolvedCity {
        let city = rawCity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !city.isEmpty else { throw RestaurantSearchError.locationNotFound }
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        components?.queryItems = [
            URLQueryItem(name: "name", value: Self.canonicalQuery(for: city)),
            URLQueryItem(name: "count", value: "10"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let url = components?.url else { throw RestaurantSearchError.locationNotFound }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("TasteMap-iOS/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            throw RestaurantSearchError.locationNotFound
        }
        let values = try JSONDecoder().decode(OpenMeteoResponse.self, from: data).results ?? []
        guard let best = values.max(by: { score($0, city: city) < score($1, city: city) }),
              (-90...90).contains(best.latitude),
              (-180...180).contains(best.longitude) else {
            throw RestaurantSearchError.locationNotFound
        }
        return RestaurantResolvedCity(
            displayName: best.name,
            countryCode: best.countryCode.uppercased(),
            region: MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: best.latitude, longitude: best.longitude),
                latitudinalMeters: 120_000,
                longitudinalMeters: 120_000
            )
        )
    }

    static func canonicalQuery(for city: String) -> String {
        aliases[normalized(city)] ?? city.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func score(_ value: OpenMeteoResult, city: String) -> Int {
        let requested = Self.normalized(Self.canonicalQuery(for: city))
        let exactName = Self.normalized(value.name) == requested ? 1_000_000_000 : 0
        let featurePriority: Int
        switch value.featureCode {
        case "PPLC": featurePriority = 500_000_000
        case "PPLA", "PPLA2": featurePriority = 400_000_000
        case "PPL": featurePriority = 300_000_000
        default: featurePriority = 0
        }
        return exactName + featurePriority + min(value.population ?? 0, 250_000_000)
    }

    private static func normalized(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    // Common Chinese exonyms need canonical provider spellings because global
    // gazetteers do not consistently index simplified-Chinese alternate names.
    private static let aliases: [String: String] = [
        "纽约": "New York", "纽约市": "New York", "newyork": "New York", "newyorkcity": "New York",
        "东京": "Tokyo", "东京都": "Tokyo", "大阪": "Osaka", "京都": "Kyoto",
        "首尔": "Seoul", "新加坡": "Singapore", "曼谷": "Bangkok",
        "吉隆坡": "Kuala Lumpur", "雅加达": "Jakarta", "胡志明市": "Ho Chi Minh City",
        "悉尼": "Sydney", "墨尔本": "Melbourne", "奥克兰": "Auckland",
        "伦敦": "London", "巴黎": "Paris", "柏林": "Berlin", "慕尼黑": "Munich",
        "罗马": "Rome", "米兰": "Milan", "马德里": "Madrid", "巴塞罗那": "Barcelona",
        "阿姆斯特丹": "Amsterdam", "布鲁塞尔": "Brussels", "维也纳": "Vienna",
        "苏黎世": "Zurich", "伊斯坦布尔": "Istanbul", "迪拜": "Dubai",
        "洛杉矶": "Los Angeles", "旧金山": "San Francisco", "西雅图": "Seattle",
        "芝加哥": "Chicago", "波士顿": "Boston", "华盛顿": "Washington DC",
        "拉斯维加斯": "Las Vegas", "迈阿密": "Miami", "多伦多": "Toronto",
        "温哥华": "Vancouver", "蒙特利尔": "Montreal",
        "香港": "Hong Kong", "澳门": "Macao", "台北": "Taipei",
        "上海": "Shanghai", "上海市": "Shanghai", "北京": "Beijing", "北京市": "Beijing",
        "杭州": "Hangzhou", "杭州市": "Hangzhou", "广州": "Guangzhou", "广州市": "Guangzhou",
        "深圳": "Shenzhen", "深圳市": "Shenzhen", "成都": "Chengdu", "成都市": "Chengdu",
    ]

    private struct OpenMeteoResponse: Decodable {
        let results: [OpenMeteoResult]?
    }

    private struct OpenMeteoResult: Decodable {
        let name: String
        let latitude: Double
        let longitude: Double
        let featureCode: String
        let countryCode: String
        let population: Int?

        enum CodingKeys: String, CodingKey {
            case name, latitude, longitude, population
            case featureCode = "feature_code"
            case countryCode = "country_code"
        }
    }
}

struct PhotonRestaurantSearchService: RestaurantSearching {
    private let session: URLSession
    private let cityResolver: WorldwideCityResolver

    nonisolated init(session: URLSession = .shared) {
        self.session = session
        cityResolver = WorldwideCityResolver(session: session)
    }

    func search(query: String) async throws -> [RestaurantCandidate] {
        try await search(query: query, scope: RestaurantSearchScope())
    }

    func search(query: String, scope: RestaurantSearchScope) async throws -> [RestaurantCandidate] {
        let resolvedCity = scope.city.isEmpty ? nil : try await cityResolver.resolve(scope.city)
        return try await search(query: query, scopeCity: scope.city, resolvedCity: resolvedCity)
    }

    func search(
        query: String,
        scopeCity: String,
        resolvedCity: RestaurantResolvedCity?
    ) async throws -> [RestaurantCandidate] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { throw RestaurantSearchError.emptyQuery }
        var components = URLComponents(string: "https://photon.komoot.io/api/")
        var queryItems = [
            URLQueryItem(name: "q", value: providerQuery(query)),
            URLQueryItem(name: "limit", value: "30"),
            URLQueryItem(name: "dedupe", value: "1"),
        ]
        if let resolvedCity {
            let region = resolvedCity.region
            queryItems += [
                URLQueryItem(name: "lat", value: String(region.center.latitude)),
                URLQueryItem(name: "lon", value: String(region.center.longitude)),
                URLQueryItem(name: "bbox", value: boundingBox(region)),
                URLQueryItem(name: "location_bias_scale", value: "0.05"),
            ]
        } else if !scopeCity.isEmpty {
            queryItems[0] = URLQueryItem(
                name: "q",
                value: "\(providerQuery(query)) \(WorldwideCityResolver.canonicalQuery(for: scopeCity))"
            )
        }
        components?.queryItems = queryItems
        guard let url = components?.url else { throw RestaurantSearchError.locationNotFound }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("TasteMap-iOS/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            throw RestaurantSearchError.locationNotFound
        }
        let responseBody = try JSONDecoder().decode(PhotonResponse.self, from: data)
        var seen = Set<String>()
        let candidates: [RestaurantCandidate] = responseBody.features.compactMap { feature in
            guard let candidate = candidate(from: feature, fallbackCity: scopeCity),
                  resolvedCity?.region.contains(candidate.coordinate) != false,
                  seen.insert(candidate.placeIdentities.first?.externalID ?? candidate.name).inserted else {
                return nil
            }
            return candidate
        }
        guard let resolvedCity else { return candidates }
        let exactCityCandidates = candidates.filter {
            normalized($0.city) == normalized(resolvedCity.displayName)
        }
        return exactCityCandidates.isEmpty ? candidates : exactCityCandidates
    }

    func searchQualifiedName(query: String, scopeCity: String, resolvedCity: RestaurantResolvedCity) async throws -> [RestaurantCandidate] {
        let words = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard (3...8).contains(words.count) else { return [] }
        // Try at most three name/place splits. No merchant or neighbourhood is
        // hard-coded, and provider suggestions must resolve an exact place name.
        for split in 2...min(4, words.count - 1) {
            try Task.checkCancellation()
            let name = words.prefix(split).joined(separator: " ")
            let place = words.dropFirst(split).joined(separator: " ")
            guard let anchor = try await placeAnchor(place, city: resolvedCity) else { continue }
            let matches = try await search(query: name, scopeCity: scopeCity, resolvedCity: resolvedCity)
                .filter {
                    normalized($0.name) == normalized(name)
                        && normalized($0.city) == normalized(resolvedCity.displayName)
                }
                .sorted {
                    RestaurantDistanceOrdering.distance(from: anchor, to: $0.coordinate)
                        < RestaurantDistanceOrdering.distance(from: anchor, to: $1.coordinate)
                }
            if !matches.isEmpty {
                return matches.map { candidate in
                    var value = candidate
                    value.resolvedSearchQuery = query
                    return value
                }
            }
        }
        return []
    }

    private func placeAnchor(_ place: String, city: RestaurantResolvedCity) async throws -> RestaurantCoordinate? {
        var components = URLComponents(string: "https://photon.komoot.io/api/")!
        components.queryItems = [
            .init(name: "q", value: place), .init(name: "limit", value: "5"),
            .init(name: "bbox", value: boundingBox(city.region)),
            .init(name: "lat", value: String(city.region.center.latitude)),
            .init(name: "lon", value: String(city.region.center.longitude)),
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 6
        request.setValue("TasteMap-iOS/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw RestaurantSearchError.locationNotFound
        }
        let features = try JSONDecoder().decode(PhotonResponse.self, from: data).features
        for feature in features {
            let properties = feature.properties
            guard properties.osmKey == "place", normalized(properties.name ?? "") == normalized(place),
                  normalized(properties.city ?? "") == normalized(city.displayName),
                  feature.geometry.coordinates.count >= 2 else { continue }
            let coordinate = RestaurantCoordinate(latitude: feature.geometry.coordinates[1], longitude: feature.geometry.coordinates[0], reference: .wgs84)
            if city.region.contains(coordinate) { return coordinate }
        }
        return nil
    }

    private func providerQuery(_ query: String) -> String {
        let normalized = query.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
        let diningIntents = [
            "餐厅", "餐馆", "饭店", "美食", "小吃", "restaurants", "restaurant", "food",
        ]
        return diningIntents.contains(normalized) ? "restaurant" : query
    }

    private func normalized(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    private func boundingBox(_ region: MKCoordinateRegion) -> String {
        let minLongitude = region.center.longitude - region.span.longitudeDelta / 2
        let minLatitude = region.center.latitude - region.span.latitudeDelta / 2
        let maxLongitude = region.center.longitude + region.span.longitudeDelta / 2
        let maxLatitude = region.center.latitude + region.span.latitudeDelta / 2
        return "\(minLongitude),\(minLatitude),\(maxLongitude),\(maxLatitude)"
    }

    private func candidate(
        from feature: PhotonFeature,
        fallbackCity: String
    ) -> RestaurantCandidate? {
        let properties = feature.properties
        guard feature.geometry.coordinates.count >= 2,
              let name = properties.name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty,
              isDiningPlace(properties) else {
            return nil
        }
        let longitude = feature.geometry.coordinates[0]
        let latitude = feature.geometry.coordinates[1]
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        let identity = "osm:\(properties.osmType.lowercased()):\(properties.osmID)"
        let address = uniqueText([
            [properties.houseNumber, properties.street].compactMap { $0 }.joined(separator: " "),
            properties.locality,
            properties.district,
            properties.city,
            properties.state,
            properties.country,
            properties.postcode,
        ]).joined(separator: " · ")
        return RestaurantCandidate(
            name: name,
            address: address,
            city: properties.city ?? properties.state ?? fallbackCity,
            district: properties.district ?? properties.locality ?? "",
            latitude: latitude,
            longitude: longitude,
            placeIdentities: [
                RestaurantCandidatePlaceIdentity(
                    provider: .other,
                    externalID: identity,
                    isPrimary: true
                )
            ],
            categoryHints: ["restaurant", properties.osmValue],
            coordinateReference: .wgs84
        )
    }

    private func isDiningPlace(_ properties: PhotonProperties) -> Bool {
        switch (properties.osmKey, properties.osmValue) {
        case ("amenity", "restaurant"), ("amenity", "cafe"), ("amenity", "fast_food"),
             ("amenity", "food_court"), ("amenity", "bar"), ("amenity", "pub"),
             ("amenity", "biergarten"), ("amenity", "ice_cream"),
             ("shop", "bakery"), ("shop", "deli"), ("shop", "confectionery"):
            return true
        default:
            return false
        }
    }

    private func uniqueText(_ values: [String?]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty,
                  seen.insert(value).inserted else { return nil }
            return value
        }
    }

    private struct PhotonResponse: Decodable {
        let features: [PhotonFeature]
    }

    private struct PhotonFeature: Decodable {
        let properties: PhotonProperties
        let geometry: PhotonGeometry
    }

    private struct PhotonGeometry: Decodable {
        let coordinates: [Double]
    }

    private struct PhotonProperties: Decodable {
        let osmType: String
        let osmID: Int64
        let osmKey: String
        let osmValue: String
        let name: String?
        let houseNumber: String?
        let street: String?
        let locality: String?
        let district: String?
        let city: String?
        let state: String?
        let country: String?
        let postcode: String?

        enum CodingKeys: String, CodingKey {
            case name, street, locality, district, city, state, country, postcode
            case osmType = "osm_type"
            case osmID = "osm_id"
            case osmKey = "osm_key"
            case osmValue = "osm_value"
            case houseNumber = "housenumber"
        }
    }
}

struct WorldwideRestaurantSearchService: RestaurantSearching {
    private let mapKit: any RestaurantSearching
    private let photon: PhotonRestaurantSearchService
    private let cityResolver: WorldwideCityResolver

    nonisolated init(
        session: URLSession = .shared,
        mapKit: any RestaurantSearching = MapKitRestaurantSearchService()
    ) {
        self.mapKit = mapKit
        photon = PhotonRestaurantSearchService(session: session)
        cityResolver = WorldwideCityResolver(session: session)
    }

    func search(query: String) async throws -> [RestaurantCandidate] {
        try await mapKit.search(query: query)
    }

    func search(query: String, scope: RestaurantSearchScope) async throws -> [RestaurantCandidate] {
        try Task.checkCancellation()
        guard !scope.city.isEmpty else { return try await mapKit.search(query: query, scope: scope) }
        let resolvedCity = try? await cityResolver.resolve(scope.city)
        try Task.checkCancellation()
        if let resolvedCity, resolvedCity.countryCode != "CN" {
            do {
                let values = try await photon.search(
                    query: query,
                    scopeCity: scope.city,
                    resolvedCity: resolvedCity
                )
                // A provider can return dining suggestions that match only the
                // neighbourhood, not the requested restaurant. Such a response
                // is not a successful name search and must not suppress fallback.
                let matches = RestaurantSearchRelevancePolicy.rankedMatches(
                    values, query: query, scopeCity: scope.city
                )
                if !matches.isEmpty { return matches }
                let qualified = try await photon.searchQualifiedName(query: query, scopeCity: scope.city, resolvedCity: resolvedCity)
                if !qualified.isEmpty { return qualified }
            } catch {
                try Task.checkCancellation()
                if (error as? URLError)?.code == .cancelled || error is CancellationError { throw error }
                // Apple Maps remains the independent provider fallback.
            }
            return RestaurantSearchRelevancePolicy.rankedMatches(
                try await mapKit.search(query: query, scope: scope),
                query: query, scopeCity: scope.city
            )
        }

        do {
            let values = try await mapKit.search(query: query, scope: scope)
            let scoped = resolvedCity.map { resolved in
                values.filter { resolved.region.contains($0.coordinate) }
            } ?? values
            let matches = RestaurantSearchRelevancePolicy.rankedMatches(
                scoped, query: query, scopeCity: scope.city
            )
            if !matches.isEmpty { return matches }
        } catch {
            try Task.checkCancellation()
            if (error as? URLError)?.code == .cancelled || error is CancellationError { throw error }
            // Photon handles Apple Maps outages and China-region limitations.
        }
        return RestaurantSearchRelevancePolicy.rankedMatches(
            try await photon.search(
                query: query,
                scopeCity: scope.city,
                resolvedCity: resolvedCity
            ),
            query: query, scopeCity: scope.city
        )
    }

    func nearby(center: RestaurantCoordinate, radiusMeters: Double) async throws -> [RestaurantCandidate] {
        try await mapKit.nearby(center: center, radiusMeters: radiusMeters)
    }

    func locationContext(for coordinate: RestaurantCoordinate) async throws -> RestaurantLocationContext {
        try await mapKit.locationContext(for: coordinate)
    }

    func coordinate(for address: String, city: String) async throws -> RestaurantCoordinate {
        try await mapKit.coordinate(for: address, city: city)
    }
}

private extension MKCoordinateRegion {
    func contains(_ coordinate: RestaurantCoordinate) -> Bool {
        guard coordinate.isValid else { return false }
        let latitudeDelta = abs(coordinate.latitude - center.latitude)
        let rawLongitudeDelta = abs(coordinate.longitude - center.longitude)
        let longitudeDelta = min(rawLongitudeDelta, 360 - rawLongitudeDelta)
        return latitudeDelta <= span.latitudeDelta / 2
            && longitudeDelta <= span.longitudeDelta / 2
    }
}
