import MapKit
import Testing
import UIKit
@testable import TasteMap

#if DEBUG
/// Opt-in diagnostic experiment, not a replacement for the Hybrid <= 1 pt
/// acceptance test. The animated samples are retained even when they disagree.
@Suite("MapKit frame/projection diagnostic", .serialized)
@MainActor
struct MapMarkerFrameDiagnosticsTests {
    @Test("Controlled camera animation records model and presentation independently",
          .enabled(if: ProcessInfo.processInfo.environment["TASTEMAP_MAP_FRAME_DIAGNOSTICS"] == "1"))
    func controlledAnimationFrameProbe() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            previousKeyWindow?.makeKey()
        }
        let map = MKMapView(frame: CGRect(x: 0, y: 207, width: 402, height: 667))
        map.isPitchEnabled = false
        map.isRotateEnabled = false
        let coordinate = CLLocationCoordinate2D(latitude: 30.274260, longitude: 120.155000)
        let marker = RestaurantMapMarkerPresentation(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000032017")!,
            name: "公开坐标动画诊断", latitude: coordinate.latitude, longitude: coordinate.longitude,
            status: .visited, visual: .category(.other), recommendationRank: nil,
            visitCount: 4, averageRating: 4, distanceKilometers: nil
        )
        let delegate = FrameProbeMapDelegate(marker: marker)
        map.delegate = delegate
        controller.view.addSubview(map)
        let annotation = MKPointAnnotation()
        annotation.coordinate = coordinate
        map.setRegion(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 30.274120, longitude: 120.155140),
            span: MKCoordinateSpan(latitudeDelta: 0.045896, longitudeDelta: 0.033750)
        ), animated: false)
        map.addAnnotation(annotation)
        // Layout/visibility readiness is for this isolated experiment only;
        // the original pan test's gesture and wait contract stays untouched.
        for _ in 0..<90 {
            if let view = delegate.markerView, view.window != nil,
               view.qaFrameSample(in: map).anchorError <= 1 { break }
            try await Task.sleep(for: .milliseconds(16))
        }
        let view = try #require(delegate.markerView)
        let baseline = view.qaFrameSample(in: map)
        print("TASTEMAP_MAP_FRAME_PROBE baseline \(baseline.diagnostic)")
        #expect(baseline.anchorError <= 1)
        map.setRegion(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 30.280120, longitude: 120.163140),
            span: map.region.span
        ), animated: true)
        var samples: [RestaurantMapMarkerFrameSample] = []
        for index in 0..<120 {
            let sample = view.qaFrameSample(in: map)
            samples.append(sample)
            print("TASTEMAP_MAP_FRAME_PROBE frame=\(index) \(sample.diagnostic)")
            try await Task.sleep(for: .milliseconds(16))
        }
        let final = try #require(samples.last)
        print("TASTEMAP_MAP_FRAME_PROBE summary samples=\(samples.count) maxModelError=\(samples.map(\.anchorError).max() ?? 0) maxProjectionReadDrift=\(samples.map(\.projectionReadDrift).max() ?? 0)")
        #expect(samples.count == 120)
        #expect(samples.contains { $0.presented != nil })
        #expect(final.anchorError <= 1)
        #expect(annotation.coordinate.latitude == coordinate.latitude)
        #expect(annotation.coordinate.longitude == coordinate.longitude)
        #expect(view.centerOffset == .zero)
        #expect(view.bounds.size == CGSize(width: 44, height: 44))
    }
}

@MainActor
private final class FrameProbeMapDelegate: NSObject, MKMapViewDelegate {
    let marker: RestaurantMapMarkerPresentation
    var markerView: RestaurantMarkerAnnotationView?

    init(marker: RestaurantMapMarkerPresentation) { self.marker = marker }

    func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
        let view = RestaurantMarkerAnnotationView(annotation: annotation, reuseIdentifier: "frame-probe")
        _ = view.configure(marker)
        view.setDensityStyle(.resolve(latitudeDelta: mapView.region.span.latitudeDelta))
        view.setLayerPriority(rank: 8, count: 18)
        view.displayPriority = .required
        markerView = view
        return view
    }
}
#endif
