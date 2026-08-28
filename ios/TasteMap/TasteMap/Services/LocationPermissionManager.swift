import Combine
import CoreLocation
import Foundation

enum RestaurantLocationError: Error, Equatable {
    case permissionDenied
    case unavailable
    case requestInProgress
}

@MainActor
protocol RestaurantLocationProviding: AnyObject {
    var authorizationStatus: CLAuthorizationStatus { get }
    func requestCurrentLocation() async throws -> CLLocation
}

@MainActor
final class LocationPermissionManager: NSObject, ObservableObject, CLLocationManagerDelegate, RestaurantLocationProviding {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var isLocating = false

    private let locationManager: CLLocationManager
    private var continuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        let locationManager = CLLocationManager()
        self.locationManager = locationManager
        authorizationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
    }

    var isDeniedOrRestricted: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    func requestWhenInUseAuthorizationIfNeeded() {
        guard authorizationStatus == .notDetermined else { return }
        locationManager.requestWhenInUseAuthorization()
    }

    func requestCurrentLocation() async throws -> CLLocation {
        guard continuation == nil else { throw RestaurantLocationError.requestInProgress }
        switch authorizationStatus {
        case .denied, .restricted:
            throw RestaurantLocationError.permissionDenied
        case .authorizedAlways, .authorizedWhenInUse:
            break
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        @unknown default:
            throw RestaurantLocationError.unavailable
        }

        isLocating = true
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
                locationManager.requestLocation()
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if continuation != nil { manager.requestLocation() }
        case .denied, .restricted:
            finish(with: .failure(RestaurantLocationError.permissionDenied))
        case .notDetermined:
            break
        @unknown default:
            finish(with: .failure(RestaurantLocationError.unavailable))
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            finish(with: .failure(RestaurantLocationError.unavailable))
            return
        }
        currentLocation = location
        finish(with: .success(location))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(with: .failure(error))
    }

    private func finish(with result: Result<CLLocation, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        isLocating = false
        continuation.resume(with: result)
    }
}
