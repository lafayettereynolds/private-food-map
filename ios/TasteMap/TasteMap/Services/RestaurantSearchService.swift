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

enum RestaurantDistanceOrdering {
    static func distance(from origin: RestaurantCoordinate, to target: RestaurantCoordinate) -> CLLocationDistance {
        CLLocation(latitude: origin.latitude, longitude: origin.longitude)
            .distance(from: CLLocation(latitude: target.latitude, longitude: target.longitude))
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
                photoURL: candidate.photoURL
            )
        }
        .sorted {
            ($0.distanceMeters ?? .greatestFiniteMagnitude)
                < ($1.distanceMeters ?? .greatestFiniteMagnitude)
        }
    }
}

struct MapKitRestaurantSearchService: RestaurantSearching {
    nonisolated init() {}

    func search(query: String) async throws -> [RestaurantCandidate] {
        try await search(query: query, scope: RestaurantSearchScope())
    }

    func search(query: String, scope: RestaurantSearchScope) async throws -> [RestaurantCandidate] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { throw RestaurantSearchError.emptyQuery }

        let request = MKLocalSearch.Request()
        request.resultTypes = .pointOfInterest
        if !scope.city.isEmpty, let cityRegion = try? await region(for: scope.city) {
            request.naturalLanguageQuery = query
            request.region = cityRegion
        } else {
            request.naturalLanguageQuery = scope.city.isEmpty ? query : "\(scope.city) \(query)"
            if let center = scope.center, center.isValid {
                request.region = MKCoordinateRegion(
                    center: center.clLocationCoordinate,
                    latitudinalMeters: scope.radiusMeters,
                    longitudinalMeters: scope.radiusMeters
                )
            }
        }

        let response = try await MKLocalSearch(request: request).start()
        let values = candidates(from: response.mapItems, city: scope.city)
        guard let center = scope.center else { return values }
        return RestaurantDistanceOrdering.measuringAndSorting(values, from: center)
    }

    func nearby(center: RestaurantCoordinate, radiusMeters: Double = 3_000) async throws -> [RestaurantCandidate] {
        guard center.isValid else { throw RestaurantSearchError.invalidCoordinate }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "餐厅"
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(
            center: center.clLocationCoordinate,
            latitudinalMeters: radiusMeters * 2,
            longitudinalMeters: radiusMeters * 2
        )
        let response = try await MKLocalSearch(request: request).start()
        return RestaurantDistanceOrdering.measuringAndSorting(
            candidates(from: response.mapItems, city: ""),
            from: center
        )
            .filter { ($0.distanceMeters ?? .greatestFiniteMagnitude) <= radiusMeters }
    }

    func locationContext(for coordinate: RestaurantCoordinate) async throws -> RestaurantLocationContext {
        guard coordinate.isValid else { throw RestaurantSearchError.invalidCoordinate }
        let location = CLLocation(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        if #available(iOS 26.0, *) {
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
        return RestaurantCoordinate(latitude: value.latitude, longitude: value.longitude)
    }

    private func region(for city: String) async throws -> MKCoordinateRegion {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = city
        request.resultTypes = .address
        return try await MKLocalSearch(request: request).start().boundingRegion
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
            return RestaurantCandidate(
                name: name,
                address: address,
                city: city,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                appleMapItemIdentifier: externalID
            )
        }
    }

    private func mapItemCoordinate(_ mapItem: MKMapItem) -> CLLocationCoordinate2D {
        if #available(iOS 26.0, *) {
            return mapItem.location.coordinate
        }
        return mapItem.placemark.coordinate
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

    private func legacyAddress(from placemark: CLPlacemark) -> String {
        [placemark.subThoroughfare, placemark.thoroughfare, placemark.subLocality,
         placemark.locality, placemark.administrativeArea]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private extension RestaurantCoordinate {
    var clLocationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
