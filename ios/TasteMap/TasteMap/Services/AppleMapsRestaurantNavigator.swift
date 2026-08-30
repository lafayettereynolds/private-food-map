import CoreLocation
import MapKit

@MainActor
protocol RestaurantNavigating {
    @discardableResult
    func openInAppleMaps(_ restaurant: Restaurant) -> Bool
}

struct AppleMapsRestaurantNavigator: RestaurantNavigating {
    func mapItem(for restaurant: Restaurant) -> MKMapItem {
        let location = CLLocation(
            latitude: restaurant.latitude,
            longitude: restaurant.longitude
        )
        let mapItem: MKMapItem
        if #available(iOS 26.0, *) {
            mapItem = MKMapItem(location: location, address: nil)
        } else {
            mapItem = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
        }
        mapItem.name = restaurant.name
        return mapItem
    }

    @discardableResult
    func openInAppleMaps(_ restaurant: Restaurant) -> Bool {
        mapItem(for: restaurant).openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault,
        ])
    }
}
