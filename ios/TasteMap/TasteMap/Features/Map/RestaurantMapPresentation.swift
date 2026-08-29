import CoreLocation
import Foundation

enum RestaurantMapMarkerStatus: String, Equatable {
    case visited
    case wantToGo
    case recommended

    var accessibilityTitle: String {
        switch self {
        case .visited: "去过"
        case .wantToGo: "想吃"
        case .recommended: "适合你"
        }
    }
}

enum RestaurantMapMarkerVisual: Equatable {
    case photo(UUID)
    case merchantImage(URL)
    case emoji(String)
    case fallback
}

struct RestaurantMapMarkerPresentation: Identifiable, Equatable {
    let id: UUID
    let name: String
    let latitude: Double
    let longitude: Double
    let status: RestaurantMapMarkerStatus
    let visual: RestaurantMapMarkerVisual
    let visitCount: Int
    let averageRating: Double?
    let distanceKilometers: Double?
}

@MainActor
enum RestaurantMapMarkerBuilder {
    static func build(
        items: [RestaurantBrowseItem],
        photos: [PhotoAsset],
        segment: RestaurantBrowseSegment,
        currentLocation: CLLocation? = nil
    ) -> [RestaurantMapMarkerPresentation] {
        var activePhotosByReference: [String: PhotoAsset] = [:]
        for photo in photos where isActive(photo) {
            activePhotosByReference[photo.id.uuidString.lowercased()] = photo
            if let remoteID = trimmed(photo.remoteID) {
                activePhotosByReference[remoteID.lowercased()] = photo
            }
        }

        return items.compactMap { item in
            let restaurant = item.restaurant
            guard restaurant.deletedAt == nil,
                  RestaurantMapCoordinatePolicy.isValid(
                    latitude: restaurant.latitude,
                    longitude: restaurant.longitude
                  ) else { return nil }

            let record = restaurant.remoteRecordData.flatMap {
                try? JSONDecoder().decode(RestaurantJSONContractV1.self, from: $0)
            }
            let visual: RestaurantMapMarkerVisual
            if let markerPhotoID = trimmed(record?.markerPhotoId),
               let photo = activePhotosByReference[markerPhotoID.lowercased()],
               photo.restaurantId == restaurant.id,
               photo.kind == .restaurantMarker {
                visual = .photo(photo.id)
            } else if let merchantURL = RestaurantDetailMetadata.safeHTTPSURL(record?.merchantImageUrl) {
                visual = .merchantImage(merchantURL)
            } else if let photo = item.photo,
                      isActive(photo),
                      photo.restaurantId == restaurant.id {
                visual = .photo(photo.id)
            } else if let emoji = trimmed(record?.markerEmoji) {
                visual = .emoji(emoji)
            } else {
                visual = .fallback
            }

            return RestaurantMapMarkerPresentation(
                id: restaurant.id,
                name: restaurant.name,
                latitude: restaurant.latitude,
                longitude: restaurant.longitude,
                status: status(for: restaurant, segment: segment),
                visual: visual,
                visitCount: item.visitCount,
                averageRating: item.averageRating,
                distanceKilometers: distanceKilometers(
                    from: currentLocation,
                    to: restaurant,
                    status: status(for: restaurant, segment: segment)
                )
            )
        }
    }

    private static func status(
        for restaurant: Restaurant,
        segment: RestaurantBrowseSegment
    ) -> RestaurantMapMarkerStatus {
        if segment == .forYou { return .recommended }
        return restaurant.status == .wantToGo ? .wantToGo : .visited
    }

    private static func isActive(_ photo: PhotoAsset) -> Bool {
        photo.deletedAt == nil && photo.binaryDeletedAt == nil && photo.uploadState != .deleted
    }

    private static func distanceKilometers(
        from currentLocation: CLLocation?,
        to restaurant: Restaurant,
        status: RestaurantMapMarkerStatus
    ) -> Double? {
        guard status == .wantToGo,
              let currentLocation,
              RestaurantMapCoordinatePolicy.isValid(
                latitude: currentLocation.coordinate.latitude,
                longitude: currentLocation.coordinate.longitude
              ) else { return nil }
        let restaurantLocation = CLLocation(
            latitude: restaurant.latitude,
            longitude: restaurant.longitude
        )
        return currentLocation.distance(from: restaurantLocation) / 1_000
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
}

enum RestaurantMapCoordinatePolicy {
    static func isValid(latitude: Double, longitude: Double) -> Bool {
        latitude.isFinite
            && longitude.isFinite
            && (-90 ... 90).contains(latitude)
            && (-180 ... 180).contains(longitude)
            && !(latitude == 0 && longitude == 0)
    }
}

enum RestaurantMapMarkerMetrics {
    static let baseDiameter = 44.0
    static let selectionIncrease = 8.0

    /// Keeps the existing Web rule: want-to-go markers scale from 1.28x nearby
    /// to 0.78x at 30 km and beyond, using a logarithmic distance curve.
    static func wantedScale(distanceKilometers: Double) -> Double {
        guard distanceKilometers.isFinite, distanceKilometers >= 0 else { return 1 }
        let progress = min(1, log1p(distanceKilometers) / log1p(30))
        return 1.28 - progress * 0.5
    }

    static func diameter(
        status: RestaurantMapMarkerStatus,
        distanceKilometers: Double?,
        isSelected: Bool
    ) -> Double {
        let scale: Double
        if status == .wantToGo, let distanceKilometers {
            scale = wantedScale(distanceKilometers: distanceKilometers)
        } else {
            scale = 1
        }
        return baseDiameter * scale + (isSelected ? selectionIncrease : 0)
    }
}

enum RestaurantMapCameraTarget: Equatable {
    case unchanged
    case region(
        centerLatitude: Double,
        centerLongitude: Double,
        latitudeDelta: Double,
        longitudeDelta: Double
    )
}

enum RestaurantMapCameraPolicy {
    static let singlePointSpan = 0.04
    static let minimumMultiPointSpan = 0.025
    static let resultPadding = 1.35

    static func target(for markers: [RestaurantMapMarkerPresentation]) -> RestaurantMapCameraTarget {
        guard let first = markers.first else { return .unchanged }
        guard markers.count > 1 else {
            return .region(
                centerLatitude: first.latitude,
                centerLongitude: first.longitude,
                latitudeDelta: singlePointSpan,
                longitudeDelta: singlePointSpan
            )
        }

        var minimumLatitude = first.latitude
        var maximumLatitude = first.latitude
        var minimumLongitude = first.longitude
        var maximumLongitude = first.longitude
        for marker in markers.dropFirst() {
            minimumLatitude = min(minimumLatitude, marker.latitude)
            maximumLatitude = max(maximumLatitude, marker.latitude)
            minimumLongitude = min(minimumLongitude, marker.longitude)
            maximumLongitude = max(maximumLongitude, marker.longitude)
        }
        let latitudeDelta = max(minimumMultiPointSpan, maximumLatitude - minimumLatitude) * resultPadding
        let longitudeDelta = max(minimumMultiPointSpan, maximumLongitude - minimumLongitude) * resultPadding
        return .region(
            centerLatitude: (minimumLatitude + maximumLatitude) / 2,
            centerLongitude: (minimumLongitude + maximumLongitude) / 2,
            latitudeDelta: min(170, latitudeDelta),
            longitudeDelta: min(360, longitudeDelta)
        )
    }
}

struct RestaurantMapClusterPresentation: Equatable {
    let members: [RestaurantMapMarkerPresentation]

    var count: Int { members.count }
    var expansionTarget: RestaurantMapCameraTarget {
        RestaurantMapCameraPolicy.target(for: members)
    }
}

enum RestaurantMapRenderState: Equatable {
    case loading
    case ready
    case failed(String)
}
