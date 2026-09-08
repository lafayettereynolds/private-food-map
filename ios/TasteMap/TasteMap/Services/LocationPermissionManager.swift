import Combine
import CoreLocation
import Foundation

enum RestaurantLocationError: Error, Equatable {
    case permissionDenied
    case unavailable
    case requestInProgress
    case staleOrInaccurate
    case preciseLocationRequired
}

@MainActor
protocol RestaurantLocationProviding: AnyObject {
    var authorizationStatus: CLAuthorizationStatus { get }
    var accuracyAuthorization: CLAccuracyAuthorization { get }
    func requestCurrentLocation() async throws -> CLLocation
}

/// Map and Add can overlap while a fresh sensor request is still running.
/// Share that in-flight request only; the next request must acquire a new fix.
@MainActor
final class RestaurantLocationRequestCoordinator {
    private var pending: Task<CLLocation, Error>?

    func request(_ acquire: @escaping @MainActor () async throws -> CLLocation) async throws -> CLLocation {
        if let pending { return try await pending.value }
        let task = Task { try await acquire() }
        pending = task
        defer { pending = nil }
        return try await task.value
    }
}

enum RestaurantLocationFixPolicy {
    static let maximumAge: TimeInterval = 15
    static let maximumFutureSkew: TimeInterval = 5
    static let preferredPreciseHorizontalAccuracy: CLLocationAccuracy = 50
    static let maximumPreciseHorizontalAccuracy: CLLocationAccuracy = 100
    static let maximumReducedHorizontalAccuracy: CLLocationAccuracy = 10_000
    static let preciseFixSettlingDuration: Duration = .seconds(3)
    // Core Location may first replay an accurate *cached* position. That is
    // reusable by text search, but not proof of a newly requested Nearby fix.
    static let requestTimestampTolerance: TimeInterval = 1

    static func belongsToRequest(_ location: CLLocation, startedAt: Date) -> Bool {
        location.timestamp >= startedAt.addingTimeInterval(-requestTimestampTolerance)
    }

    /// Recheck at delivery, not only when Core Location first calls back. A
    /// settling/timeout task may resume much later after the App was suspended.
    static func isUsableForDelivery(
        _ location: CLLocation,
        startedAt: Date,
        accuracyAuthorization: CLAccuracyAuthorization,
        now: Date = Date()
    ) -> Bool {
        belongsToRequest(location, startedAt: startedAt)
            && isUsable(location, accuracyAuthorization: accuracyAuthorization, now: now)
    }

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

    static func isPreferred(
        _ location: CLLocation,
        accuracyAuthorization: CLAccuracyAuthorization,
        now: Date = Date()
    ) -> Bool {
        guard isUsable(
            location,
            accuracyAuthorization: accuracyAuthorization,
            now: now
        ) else { return false }
        if accuracyAuthorization == .reducedAccuracy { return true }
        return location.horizontalAccuracy <= preferredPreciseHorizontalAccuracy
    }

    static func bestUsableLocation(
        in locations: [CLLocation],
        comparedWith current: CLLocation?,
        accuracyAuthorization: CLAccuracyAuthorization,
        now: Date = Date()
    ) -> CLLocation? {
        let candidates = ([current].compactMap { $0 } + locations).filter {
            isUsable($0, accuracyAuthorization: accuracyAuthorization, now: now)
        }
        return candidates.min { left, right in
            if left.horizontalAccuracy != right.horizontalAccuracy {
                return left.horizontalAccuracy < right.horizontalAccuracy
            }
            return left.timestamp > right.timestamp
        }
    }
}

/// Text search may reuse a precise fix, but an expired accepted fix means
/// "refresh the origin", not "silently forget location for the rest of the page".
/// The injected provider already has a bounded request timeout. A failure never
/// prevents the independent city/name query from proceeding without GPS bias.
@MainActor
enum RestaurantSearchLocationPolicy {
    static func location(
        accepted: CLLocation?,
        authorizationStatus: CLAuthorizationStatus,
        accuracyAuthorization: CLAccuracyAuthorization,
        now: () -> Date = { Date() },
        refresh: () async throws -> CLLocation
    ) async -> CLLocation? {
        guard let accepted,
              authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse,
              accuracyAuthorization == .fullAccuracy else { return nil }
        if RestaurantLocationFixPolicy.isUsable(accepted, accuracyAuthorization: .fullAccuracy, now: now()) {
            return accepted
        }
        guard let updated = try? await refresh(), !Task.isCancelled,
              RestaurantLocationFixPolicy.isUsable(updated, accuracyAuthorization: .fullAccuracy, now: now()) else { return nil }
        return updated
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
    private var preciseFixSettlingTask: Task<Void, Never>?
    private var bestUsableLocation: CLLocation?
    private var requestID: UUID?
    private var requestStartedAt: Date?

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

        let requestID = UUID()
        self.requestID = requestID
        isLocating = true
        bestUsableLocation = nil
        preciseFixSettlingTask?.cancel()
        preciseFixSettlingTask = nil
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
                    beginFreshLocationRequest()
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.requestID == requestID else { return }
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
        guard continuation != nil, let requestStartedAt else { return }
#if DEBUG
        for location in locations {
            RestaurantAcquisitionDebugTrace.record("location_callback", location: location, fields: [
                "belongsToRequest": RestaurantLocationFixPolicy.belongsToRequest(location, startedAt: requestStartedAt),
                "accuracyAuthorization": manager.accuracyAuthorization == .fullAccuracy ? "full" : "reduced",
            ])
        }
#endif
        guard let location = RestaurantLocationFixPolicy.bestUsableLocation(
            in: locations.filter { RestaurantLocationFixPolicy.belongsToRequest($0, startedAt: requestStartedAt) },
            comparedWith: bestUsableLocation,
            accuracyAuthorization: manager.accuracyAuthorization
        ) else { return }
        bestUsableLocation = location

        if RestaurantLocationFixPolicy.isPreferred(
            location,
            accuracyAuthorization: manager.accuracyAuthorization
        ) {
            finish(with: .success(location))
            return
        }

        guard preciseFixSettlingTask == nil else { return }
        preciseFixSettlingTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: RestaurantLocationFixPolicy.preciseFixSettlingDuration)
            guard !Task.isCancelled, let self, let location = self.bestUsableLocation else { return }
            self.finish(with: .success(location))
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let locationError = error as? CLError, locationError.code == .locationUnknown {
            return
        }
        if let bestUsableLocation {
            finish(with: .success(bestUsableLocation))
            return
        }
        finish(with: .failure(error))
    }

    private func beginFreshLocationRequest() {
        guard requestStartedAt == nil else { return }
        timeoutTask?.cancel()
        requestStartedAt = Date()
        locationManager.startUpdatingLocation()
        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            if let bestUsableLocation = self.bestUsableLocation {
                self.finish(with: .success(bestUsableLocation))
            } else {
                self.finish(with: .failure(RestaurantLocationError.staleOrInaccurate))
            }
        }
    }

    private func finish(with result: Result<CLLocation, Error>) {
        guard let continuation else { return }
        let deliveredResult = result.flatMap { location -> Result<CLLocation, Error> in
            guard let requestStartedAt,
                  RestaurantLocationFixPolicy.isUsableForDelivery(
                    location, startedAt: requestStartedAt,
                    accuracyAuthorization: locationManager.accuracyAuthorization
                  ) else { return .failure(RestaurantLocationError.staleOrInaccurate) }
            return .success(location)
        }
        self.continuation = nil
        requestID = nil
        requestStartedAt = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        preciseFixSettlingTask?.cancel()
        preciseFixSettlingTask = nil
        locationManager.stopUpdatingLocation()
        if case .success(let location) = deliveredResult {
            currentLocation = location
#if DEBUG
            RestaurantAcquisitionDebugTrace.record("accepted_location", location: location)
#endif
        }
        bestUsableLocation = nil
        isLocating = false
        continuation.resume(with: deliveredResult)
    }
}

#if DEBUG
/// Explicit, temporary real-device diagnostics. No persistent logging, no
/// credentials/owner IDs, no test GPS, and no Release implementation.
enum RestaurantAcquisitionDebugTrace {
    static func record(_ event: String, location: CLLocation, fields: [String: Any] = [:]) {
        guard ProcessInfo.processInfo.environment["TASTEMAP_LOCATION_DIAGNOSTICS"] == "1" else { return }
        var value = fields
        value["event"] = event
        value["latitude"] = location.coordinate.latitude
        value["longitude"] = location.coordinate.longitude
        value["ageSeconds"] = Date().timeIntervalSince(location.timestamp)
        value["horizontalAccuracy"] = location.horizontalAccuracy
        value["simulatedBySoftware"] = location.sourceInformation?.isSimulatedBySoftware ?? false
        value["producedByAccessory"] = location.sourceInformation?.isProducedByAccessory ?? false
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return }
        print("TasteMapLocationTrace \(text)")
    }
}
#endif
