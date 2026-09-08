import CoreLocation
import Foundation
import MapKit

struct RestaurantSearchScope: Equatable, Sendable {
    var city: String
    var center: RestaurantCoordinate?
    var radiusMeters: Double

    init(city: String = "", center: RestaurantCoordinate? = nil, radiusMeters: Double = 20_000) {
        self.city = city.trimmingCharacters(in: .whitespacesAndNewlines)
        self.center = center
        self.radiusMeters = radiusMeters
    }
}

struct RestaurantLocationContext: Equatable, Sendable {
    let city: String
    let district: String
    let address: String
}

protocol RestaurantSearching: Sendable {
    func search(query: String) async throws -> [RestaurantCandidate]
    func search(query: String, scope: RestaurantSearchScope) async throws -> [RestaurantCandidate]
    func nearby(center: RestaurantCoordinate, radiusMeters: Double) async throws -> [RestaurantCandidate]
    func locationContext(for coordinate: RestaurantCoordinate) async throws -> RestaurantLocationContext
    func coordinate(for address: String, city: String) async throws -> RestaurantCoordinate
}

extension RestaurantSearching {
    func search(query: String, scope: RestaurantSearchScope) async throws -> [RestaurantCandidate] {
        let city = scope.city.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await search(query: city.isEmpty ? query : "\(city) \(query)")
    }

    func nearby(center: RestaurantCoordinate, radiusMeters: Double) async throws -> [RestaurantCandidate] {
        try await search(query: "餐厅")
    }

    func locationContext(for coordinate: RestaurantCoordinate) async throws -> RestaurantLocationContext {
        RestaurantLocationContext(city: "", district: "", address: "")
    }

    func coordinate(for address: String, city: String) async throws -> RestaurantCoordinate {
        throw RestaurantSearchError.locationNotFound
    }
}

enum RestaurantSearchError: Error, Equatable {
    case emptyQuery
    case invalidCoordinate
    case locationNotFound
}

enum RestaurantSearchRelevancePolicy {
    static func rankedMatches(
        _ candidates: [RestaurantCandidate],
        query: String,
        scopeCity: String = ""
    ) -> [RestaurantCandidate] {
        let normalizedQuery = normalized(query)
        let compactQuery = compact(normalizedQuery)
        let queryTerms = terms(normalizedQuery)
        let compactScopeCity = compact(normalized(scopeCity))
        guard !compactQuery.isEmpty else { return [] }

        return candidates.enumerated().compactMap { index, candidate -> (RestaurantCandidate, Int, Int)? in
            guard let score = relevanceScore(
                candidate,
                compactQuery: compactQuery,
                queryTerms: queryTerms,
                compactScopeCity: compactScopeCity
            ) else { return nil }
            return (candidate, score, index)
        }
        .sorted { left, right in
            left.1 == right.1 ? left.2 < right.2 : left.1 > right.1
        }
        .map(\.0)
    }

    private static func relevanceScore(
        _ candidate: RestaurantCandidate,
        compactQuery: String,
        queryTerms: [String],
        compactScopeCity: String
    ) -> Int? {
        let name = compact(normalized(candidate.name))
        let address = compact(normalized(candidate.address))
        let categories = compact(normalized(candidate.categoryHints.joined(separator: " ")))
        let searchable = compact(normalized([
            candidate.name,
            candidate.address,
            candidate.city,
            candidate.district,
            candidate.categoryHints.joined(separator: " "),
        ].joined(separator: " ")))

        if name == compactQuery { return 1_000 }
        if name.hasPrefix(compactQuery) { return 900 }
        if name.contains(compactQuery) { return 850 }
        if queryVariants(compactQuery).dropFirst().contains(where: { name.contains(compact(normalized($0))) }) { return 825 }
        if matchesDiningAbbreviation(name: name, query: compactQuery) { return 825 }
        if address.contains(compactQuery) { return 750 }
        if categories.contains(compactQuery) { return 650 }
        if !queryTerms.isEmpty,
           queryTerms.allSatisfy({ searchable.contains(compact($0)) }) {
            return 600
        }
        if let resolvedQuery = candidate.resolvedSearchQuery,
           compact(normalized(resolvedQuery)) == compactQuery {
            // Provider fallback already verified the exact business name and
            // independently resolved the location qualifier inside the chosen city.
            return 590
        }
        // A provider-filtered category/location search such as “餐厅”,
        // “上海餐厅” or “New York restaurant” cannot be expected to contain
        // the entire phrase in an individual Restaurant name. Remove one
        // recognized dining intent and validate the remaining place text.
        // Specific-name searches retain the stricter rules above.
        for intent in diningIntentTerms {
            let compactIntent = compact(normalized(intent))
            guard compactQuery.contains(compactIntent) else { continue }
            let placeRemainder = compactQuery.replacingOccurrences(of: compactIntent, with: "")
            if placeRemainder.isEmpty { return 550 }
            if searchable.contains(placeRemainder) { return 575 }
            if !compactScopeCity.isEmpty,
               (compactScopeCity.contains(placeRemainder)
                    || placeRemainder.contains(compactScopeCity)) {
                return 560
            }
        }
        return nil
    }

    private static func matchesDiningAbbreviation(name: String, query: String) -> Bool {
        ["拉面", "火锅", "烧烤", "咖啡", "寿司", "面馆", "奶茶"].contains { suffix in
            guard query.hasSuffix(suffix) else { return false }
            let prefix = String(query.dropLast(suffix.count))
            guard prefix.count >= 2, let start = name.range(of: prefix) else { return false }
            let tail = name[start.upperBound...]
            guard let end = tail.range(of: suffix) else { return false }
            return tail.distance(from: tail.startIndex, to: end.lowerBound) <= 6
        }
    }

    static func queryVariants(_ query: String) -> [String] {
        let aliases = ["kfc": "肯德基", "mcdonalds": "麦当劳", "starbucks": "星巴克", "haidilao": "海底捞", "兰州拉面": "兰州牛肉拉面"]
        if let alias = aliases[compact(normalized(query))] { return [query, alias] }
        return [query]
    }

    private static let diningIntentTerms = [
        "餐厅", "餐馆", "饭店", "美食", "小吃", "咖啡馆", "咖啡店", "烘焙店",
        "restaurant", "restaurants", "food", "cafe", "bakery",
    ]

    private static func normalized(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
    }

    private static func compact(_ value: String) -> String {
        value.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
    }

    private static func terms(_ value: String) -> [String] {
        value.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}

enum RestaurantDistanceOrdering {
    static func distance(from origin: RestaurantCoordinate, to target: RestaurantCoordinate) -> CLLocationDistance {
        let (start, end) = RestaurantCoordinateNormalization.comparable(origin, target)
        return CLLocation(latitude: start.latitude, longitude: start.longitude)
            .distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
    }

    static func measuringAndSorting(
        _ candidates: [RestaurantCandidate],
        from origin: RestaurantCoordinate
    ) -> [RestaurantCandidate] {
        candidates.map { candidate in
            RestaurantCandidate(
                id: candidate.id,
                name: candidate.name,
                address: candidate.address,
                city: candidate.city,
                district: candidate.district,
                latitude: candidate.latitude,
                longitude: candidate.longitude,
                appleMapItemIdentifier: candidate.appleMapItemIdentifier,
                placeIdentities: candidate.placeIdentities,
                distanceMeters: distance(from: origin, to: candidate.coordinate),
                photoURL: candidate.photoURL,
                phone: candidate.phone,
                websiteURL: candidate.websiteURL,
                openingHours: candidate.openingHours,
                categoryHints: candidate.categoryHints,
                coordinateReference: candidate.coordinateReference
            )
        }
        .sorted {
            ($0.distanceMeters ?? .greatestFiniteMagnitude)
                < ($1.distanceMeters ?? .greatestFiniteMagnitude)
        }
    }
}

enum RestaurantNearbySearchPolicy {
    static let keywords = ["餐厅", "美食", "饭店", "小吃"]
    static let fallbackKeywords = ["餐饮", "餐馆", "咖啡馆", "烘焙店"]
    static let pointOfInterestCategories: [MKPointOfInterestCategory] = [
        .restaurant,
        .cafe,
        .bakery,
        .foodMarket,
    ]

    static func keywordRequest(
        matching query: String,
        center: RestaurantCoordinate,
        radiusMeters: Double,
        requiresRegion: Bool = false
    ) -> MKLocalSearch.Request {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
            latitudinalMeters: radiusMeters * 2,
            longitudinalMeters: radiusMeters * 2
        )
        if #available(iOS 18.0, *), requiresRegion {
            request.regionPriority = .required
        }
        return request
    }

    /// MapKit treats `region` as a ranking hint rather than a hard boundary.
    /// A wider second-pass hint helps a temporarily sparse provider response
    /// discover the nearest POIs; `merge` still enforces the user-facing radius.
    static func fallbackProviderRadius(for resultRadius: Double) -> Double {
        max(12_000, resultRadius * 4)
    }

    static func merge(
        _ batches: [[RestaurantCandidate]],
        from origin: RestaurantCoordinate,
        radiusMeters: Double
    ) -> [RestaurantCandidate] {
        var seen = Set<String>()
        let unique = batches.flatMap { $0 }.filter { candidate in
            seen.insert(identityKey(for: candidate)).inserted
        }
        return RestaurantDistanceOrdering.measuringAndSorting(unique, from: origin)
            .filter { ($0.distanceMeters ?? .greatestFiniteMagnitude) <= radiusMeters }
    }

    private static func identityKey(for candidate: RestaurantCandidate) -> String {
        if let identity = candidate.placeIdentities.first {
            return "\(identity.provider.rawValue):\(identity.externalID)"
        }
        let normalizedName = candidate.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return "coordinate:\(normalizedName):\(candidate.latitude.rounded(toPlaces: 5)):\(candidate.longitude.rounded(toPlaces: 5))"
    }
}

struct MapKitRestaurantSearchService: RestaurantSearching {
    private struct NearbyBatch {
        let candidates: [RestaurantCandidate]
        let completed: Bool

        static var failed: NearbyBatch { NearbyBatch(candidates: [], completed: false) }
    }

    nonisolated init() {}

    func search(query: String) async throws -> [RestaurantCandidate] {
        try await search(query: query, scope: RestaurantSearchScope())
    }

    func search(query: String, scope: RestaurantSearchScope) async throws -> [RestaurantCandidate] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { throw RestaurantSearchError.emptyQuery }
        var scope = scope
        if let center = scope.center, center.reference == .wgs84 {
            // A failed GPS conversion must not block independent city search.
            scope.center = try? await providerOrigin(center)
        }
        var collected: [RestaurantCandidate] = []
        var completedProviderRequest = false
        var lastProviderError: (any Error)?
        let cityRegion: MKCoordinateRegion?
        if scope.city.isEmpty {
            cityRegion = nil
        } else {
            cityRegion = try? await region(for: scope.city)
        }

        let nearbyRegion = scope.center.flatMap { center -> MKCoordinateRegion? in
            guard center.isValid, cityRegion?.contains(center) != false else { return nil }
            return MKCoordinateRegion(center: center.clLocationCoordinate,
                                      latitudinalMeters: 6_000, longitudinalMeters: 6_000)
        }
        if let cityRegion {
            do {
                collected += try await providerCandidates(
                    query: query,
                    region: cityRegion,
                    fallbackCity: scope.city,
                    requiresRegion: true
                )
                completedProviderRequest = true
            } catch {
                lastProviderError = error
            }
        } else if let center = scope.center, center.isValid {
            do {
                collected += try await providerCandidates(
                    query: query,
                    region: MKCoordinateRegion(
                        center: center.clLocationCoordinate,
                        latitudinalMeters: scope.radiusMeters,
                        longitudinalMeters: scope.radiusMeters
                    ),
                    fallbackCity: scope.city,
                    requiresRegion: false
                )
                completedProviderRequest = true
            } catch {
                lastProviderError = error
            }
        }

        // City ranking is not nearby ranking. Always supplement the city result
        // at the accepted GPS fix, even if the city query returned other branches.
        // Query expansions are names only; every displayed place is resolved by
        // the provider and must still pass the original query's relevance gate.
        let variants = RestaurantSearchRelevancePolicy.queryVariants(query)
        for variant in variants {
            if let nearbyRegion {
                if let batch = try? await providerCandidates(query: variant, region: nearbyRegion,
                                                            fallbackCity: scope.city, requiresRegion: true) {
                    collected += batch
                    completedProviderRequest = true
                }
            }
            if variant != query, let batch = try? await providerCandidates(
                query: variant, region: cityRegion, fallbackCity: scope.city,
                requiresRegion: cityRegion != nil
            ) {
                collected += batch
                completedProviderRequest = true
            }
        }
        let completions = await RestaurantSearchCompletionLookup().queries(
            query: query, region: nearbyRegion ?? cityRegion
        )
        for completion in completions.prefix(3) {
            if let batch = try? await providerCandidates(
                query: completion, region: nearbyRegion ?? cityRegion,
                fallbackCity: scope.city, requiresRegion: cityRegion != nil
            ) {
                collected += batch
                completedProviderRequest = true
            }
        }

        var values = RestaurantSearchRelevancePolicy.rankedMatches(
            deduplicated(collected),
            query: query,
            scopeCity: scope.city
        )

        // A remote-city search must never drift back to the device's current
        // city. Repeat sparse searches with a location-bearing query, while
        // retaining the required resolved region when one is available.
        if values.isEmpty {
            let worldwideQuery = scope.city.isEmpty ? query : "\(scope.city) \(query)"
            do {
                collected += try await providerCandidates(
                    query: worldwideQuery,
                    region: cityRegion,
                    fallbackCity: scope.city,
                    requiresRegion: cityRegion != nil
                )
                completedProviderRequest = true
            } catch {
                lastProviderError = error
            }
            values = RestaurantSearchRelevancePolicy.rankedMatches(
                deduplicated(collected),
                query: query,
                scopeCity: scope.city
            )
        }
        if !completedProviderRequest, let lastProviderError { throw lastProviderError }
        guard let center = scope.center, nearbyRegion != nil else { return values }
        return RestaurantDistanceOrdering.measuringAndSorting(values, from: center)
    }

    private func providerCandidates(
        query: String,
        region: MKCoordinateRegion?,
        fallbackCity: String,
        requiresRegion: Bool
    ) async throws -> [RestaurantCandidate] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest
        request.pointOfInterestFilter = MKPointOfInterestFilter(
            including: RestaurantNearbySearchPolicy.pointOfInterestCategories
        )
        if let region {
            request.region = region
            if #available(iOS 18.0, *), requiresRegion {
                request.regionPriority = .required
            }
        }
        let response = try await MKLocalSearch(request: request).start()
        let values = candidates(from: response.mapItems, city: fallbackCity)
        guard values.allSatisfy({ $0.coordinateReference != .unspecified }) else {
            throw RestaurantSearchError.locationNotFound
        }
        guard requiresRegion, let region else { return values }
        // `regionPriority` is unavailable on older deployment targets, and a
        // provider may still be imprecise. The coordinate gate makes the city
        // boundary a product rule instead of trusting ranking alone.
        return values.filter { region.contains($0.coordinate) }
    }

    private func deduplicated(_ candidates: [RestaurantCandidate]) -> [RestaurantCandidate] {
        var seen = Set<String>()
        return candidates.filter { candidate in
            let key: String
            if let identity = candidate.placeIdentities.first {
                key = "\(identity.provider.rawValue):\(identity.externalID)"
            } else {
                key = "\(candidate.name.lowercased()):\(candidate.latitude.rounded(toPlaces: 5)):\(candidate.longitude.rounded(toPlaces: 5))"
            }
            return seen.insert(key).inserted
        }
    }

    func nearby(center: RestaurantCoordinate, radiusMeters: Double = 3_000) async throws -> [RestaurantCandidate] {
        guard center.isValid else { throw RestaurantSearchError.invalidCoordinate }
        let center = try await providerOrigin(center)
        async let proximityBatch = nearbyPointsOfInterest(
            center: center,
            radiusMeters: radiusMeters
        )
        async let restaurantBatch = nearbyCandidates(
            matching: RestaurantNearbySearchPolicy.keywords[0],
            center: center,
            radiusMeters: radiusMeters
        )
        async let foodBatch = nearbyCandidates(
            matching: RestaurantNearbySearchPolicy.keywords[1],
            center: center,
            radiusMeters: radiusMeters
        )
        async let diningBatch = nearbyCandidates(
            matching: RestaurantNearbySearchPolicy.keywords[2],
            center: center,
            radiusMeters: radiusMeters
        )
        async let localFoodBatch = nearbyCandidates(
            matching: RestaurantNearbySearchPolicy.keywords[3],
            center: center,
            radiusMeters: radiusMeters
        )
        let primary = await [proximityBatch, restaurantBatch, foodBatch, diningBatch, localFoodBatch]
        var outcomes = primary
        var merged = RestaurantNearbySearchPolicy.merge(
            primary.filter(\.completed).map(\.candidates),
            from: center,
            radiusMeters: radiusMeters
        )
        // A broad 3 km query can be filled by famous venues and omit the shop
        // next door. Merge a genuinely local POI pass before choosing nearest.
        async let localPoints = nearbyPointsOfInterest(center: center, radiusMeters: min(500, radiusMeters))
        // A local POI response can still omit a small Restaurant that a local
        // text query resolves. Supplement by dining intent, never a hard-coded
        // merchant name, and constrain this query before provider ranking.
        async let localRestaurants = nearbyCandidates(
            matching: RestaurantNearbySearchPolicy.keywords[0],
            center: center,
            radiusMeters: min(500, radiusMeters),
            requiresRegion: true
        )
        outcomes += await [localPoints, localRestaurants]
        merged = RestaurantNearbySearchPolicy.merge(outcomes.filter(\.completed).map(\.candidates),
                                                   from: center, radiusMeters: radiusMeters)
        if !merged.isEmpty { return merged }

        // A single empty MapKit response must not mask failures from the other
        // request types as a definitive "there are no nearby Restaurants".
        // Retry once with a broader provider ranking window and alternate local
        // vocabulary, while preserving the strict result radius below.
        let fallbackRadius = RestaurantNearbySearchPolicy.fallbackProviderRadius(for: radiusMeters)
        async let fallbackProximity = nearbyPointsOfInterest(
            center: center,
            radiusMeters: fallbackRadius
        )
        async let fallbackDiningBatch = nearbyCandidates(
            matching: RestaurantNearbySearchPolicy.fallbackKeywords[0],
            center: center,
            radiusMeters: fallbackRadius
        )
        async let fallbackRestaurantBatch = nearbyCandidates(
            matching: RestaurantNearbySearchPolicy.fallbackKeywords[1],
            center: center,
            radiusMeters: fallbackRadius
        )
        async let cafeBatch = nearbyCandidates(
            matching: RestaurantNearbySearchPolicy.fallbackKeywords[2],
            center: center,
            radiusMeters: fallbackRadius
        )
        async let bakeryBatch = nearbyCandidates(
            matching: RestaurantNearbySearchPolicy.fallbackKeywords[3],
            center: center,
            radiusMeters: fallbackRadius
        )
        outcomes += await [
            fallbackProximity,
            fallbackDiningBatch,
            fallbackRestaurantBatch,
            cafeBatch,
            bakeryBatch,
        ]
        merged = RestaurantNearbySearchPolicy.merge(
            outcomes.filter(\.completed).map(\.candidates),
            from: center,
            radiusMeters: radiusMeters
        )
        if !merged.isEmpty { return merged }

        // An empty state is trustworthy only when every independent provider
        // request completed. A partial provider outage remains recoverable and
        // must render Retry instead of the misleading zero-result message.
        guard outcomes.allSatisfy(\.completed) else {
            throw RestaurantSearchError.locationNotFound
        }
        return []
    }

    private func nearbyPointsOfInterest(
        center: RestaurantCoordinate,
        radiusMeters: Double
    ) async -> NearbyBatch {
        let request = MKLocalPointsOfInterestRequest(
            center: center.clLocationCoordinate,
            radius: radiusMeters
        )
        request.pointOfInterestFilter = MKPointOfInterestFilter(
            including: RestaurantNearbySearchPolicy.pointOfInterestCategories
        )
        guard let response = try? await MKLocalSearch(request: request).start() else { return .failed }
        let values = candidates(from: response.mapItems, city: "")
        guard values.allSatisfy({ $0.coordinateReference != .unspecified }) else { return .failed }
        return NearbyBatch(candidates: values, completed: true)
    }

    private func nearbyCandidates(
        matching query: String,
        center: RestaurantCoordinate,
        radiusMeters: Double,
        requiresRegion: Bool = false
    ) async -> NearbyBatch {
        let request = RestaurantNearbySearchPolicy.keywordRequest(
            matching: query,
            center: center,
            radiusMeters: radiusMeters,
            requiresRegion: requiresRegion
        )
        guard let response = try? await MKLocalSearch(request: request).start() else { return .failed }
        let values = candidates(from: response.mapItems, city: "")
        guard values.allSatisfy({ $0.coordinateReference != .unspecified }) else { return .failed }
        return NearbyBatch(candidates: values, completed: true)
    }

    func locationContext(for coordinate: RestaurantCoordinate) async throws -> RestaurantLocationContext {
        guard coordinate.isValid else { throw RestaurantSearchError.invalidCoordinate }
        if #available(iOS 26.0, *) {
            let coordinate = try await providerOrigin(coordinate)
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            guard let request = MKReverseGeocodingRequest(location: location),
                  let mapItem = try await request.mapItems.first else {
                throw RestaurantSearchError.locationNotFound
            }
            let representations = mapItem.addressRepresentations
            let city = representations?.cityName ?? ""
            let district = representations?.cityWithContext ?? ""
            let address = mapItem.address?.fullAddress
                ?? representations?.fullAddress(includingRegion: true, singleLine: true)
                ?? ""
            return RestaurantLocationContext(city: city, district: district, address: address)
        }

        let raw = RestaurantCoordinateNormalization.wgs84(from: coordinate)
        let location = CLLocation(latitude: raw.latitude, longitude: raw.longitude)
        guard let placemark = try await CLGeocoder().reverseGeocodeLocation(location).first else {
            throw RestaurantSearchError.locationNotFound
        }
        return RestaurantLocationContext(
            city: placemark.locality ?? placemark.administrativeArea ?? "",
            district: placemark.subLocality ?? placemark.subAdministrativeArea ?? "",
            address: placemark.name ?? legacyAddress(from: placemark)
        )
    }

    func coordinate(for address: String, city: String) async throws -> RestaurantCoordinate {
        let query = [city, address]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !query.isEmpty else { throw RestaurantSearchError.locationNotFound }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.address, .pointOfInterest]
        let response = try await MKLocalSearch(request: request).start()
        guard let item = response.mapItems.first else { throw RestaurantSearchError.locationNotFound }
        let value = mapItemCoordinate(item)
        return RestaurantCoordinate(latitude: value.latitude, longitude: value.longitude,
            reference: RestaurantCoordinateNormalization.mapKitReference(countryCode: item.placemark.isoCountryCode ?? "") ?? .unspecified)
    }

    private func region(for city: String) async throws -> MKCoordinateRegion {
        guard let placemark = try await CLGeocoder().geocodeAddressString(city).first,
              let location = placemark.location else {
            throw RestaurantSearchError.locationNotFound
        }
        let coordinate = location.coordinate
        guard CLLocationCoordinate2DIsValid(coordinate) else {
            throw RestaurantSearchError.locationNotFound
        }
        // Covers a metropolitan area rather than the arbitrary bounding box
        // of every text-search match bearing the same city name.
        return MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 120_000,
            longitudinalMeters: 120_000
        )
    }

    private func candidates(
        from mapItems: [MKMapItem],
        city: String
    ) -> [RestaurantCandidate] {
        var seen = Set<String>()
        return mapItems.compactMap { mapItem in
            guard let name = mapItem.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { return nil }
            let coordinate = mapItemCoordinate(mapItem)
            let externalID = mapItemExternalID(mapItem)
            let key = externalID ?? "\(name)|\(coordinate.latitude)|\(coordinate.longitude)"
            guard seen.insert(key).inserted else { return nil }
            let address = mapItemAddress(mapItem)
            let providerCity = mapItemCity(mapItem).trimmingCharacters(in: .whitespacesAndNewlines)
            return RestaurantCandidate(
                name: name,
                address: address,
                city: providerCity.isEmpty ? city : providerCity,
                district: mapItemDistrict(mapItem),
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                appleMapItemIdentifier: externalID,
                phone: mapItem.phoneNumber,
                websiteURL: mapItem.url,
                categoryHints: [mapItem.pointOfInterestCategory?.rawValue].compactMap { $0 },
                coordinateReference: RestaurantCoordinateNormalization.mapKitReference(
                    countryCode: mapItem.placemark.isoCountryCode ?? ""
                ) ?? .unspecified
            )
        }
    }

    private func mapItemCoordinate(_ mapItem: MKMapItem) -> CLLocationCoordinate2D {
        if #available(iOS 26.0, *) {
            return mapItem.location.coordinate
        }
        return mapItem.placemark.coordinate
    }

    private func providerOrigin(_ point: RestaurantCoordinate) async throws -> RestaurantCoordinate {
        guard point.reference == .wgs84 else { return point }
        // Core Location country lookup uses the untouched sensor coordinate.
        let geocoder = CLGeocoder()
        let marks = try await geocoder.reverseGeocodeLocation(
            CLLocation(latitude: point.latitude, longitude: point.longitude)
        )
        guard let country = marks.first?.isoCountryCode,
              let reference = RestaurantCoordinateNormalization.mapKitReference(countryCode: country) else {
            throw RestaurantSearchError.locationNotFound
        }
        return reference == .gcj02 ? RestaurantCoordinateNormalization.gcj02(from: point) : point
    }

    private func mapItemExternalID(_ mapItem: MKMapItem) -> String? {
        if #available(iOS 18.0, *) {
            return mapItem.identifier?.rawValue
        }
        return nil
    }

    private func mapItemAddress(_ mapItem: MKMapItem) -> String {
        if #available(iOS 26.0, *) {
            return mapItem.address?.fullAddress
                ?? mapItem.addressRepresentations?.fullAddress(includingRegion: true, singleLine: true)
                ?? ""
        }
        return mapItem.placemark.title ?? legacyAddress(from: mapItem.placemark)
    }

    private func mapItemCity(_ mapItem: MKMapItem) -> String {
        if #available(iOS 26.0, *) {
            return mapItem.addressRepresentations?.cityName ?? ""
        }
        return mapItem.placemark.locality ?? mapItem.placemark.administrativeArea ?? ""
    }

    private func mapItemDistrict(_ mapItem: MKMapItem) -> String {
        // cityWithContext is "Cupertino, CA", not a neighbourhood (MapKit's
        // header documents this explicitly). Preserve the provider's actual
        // sub-locality before using city context as a last-resort display value;
        // otherwise iOS 26 discards the evidence needed by name + district search.
        if let district = mapItem.placemark.subLocality?.trimmingCharacters(in: .whitespacesAndNewlines),
           !district.isEmpty { return district }
        if let district = mapItem.placemark.subAdministrativeArea?.trimmingCharacters(in: .whitespacesAndNewlines),
           !district.isEmpty { return district }
        if #available(iOS 26.0, *) {
            return mapItem.addressRepresentations?.cityWithContext ?? ""
        }
        return ""
    }

    private func legacyAddress(from placemark: CLPlacemark) -> String {
        [placemark.subThoroughfare, placemark.thoroughfare, placemark.subLocality,
         placemark.locality, placemark.administrativeArea]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

/// A bounded provider-side completion pass for submitted shorthand queries.
/// A suggestion is never a Restaurant until MKLocalSearch resolves its facts.
@MainActor
private final class RestaurantSearchCompletionLookup: NSObject, MKLocalSearchCompleterDelegate {
    private let completer = MKLocalSearchCompleter()
    private var continuation: CheckedContinuation<[String], Never>?
    private var timeout: Task<Void, Never>?

    func queries(query: String, region: MKCoordinateRegion?) async -> [String] {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                completer.delegate = self
                completer.resultTypes = .pointOfInterest
                completer.pointOfInterestFilter = MKPointOfInterestFilter(
                    including: RestaurantNearbySearchPolicy.pointOfInterestCategories)
                if let region { completer.region = region }
                timeout = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled else { return }
                    self?.finish([])
                }
                completer.queryFragment = query
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish([]) }
        }
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        finish(completer.results.prefix(3).map { [$0.title, $0.subtitle].filter { !$0.isEmpty }.joined(separator: " ") })
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) { finish([]) }

    private func finish(_ values: [String]) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel()
        completer.cancel()
        completer.delegate = nil
        continuation.resume(returning: values)
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let scale = pow(10, Double(places))
        return (self * scale).rounded() / scale
    }
}

private extension RestaurantCoordinate {
    var clLocationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
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
