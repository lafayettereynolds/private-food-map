import CoreGraphics
import Foundation
import MapKit
import Testing
@testable import TasteMap

@Suite("Map marker viewport and membership stability")
struct MapMarkerViewportStabilityTests {
    @Test("A north/south Mercator pan keeps marker size and grouping scale")
    func mercatorPanDoesNotChangeMarkerScale() {
        let mapHeight = MKMapSize.world.height / 360 * 2.4
        let projectedSize = CGSize(width: mapHeight * 0.5, height: mapHeight)
        let viewportSize = CGSize(width: 390, height: 780)
        func latitudeSpan(at latitude: Double) -> Double {
            let center = MKMapPoint(CLLocationCoordinate2D(latitude: latitude, longitude: 120))
            return MKMapPoint(x: center.x, y: center.y - mapHeight / 2).coordinate.latitude
                - MKMapPoint(x: center.x, y: center.y + mapHeight / 2).coordinate.latitude
        }
        let equatorSpan = latitudeSpan(at: 0)
        let northernSpan = latitudeSpan(at: 60)
        #expect(abs(equatorSpan - northernSpan) > 1)
        // This difference caused the old current-region code to resize and
        // regroup Restaurants even though every projected distance was fixed.
        #expect(RestaurantMapMarkerDensityStyle.groupingProgress(latitudeDelta: equatorSpan)
            != RestaurantMapMarkerDensityStyle.groupingProgress(latitudeDelta: northernSpan))
        var scale = RestaurantMapMarkerViewportScale()
        let initial = scale.resolve(latitudeDelta: equatorSpan, projectedSize: projectedSize, viewportSize: viewportSize)
        let revision = scale.revision
        for latitude in [30.0, 60.0, 30.0, 0.0] {
            let panned = scale.resolve(latitudeDelta: latitudeSpan(at: latitude), projectedSize: projectedSize, viewportSize: viewportSize)
            #expect(panned == initial)
            #expect(scale.revision == revision)
        }
    }

    @Test("Actual zoom and viewport resize still advance continuously and restore the regional baseline")
    func zoomAndResizeAdvanceScale() {
        var scale = RestaurantMapMarkerViewportScale()
        let viewport = CGSize(width: 390, height: 780)
        for span in [2.4, 8, 30, 80, 30, 8, 2.4] {
            let resolved = scale.resolve(latitudeDelta: span, projectedSize: CGSize(width: span * 100, height: span * 200), viewportSize: viewport)
            #expect(resolved == span)
            #expect(RestaurantMapMarkerDensityStyle.resolve(latitudeDelta: resolved)
                == RestaurantMapMarkerDensityStyle.resolve(latitudeDelta: span))
        }
        #expect(scale.resolve(latitudeDelta: 1.2, projectedSize: CGSize(width: 240, height: 480), viewportSize: CGSize(width: 390, height: 390)) == 1.2)
    }

    @Test("A retained exact-coordinate group resolves current images, status and name without a camera change")
    func membershipDoesNotRetainStalePresentation() throws {
        let first = marker(1, name: "Front", status: .visited, visual: .emoji("🍜"))
        let second = marker(2, name: "Old back", status: .wantToGo, visual: .emoji("☕️"))
        let snapshot = RestaurantMapRegionalGroupingSnapshot(groups: [[first, second]])
        var current = [first.id: first, second.id: second]
        #expect(snapshot.members(for: first.id) { current[$0] } == [first, second])
        let updated = marker(2, name: "Updated back", status: .visited, visual: .photo(UUID()))
        current[second.id] = updated
        let members = try #require(snapshot.members(for: first.id) { current[$0] })
        #expect(members == [first, updated])
        #expect(members[1].imageResolution == updated.imageResolution)
        #expect(snapshot.visibleRepresentativeIDs == [first.id])
        #expect(members.allSatisfy { $0.latitude == 30.27 && $0.longitude == 120.15 })
        current[second.id] = nil
        #expect(snapshot.members(for: first.id) { current[$0] } == [first])
    }

    private func marker(_ value: Int, name: String, status: RestaurantMapMarkerStatus, visual: RestaurantMapMarkerVisual) -> RestaurantMapMarkerPresentation {
        RestaurantMapMarkerPresentation(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!,
            name: name, latitude: 30.27, longitude: 120.15, status: status,
            visual: visual, visitCount: 1, averageRating: 4.5, distanceKilometers: nil
        )
    }
}
