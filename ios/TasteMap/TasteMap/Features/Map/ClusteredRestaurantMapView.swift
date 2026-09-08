import MapKit
import SwiftUI
import UIKit

struct RestaurantMapView: UIViewRepresentable {
    let markers: [RestaurantMapMarkerPresentation]
    let photosByID: [UUID: PhotoAsset]
    let photoCoordinator: PhotoTransferCoordinator?
    let photoAPI: (any PhotoBinaryAPI)?
    let userAvatarPreset: ProfileAvatarPreset
    let userAvatarPhoto: PhotoAsset?
    let showsUserLocation: Bool
    @Binding var selectedRestaurantID: UUID?
    let fitRequestID: UUID
    let locationRequestID: UUID?
    let onRenderStateChange: (RestaurantMapRenderState) -> Void
    let onViewportChange: (RestaurantMapViewport) -> Void
    var onGroupSelection: (([UUID]) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = showsUserLocation
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.pointOfInterestFilter = .includingAll
        mapView.isScrollEnabled = true
        mapView.isZoomEnabled = true
        mapView.isRotateEnabled = true
        mapView.isPitchEnabled = false
        mapView.accessibilityIdentifier = "restaurant-map"
        context.coordinator.setRenderState(.loading)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self
        mapView.showsUserLocation = showsUserLocation
        context.coordinator.updateAnnotations(on: mapView)
        context.coordinator.updateUserLocationView(on: mapView)
        context.coordinator.applySelection(on: mapView)
        context.coordinator.fitIfRequested(on: mapView)
        context.coordinator.centerOnUserIfRequested(on: mapView)
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: RestaurantMapView
        private var annotationsByID: [UUID: RestaurantMapAnnotation] = [:]
        private var imageTasks: [String: Task<Void, Never>] = [:]
        private var userAvatarTask: Task<Void, Never>?
        private var lastFitRequestID: UUID?
        private var lastLocationRequestID: UUID?
        private var lastSelectedRestaurantID: UUID?
        private var isUserInteracting = false
        private var hasDeferredFit = false
        private var renderState: RestaurantMapRenderState = .loading
        private var markerLayerRanks: [UUID: Int] = [:]
        private var regionalGroupingSnapshot = RestaurantMapRegionalGroupingSnapshot(groups: [])
        private var markerViewportScale = RestaurantMapMarkerViewportScale()
        private var lastMarkerLayoutKey = ""
        #if DEBUG
        private weak var gestureTestArea: UIView?
        #endif

        init(parent: RestaurantMapView) {
            self.parent = parent
        }

        deinit {
            imageTasks.values.forEach { $0.cancel() }
            userAvatarTask?.cancel()
        }

        func updateAnnotations(on mapView: MKMapView) {
            // Keep one stable annotation identity for the complete filtered
            // result. MapKit virtualizes offscreen views itself; rebuilding the
            // data set after every pan caused visible image/fallback flashing.
            let visibleMarkers = parent.markers
            let incoming = Dictionary(uniqueKeysWithValues: visibleMarkers.map { ($0.id, $0) })
            let removedIDs = Set(annotationsByID.keys).subtracting(incoming.keys)
            let removed = removedIDs.compactMap { annotationsByID.removeValue(forKey: $0) }
            for key in Array(imageTasks.keys) where removedIDs.contains(where: { key.contains($0.uuidString) }) {
                imageTasks[key]?.cancel()
                imageTasks[key] = nil
            }
            if !removed.isEmpty { mapView.removeAnnotations(removed) }

            var added: [RestaurantMapAnnotation] = []
            for marker in visibleMarkers {
                if let annotation = annotationsByID[marker.id] {
                    guard annotation.presentation != marker else { continue }
                    annotation.presentation = marker
                    // Metadata/photo refreshes are not location changes.
                    // Avoid redundant KVO coordinate animations in MapKit.
                    if annotation.coordinate.latitude != marker.latitude
                        || annotation.coordinate.longitude != marker.longitude {
                        annotation.coordinate = marker.coordinate
                    }
                    annotation.title = marker.name
                    if let view = mapView.view(for: annotation) as? RestaurantMarkerAnnotationView {
                        configure(view, for: annotation)
                    }
                } else {
                    let annotation = RestaurantMapAnnotation(presentation: marker)
                    annotationsByID[marker.id] = annotation
                    added.append(annotation)
                }
            }
            refreshMarkerLayerRanks()
            if !added.isEmpty { mapView.addAnnotations(added) }
            applyMarkerLayerOrder(on: mapView)
            applyAnchoredMarkerVisibility(on: mapView)
        }

        func applySelection(on mapView: MKMapView) {
            let selectedID = parent.selectedRestaurantID
            if selectedID != lastSelectedRestaurantID {
                if let previousID = lastSelectedRestaurantID,
                   let previous = annotationsByID[previousID] {
                    mapView.deselectAnnotation(previous, animated: false)
                }
                if let selectedID, let selected = annotationsByID[selectedID] {
                    mapView.selectAnnotation(selected, animated: false)
                }
                lastSelectedRestaurantID = selectedID
            }
            applyMarkerLayerOrder(on: mapView)
        }

        func fitIfRequested(on mapView: MKMapView) {
            guard lastFitRequestID != parent.fitRequestID else { return }
            guard !parent.markers.isEmpty else { return }
            if isUserInteracting {
                hasDeferredFit = true
                return
            }
            lastFitRequestID = parent.fitRequestID
            hasDeferredFit = false
            applyCameraTarget(
                RestaurantMapCameraPolicy.target(for: parent.markers),
                on: mapView,
                animated: mapView.window != nil
            )
        }

        func centerOnUserIfRequested(on mapView: MKMapView) {
            guard let requestID = parent.locationRequestID,
                  lastLocationRequestID != requestID,
                  let location = mapView.userLocation.location,
                  RestaurantMapCoordinatePolicy.isValid(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                  ) else { return }
            lastLocationRequestID = requestID
            applyCameraTarget(
                .region(
                    centerLatitude: location.coordinate.latitude,
                    centerLongitude: location.coordinate.longitude,
                    latitudeDelta: 0.03,
                    longitudeDelta: 0.03
                ),
                on: mapView,
                animated: true
            )
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                let identifier = "taste-map-user-location"
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                    as? TasteMapUserLocationAnnotationView)
                    ?? TasteMapUserLocationAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                view.annotation = annotation
                configureUserLocation(view)
                view.zPriority = .max
                view.selectedZPriority = .max
                view.layer.zPosition = Self.userLocationLayerPosition
                return view
            }
            guard let restaurant = annotation as? RestaurantMapAnnotation else { return nil }
            let identifier = "taste-map-restaurant"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                as? RestaurantMarkerAnnotationView)
                ?? RestaurantMarkerAnnotationView(annotation: restaurant, reuseIdentifier: identifier)
            view.annotation = restaurant
            view.clusteringIdentifier = nil
            view.displayPriority = .required
            view.collisionMode = .circle
            configure(view, for: restaurant)
            applyMarkerLayerOrder(to: view, restaurantID: restaurant.presentation.id)
            return view
        }

        func mapView(_ mapView: MKMapView, didAdd views: [MKAnnotationView]) {
            guard views.contains(where: { $0 is RestaurantMarkerAnnotationView }) else { return }
            applyMarkerLayerOrder(on: mapView)
            applyAnchoredMarkerVisibility(on: mapView)
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let annotation = view.annotation as? RestaurantMapAnnotation else { return }
            let feedback = UISelectionFeedbackGenerator()
            feedback.prepare()
            feedback.selectionChanged()
            if let group = regionalGroup(for: annotation.presentation.id),
               group.count > 1,
               parent.selectedRestaurantID != annotation.presentation.id {
                mapView.deselectAnnotation(annotation, animated: false)
                if RestaurantMapRegionalGroupingPolicy.isCoincident(group) {
                    showCoincidentRestaurants(group, on: mapView)
                } else {
                    zoomIntoRegionalGroup(group, on: mapView)
                }
                return
            }
            parent.selectedRestaurantID = annotation.presentation.id
            lastSelectedRestaurantID = annotation.presentation.id
            applyMarkerLayerOrder(on: mapView)
        }

        func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
            guard let annotation = view.annotation as? RestaurantMapAnnotation,
                  parent.selectedRestaurantID == annotation.presentation.id else { return }
            parent.selectedRestaurantID = nil
            lastSelectedRestaurantID = nil
            applyMarkerLayerOrder(on: mapView)
        }

        func mapViewWillStartLoadingMap(_ mapView: MKMapView) {
            setRenderState(.loading)
        }

        func mapViewDidFinishLoadingMap(_ mapView: MKMapView) {
            setRenderState(.ready)
        }

        func mapView(_ mapView: MKMapView, didFailLoadingMapWithError error: any Error) {
            setRenderState(.failed("地图暂时没有加载出来，请检查网络后重试。"))
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            #if DEBUG
            traceQACamera("regionWillChange animated=\(animated)", on: mapView)
            #endif
            if mapView.gestureRecognizers?.contains(where: {
                $0.state == .began || $0.state == .changed
            }) == true {
                isUserInteracting = true
            }
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            // Size and progressive visibility follow zoom without ever
            // moving a circle away from its Restaurant coordinate.
            applyAnchoredMarkerVisibility(on: mapView)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            #if DEBUG
            traceQACamera("regionDidChange animated=\(animated)", on: mapView)
            #endif
            // Stable annotations remain at their own coordinates. Zoom only
            // changes their size and which favorite representatives are visible.
            updateAnnotations(on: mapView)
            let region = mapView.region
            let viewport = RestaurantMapViewport(
                centerLatitude: region.center.latitude,
                centerLongitude: region.center.longitude,
                latitudeDelta: region.span.latitudeDelta,
                longitudeDelta: region.span.longitudeDelta
            )
            mapView.accessibilityValue = String(
                format: "center %.6f,%.6f; span %.6f,%.6f",
                viewport.centerLatitude,
                viewport.centerLongitude,
                viewport.latitudeDelta,
                viewport.longitudeDelta
            )
            parent.onViewportChange(viewport)
            guard isUserInteracting else { return }
            let stillInteracting = mapView.gestureRecognizers?.contains(where: {
                $0.state == .began || $0.state == .changed
            }) == true
            guard !stillInteracting else { return }
            isUserInteracting = false
            if hasDeferredFit { fitIfRequested(on: mapView) }
        }

        func updateUserLocationView(on mapView: MKMapView) {
            guard let view = mapView.view(for: mapView.userLocation) as? TasteMapUserLocationAnnotationView else {
                return
            }
            configureUserLocation(view)
            view.zPriority = .max
            view.selectedZPriority = .max
            view.layer.zPosition = Self.userLocationLayerPosition
        }

        func setRenderState(_ state: RestaurantMapRenderState) {
            guard state != renderState else { return }
            renderState = state
            DispatchQueue.main.async { [weak self] in
                self?.parent.onRenderStateChange(state)
            }
        }

        private func configure(
            _ view: RestaurantMarkerAnnotationView,
            for annotation: RestaurantMapAnnotation
        ) {
            configureImage(view, marker: annotation.presentation, taskKey: annotation.presentation.id.uuidString)
        }

        private func configureImage(
            _ view: RestaurantMarkerAnnotationView,
            marker: RestaurantMapMarkerPresentation,
            taskKey: String
        ) {
            guard view.configure(marker) else { return }
            imageTasks[taskKey]?.cancel()
            view.beginImageLoad(for: marker.id)
            let generation = view.imageGeneration
            imageTasks[taskKey] = Task { @MainActor [weak view] in
                let result = await RestaurantImageLoader.image(
                    resolution: marker.imageResolution,
                    photosByID: parent.photosByID,
                    coordinator: parent.photoCoordinator,
                    photoAPI: parent.photoAPI,
                    variant: .thumbnail,
                    semanticID: marker.id.uuidString
                )
                guard !Task.isCancelled else { return }
                view?.finishImageLoad(result?.image, for: marker, generation: generation)
            }
        }

        private func configureUserLocation(_ view: TasteMapUserLocationAnnotationView) {
            view.configure(preset: parent.userAvatarPreset)
            guard let photo = parent.userAvatarPhoto,
                  photo.deletedAt == nil,
                  let coordinator = parent.photoCoordinator else {
                userAvatarTask?.cancel()
                userAvatarTask = nil
                view.finishPhotoLoad(reference: nil, image: nil)
                return
            }
            let reference = photo.id
            guard view.representedPhotoReference != reference else { return }
            userAvatarTask?.cancel()
            view.beginPhotoLoad(reference: reference)
            userAvatarTask = Task { @MainActor [weak view] in
                let data = try? await coordinator.imageData(for: photo, variant: .thumbnail)
                guard !Task.isCancelled else { return }
                view?.finishPhotoLoad(
                    reference: reference,
                    image: data.flatMap(UIImage.init(data:))
                )
            }
        }

        /// Layer order changes stacking only, never geographic anchors.
        private func applyMarkerLayerOrder(on mapView: MKMapView) {
            refreshMarkerLayerRanks()
            for (restaurantID, annotation) in annotationsByID {
                guard let view = mapView.view(for: annotation) as? RestaurantMarkerAnnotationView else {
                    continue
                }
                applyMarkerLayerOrder(to: view, restaurantID: restaurantID)
            }
            if let userView = mapView.view(for: mapView.userLocation) as? TasteMapUserLocationAnnotationView {
                userView.zPriority = .max
                userView.selectedZPriority = .max
                userView.layer.zPosition = Self.userLocationLayerPosition
            }
        }

        private func applyMarkerLayerOrder(
            to view: RestaurantMarkerAnnotationView,
            restaurantID: UUID
        ) {
            if markerLayerRanks[restaurantID] == nil { refreshMarkerLayerRanks() }
            view.setLayerPriority(rank: markerLayerRanks[restaurantID] ?? 0, count: markerLayerRanks.count)
        }

        private func refreshMarkerLayerRanks() {
            markerLayerRanks = RestaurantMapMarkerLayerPolicy.layerRanks(
                annotationsByID.values.map(\.presentation),
                selectedRestaurantID: parent.selectedRestaurantID
            )
        }

        private func applyAnchoredMarkerVisibility(on mapView: MKMapView) {
            #if DEBUG
            updateGestureTestArea(on: mapView)
            #endif
            let markers = annotationsByID.values.map(\.presentation)
            let latitudeDelta = markerViewportScale.resolve(
                latitudeDelta: mapView.region.span.latitudeDelta,
                projectedSize: CGSize(width: mapView.visibleMapRect.width, height: mapView.visibleMapRect.height),
                viewportSize: mapView.bounds.size
            )
            let densityStyle = RestaurantMapMarkerDensityStyle.resolve(
                latitudeDelta: latitudeDelta
            )
            let layoutKey = markerLayoutKey(for: markers, on: mapView)
            if layoutKey != lastMarkerLayoutKey {
                lastMarkerLayoutKey = layoutKey
                let screenPoints = Dictionary(uniqueKeysWithValues: annotationsByID.map { restaurantID, annotation in
                    (restaurantID, mapView.convert(annotation.coordinate, toPointTo: mapView))
                })
                let groups = RestaurantMapRegionalGroupingPolicy.groups(
                    for: markers,
                    screenPoints: screenPoints,
                    requiredCenterDistance: densityStyle.regionalGroupingDistance,
                    latitudeDelta: latitudeDelta
                )
                regionalGroupingSnapshot = RestaurantMapRegionalGroupingSnapshot(groups: groups)
            }
            var activeStackImageKeys: Set<String> = []
            for (restaurantID, annotation) in annotationsByID {
                guard let view = mapView.view(for: annotation) as? RestaurantMarkerAnnotationView else {
                    continue
                }
                let group = regionalGroup(for: restaurantID)
                view.setGroup(
                    count: group?.count ?? 1,
                    stacked: (group?.count ?? 1) > 1
                        && RestaurantMapRegionalGroupingPolicy.isCoincident(group ?? [])
                )
                view.setDensityStyle(densityStyle)
                let isCoincidentStack = (group?.count ?? 1) > 1
                    && RestaurantMapRegionalGroupingPolicy.isCoincident(group ?? [])
                let backMembers = isCoincidentStack ? Array((group ?? []).dropFirst().prefix(TasteMapDesignTokens.MapRestaurantMarker.stackBackOffsets.count)) : []
                for (backView, member) in view.setStackMembers(backMembers) {
                    let key = "\(restaurantID.uuidString):\(member.id.uuidString)"
                    activeStackImageKeys.insert(key)
                    configureImage(backView, marker: member, taskKey: key)
                    backView.isAccessibilityElement = false
                    backView.accessibilityElementsHidden = true
                    backView.accessibilityIdentifier = nil
                    backView.accessibilityLabel = nil
                }
                view.setProgressivelyVisible(regionalGroupingSnapshot.visibleRepresentativeIDs.contains(restaurantID))
            }
            for key in Array(imageTasks.keys) where key.contains(":") && !activeStackImageKeys.contains(key) {
                imageTasks[key]?.cancel()
                imageTasks[key] = nil
            }
        }

        private func regionalGroup(for representativeID: UUID) -> [RestaurantMapMarkerPresentation]? {
            regionalGroupingSnapshot.members(for: representativeID) { annotationsByID[$0]?.presentation }
        }

        #if DEBUG
        private func traceQACamera(_ event: String, on mapView: MKMapView) {
            guard ProcessInfo.processInfo.environment["TASTEMAP_MAP_FRAME_DIAGNOSTICS"] == "1" else { return }
            func activeGestures(in view: UIView) -> [String] {
                (view.gestureRecognizers ?? []).filter { $0.state == .began || $0.state == .changed }
                    .map { "\(type(of: $0)):\($0.state.rawValue)" }
                    + view.subviews.flatMap { activeGestures(in: $0) }
            }
            print("TASTEMAP_MAP_CAMERA_TRACE time=\(CACurrentMediaTime()) event=\(event) center=\(mapView.region.center.latitude),\(mapView.region.center.longitude) span=\(mapView.region.span.latitudeDelta),\(mapView.region.span.longitudeDelta) fit=\(parent.fitRequestID) selected=\(parent.selectedRestaurantID?.uuidString ?? "none") gestures=\(activeGestures(in: mapView))")
        }

        /// A non-rendering, touch-through target lets XCTest send real pinch
        /// gestures inside MapKit, away from the overlaid bottom navigation.
        /// It never substitutes a viewport, coordinate or geometry reading.
        private func updateGestureTestArea(on mapView: MKMapView) {
            guard ProcessInfo.processInfo.environment["TASTEMAP_VISUAL_QA_MODE"] == "dense-mall"
                || ProcessInfo.processInfo.environment["TASTEMAP_MAP_GEOMETRY_QA"] == "1" else { return }
            let target: UIView
            if let existing = gestureTestArea {
                target = existing
            } else {
                target = UIView()
                target.backgroundColor = .clear
                target.isUserInteractionEnabled = false
                target.isAccessibilityElement = true
                target.accessibilityIdentifier = "restaurant-map-gesture-area"
                target.accessibilityLabel = "地图缩放测试区域"
                mapView.addSubview(target)
                gestureTestArea = target
            }
            let side = min(180, mapView.bounds.width * 0.5, mapView.bounds.height * 0.35)
            target.frame = CGRect(x: mapView.bounds.midX - side / 2, y: mapView.bounds.midY - side / 2, width: side, height: side)
        }
        #endif

        private func markerLayoutKey(
            for markers: [RestaurantMapMarkerPresentation],
            on mapView: MKMapView
        ) -> String {
            let markerKey = markers.sorted { $0.id.uuidString < $1.id.uuidString }.map {
                "\($0.id.uuidString):\($0.latitude):\($0.longitude):\($0.recommendationRank ?? 0):\($0.averageRating ?? -1):\($0.visitCount)"
            }.joined(separator: "|")
            return "\(markerViewportScale.revision):\(mapView.camera.pitch):\(mapView.camera.heading):\(markerKey)"
        }

        private func showCoincidentRestaurants(
            _ group: [RestaurantMapMarkerPresentation], on mapView: MKMapView
        ) {
            if let onGroupSelection = parent.onGroupSelection {
                onGroupSelection(group.map(\.id))
                return
            }
            // Native rollback/public-map consumers keep the same ability to
            // reach every record. Hybrid sends IDs to the shared React sheet.
            guard var presenter = mapView.window?.rootViewController else { return }
            while let presented = presenter.presentedViewController { presenter = presented }
            let chooser = UIAlertController(
                title: "此处的餐厅", message: "选择一家查看详情", preferredStyle: .actionSheet
            )
            for marker in group {
                chooser.addAction(UIAlertAction(title: marker.name, style: .default) { [weak self] _ in
                    self?.parent.selectedRestaurantID = marker.id
                })
            }
            chooser.addAction(UIAlertAction(title: "取消", style: .cancel))
            chooser.popoverPresentationController?.sourceView = mapView
            chooser.popoverPresentationController?.sourceRect = CGRect(
                x: mapView.bounds.midX, y: mapView.bounds.midY, width: 1, height: 1
            )
            presenter.present(chooser, animated: true)
        }

        private func zoomIntoRegionalGroup(
            _ group: [RestaurantMapMarkerPresentation],
            on mapView: MKMapView
        ) {
            guard let first = group.first else { return }
            let latitudes = group.map(\.latitude)
            let longitudes = group.map(\.longitude)
            guard let minimumLatitude = latitudes.min(),
                  let maximumLatitude = latitudes.max(),
                  let minimumLongitude = longitudes.min(),
                  let maximumLongitude = longitudes.max() else { return }
            let latitudeDelta = max(0.006, (maximumLatitude - minimumLatitude) * 1.6)
            let longitudeDelta = max(0.006, (maximumLongitude - minimumLongitude) * 1.6)
            let region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: (minimumLatitude + maximumLatitude) / 2,
                    longitude: (minimumLongitude + maximumLongitude) / 2
                ),
                span: MKCoordinateSpan(
                    latitudeDelta: min(mapView.region.span.latitudeDelta / 1.8, latitudeDelta),
                    longitudeDelta: min(mapView.region.span.longitudeDelta / 1.8, longitudeDelta)
                )
            )
            #if DEBUG
            traceQACamera("groupZoom target=\(region.center.latitude),\(region.center.longitude)", on: mapView)
            #endif
            mapView.setRegion(mapView.regionThatFits(region), animated: true)
            if first.id == parent.selectedRestaurantID { parent.selectedRestaurantID = nil }
        }

        private static let userLocationLayerPosition: CGFloat = 1_000_000

        private func applyCameraTarget(
            _ target: RestaurantMapCameraTarget,
            on mapView: MKMapView,
            animated: Bool
        ) {
            guard case let .region(
                centerLatitude,
                centerLongitude,
                latitudeDelta,
                longitudeDelta
            ) = target else { return }
            let region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: centerLatitude,
                    longitude: centerLongitude
                ),
                span: MKCoordinateSpan(
                    latitudeDelta: latitudeDelta,
                    longitudeDelta: longitudeDelta
                )
            )
            #if DEBUG
            traceQACamera("cameraTarget target=\(centerLatitude),\(centerLongitude) animated=\(animated)", on: mapView)
            #endif
            mapView.setRegion(mapView.regionThatFits(region), animated: animated)
        }
    }
}

private final class RestaurantMapAnnotation: NSObject, MKAnnotation {
    dynamic var coordinate: CLLocationCoordinate2D
    dynamic var title: String?
    var presentation: RestaurantMapMarkerPresentation

    init(presentation: RestaurantMapMarkerPresentation) {
        self.presentation = presentation
        coordinate = presentation.coordinate
        title = presentation.name
        super.init()
    }
}

private extension RestaurantMapMarkerPresentation {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

@MainActor
private final class TasteMapUserLocationAnnotationView: MKAnnotationView {
    private let haloView = UIView()
    private let pointerOuterView = UIView()
    private let pointerInnerView = UIView()
    private let bubbleView = UIView()
    private let avatarBorderView = UIView()
    private let avatarView = UIImageView()
    private(set) var representedPhotoReference: UUID?
    private var presetImage: UIImage?

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        let metrics = TasteMapDesignTokens.MapLocationMarker.self
        frame = CGRect(x: 0, y: 0, width: metrics.width, height: metrics.height)
        backgroundColor = .clear
        clipsToBounds = false
        centerOffset = CGPoint(x: 0, y: metrics.centerOffsetY)
        collisionMode = .circle
        displayPriority = .required
        canShowCallout = false

        haloView.frame = CGRect(
            x: (metrics.width - metrics.haloDiameter) / 2,
            y: 0,
            width: metrics.haloDiameter,
            height: metrics.haloDiameter
        )
        haloView.backgroundColor = TasteMapCoreTheme.brandUIColor.withAlphaComponent(0.15)
        haloView.layer.cornerRadius = metrics.haloDiameter / 2
        haloView.layer.shadowColor = UIColor.black.cgColor
        haloView.layer.shadowOpacity = 0.12
        haloView.layer.shadowRadius = 4
        haloView.layer.shadowOffset = CGSize(width: 0, height: 2)
        addSubview(haloView)

        pointerOuterView.bounds = CGRect(
            x: 0,
            y: 0,
            width: metrics.pointerOuterSide,
            height: metrics.pointerOuterSide
        )
        pointerOuterView.center = CGPoint(x: metrics.width / 2, y: metrics.pointerCenterY)
        pointerOuterView.backgroundColor = .systemBackground
        pointerOuterView.layer.cornerRadius = 3
        pointerOuterView.transform = CGAffineTransform(rotationAngle: .pi / 4)
        pointerOuterView.layer.shadowColor = UIColor.black.cgColor
        pointerOuterView.layer.shadowOpacity = 0.12
        pointerOuterView.layer.shadowRadius = 3
        pointerOuterView.layer.shadowOffset = CGSize(width: 1, height: 1)
        addSubview(pointerOuterView)

        pointerInnerView.frame = CGRect(
            x: (metrics.pointerOuterSide - metrics.pointerInnerSide) / 2,
            y: (metrics.pointerOuterSide - metrics.pointerInnerSide) / 2,
            width: metrics.pointerInnerSide,
            height: metrics.pointerInnerSide
        )
        pointerInnerView.backgroundColor = TasteMapCoreTheme.brandUIColor
        pointerInnerView.layer.cornerRadius = 1.5
        pointerOuterView.addSubview(pointerInnerView)

        bubbleView.frame = CGRect(
            x: (metrics.width - metrics.bubbleDiameter) / 2,
            y: metrics.bubbleTop,
            width: metrics.bubbleDiameter,
            height: metrics.bubbleDiameter
        )
        bubbleView.backgroundColor = TasteMapCoreTheme.brandUIColor
        bubbleView.layer.cornerRadius = metrics.bubbleDiameter / 2
        bubbleView.layer.shadowColor = UIColor.black.cgColor
        bubbleView.layer.shadowOpacity = 0.16
        bubbleView.layer.shadowRadius = 4
        bubbleView.layer.shadowOffset = CGSize(width: 0, height: 2)
        addSubview(bubbleView)

        avatarBorderView.frame = CGRect(
            x: (metrics.bubbleDiameter - metrics.avatarBorderDiameter) / 2,
            y: (metrics.bubbleDiameter - metrics.avatarBorderDiameter) / 2,
            width: metrics.avatarBorderDiameter,
            height: metrics.avatarBorderDiameter
        )
        avatarBorderView.backgroundColor = .systemBackground
        avatarBorderView.layer.cornerRadius = metrics.avatarBorderDiameter / 2
        bubbleView.addSubview(avatarBorderView)

        avatarView.frame = CGRect(
            x: (metrics.avatarBorderDiameter - metrics.avatarDiameter) / 2,
            y: (metrics.avatarBorderDiameter - metrics.avatarDiameter) / 2,
            width: metrics.avatarDiameter,
            height: metrics.avatarDiameter
        )
        avatarView.contentMode = .scaleAspectFill
        avatarView.clipsToBounds = true
        avatarView.layer.cornerRadius = metrics.avatarDiameter / 2
        avatarBorderView.addSubview(avatarView)
        isAccessibilityElement = true
        accessibilityLabel = "我的当前位置"
        accessibilityIdentifier = "restaurant-map-user-avatar-marker"
    }

    required init?(coder: NSCoder) { nil }

    func configure(preset: ProfileAvatarPreset) {
        presetImage = Self.presetImage(preset)
        if representedPhotoReference == nil { avatarView.image = presetImage }
    }

    func beginPhotoLoad(reference: UUID) {
        representedPhotoReference = reference
        avatarView.image = presetImage
    }

    func finishPhotoLoad(reference: UUID?, image: UIImage?) {
        representedPhotoReference = reference
        avatarView.image = image ?? presetImage
    }

    private static func presetImage(_ preset: ProfileAvatarPreset) -> UIImage? {
        guard let sheet = UIImage(named: "TasteMapAvatarPresets"),
              let cgImage = sheet.cgImage else { return nil }
        let cellWidth = cgImage.width / 4
        let cellHeight = cgImage.height / 4
        let position = preset.gridPosition
        let rect = CGRect(
            x: CGFloat(position.column * cellWidth),
            y: CGFloat(position.row * cellHeight),
            width: CGFloat(cellWidth),
            height: CGFloat(cellHeight)
        )
        guard let cropped = cgImage.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cropped, scale: sheet.scale, orientation: sheet.imageOrientation)
    }
}

#if DEBUG
/// Diagnostic evidence only. It neither changes an annotation nor substitutes
/// a presentation-layer reading for the original model/projection assertion.
struct RestaurantMapMarkerFrameSample {
    let time: CFTimeInterval
    let actual: CGPoint
    let presented: CGPoint?
    let projected: CGPoint
    let projectedAfter: CGPoint
    let center: CLLocationCoordinate2D

    var anchorError: CGFloat { hypot(actual.x - projected.x, actual.y - projected.y) }
    var projectionReadDrift: CGFloat { hypot(projectedAfter.x - projected.x, projectedAfter.y - projected.y) }
    var diagnostic: String {
        let presentation = presented.map { String(format: "%.3f,%.3f", $0.x, $0.y) } ?? "unavailable"
        return String(format: "TASTEMAP_MAP_FRAME_SAMPLE time %.6f; model %.3f,%.3f; presentation %@; projected %.3f,%.3f; projectedAfter %.3f,%.3f; mapCenter %.9f,%.9f",
                      time, actual.x, actual.y, presentation, projected.x, projected.y,
                      projectedAfter.x, projectedAfter.y, center.latitude, center.longitude)
    }
}
#endif

@MainActor
final class RestaurantMarkerAnnotationView: MKAnnotationView {
    private let outerRingLayer = CAShapeLayer()
    private(set) var stackMemberViews: [RestaurantMarkerAnnotationView] = []
    private var groupSize = 1
    private var usesStack = false
    private var restaurantAccessibilityLabel = ""
    private var normalRingColor = UIColor.clear
    private let visualContainer = UIView()
    private let dashedRingLayer = CAShapeLayer()
    private let imageView = UIImageView()
    private let emojiLabel = UILabel()
    private let surfaceDepthLayer = CAGradientLayer()
    private let chestShellView = UIImageView(image: UIImage(named: RestaurantMapMarkerShape.assetName))
    private let chestWindowMaskLayer = CAShapeLayer()
    private var treasureChestCandidateEnabled = RestaurantMapMarkerShape.treasureChestCandidateEnabled
    private var representedRestaurantID: UUID?
    private var representedVisual: RestaurantMapMarkerVisual?
    private var representedImageResolution: RestaurantImageResolution?
    private(set) var imageGeneration = 0
    private var imageRequestInFlight = false
    private var fallbackEmoji = "🍽️"
    private var markerStatus: RestaurantMapMarkerStatus = .visited
    private var distanceKilometers: Double?
    private var densityStyle: RestaurantMapMarkerDensityStyle = .venue

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        centerOffset = .zero
        // MapKit owns this fixed anchor box. Only its centered contents scale.
        let target = TasteMapDesignTokens.Control.minimumHitTarget
        bounds = CGRect(x: 0, y: 0, width: target, height: target)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 1.5
        layer.shadowOffset = CGSize(width: 0, height: 1)

        outerRingLayer.fillColor = UIColor.white.withAlphaComponent(0.98).cgColor
        outerRingLayer.strokeColor = UIColor(red: 0.20, green: 0.28, blue: 0.33, alpha: 0.16).cgColor
        outerRingLayer.lineWidth = CGFloat(RestaurantMapMarkerRingPolicy.outerHairlineWidth)
        visualContainer.clipsToBounds = true
        visualContainer.backgroundColor = .secondarySystemBackground
        dashedRingLayer.fillColor = UIColor.clear.cgColor
        dashedRingLayer.lineCap = .butt
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        emojiLabel.adjustsFontSizeToFitWidth = true
        emojiLabel.font = .systemFont(ofSize: 17)
        emojiLabel.minimumScaleFactor = 0.75
        emojiLabel.textAlignment = .center
        surfaceDepthLayer.colors = [
            UIColor.white.withAlphaComponent(0.16).cgColor,
            UIColor.clear.cgColor,
            UIColor(red: 0.10, green: 0.15, blue: 0.12, alpha: 0.10).cgColor,
        ]
        surfaceDepthLayer.locations = [0, 0.54, 1]
        surfaceDepthLayer.startPoint = CGPoint(x: 0.12, y: 0.04)
        surfaceDepthLayer.endPoint = CGPoint(x: 0.88, y: 0.96)

        layer.addSublayer(outerRingLayer)
        addSubview(visualContainer)
        visualContainer.layer.addSublayer(dashedRingLayer)
        visualContainer.addSubview(imageView)
        visualContainer.addSubview(emojiLabel)
        visualContainer.layer.addSublayer(surfaceDepthLayer)
        chestShellView.contentMode = .scaleAspectFit
        chestShellView.isUserInteractionEnabled = false
        chestWindowMaskLayer.fillRule = .evenOdd
        chestShellView.layer.mask = chestWindowMaskLayer
        visualContainer.addSubview(chestShellView)
        isAccessibilityElement = true
    }

    required init?(coder: NSCoder) { nil }

    #if DEBUG
    // In-process UI-test geometry evidence only; normal users never receive
    // diagnostic coordinates as an accessibility value.
    override var accessibilityValue: String? {
        get {
            guard (ProcessInfo.processInfo.environment["TASTEMAP_VISUAL_QA_MODE"] == "dense-mall"
                || ProcessInfo.processInfo.environment["TASTEMAP_MAP_GEOMETRY_QA"] == "1"),
                  let annotation else { return super.accessibilityValue }
            var ancestor = superview
            while let current = ancestor, !(current is MKMapView) { ancestor = current.superview }
            guard let mapView = ancestor as? MKMapView else { return super.accessibilityValue }
            let actual = visualContainer.convert(
                CGPoint(x: visualContainer.bounds.midX, y: visualContainer.bounds.midY), to: mapView
            )
            let projected = mapView.convert(annotation.coordinate, toPointTo: mapView)
            let geometry = String(
                format: "anchorError %.3f,%.3f; diameter %.3f; coordinate %.6f,%.6f; groupSize %d; kind %@",
                actual.x - projected.x, actual.y - projected.y,
                outerRingLayer.path?.boundingBoxOfPath.width ?? 0,
                annotation.coordinate.latitude, annotation.coordinate.longitude,
                groupSize, groupSize > 1 ? (usesStack ? "stack" : "representative") : "restaurant"
            )
            guard ProcessInfo.processInfo.environment["TASTEMAP_MAP_GEOMETRY_QA"] == "1" else { return geometry }
            let diagnostic = ProcessInfo.processInfo.environment["TASTEMAP_MAP_FRAME_DIAGNOSTICS"] == "1"
                ? "; " + qaFrameSample(in: mapView, actual: actual, projected: projected).diagnostic : ""
            let members = ([self] + stackMemberViews).map {
                "\($0.representedRestaurantID?.uuidString ?? "none"):\($0.imageGeneration)"
            }.joined(separator: ",")
            return geometry + diagnostic + String(format: "; priority %.3f; layer %.3f; members %@", zPriority.rawValue, layer.zPosition, members)
        }
        set { super.accessibilityValue = newValue }
    }

    func qaFrameSample(in mapView: MKMapView, actual: CGPoint? = nil, projected: CGPoint? = nil) -> RestaurantMapMarkerFrameSample {
        let center = CGPoint(x: visualContainer.bounds.midX, y: visualContainer.bounds.midY)
        let modelPoint = actual ?? visualContainer.convert(center, to: mapView)
        let coordinate = annotation?.coordinate ?? kCLLocationCoordinate2DInvalid
        let projectedPoint = projected ?? mapView.convert(coordinate, toPointTo: mapView)
        let time = CACurrentMediaTime()
        let presented: CGPoint?
        if let visualLayer = visualContainer.layer.presentation(), let mapLayer = mapView.layer.presentation() {
            presented = visualLayer.convert(center, to: mapLayer)
        } else { presented = nil }
        return RestaurantMapMarkerFrameSample(
            time: time, actual: modelPoint, presented: presented, projected: projectedPoint,
            projectedAfter: mapView.convert(coordinate, toPointTo: mapView), center: mapView.region.center
        )
    }
    #endif

    override func prepareForReuse() {
        super.prepareForReuse()
        representedRestaurantID = nil
        representedVisual = nil
        representedImageResolution = nil
        imageGeneration += 1
        imageRequestInFlight = false
        imageView.image = nil
        emojiLabel.text = nil
        layer.zPosition = 0
        zPriority = .defaultUnselected
        selectedZPriority = .defaultSelected
        centerOffset = .zero
        densityStyle = .venue
        groupSize = 1
        usesStack = false
        _ = setStackMembers([])
        isHidden = false
        isAccessibilityElement = true
    }

    override var isSelected: Bool {
        didSet {
            guard oldValue != isSelected else { return }
            setNeedsLayout()
        }
    }

    func setLayerPriority(rank: Int, count: Int) {
        let priority = RestaurantMapMarkerLayerPolicy.mapKitPriority(rank: rank, count: count)
        // layer.zPosition alone is not persistent: MapKit recomposites its
        // annotation views during pan/reuse. Give MapKit the same stable rank.
        let normal = MKAnnotationViewZPriority(rawValue: priority)
        let selected = MKAnnotationViewZPriority(rawValue: 950)
        if zPriority != normal { zPriority = normal }
        if selectedZPriority != selected { selectedZPriority = selected }
        // Do not compete with MapKit by writing the root CALayer zPosition.
        // Only the local back-member layers inside one stack own their zPosition.
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let diameter = RestaurantMapMarkerMetrics.diameter(
            status: markerStatus,
            distanceKilometers: distanceKilometers,
            isSelected: isSelected,
            densityStyle: densityStyle
        )
        let whiteRingWidth = CGFloat(RestaurantMapMarkerRingPolicy.outerWhiteRingWidth)
        let outerDiameter = diameter + whiteRingWidth * 2
        let shape = RestaurantMapMarkerShape.resolve(status: markerStatus, candidateEnabled: treasureChestCandidateEnabled)
        let usesChest = shape == .treasureChest
        // Never resize/reposition the annotation while MapKit lays it out.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let outerFrame = CGRect(
            x: (bounds.width - outerDiameter) / 2, y: (bounds.height - outerDiameter) / 2,
            width: outerDiameter, height: outerDiameter
        )
        for (index, backView) in stackMemberViews.enumerated() {
            let offset = TasteMapDesignTokens.MapRestaurantMarker.stackBackOffsets[index]
            backView.center = CGPoint(x: bounds.midX + offset.width, y: bounds.midY + offset.height)
            backView.setDensityStyle(densityStyle)
        }
        outerRingLayer.frame = bounds
        outerRingLayer.path = shape.path(in: outerFrame)
        outerRingLayer.isHidden = usesChest
        layer.shadowPath = usesChest ? nil : shape.path(in: outerFrame)
        visualContainer.frame = outerFrame.insetBy(dx: whiteRingWidth, dy: whiteRingWidth)
        visualContainer.clipsToBounds = !usesChest
        visualContainer.backgroundColor = usesChest ? .clear : .secondarySystemBackground
        visualContainer.layer.cornerRadius = usesChest ? 0 : diameter / 2
        // PNG fills the same outer diameter, including the former separation
        // ring's space. The annotation and centered visual container never move.
        let chestFrame = visualContainer.bounds.insetBy(dx: -whiteRingWidth, dy: -whiteRingWidth)
        let borderWidth: CGFloat = isSelected ? 3 : 2
        let usesDashedRing = !usesChest && RestaurantMapMarkerRingPolicy.isDashed(status: markerStatus)
        visualContainer.layer.borderWidth = usesChest || usesDashedRing ? 0 : borderWidth
        dashedRingLayer.isHidden = !usesDashedRing
        dashedRingLayer.frame = visualContainer.bounds
        dashedRingLayer.path = UIBezierPath(
            ovalIn: visualContainer.bounds.insetBy(dx: borderWidth / 2, dy: borderWidth / 2)
        ).cgPath
        dashedRingLayer.lineWidth = borderWidth
        dashedRingLayer.lineDashPattern = RestaurantMapMarkerRingPolicy.unvisitedDashPattern.map(NSNumber.init(value:))
        imageView.frame = usesChest ? RestaurantMapMarkerShape.photoFrame(in: chestFrame)
            : visualContainer.bounds.insetBy(dx: borderWidth, dy: borderWidth)
        imageView.layer.cornerRadius = usesChest ? 0 : max(0, (diameter - borderWidth * 2) / 2)
        let fallbackInset = borderWidth + 3 * (1 - densityStyle.farZoomProgress)
        emojiLabel.frame = usesChest ? RestaurantMapMarkerShape.photoFrame(in: chestFrame)
            : visualContainer.bounds.insetBy(dx: fallbackInset, dy: fallbackInset)
        emojiLabel.font = .systemFont(ofSize: max(4, diameter * 0.58))
        surfaceDepthLayer.frame = visualContainer.bounds
        surfaceDepthLayer.cornerRadius = usesChest ? 0 : diameter / 2
        surfaceDepthLayer.isHidden = usesChest
        chestShellView.isHidden = !usesChest
        if usesChest && (chestShellView.frame != chestFrame || chestWindowMaskLayer.path == nil) {
            chestShellView.frame = chestFrame
            chestWindowMaskLayer.frame = chestShellView.bounds
            chestWindowMaskLayer.path = RestaurantMapMarkerShape.shellMask(in: chestShellView.bounds)
        }
    }

#if DEBUG
    /// Isolated unit-test access only; no launch flag or product setting enables
    /// Lafayette's paused candidate in a formal app instance.
    func setTreasureChestCandidateForTesting(_ enabled: Bool) {
        treasureChestCandidateEnabled = enabled
        stackMemberViews.forEach { $0.setTreasureChestCandidateForTesting(enabled) }
        setNeedsLayout()
    }
#endif

    /// Returns true only when this visual still needs an image request. Pure
    /// metadata/layout updates keep the already rendered bitmap in place.
    func configure(_ marker: RestaurantMapMarkerPresentation) -> Bool {
        let visualChanged = representedRestaurantID != marker.id || representedVisual != marker.visual
            || representedImageResolution != marker.imageResolution
        representedRestaurantID = marker.id
        representedVisual = marker.visual
        representedImageResolution = marker.imageResolution
        markerStatus = marker.status
        distanceKilometers = marker.distanceKilometers
        switch marker.visual {
        case .emoji(let value): fallbackEmoji = value
        case .category(let value): fallbackEmoji = FoodCategoryEmojiResolver.resolve(
            name: marker.name,
            fallbackCategory: value
        )
        case .photo: fallbackEmoji = FoodCategoryEmojiResolver.resolve(name: marker.name)
        }
        emojiLabel.text = fallbackEmoji
        let ringRating = RestaurantMapMarkerRingPolicy.isUnvisited(status: marker.status) ? nil : marker.averageRating
        let ringColor = ratingColor(ringRating).cgColor
        normalRingColor = UIColor(cgColor: ringColor)
        visualContainer.layer.borderColor = ringColor
        dashedRingLayer.strokeColor = ringColor
        visualContainer.alpha = RestaurantMapMarkerRingPolicy.opacity(status: marker.status)
        if visualChanged {
            imageGeneration += 1
            imageRequestInFlight = false
            imageView.image = nil
            showFallback()
        }
        accessibilityIdentifier = "restaurant-map-marker-\(marker.id.uuidString)"
        let rating = marker.averageRating.map { String(format: "，评分 %.1f", $0) } ?? "，未评分"
        restaurantAccessibilityLabel = "\(marker.name)，\(marker.status.accessibilityTitle)，\(marker.visitCount) 次到访\(rating)"
        refreshGroupAccessibility()
        setNeedsLayout()
        guard !marker.imageResolution.isFallbackOnly else { return false }
        return visualChanged || (imageView.image == nil && !imageRequestInFlight)
    }

    func setGroup(count: Int, stacked: Bool) {
        let count = max(1, count)
        guard groupSize != count || usesStack != stacked else { return }
        groupSize = count
        usesStack = stacked
        refreshGroupAccessibility()
        setNeedsLayout()
        layoutIfNeeded()
        refreshVisualVisibility()
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard !isHidden else { return false }
        return super.point(inside: point, with: event)
            || stackMemberViews.contains { $0.frame.contains(point) }
    }

    /// Real local Restaurant thumbnails, not repeated outlines or copies of
    /// the leader photo. Back offsets belong to this composite, not the map.
    @discardableResult
    func setStackMembers(_ members: [RestaurantMapMarkerPresentation]) -> [(RestaurantMarkerAnnotationView, RestaurantMapMarkerPresentation)] {
        let members = Array(members.prefix(TasteMapDesignTokens.MapRestaurantMarker.stackBackOffsets.count))
        guard !members.isEmpty || !stackMemberViews.isEmpty else { return [] }
        let countChanged = stackMemberViews.count != members.count
        while stackMemberViews.count > members.count {
            let removed = stackMemberViews.removeLast()
            removed.prepareForReuse()
            removed.removeFromSuperview()
        }
        while stackMemberViews.count < members.count {
            let backView = RestaurantMarkerAnnotationView(annotation: nil, reuseIdentifier: nil)
            backView.treasureChestCandidateEnabled = treasureChestCandidateEnabled
            backView.isAccessibilityElement = false
            backView.accessibilityElementsHidden = true
            backView.isUserInteractionEnabled = false
            stackMemberViews.append(backView)
            backView.layer.zPosition = -CGFloat(stackMemberViews.count)
            insertSubview(backView, at: 0)
        }
        if countChanged {
            setNeedsLayout()
            layoutIfNeeded()
        }
        return Array(zip(stackMemberViews, members))
    }

    private func refreshGroupAccessibility() {
        accessibilityLabel = groupSize > 1
            ? restaurantAccessibilityLabel + (usesStack ? "，此处有重叠餐厅，查看列表" : "，区域代表餐厅，放大查看")
            : restaurantAccessibilityLabel
    }

    func setDensityStyle(_ value: RestaurantMapMarkerDensityStyle) {
        guard abs(value.baseDiameter - densityStyle.baseDiameter) >= 0.15 else { return }
        densityStyle = value
        setNeedsLayout()
        layoutIfNeeded()
        refreshVisualVisibility()
    }

    func setProgressivelyVisible(_ visible: Bool) {
        isHidden = !visible
        isAccessibilityElement = visible
        accessibilityElementsHidden = !visible
        accessibilityIdentifier = visible ? representedRestaurantID.map { "restaurant-map-marker-\($0.uuidString)" } : nil
        if visible { refreshGroupAccessibility() } else { accessibilityLabel = nil }
    }

    func beginImageLoad(for restaurantID: UUID) {
        guard representedRestaurantID == restaurantID else { return }
        imageRequestInFlight = true
    }

    func show(image: UIImage, for restaurantID: UUID) {
        guard representedRestaurantID == restaurantID else { return }
        imageRequestInFlight = false
        imageView.image = image
        refreshVisualVisibility()
    }

    func finishImageLoad(_ image: UIImage?, for marker: RestaurantMapMarkerPresentation, generation: Int) {
        guard representedRestaurantID == marker.id,
              representedVisual == marker.visual,
              representedImageResolution == marker.imageResolution,
              imageGeneration == generation else { return }
        imageRequestInFlight = false
        imageView.image = image
        refreshVisualVisibility()
    }

    func showFallback() {
        imageRequestInFlight = false
        imageView.image = nil
        emojiLabel.text = fallbackEmoji
        refreshVisualVisibility()
    }

    private func refreshVisualVisibility() {
        // Regional representatives retain the favorite Restaurant's own
        // visual. Zoom never substitutes an unrelated decorative food symbol.
        let showsImage = imageView.image != nil
        imageView.isHidden = !showsImage
        emojiLabel.isHidden = showsImage
        visualContainer.backgroundColor = .secondarySystemBackground
        visualContainer.layer.borderColor = normalRingColor.cgColor
        surfaceDepthLayer.isHidden = false
    }

    private func ratingColor(_ rating: Double?) -> UIColor {
        let color = RestaurantScoreColorPolicy.color(forFivePointRating: rating)
        return UIColor(red: color.red, green: color.green, blue: color.blue, alpha: 1)
    }

}
