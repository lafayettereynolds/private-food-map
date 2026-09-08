import CoreLocation
import Foundation
import Testing
@testable import TasteMap

@Suite("GPS delivery-time validation")
@MainActor
struct LocationDeliveryPolicyTests {
    @Test("An initially usable best fix is rejected when a suspended settling or timeout task delivers it late")
    func suspendedDeliveryRejectsExpiredFix() {
        let startedAt = Date(timeIntervalSince1970: 2_000_000_000)
        let fix = location(timestamp: startedAt, accuracy: 80)
        #expect(RestaurantLocationFixPolicy.isUsableForDelivery(fix, startedAt: startedAt,
            accuracyAuthorization: .fullAccuracy, now: startedAt.addingTimeInterval(3)))
        #expect(!RestaurantLocationFixPolicy.isUsableForDelivery(fix, startedAt: startedAt,
            accuracyAuthorization: .fullAccuracy, now: startedAt.addingTimeInterval(30)))
    }

    @Test("Delivery rechecks the current precision authorization instead of retaining a prior reduced-accuracy success")
    func changedPrecisionRequiresRevalidation() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let coarse = location(timestamp: now, accuracy: 5_000)
        #expect(RestaurantLocationFixPolicy.isUsableForDelivery(coarse, startedAt: now,
            accuracyAuthorization: .reducedAccuracy, now: now))
        #expect(!RestaurantLocationFixPolicy.isUsableForDelivery(coarse, startedAt: now,
            accuracyAuthorization: .fullAccuracy, now: now))
    }

    @Test("A recent fix from a previous request cannot be delivered as the new request")
    func oldRequestCannotDeliver() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        #expect(!RestaurantLocationFixPolicy.isUsableForDelivery(location(timestamp: now.addingTimeInterval(-5), accuracy: 10),
            startedAt: now, accuracyAuthorization: .fullAccuracy, now: now))
    }

    private func location(timestamp: Date, accuracy: CLLocationAccuracy) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: 1, longitude: 1), altitude: 0,
            horizontalAccuracy: accuracy, verticalAccuracy: 1, timestamp: timestamp)
    }
}
