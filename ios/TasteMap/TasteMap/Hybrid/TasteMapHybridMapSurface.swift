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
    private var presentation = TasteMapHybridMapPresentationState()
    private var layoutRequest: TasteMapHybridMapSurfaceUpdateRequest?

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

    func receiveUpdate(visible: Bool) -> UInt64 {
        let revision = presentation.receiveUpdate()
        if !visible {
            layoutRequest = nil
            presentation.apply(visible: false, revision: revision)
            overlay.isHidden = true
        }
        return revision
    }

    func setRouteAllowsMap(_ allowed: Bool) {
        presentation.routeAllowsMap = allowed
        if !allowed { layoutRequest = nil }
        if presentation.isVisible { layoutIfNeeded() }
        else { overlay.isHidden = true }
    }

    func apply(
        _ request: TasteMapHybridMapSurfaceUpdateRequest,
        revision: UInt64,
        resources: TasteMapHybridMapSurfaceResources
    ) throws {
        guard presentation.isCurrent(revision) else { return }
        guard request.requestID.count >= 8, request.requestID.count <= 128,
              request.viewportWidth.isFinite, request.viewportWidth > 0,
              request.viewportHeight.isFinite, request.viewportHeight > 0 else {
            throw TasteMapHybridMapSurfaceError.invalidGeometry
        }
        guard request.visible else {
            layoutRequest = nil
            presentation.apply(visible: false, revision: revision)
            overlay.isHidden = true
            // Keep the persistent MapKit model, annotations, decoded images and
            // viewport intact while React shows another route. Re-projecting a
            // hidden map made every Restaurant tap compete with navigation.
            return
        }
        try applyGeometry(request)
        layoutRequest = request
        presentation.apply(visible: true, revision: revision)
        overlay.isHidden = !presentation.isVisible
        model.update(request, resources: resources)
    }

    /// Native container/safe-area layout can settle after the last JS update.
    /// Reproject its latest geometry without requerying or rebuilding MapKit.
    func layoutIfNeeded() {
        guard presentation.isVisible, let request = layoutRequest else {
            overlay.isHidden = true
            return
        }
        do {
            try applyGeometry(request)
            overlay.isHidden = !presentation.isVisible
        } catch {
            overlay.isHidden = true
        }
    }

    private func applyGeometry(_ request: TasteMapHybridMapSurfaceUpdateRequest) throws {
        guard let parent, let webView else { throw TasteMapHybridMapSurfaceError.hostUnavailable }
        let webFrame = webView.convert(webView.bounds, to: parent.view)
        let frame = TasteMapHybridMapSurfaceGeometry.project(
            request.frame, viewportWidth: request.viewportWidth, webFrame: webFrame
        ).intersection(parent.view.bounds)
        guard frame.width >= 40, frame.height >= 80 else {
            throw TasteMapHybridMapSurfaceError.invalidGeometry
        }

        let overlayFrame = frame.integral
        if overlay.frame != overlayFrame { overlay.frame = overlayFrame }
        let exclusions = request.reactControlExclusions.compactMap { value -> CGRect? in
            let absolute = TasteMapHybridMapSurfaceGeometry.project(
                value, viewportWidth: request.viewportWidth, webFrame: webFrame
            )
            let clipped = absolute.intersection(frame)
            guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return nil }
            return clipped.offsetBy(dx: -overlayFrame.minX, dy: -overlayFrame.minY).insetBy(dx: -2, dy: -2)
        }
        if overlay.reactControlExclusions != exclusions { overlay.reactControlExclusions = exclusions }
        if parent.view.subviews.last !== overlay { parent.view.bringSubviewToFront(overlay) }
    }
}

enum TasteMapHybridMapSurfaceGeometry {
    static func project(_ rect: TasteMapHybridMapSurfaceRect, viewportWidth: Double, webFrame: CGRect) -> CGRect {
        // CSS pixels have one scale in both axes. Keyboard/visual viewport
        // height changes are not permission to squash the map and its cutouts.
        let scale = webFrame.width / CGFloat(viewportWidth)
        return CGRect(
            x: webFrame.minX + CGFloat(rect.x) * scale,
            y: webFrame.minY + CGFloat(rect.y) * scale,
            width: CGFloat(rect.width) * scale,
            height: CGFloat(rect.height) * scale
        )
    }
}

private enum TasteMapHybridMapSurfaceError: Error {
    case hostUnavailable
    case invalidGeometry
}

/// A transparent cut-out lets the existing React Add CTA, selected card and
/// state notices remain visible and receive their original WebView hit targets.
final class TasteMapHybridMapOverlayView: UIView {
    var reactControlExclusions: [CGRect] = [] {
        didSet { setNeedsLayout() }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard super.point(inside: point, with: event) else { return false }
        return !reactControlExclusions.contains(where: { $0.contains(point) })
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        var path = UIBezierPath(rect: bounds).cgPath
        for exclusion in reactControlExclusions {
            let isFullWidthBottomBar = exclusion.minX <= bounds.minX + 2
                && exclusion.maxX >= bounds.maxX - 2
                && exclusion.maxY >= bounds.maxY - 2
            // Subtract each control, rather than XOR-ing all openings. Two
            // overlapping controls must never make MapKit visible again.
            path = path.subtracting(UIBezierPath(
                roundedRect: exclusion,
                cornerRadius: isFullWidthBottomBar ? 0 : 18
            ).cgPath)
        }
        let mask = CAShapeLayer()
        mask.frame = bounds
        mask.path = path
        mask.fillRule = .nonZero
        layer.mask = mask
    }
}

@MainActor
private final class TasteMapHybridMapSurfaceModel: ObservableObject {
    @Published private(set) var markers: [RestaurantMapMarkerPresentation] = []
    @Published private(set) var photosByID: [UUID: PhotoAsset] = [:]
    @Published private(set) var userAvatarPreset: ProfileAvatarPreset = .polarBear
    @Published private(set) var userAvatarPhoto: PhotoAsset?
    @Published private(set) var tasteDataProgress: TasteMapHybridTasteDataProgressDTO?
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
            let providerMerchantImageURL = TasteMapHybridMapMarkerVisualPolicy.providerMerchantImageURL(
                value.image
            )
            return RestaurantMapMarkerPresentation(
                id: nativeID,
                name: value.name,
                latitude: value.latitude,
                longitude: value.longitude,
                status: Self.markerStatus(value.status),
                visual: markerVisual,
                publicPhotoID: nil,
                fallbackMerchantImageURL: providerMerchantImageURL,
                allowsRemoteImages: providerMerchantImageURL != nil,
                recommendationRank: value.recommendationRank,
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
        tasteDataProgress = request.tasteDataProgress
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

    func selectGroupFromMap(_ nativeIDs: [UUID]) {
        let ids = nativeIDs.compactMap { originalIDByNativeID[$0] }
        guard ids.count > 1 else { return }
        runtime?.mapSurfaceDidSelectGroup(restaurantIDs: ids)
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

/// Converts a typed Hybrid image descriptor into the Personal Map visual
/// contract. Owner photos and real Provider merchant images are allowed;
/// another user's UGC remains excluded from this private surface.
enum TasteMapHybridMapMarkerVisualPolicy {
    static func providerMerchantImageURL(_ image: TasteMapHybridImageDescriptor) -> URL? {
        guard image.kind == .providerMerchant else { return nil }
        return RestaurantImagePriorityPolicy.safeHTTPSURL(image.resourceURL)
    }

    static func resolve(
        _ image: TasteMapHybridImageDescriptor,
        fallbackEmoji: String,
        restaurantName: String,
        photosByID: [UUID: PhotoAsset]
    ) -> RestaurantMapMarkerVisual {
        let matchingPhoto = image.photoID.flatMap { reference in
            photosByID.values.first {
                $0.deletedAt == nil && $0.binaryDeletedAt == nil && $0.uploadState != .deleted &&
                    ($0.id.uuidString.caseInsensitiveCompare(reference) == .orderedSame
                    || $0.remoteID?.caseInsensitiveCompare(reference) == .orderedSame)
            }
        }
        let emoji = RestaurantMapMarkerVisual.emoji(
            FoodCategoryEmojiResolver.sanitized(fallbackEmoji, restaurantName: restaurantName)
        )
        switch image.kind {
        case .ownerPhoto, .nativeResource:
            return matchingPhoto.map { .photo($0.id) } ?? emoji
        case .foodCategoryVisual:
            // The canonical descriptor carries an explicit owner selection.
            // Do not reclassify a frog/flag/plate as inferred cuisine artwork.
            return RestaurantOwnerAvatarEmojiPolicy.normalized(image.preferredEmoji)
                .map(RestaurantMapMarkerVisual.emoji) ?? emoji
        case .providerMerchant, .foodDiningFallback:
            // The provider URL is loaded through the canonical image plan;
            // this value remains the visible fallback if loading fails.
            return emoji
        case .activityPhoto, .publicUGC, .publicOrCached:
            // Personal Map never renders another user's UGC. Legacy descriptor
            // kinds remain decodable but safely collapse to the food emoji.
            return emoji
        }
    }
}

@MainActor
private struct TasteMapHybridMapSurfaceView: View {
    @ObservedObject var model: TasteMapHybridMapSurfaceModel

    var body: some View {
        ZStack(alignment: .top) {
            RestaurantMapView(
                markers: model.markers,
                photosByID: model.photosByID,
                photoCoordinator: model.photoCoordinator,
                photoAPI: model.photoAPI,
                userAvatarPreset: model.userAvatarPreset,
                userAvatarPhoto: model.userAvatarPhoto,
                showsUserLocation: true,
                selectedRestaurantID: Binding(
                    get: { model.selectedNativeRestaurantID },
                    set: { model.selectFromMap($0) }
                ),
                fitRequestID: model.fitRequestID,
                locationRequestID: nil,
                onRenderStateChange: { model.setRenderState($0) },
                onViewportChange: { model.publishViewport($0) },
                onGroupSelection: { model.selectGroupFromMap($0) }
            )
            .accessibilityIdentifier("hybrid-mapkit-restaurant-map")

            if let progress = model.tasteDataProgress {
                Text("（\(progress.displayCount) / \(progress.target) · \(progress.message)）")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(red: 23 / 255, green: 63 / 255, blue: 91 / 255))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.top, 7)
                    .padding(.horizontal, 10)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("taste-data-progress")
                    .accessibilityLabel("口味数据进度，\(progress.displayCount) / \(progress.target)，\(progress.message)")
            }
        }
    }
}
