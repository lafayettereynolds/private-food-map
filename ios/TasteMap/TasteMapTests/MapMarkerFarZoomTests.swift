import Foundation
import Testing
@testable import TasteMap

@Suite("Restaurant markers at national and worldwide scale")
struct MapMarkerFarZoomTests {
    @Test("Approved regional size stays intact, then shrinks continuously and reversibly")
    func continuousFarScale() {
        for span in [1.5, 2.0, 2.4] {
            let style = RestaurantMapMarkerDensityStyle.resolve(latitudeDelta: span)
            #expect(style.baseDiameter == 24)
            #expect(style.unvisitedIncrease == 4)
            #expect(style.selectionIncrease == 2)
        }
        let spans = [2.4, 2.40001, 4, 8, 15, 30, 50, 80]
        let styles = spans.map { RestaurantMapMarkerDensityStyle.resolve(latitudeDelta: $0) }
        for index in styles.indices.dropFirst() {
            #expect(styles[index].baseDiameter < styles[index - 1].baseDiameter)
            #expect(styles[index].regionalGroupingDistance == styles[0].regionalGroupingDistance)
        }
        #expect(styles[0].baseDiameter - styles[1].baseDiameter < 0.001)
        #expect(styles.last?.baseDiameter == 10)
        #expect(styles.last?.unvisitedIncrease == 1)
        #expect(styles.last?.selectionIncrease == 1)
        #expect(Array(spans.reversed().map {
            RestaurantMapMarkerDensityStyle.resolve(latitudeDelta: $0)
        }.reversed()) == styles)
        let midpoint = RestaurantMapMarkerDensityStyle.resolve(latitudeDelta: sqrt(2.4 * 80))
        #expect(abs(midpoint.baseDiameter - 17) < 0.000001)
        #expect(RestaurantMapMarkerDensityStyle.resolve(latitudeDelta: 180) == .world)
    }

    @Test("Pending remains slightly larger at every far scale and GPS never affects size")
    func pendingFarScale() {
        for span in [2.4, 8, 30, 80] {
            let style = RestaurantMapMarkerDensityStyle.resolve(latitudeDelta: span)
            for selected in [false, true] {
                let visited = RestaurantMapMarkerMetrics.diameter(
                    status: .visited, distanceKilometers: nil, isSelected: selected, densityStyle: style
                )
                for status: RestaurantMapMarkerStatus in [.wantToGo, .recommended] {
                    for distance: Double? in [nil, 0, 100, .nan] {
                        let pending = RestaurantMapMarkerMetrics.diameter(
                            status: status, distanceKilometers: distance, isSelected: selected, densityStyle: style
                        )
                        #expect(pending > visited)
                        #expect(abs(pending - visited - style.unvisitedIncrease) < 0.000001)
                    }
                }
            }
        }
    }
}
