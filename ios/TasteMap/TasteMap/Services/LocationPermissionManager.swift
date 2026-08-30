import Combine
import CoreLocation
import Foundation

enum RestaurantLocationError: Error, Equatable {
    case permissionDenied
    case unavailable
    case requestInProgress
    case staleOrInaccurate
}

@MainActor
protocol RestaurantLocationProviding: AnyObject {
    var authorizationStatus: CLAuthorizationStatus { get }
    var accuracyAuthorization: CLAccuracyAuthorization { get }
    func requestCurrentLocation() async throws -> CLLocation
}

enum RestaurantLocationFixPolicy {
    static let maximumAge: TimeInterval = 15
    static let maximumFutureSkew: TimeInterval = 5
    static let maximumPreciseHorizontalAccuracy: CLLocationAccuracy = 1_000
    static let maximumReducedHorizontalAccuracy: CLLocationAccuracy = 10_000

    static func isUsable(
        _ location: CLLocation,
        accuracyAuthorization: CLAccuracyAuthorization,
        now: Date = Date()
    ) -> Bool {
        guard CLLocationCoordinate2DIsValid(location.coordinate),
              location.horizontalAccuracy >= 0 else { return false }

        let age = now.timeIntervalSince(location.timestamp)
        guard age >= -maximumFutureSkew, age <= maximumAge else { return false }

        let maximumAccuracy = accuracyAuthorization == .reducedAccuracy
            ? maximumReducedHorizontalAccuracy
            : maximumPreciseHorizontalAccuracy
        return location.horizontalAccuracy <= maximumAccuracy
    }
}

@MainActor
final class LocationPermissionManager: NSObject, ObservableObject, CLLocationManagerDelegate, RestaurantLocationProviding {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var isLocating = false

    private let locationManager: CLLocationManager
    private var continuation: CheckedContinuation<CLLocation, Error>?
    private var timeoutTask: Task<Void, Never>?

    override init() {
        let locationManager = CLLocationManager()
        self.locationManager = locationManager
        authorizationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = kCLDistanceFilterNone
    }

    var accuracyAuthorization: CLAccuracyAuthorization {
        locationManager.accuracyAuthorization
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
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
                    beginFreshLocationRequest()
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finish(with: .failure(CancellationError()))
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if continuation != nil { beginFreshLocationRequest() }
        case .denied, .restricted:
            finish(with: .failure(RestaurantLocationError.permissionDenied))
        case .notDetermined:
            break
        @unknown default:
            finish(with: .failure(RestaurantLocationError.unavailable))
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.reversed().first(where: {
            RestaurantLocationFixPolicy.isUsable(
                $0,
                accuracyAuthorization: manager.accuracyAuthorization
            )
        }) else { return }
        currentLocation = location
        finish(with: .success(location))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let locationError = error as? CLError, locationError.code == .locationUnknown {
            return
        }
        finish(with: .failure(error))
    }

    private func beginFreshLocationRequest() {
        timeoutTask?.cancel()
        locationManager.startUpdatingLocation()
        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled else { return }
            self?.finish(with: .failure(RestaurantLocationError.staleOrInaccurate))
        }
    }

    private func finish(with result: Result<CLLocation, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        locationManager.stopUpdatingLocation()
        isLocating = false
        continuation.resume(with: result)
    }
}
