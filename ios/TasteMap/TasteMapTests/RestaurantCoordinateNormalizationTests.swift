import Foundation
import Testing
@testable import TasteMap

@Suite("Explicit acquisition coordinate references")
struct RestaurantCoordinateNormalizationTests {
    // Synthetic public-area fixture, never a recorded user location.
    private let gps = RestaurantCoordinate(latitude: 30.22, longitude: 120.17, reference: .wgs84)

    @Test func matchingReferencesDoNotMove() {
        let map = RestaurantCoordinateNormalization.gcj02(from: gps)
        #expect(RestaurantCoordinateNormalization.gcj02(from: map) == map)
        let (a, b) = RestaurantCoordinateNormalization.comparable(gps, gps)
        #expect(a == gps && b == gps)
        #expect(map.reference == .gcj02)
        #expect(gps.latitude == 30.22 && gps.longitude == 120.17)
    }

    @Test func mixedReferencesDescribeTheSamePointSymmetrically() {
        let map = RestaurantCoordinateNormalization.gcj02(from: gps)
        #expect(RestaurantDistanceOrdering.distance(from: gps, to: map) < 0.01)
        #expect(RestaurantDistanceOrdering.distance(from: map, to: gps) < 0.01)
        let bare = RestaurantCoordinate(latitude: map.latitude, longitude: map.longitude)
        #expect(RestaurantDistanceOrdering.distance(from: gps, to: bare) > 400)
    }

    @Test func repeatedRankingPreservesReferenceAndDistanceWithoutMutatingCoordinates() {
        let map = RestaurantCoordinateNormalization.gcj02(from: gps)
        let close = RestaurantCandidate(name: "公开区域测试近店", address: "", latitude: map.latitude + 0.0005,
            longitude: map.longitude, coordinateReference: .gcj02)
        let far = RestaurantCandidate(name: "公开区域测试远店", address: "", latitude: map.latitude + 0.005,
            longitude: map.longitude, coordinateReference: .gcj02)
        let first = RestaurantDistanceOrdering.measuringAndSorting([far, close], from: gps)
        let second = RestaurantDistanceOrdering.measuringAndSorting(first, from: gps)
        #expect(first == second)
        #expect(first.first?.id == close.id)
        #expect(first.first?.coordinateReference == .gcj02)
        #expect(first.first?.latitude == close.latitude)
        #expect((first.first?.distanceMeters ?? .infinity) < 60)
    }

    @Test func unspecifiedLegacyCoordinatesAreNeverConverted() {
        let legacy = RestaurantCoordinate(latitude: 30.22, longitude: 120.17)
        #expect(RestaurantCoordinateNormalization.gcj02(from: legacy) == legacy)
        let candidate = RestaurantCandidate(name: "旧记录", address: "", latitude: 30.22, longitude: 120.17)
        #expect(candidate.coordinateReference == .unspecified)
        #expect(RestaurantDistanceOrdering.measuringAndSorting([candidate], from: legacy).first?.latitude == candidate.latitude)
    }

    @Test func countryPolicyDoesNotUseLanguageOrTreatHongKongMacaoTaiwanAsMainland() {
        #expect(RestaurantCoordinateNormalization.mapKitReference(countryCode: "CN") == .gcj02)
        for country in ["HK", "MO", "TW", "JP", "US"] {
            #expect(RestaurantCoordinateNormalization.mapKitReference(countryCode: country) == .wgs84)
        }
        #expect(RestaurantCoordinateNormalization.mapKitReference(countryCode: "") == nil)
        #expect(RestaurantCoordinateNormalization.mapKitReference(countryCode: "杭州") == nil)
        #expect(RestaurantCoordinateNormalization.mapKitReference(countryCode: "ZZ") == nil)
    }

    @Test func alreadyConvertedQueryOriginMatchesCandidateOrigin() {
        let map = RestaurantCoordinateNormalization.gcj02(from: gps)
        let close = RestaurantCandidate(name: "同源近店", address: "", latitude: map.latitude,
            longitude: map.longitude, coordinateReference: .gcj02)
        let fromGPS = RestaurantNearbySearchPolicy.merge([[close]], from: gps, radiusMeters: 100)
        let fromProvider = RestaurantNearbySearchPolicy.merge([[close]], from: map, radiusMeters: 100)
        #expect(fromGPS.count == 1 && fromProvider.count == 1)
        #expect(abs((fromGPS.first?.distanceMeters ?? -1) - (fromProvider.first?.distanceMeters ?? -2)) < 0.01)
    }

    @Test func foreignGPSIsNeverShiftedWhenComparedWithAMainlandProviderPoint() {
        let mainland = RestaurantCoordinateNormalization.gcj02(from: gps)
        for foreign in [RestaurantCoordinate(latitude: 22.3193, longitude: 114.1694, reference: .wgs84),
                        RestaurantCoordinate(latitude: 35.68, longitude: 139.76, reference: .wgs84)] {
            let (first, second) = RestaurantCoordinateNormalization.comparable(foreign, mainland)
            #expect(first == foreign)
            #expect(second.reference == .wgs84)
            #expect(abs(RestaurantDistanceOrdering.distance(from: foreign, to: mainland)
                - RestaurantDistanceOrdering.distance(from: mainland, to: foreign)) < 0.01)
        }
    }
}
