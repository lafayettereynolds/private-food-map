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
    @Binding var selectedRestaurantID: UUID?
    let fitRequestID: UUID
    let locationRequestID: UUID?
    let onRenderStateChange: (RestaurantMapRenderState) -> Void
    let onViewportChange: (RestaurantMapViewport) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
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
        private var imageTasks: [UUID: Task<Void, Never>] = [:]
        private var userAvatarTask: Task<Void, Never>?
        private var lastFitRequestID: UUID?
        private var lastLocationRequestID: UUID?
        private var lastSelectedRestaurantID: UUID?
        private var isUserInteracting = false
        private var hasDeferredFit = false
        private var renderState: RestaurantMapRenderState = .loading
        private var markerLayerRanks: [UUID: Int] = [:]

        init(parent: RestaurantMapView) {
            self.parent = parent
        }

        deinit {
            imageTasks.values.forEach { $0.cancel() }
            userAvatarTask?.cancel()
        }

        func updateAnnotations(on mapView: MKMapView) {
            let visibleMarkers = RestaurantMapViewportPolicy.visibleMarkers(
                parent.markers,
                in: RestaurantMapViewport(
                    centerLatitude: mapView.region.center.latitude,
                    centerLongitude: mapView.region.center.longitude,
                    latitudeDelta: mapView.region.span.latitudeDelta,
                    longitudeDelta: mapView.region.span.longitudeDelta
                ),
                selectedRestaurantID: parent.selectedRestaurantID
            )
            let incoming = Dictionary(uniqueKeysWithValues: visibleMarkers.map { ($0.id, $0) })
            let removedIDs = Set(annotationsByID.keys).subtracting(incoming.keys)
            let removed = removedIDs.compactMap { annotationsByID.removeValue(forKey: $0) }
            removedIDs.forEach {
                imageTasks[$0]?.cancel()
                imageTasks[$0] = nil
            }
            if !removed.isEmpty { mapView.removeAnnotations(removed) }

            var added: [RestaurantMapAnnotation] = []
            for marker in visibleMarkers {
                if let annotation = annotationsByID[marker.id] {
                    guard annotation.presentation != marker else { continue }
                    annotation.presentation = marker
                    annotation.coordinate = marker.coordinate
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

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let annotation = view.annotation as? RestaurantMapAnnotation else { return }
            let feedback = UISelectionFeedbackGenerator()
            feedback.prepare()
            feedback.selectionChanged()
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
            if mapView.gestureRecognizers?.contains(where: {
                $0.state == .began || $0.state == .changed
            }) == true {
                isUserInteracting = true
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            // Refresh only after MapKit settles a pan/zoom. Offscreen
            // annotations and their image tasks are removed, while every
            // Restaurant in the padded viewport stays an independent marker.
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
            let marker = annotation.presentation
            view.configure(marker)
            imageTasks[marker.id]?.cancel()
            imageTasks[marker.id] = nil

            guard !marker.imageResolution.isFallbackOnly else { return }
            imageTasks[marker.id] = Task { @MainActor [weak view] in
                let result = await RestaurantImageLoader.image(
                    resolution: marker.imageResolution,
                    photosByID: parent.photosByID,
                    coordinator: parent.photoCoordinator,
                    photoAPI: parent.photoAPI,
                    variant: .thumbnail,
                    semanticID: marker.id.uuidString
                )
                guard !Task.isCancelled, let result else {
                    if !Task.isCancelled { view?.showFallback() }
                    return
                }
                view?.show(image: result.image, for: marker.id)
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

        /// MapKit remains responsible for annotation placement. This method
        /// changes only the compositing order of Restaurant views, preserving
        /// exact coordinates and natural overlap across viewport refreshes.
        private func applyMarkerLayerOrder(on mapView: MKMapView) {
            refreshMarkerLayerRanks()
            for (restaurantID, annotation) in annotationsByID {
                guard let view = mapView.view(for: annotation) as? RestaurantMarkerAnnotationView else {
                    continue
                }
                view.layer.zPosition = CGFloat(markerLayerRanks[restaurantID] ?? 0)
            }
            if let userView = mapView.view(for: mapView.userLocation) as? TasteMapUserLocationAnnotationView {
                userView.layer.zPosition = Self.userLocationLayerPosition
            }
        }

        private func applyMarkerLayerOrder(
            to view: RestaurantMarkerAnnotationView,
            restaurantID: UUID
        ) {
            if markerLayerRanks[restaurantID] == nil { refreshMarkerLayerRanks() }
            view.layer.zPosition = CGFloat(markerLayerRanks[restaurantID] ?? 0)
        }

        private func refreshMarkerLayerRanks() {
            markerLayerRanks = RestaurantMapMarkerLayerPolicy.layerRanks(
                annotationsByID.values.map(\.presentation),
                selectedRestaurantID: parent.selectedRestaurantID
            )
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
    private let avatarView = UIImageView()
    private(set) var representedPhotoReference: UUID?
    private var presetImage: UIImage?

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 54, height: 54)
        backgroundColor = .clear
        collisionMode = .circle
        displayPriority = .required
        canShowCallout = false

        haloView.frame = CGRect(x: 2, y: 2, width: 50, height: 50)
        haloView.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.18)
        haloView.layer.cornerRadius = 25
        haloView.layer.shadowColor = UIColor.black.cgColor
        haloView.layer.shadowOpacity = 0.14
        haloView.layer.shadowRadius = 5
        haloView.layer.shadowOffset = CGSize(width: 0, height: 2)
        addSubview(haloView)

        avatarView.frame = CGRect(x: 7, y: 7, width: 40, height: 40)
        avatarView.contentMode = .scaleAspectFill
        avatarView.clipsToBounds = true
        avatarView.layer.cornerRadius = 20
        avatarView.layer.borderWidth = 3
        avatarView.layer.borderColor = UIColor.white.cgColor
        addSubview(avatarView)
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

@MainActor
private final class RestaurantMarkerAnnotationView: MKAnnotationView {
    private let visualContainer = UIView()
    private let imageView = UIImageView()
    private let emojiLabel = UILabel()
    private var representedRestaurantID: UUID?
    private var fallbackEmoji = "🍽️"
    private var markerStatus: RestaurantMapMarkerStatus = .visited
    private var distanceKilometers: Double?

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        centerOffset = CGPoint(x: 0, y: -22)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.16
        layer.shadowRadius = 5
        layer.shadowOffset = CGSize(width: 0, height: 2)

        visualContainer.clipsToBounds = true
        visualContainer.backgroundColor = .secondarySystemBackground
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        emojiLabel.adjustsFontSizeToFitWidth = true
        emojiLabel.font = .systemFont(ofSize: 25)
        emojiLabel.minimumScaleFactor = 0.75
        emojiLabel.textAlignment = .center

        addSubview(visualContainer)
        visualContainer.addSubview(imageView)
        visualContainer.addSubview(emojiLabel)
        isAccessibilityElement = true
    }

    required init?(coder: NSCoder) { nil }

    override func prepareForReuse() {
        super.prepareForReuse()
        representedRestaurantID = nil
        imageView.image = nil
        emojiLabel.text = nil
        layer.zPosition = 0
    }

    override var isSelected: Bool {
        didSet {
            guard oldValue != isSelected else { return }
            setNeedsLayout()
            transform = isSelected ? CGAffineTransform(scaleX: 1.04, y: 1.04) : .identity
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let diameter = RestaurantMapMarkerMetrics.diameter(
            status: markerStatus,
            distanceKilometers: distanceKilometers,
            isSelected: isSelected
        )
        bounds = CGRect(x: 0, y: 0, width: diameter + 8, height: diameter + 8)
        centerOffset = CGPoint(x: 0, y: -(diameter / 2))
        visualContainer.frame = CGRect(x: 4, y: 2, width: diameter, height: diameter)
        visualContainer.layer.cornerRadius = diameter / 2
        visualContainer.layer.borderWidth = isSelected ? 4 : 3
        imageView.frame = visualContainer.bounds.insetBy(dx: 3, dy: 3)
        imageView.layer.cornerRadius = max(0, (diameter - 6) / 2)
        emojiLabel.frame = visualContainer.bounds.insetBy(dx: 6, dy: 6)
    }

    func configure(_ marker: RestaurantMapMarkerPresentation) {
        representedRestaurantID = marker.id
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
        visualContainer.layer.borderColor = ratingColor(marker.averageRating).cgColor
        imageView.image = nil
        showFallback()
        accessibilityIdentifier = "restaurant-map-marker-\(marker.id.uuidString)"
        let rating = marker.averageRating.map { String(format: "，评分 %.1f", $0) } ?? "，未评分"
        accessibilityLabel = "\(marker.name)，\(marker.status.accessibilityTitle)，\(marker.visitCount) 次到访\(rating)"
        setNeedsLayout()
    }

    func show(image: UIImage, for restaurantID: UUID) {
        guard representedRestaurantID == restaurantID else { return }
        imageView.image = image
        emojiLabel.isHidden = true
    }

    func showFallback() {
        imageView.image = nil
        emojiLabel.isHidden = false
        emojiLabel.text = fallbackEmoji
    }

    private func ratingColor(_ rating: Double?) -> UIColor {
        let color = RestaurantScoreColorPolicy.color(forFivePointRating: rating)
        return UIColor(red: color.red, green: color.green, blue: color.blue, alpha: 1)
    }

}
