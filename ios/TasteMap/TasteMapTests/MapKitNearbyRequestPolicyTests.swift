import MapKit
import Testing
@testable import TasteMap

@Suite("Local nearby provider request policy")
struct MapKitNearbyRequestPolicyTests {
    @Test("The local keyword supplement is centered on the supplied fix and constrains provider ranking")
    func localRequestPreservesOriginAndBoundary() {
        let origin = RestaurantCoordinate(latitude: 35.68, longitude: 139.76)
        let request = RestaurantNearbySearchPolicy.keywordRequest(
            matching: RestaurantNearbySearchPolicy.keywords[0],
            center: origin,
            radiusMeters: 500,
            requiresRegion: true
        )
        #expect(request.naturalLanguageQuery == "餐厅")
        #expect(request.resultTypes == .pointOfInterest)
        #expect(request.region.center.latitude == origin.latitude)
        #expect(request.region.center.longitude == origin.longitude)
        #expect(request.region.span.latitudeDelta < 0.011)
        #expect(request.region.span.longitudeDelta < 0.014)
        if #available(iOS 18.0, *) {
            #expect(request.regionPriority == .required)
        }
    }

    @Test("Local text results join the same identity deduplication, real distance order and hard cutoff")
    func localSupplementPrecedesMoreDistantResults() {
        let origin = RestaurantCoordinate(latitude: 35.68, longitude: 139.76)
        let broad = RestaurantCandidate(name: "测试远店", address: "", latitude: 35.685,
            longitude: 139.76, appleMapItemIdentifier: "public-far")
        let local = RestaurantCandidate(name: "测试近店", address: "", latitude: 35.6803,
            longitude: 139.76, appleMapItemIdentifier: "public-close")
        let outside = RestaurantCandidate(name: "测试范围外店", address: "", latitude: 35.73,
            longitude: 139.76, appleMapItemIdentifier: "public-outside")
        let results = RestaurantNearbySearchPolicy.merge([[broad], [local, broad, outside]],
            from: origin, radiusMeters: 3_000)
        #expect(results.map(\.name) == ["测试近店", "测试远店"])
        #expect(results.allSatisfy { ($0.distanceMeters ?? .infinity) <= 3_000 })
    }
}
