import Foundation
import MapKit

protocol RestaurantSearching {
    func search(query: String) async throws -> [RestaurantCandidate]
}

struct MapKitRestaurantSearchService: RestaurantSearching {
    nonisolated init() {}

    func search(query: String) async throws -> [RestaurantCandidate] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest

        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.compactMap { mapItem in
            guard let name = mapItem.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else {
                return nil
            }

            let address = mapItem.address?.fullAddress
                ?? mapItem.addressRepresentations?.fullAddress(includingRegion: true, singleLine: true)
                ?? ""
            let coordinate = mapItem.location.coordinate

            return RestaurantCandidate(
                name: name,
                address: address,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                appleMapItemIdentifier: mapItem.identifier?.rawValue
            )
        }
    }
}
