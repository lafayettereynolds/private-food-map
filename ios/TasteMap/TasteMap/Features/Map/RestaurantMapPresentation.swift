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
        case .recommended: "推荐"
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

/// A MapKit-independent viewport value keeps large-library culling testable
/// without creating an MKMapView. It never aggregates Restaurants: every
/// returned value is still the original, independently selectable marker.
struct RestaurantMapViewport: Equatable, Sendable {
    let centerLatitude: Double
    let centerLongitude: Double
    let latitudeDelta: Double
    let longitudeDelta: Double
}

enum RestaurantMapViewportPolicy {
    static let prefetchPadding = 1.35

    static func visibleMarkers(
        _ markers: [RestaurantMapMarkerPresentation],
        in viewport: RestaurantMapViewport,
        selectedRestaurantID: UUID? = nil,
        padding: Double = prefetchPadding
    ) -> [RestaurantMapMarkerPresentation] {
        guard viewport.centerLatitude.isFinite,
              viewport.centerLongitude.isFinite,
              viewport.latitudeDelta.isFinite,
              viewport.longitudeDelta.isFinite,
              viewport.latitudeDelta > 0,
              viewport.longitudeDelta > 0 else {
            return markers
        }

        let safePadding = max(1, padding)
        let latitudeRadius = min(90, viewport.latitudeDelta * safePadding / 2)
        let longitudeRadius = min(180, viewport.longitudeDelta * safePadding / 2)
        return markers.filter { marker in
            if marker.id == selectedRestaurantID { return true }
            guard abs(marker.latitude - viewport.centerLatitude) <= latitudeRadius else {
                return false
            }
            guard longitudeRadius < 180 else { return true }
            return wrappedLongitudeDistance(
                marker.longitude,
                viewport.centerLongitude
            ) <= longitudeRadius
        }
    }

    private static func wrappedLongitudeDistance(_ left: Double, _ right: Double) -> Double {
        let raw = abs(left - right).truncatingRemainder(dividingBy: 360)
        return min(raw, 360 - raw)
    }
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

        let markers: [RestaurantMapMarkerPresentation] = items.compactMap { item in
            let restaurant = item.restaurant
            guard restaurant.deletedAt == nil,
                  RestaurantMapCoordinatePolicy.isValid(
                    latitude: restaurant.latitude,
                    longitude: restaurant.longitude
                  ) else { return nil }

            let record = restaurant.remoteRecordData.flatMap {
                try? JSONDecoder().decode(RestaurantJSONContractV1.self, from: $0)
            }
            let referencedMarkerPhoto = trimmed(record?.markerPhotoId).flatMap {
                activePhotosByReference[$0.lowercased()]
            }.flatMap { photo in
                photo.restaurantId == restaurant.id && photo.kind == .restaurantMarker ? photo : nil
            }
            let localPhoto = referencedMarkerPhoto
                ?? item.photo.flatMap { photo in
                    isActive(photo) && photo.restaurantId == restaurant.id ? photo : nil
                }
            let visual: RestaurantMapMarkerVisual
            switch RestaurantImagePriorityPolicy.preferred(
                localUserPhotoID: localPhoto?.id,
                providerMerchantImageURL: record?.merchantImageUrl
            ) {
            case .localUserPhoto(let photoID):
                visual = .photo(photoID)
            case .providerMerchantImage(let url):
                visual = .merchantImage(url)
            case .publicOrCachedPhoto:
                // Local Map data resolves cached/public photos to PhotoAsset first.
                visual = .fallback
            case .foodDiningFallback:
                if let emoji = trimmed(record?.markerEmoji) {
                    visual = .emoji(emoji)
                } else {
                    visual = .fallback
                }
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
        return RestaurantMapMarkerCollisionPolicy.dispersed(markers)
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

/// MapKit collision avoidance without merging Restaurants into an aggregate.
/// Restaurants that share the same map coordinate are dispersed by a tiny,
/// deterministic offset so every Restaurant remains independently selectable
/// at every zoom level.
enum RestaurantMapMarkerCollisionPolicy {
    private struct CoordinateBucket: Hashable {
        let latitude: Int
        let longitude: Int
    }

    static func dispersed(
        _ markers: [RestaurantMapMarkerPresentation]
    ) -> [RestaurantMapMarkerPresentation] {
        let groups = Dictionary(grouping: markers) {
            CoordinateBucket(
                latitude: Int(($0.latitude * 100_000).rounded()),
                longitude: Int(($0.longitude * 100_000).rounded())
            )
        }
        var resolvedByID: [UUID: RestaurantMapMarkerPresentation] = [:]
        for group in groups.values {
            let ordered = group.sorted { $0.id.uuidString < $1.id.uuidString }
            guard ordered.count > 1 else {
                if let marker = ordered.first { resolvedByID[marker.id] = marker }
                continue
            }
            for (index, marker) in ordered.enumerated() {
                let angle = (Double(index) / Double(ordered.count)) * 2 * Double.pi
                let latitudeOffset = cos(angle) * 0.000_12
                let longitudeScale = max(0.2, cos(marker.latitude * Double.pi / 180))
                let longitudeOffset = sin(angle) * 0.000_12 / longitudeScale
                resolvedByID[marker.id] = RestaurantMapMarkerPresentation(
                    id: marker.id,
                    name: marker.name,
                    latitude: marker.latitude + latitudeOffset,
                    longitude: marker.longitude + longitudeOffset,
                    status: marker.status,
                    visual: marker.visual,
                    visitCount: marker.visitCount,
                    averageRating: marker.averageRating,
                    distanceKilometers: marker.distanceKilometers
                )
            }
        }
        return markers.compactMap { resolvedByID[$0.id] }
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

enum RestaurantMapRenderState: Equatable {
    case loading
    case ready
    case failed(String)
}
