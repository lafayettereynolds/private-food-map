import CoreGraphics
import Testing
@testable import TasteMap

@Suite("Hybrid Map surface CSS-to-native geometry")
struct HybridMapSurfaceGeometryTests {
    @Test("A different WebKit viewport height never compresses the map or its React cutout")
    func viewportHeightDoesNotDistortGeometry() {
        let webFrame = CGRect(x: 0, y: 0, width: 402, height: 874)
        let map = TasteMapHybridMapSurfaceRect(x: 0, y: 207, width: 402, height: 667)
        let add = TasteMapHybridMapSurfaceRect(x: 150, y: 754, width: 102, height: 43)
        let projectedMap = TasteMapHybridMapSurfaceGeometry.project(map, viewportWidth: 402, webFrame: webFrame)
        let projectedAdd = TasteMapHybridMapSurfaceGeometry.project(add, viewportWidth: 402, webFrame: webFrame)
        #expect(projectedMap == CGRect(x: 0, y: 207, width: 402, height: 667))
        #expect(projectedMap.maxY == webFrame.maxY)
        #expect(projectedAdd == CGRect(x: 150, y: 754, width: 102, height: 43))
        // The former separate Y ratio made an expanded layout viewport look
        // like the reported half-height canvas, with its cutout far above CTA.
        let oldYRatio = webFrame.height / 1750
        #expect(abs(CGFloat(map.y + map.height) * oldYRatio - projectedMap.maxY) > 400)
        #expect(abs(CGFloat(add.y) * oldYRatio - projectedAdd.minY) > 350)
    }

    @Test("Pinch/focus visual coordinates use one scale and respect the Native container origin")
    func zoomedViewportAndContainerOrigin() {
        let webFrame = CGRect(x: 8, y: 62, width: 402, height: 780)
        let add = TasteMapHybridMapSurfaceRect(x: 132, y: 614, width: 102, height: 43)
        let projected = TasteMapHybridMapSurfaceGeometry.project(add, viewportWidth: 201, webFrame: webFrame)
        #expect(projected == CGRect(x: 272, y: 1290, width: 204, height: 86))
        #expect(projected.width / CGFloat(add.width) == projected.height / CGFloat(add.height))
        let restored = TasteMapHybridMapSurfaceGeometry.project(add, viewportWidth: 402, webFrame: CGRect(x: 0, y: 0, width: 402, height: 874))
        #expect(restored == CGRect(x: 132, y: 614, width: 102, height: 43))
    }
}
