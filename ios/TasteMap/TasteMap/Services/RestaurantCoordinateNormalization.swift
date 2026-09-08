import Foundation

/// Explicit conversion for a verified GCJ-02 consumer. This is
/// not a location improvement, a map-marker offset, or a storage migration.
/// Country/provider selection belongs to the provider boundary, not this math.
enum RestaurantCoordinateNormalization {
    static func gcj02(from point: RestaurantCoordinate) -> RestaurantCoordinate {
        guard point.reference == .wgs84, point.isValid else { return point }
        let x = point.longitude - 105, y = point.latitude - 35
        let pi = Double.pi
        var north = -100 + 2*x + 3*y + 0.2*y*y + 0.1*x*y + 0.2*sqrt(abs(x))
        north += (20*sin(6*x*pi) + 20*sin(2*x*pi))*2/3
        north += (20*sin(y*pi) + 40*sin(y*pi/3))*2/3
        north += (160*sin(y*pi/12) + 320*sin(y*pi/30))*2/3
        var east = 300 + x + 2*y + 0.1*x*x + 0.1*x*y + 0.1*sqrt(abs(x))
        east += (20*sin(6*x*pi) + 20*sin(2*x*pi))*2/3
        east += (20*sin(x*pi) + 40*sin(x*pi/3))*2/3
        east += (150*sin(x*pi/12) + 300*sin(x*pi/30))*2/3
        let axis = 6_378_245.0, eccentricity = 0.00669342162296594323
        let latitudeRadians = point.latitude*pi/180
        let factor = 1 - eccentricity*pow(sin(latitudeRadians), 2)
        let root = sqrt(factor)
        let latitude = point.latitude + north*180/(axis*(1-eccentricity)/(factor*root)*pi)
        let longitude = point.longitude + east*180/(axis/root*cos(latitudeRadians)*pi)
        return RestaurantCoordinate(latitude: latitude, longitude: longitude, reference: .gcj02)
    }

    /// The current mainland MapKit provider contract was measured against real
    /// device fixes and public query endpoints, not promised by Apple's generic
    /// CLLocation documentation. Never select it from UI city, language, IP or a
    /// coarse rectangular China test. Unknown country fails at the boundary.
    static func mapKitReference(countryCode: String) -> RestaurantCoordinateReference? {
        let country = countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard Locale.Region.isoRegions.contains(where: { $0.identifier == country }) else { return nil }
        return country == "CN" ? .gcj02 : .wgs84
    }

    /// Normalize the known mainland provider point, not a possibly overseas GPS
    /// endpoint. Only transient calculation values change; source data does not.
    static func wgs84(from point: RestaurantCoordinate) -> RestaurantCoordinate {
        guard point.reference == .gcj02, point.isValid else { return point }
        var result = RestaurantCoordinate(latitude: point.latitude, longitude: point.longitude, reference: .wgs84)
        for _ in 0..<5 {
            let forward = gcj02(from: result)
            result = RestaurantCoordinate(latitude: result.latitude + point.latitude - forward.latitude,
                longitude: result.longitude + point.longitude - forward.longitude, reference: .wgs84)
        }
        return result
    }

    static func comparable(_ first: RestaurantCoordinate, _ second: RestaurantCoordinate)
        -> (RestaurantCoordinate, RestaurantCoordinate) {
        if first.reference != .unspecified && second.reference != .unspecified {
            return (wgs84(from: first), wgs84(from: second))
        }
        // Legacy/provider-only points retain their existing numerical semantics.
        // Unspecified never constitutes permission to convert persisted data.
        return (first, second)
    }
}
