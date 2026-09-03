import Combine
import Foundation
import SwiftUI
import UIKit
import WebKit

@MainActor
struct TasteMapHybridMapSurfaceResources {
    let photosByID: [UUID: PhotoAsset]
    let userAvatarPhoto: PhotoAsset?
    let photoCoordinator: PhotoTransferCoordinator
    let photoAPI: any PhotoBinaryAPI
}

/// Owns one persistent presentation of the established RestaurantMapView.
/// React owns the page chrome; this host owns only the rectangle occupied by
/// the Native MapKit surface and cuts holes for React controls over that area.
@MainActor
final class TasteMapHybridMapSurfaceHost {
    private weak var parent: UIViewController?
    private weak var webView: WKWebView?
    private weak var runtime: TasteMapHybridRuntime?
    private let model: TasteMapHybridMapSurfaceModel
    private let overlay = TasteMapHybridMapOverlayView()
    private let accessibilityProbe = UIView()
    private let hostingController: UIHostingController<TasteMapHybridMapSurfaceView>

    init(parent: UIViewController, webView: WKWebView, runtime: TasteMapHybridRuntime) {
        self.parent = parent
        self.webView = webView
        self.runtime = runtime
        model = TasteMapHybridMapSurfaceModel(runtime: runtime)
        hostingController = UIHostingController(rootView: TasteMapHybridMapSurfaceView(model: model))

        overlay.accessibilityIdentifier = "hybrid-mapkit-surface"
        overlay.isHidden = true
        overlay.backgroundColor = .clear
        accessibilityProbe.isAccessibilityElement = true
        accessibilityProbe.accessibilityIdentifier = "restaurant-map"
        accessibilityProbe.accessibilityLabel = "餐厅地图"
        accessibilityProbe.accessibilityTraits = [.allowsDirectInteraction]
        accessibilityProbe.isUserInteractionEnabled = false
        accessibilityProbe.backgroundColor = .clear
        accessibilityProbe.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(hostingController.view)
        overlay.addSubview(accessibilityProbe)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: overlay.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: overlay.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: overlay.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: overlay.bottomAnchor),
            accessibilityProbe.leadingAnchor.constraint(equalTo: overlay.leadingAnchor),
            accessibilityProbe.trailingAnchor.constraint(equalTo: overlay.trailingAnchor),
            accessibilityProbe.topAnchor.constraint(equalTo: overlay.topAnchor),
            accessibilityProbe.bottomAnchor.constraint(equalTo: overlay.bottomAnchor),
        ])
        model.onViewportAccessibilityValue = { [weak accessibilityProbe] value in
            accessibilityProbe?.accessibilityValue = value
        }
        parent.addChild(hostingController)
        parent.view.addSubview(overlay)
        hostingController.didMove(toParent: parent)
    }

    func apply(
        _ request: TasteMapHybridMapSurfaceUpdateRequest,
        resources: TasteMapHybridMapSurfaceResources
    ) throws {
        guard request.requestID.count >= 8, request.requestID.count <= 128,
              request.viewportWidth.isFinite, request.viewportWidth > 0,
              request.viewportHeight.isFinite, request.viewportHeight > 0 else {
            throw TasteMapHybridMapSurfaceError.invalidGeometry
        }
        guard request.visible else {
            overlay.isHidden = true
            // Keep the persistent MapKit model, annotations, decoded images and
            // viewport intact while React shows another route. Re-projecting a
            // hidden map made every Restaurant tap compete with navigation.
            return
        }
        guard let parent, let webView else { throw TasteMapHybridMapSurfaceError.hostUnavailable }

        let webFrame = webView.convert(webView.bounds, to: parent.view)
        let scaleX = webFrame.width / CGFloat(request.viewportWidth)
        let scaleY = webFrame.height / CGFloat(request.viewportHeight)
        let frame = CGRect(
            x: webFrame.minX + CGFloat(request.frame.x) * scaleX,
            y: webFrame.minY + CGFloat(request.frame.y) * scaleY,
            width: CGFloat(request.frame.width) * scaleX,
            height: CGFloat(request.frame.height) * scaleY
        ).intersection(parent.view.bounds)
        guard frame.width >= 40, frame.height >= 80 else {
            throw TasteMapHybridMapSurfaceError.invalidGeometry
        }

        overlay.frame = frame.integral
        overlay.reactControlExclusions = request.reactControlExclusions.compactMap { value in
            let absolute = CGRect(
                x: webFrame.minX + CGFloat(value.x) * scaleX,
                y: webFrame.minY + CGFloat(value.y) * scaleY,
                width: CGFloat(value.width) * scaleX,
                height: CGFloat(value.height) * scaleY
            )
            let clipped = absolute.intersection(frame)
            guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return nil }
            return clipped.offsetBy(dx: -frame.minX, dy: -frame.minY).insetBy(dx: -2, dy: -2)
        }
        overlay.isHidden = false
        parent.view.bringSubviewToFront(overlay)
        model.update(request, resources: resources)
    }
}

private enum TasteMapHybridMapSurfaceError: Error {
    case hostUnavailable
    case invalidGeometry
}

/// A transparent cut-out lets the existing React Add CTA, selected card and
/// state notices remain visible and receive their original WebView hit targets.
private final class TasteMapHybridMapOverlayView: UIView {
    var reactControlExclusions: [CGRect] = [] {
        didSet { setNeedsLayout() }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard super.point(inside: point, with: event) else { return false }
        return !reactControlExclusions.contains(where: { $0.contains(point) })
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let path = UIBezierPath(rect: bounds)
        for exclusion in reactControlExclusions {
            path.append(UIBezierPath(roundedRect: exclusion, cornerRadius: 18))
        }
        let mask = CAShapeLayer()
        mask.frame = bounds
        mask.path = path.cgPath
        mask.fillRule = .evenOdd
        layer.mask = mask
    }
}

@MainActor
private final class TasteMapHybridMapSurfaceModel: ObservableObject {
    @Published private(set) var markers: [RestaurantMapMarkerPresentation] = []
    @Published private(set) var photosByID: [UUID: PhotoAsset] = [:]
    @Published private(set) var userAvatarPreset: ProfileAvatarPreset = .polarBear
    @Published private(set) var userAvatarPhoto: PhotoAsset?
    @Published var selectedNativeRestaurantID: UUID?
    @Published private(set) var fitRequestID = UUID()
    @Published private(set) var renderState: RestaurantMapRenderState = .loading

    private weak var runtime: TasteMapHybridRuntime?
    private var originalIDByNativeID: [UUID: String] = [:]
    private var nativeIDByOriginalID: [String: UUID] = [:]
    private var lastCameraFitKey: String?
    private var lastViewport: TasteMapHybridMapViewportDTO?
    private(set) var photoCoordinator: PhotoTransferCoordinator?
    private(set) var photoAPI: (any PhotoBinaryAPI)?
    var onViewportAccessibilityValue: ((String) -> Void)?

    init(runtime: TasteMapHybridRuntime) { self.runtime = runtime }

    func update(
        _ request: TasteMapHybridMapSurfaceUpdateRequest,
        resources: TasteMapHybridMapSurfaceResources
    ) {
        var nextOriginalIDByNativeID: [UUID: String] = [:]
        var nextNativeIDByOriginalID: [String: UUID] = [:]
        let nextMarkers = request.markers.compactMap { value -> RestaurantMapMarkerPresentation? in
            guard RestaurantMapCoordinatePolicy.isValid(latitude: value.latitude, longitude: value.longitude) else {
                return nil
            }
            let nativeID = Self.stableNativeID(value.id)
            nextOriginalIDByNativeID[nativeID] = value.id
            nextNativeIDByOriginalID[value.id] = nativeID
            let markerVisual = TasteMapHybridMapMarkerVisualPolicy.resolve(
                value.image,
                fallbackEmoji: value.fallbackEmoji,
                restaurantName: value.name,
                photosByID: resources.photosByID
            )
            return RestaurantMapMarkerPresentation(
                id: nativeID,
                name: value.name,
                latitude: value.latitude,
                longitude: value.longitude,
                status: Self.markerStatus(value.status),
                visual: markerVisual,
                publicPhotoID: nil,
                fallbackMerchantImageURL: nil,
                visitCount: max(0, value.visitCount),
                averageRating: value.averageRating,
                distanceKilometers: nil
            )
        }

        originalIDByNativeID = nextOriginalIDByNativeID
        nativeIDByOriginalID = nextNativeIDByOriginalID
        markers = nextMarkers
        photosByID = resources.photosByID
        photoCoordinator = resources.photoCoordinator
        photoAPI = resources.photoAPI
        userAvatarPreset = ProfileAvatarPreset(rawValue: request.userAvatarPresetID) ?? .polarBear
        userAvatarPhoto = resources.userAvatarPhoto
        selectedNativeRestaurantID = request.selectedRestaurantID.flatMap { nextNativeIDByOriginalID[$0] }
        if lastCameraFitKey != request.cameraFitKey {
            lastCameraFitKey = request.cameraFitKey
            fitRequestID = UUID()
        }
    }

    func selectFromMap(_ nativeID: UUID?) {
        guard selectedNativeRestaurantID != nativeID else { return }
        selectedNativeRestaurantID = nativeID
        runtime?.mapSurfaceDidSelect(restaurantID: nativeID.flatMap { originalIDByNativeID[$0] })
    }

    func publishViewport(_ viewport: RestaurantMapViewport) {
        guard viewport.centerLatitude.isFinite, viewport.centerLongitude.isFinite,
              viewport.latitudeDelta.isFinite, viewport.longitudeDelta.isFinite,
              viewport.latitudeDelta > 0, viewport.longitudeDelta > 0 else { return }
        let halfLatitude = viewport.latitudeDelta / 2
        let halfLongitude = viewport.longitudeDelta / 2
        let value = TasteMapHybridMapViewportDTO(
            bounds: TasteMapHybridMapBounds(
                north: min(90, viewport.centerLatitude + halfLatitude),
                south: max(-90, viewport.centerLatitude - halfLatitude),
                east: Self.normalizedLongitude(viewport.centerLongitude + halfLongitude),
                west: Self.normalizedLongitude(viewport.centerLongitude - halfLongitude)
            ),
            center: TasteMapHybridMapCoordinate(
                latitude: viewport.centerLatitude,
                longitude: Self.normalizedLongitude(viewport.centerLongitude)
            ),
            zoom: max(0, min(22, log2(360 / max(viewport.longitudeDelta, 0.000_001))))
        )
        guard value != lastViewport else { return }
        lastViewport = value
        onViewportAccessibilityValue?(String(
            format: "center %.6f,%.6f; span %.6f,%.6f",
            viewport.centerLatitude,
            viewport.centerLongitude,
            viewport.latitudeDelta,
            viewport.longitudeDelta
        ))
        runtime?.mapSurfaceDidChangeViewport(value)
    }

    func setRenderState(_ state: RestaurantMapRenderState) {
        renderState = state
    }

    private static func markerStatus(_ scope: TasteMapHybridMapScope) -> RestaurantMapMarkerStatus {
        switch scope {
        case .visited: .visited
        case .wantToGo: .wantToGo
        case .recommended: .recommended
        }
    }

    private static func stableNativeID(_ semanticID: String) -> UUID {
        if let value = UUID(uuidString: semanticID) { return value }
        // Deterministic FNV-derived bytes keep a non-UUID provider identifier
        // stable across pan/zoom without exposing it as a persistence identity.
        var left: UInt64 = 0xcbf29ce484222325
        var right: UInt64 = 0x84222325cbf29ce4
        for byte in semanticID.utf8 {
            left = (left ^ UInt64(byte)) &* 0x100000001b3
            right = (right ^ UInt64(byte &+ 31)) &* 0x100000001b3
        }
        let hex = String(format: "%016llx%016llx", left, right)
        let formatted = "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20).prefix(12))"
        return UUID(uuidString: formatted) ?? UUID()
    }

    private static func normalizedLongitude(_ value: Double) -> Double {
        var normalized = value.truncatingRemainder(dividingBy: 360)
        if normalized > 180 { normalized -= 360 }
        if normalized < -180 { normalized += 360 }
        return normalized
    }
}

/// Converts a typed Hybrid image descriptor into the deliberately narrower
/// Personal Map visual contract. Legacy descriptor kinds remain decodable for
/// compatibility, but they can never re-enable public/merchant Map imagery.
enum TasteMapHybridMapMarkerVisualPolicy {
    static func resolve(
        _ image: TasteMapHybridImageDescriptor,
        fallbackEmoji: String,
        restaurantName: String,
        photosByID: [UUID: PhotoAsset]
    ) -> RestaurantMapMarkerVisual {
        let matchingPhoto = image.photoID.flatMap { reference in
            photosByID.values.first {
                $0.id.uuidString.caseInsensitiveCompare(reference) == .orderedSame
                    || $0.remoteID?.caseInsensitiveCompare(reference) == .orderedSame
            }
        }
        let emoji = RestaurantMapMarkerVisual.emoji(
            FoodCategoryEmojiResolver.sanitized(fallbackEmoji, restaurantName: restaurantName)
        )
        switch image.kind {
        case .ownerPhoto, .nativeResource:
            return matchingPhoto.map { .photo($0.id) } ?? emoji
        case .foodCategoryVisual:
            return emoji
        case .activityPhoto, .publicUGC, .publicOrCached, .providerMerchant, .foodDiningFallback:
            // Personal Map never renders another user's UGC or provider imagery.
            // Legacy descriptor kinds remain decodable, but safely collapse to
            // the deterministic food emoji on this surface.
            return emoji
        }
    }
}

@MainActor
private struct TasteMapHybridMapSurfaceView: View {
    @ObservedObject var model: TasteMapHybridMapSurfaceModel

    var body: some View {
        RestaurantMapView(
            markers: model.markers,
            photosByID: model.photosByID,
            photoCoordinator: model.photoCoordinator,
            photoAPI: model.photoAPI,
            userAvatarPreset: model.userAvatarPreset,
            userAvatarPhoto: model.userAvatarPhoto,
            selectedRestaurantID: Binding(
                get: { model.selectedNativeRestaurantID },
                set: { model.selectFromMap($0) }
            ),
            fitRequestID: model.fitRequestID,
            locationRequestID: nil,
            onRenderStateChange: { model.setRenderState($0) },
            onViewportChange: { model.publishViewport($0) }
        )
        .accessibilityIdentifier("hybrid-mapkit-restaurant-map")
    }
}
