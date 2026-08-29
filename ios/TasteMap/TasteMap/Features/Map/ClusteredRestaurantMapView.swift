import MapKit
import SwiftUI
import UIKit

struct ClusteredRestaurantMapView: UIViewRepresentable {
    let markers: [RestaurantMapMarkerPresentation]
    let photosByID: [UUID: PhotoAsset]
    let photoCoordinator: PhotoTransferCoordinator?
    @Binding var selectedRestaurantID: UUID?
    let fitRequestID: UUID
    let locationRequestID: UUID?
    let onRenderStateChange: (RestaurantMapRenderState) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.pointOfInterestFilter = .includingAll
        mapView.isPitchEnabled = false
        mapView.accessibilityIdentifier = "restaurant-map"
        context.coordinator.setRenderState(.loading)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateAnnotations(on: mapView)
        context.coordinator.applySelection(on: mapView)
        context.coordinator.fitIfRequested(on: mapView)
        context.coordinator.centerOnUserIfRequested(on: mapView)
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: ClusteredRestaurantMapView
        private var annotationsByID: [UUID: RestaurantMapAnnotation] = [:]
        private var imageTasks: [UUID: Task<Void, Never>] = [:]
        private var lastFitRequestID: UUID?
        private var lastLocationRequestID: UUID?
        private var isUserInteracting = false
        private var hasDeferredFit = false
        private var renderState: RestaurantMapRenderState = .loading

        init(parent: ClusteredRestaurantMapView) {
            self.parent = parent
        }

        deinit {
            imageTasks.values.forEach { $0.cancel() }
        }

        func updateAnnotations(on mapView: MKMapView) {
            let incoming = Dictionary(uniqueKeysWithValues: parent.markers.map { ($0.id, $0) })
            let removedIDs = Set(annotationsByID.keys).subtracting(incoming.keys)
            let removed = removedIDs.compactMap { annotationsByID.removeValue(forKey: $0) }
            removedIDs.forEach {
                imageTasks[$0]?.cancel()
                imageTasks[$0] = nil
            }
            if !removed.isEmpty { mapView.removeAnnotations(removed) }

            var added: [RestaurantMapAnnotation] = []
            for marker in parent.markers {
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
            if !added.isEmpty { mapView.addAnnotations(added) }
        }

        func applySelection(on mapView: MKMapView) {
            for (id, annotation) in annotationsByID {
                let shouldSelect = id == parent.selectedRestaurantID
                let isSelected = mapView.selectedAnnotations.contains { $0 === annotation }
                if shouldSelect, !isSelected {
                    mapView.selectAnnotation(annotation, animated: false)
                } else if !shouldSelect, isSelected {
                    mapView.deselectAnnotation(annotation, animated: false)
                }
            }
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
            if annotation is MKUserLocation { return nil }
            if let cluster = annotation as? MKClusterAnnotation {
                let identifier = "taste-map-cluster"
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                    as? RestaurantClusterAnnotationView)
                    ?? RestaurantClusterAnnotationView(annotation: cluster, reuseIdentifier: identifier)
                view.annotation = cluster
                view.configure(count: cluster.memberAnnotations.count)
                return view
            }
            guard let restaurant = annotation as? RestaurantMapAnnotation else { return nil }
            let identifier = "taste-map-restaurant"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                as? RestaurantMarkerAnnotationView)
                ?? RestaurantMarkerAnnotationView(annotation: restaurant, reuseIdentifier: identifier)
            view.annotation = restaurant
            view.clusteringIdentifier = "taste-map-restaurants"
            view.displayPriority = .defaultHigh
            view.collisionMode = .circle
            configure(view, for: restaurant)
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let cluster = view.annotation as? MKClusterAnnotation {
                let members = cluster.memberAnnotations.compactMap { $0 as? RestaurantMapAnnotation }
                let presentations = members.map(\.presentation)
                applyCameraTarget(
                    RestaurantMapClusterPresentation(members: presentations).expansionTarget,
                    on: mapView,
                    animated: true
                )
                mapView.deselectAnnotation(cluster, animated: false)
                return
            }
            guard let annotation = view.annotation as? RestaurantMapAnnotation else { return }
            parent.selectedRestaurantID = annotation.presentation.id
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
            guard isUserInteracting else { return }
            let stillInteracting = mapView.gestureRecognizers?.contains(where: {
                $0.state == .began || $0.state == .changed
            }) == true
            guard !stillInteracting else { return }
            isUserInteracting = false
            if hasDeferredFit { fitIfRequested(on: mapView) }
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

            switch marker.visual {
            case let .photo(photoID):
                guard let photo = parent.photosByID[photoID], let coordinator = parent.photoCoordinator else {
                    view.showFallback()
                    return
                }
                imageTasks[marker.id] = Task { @MainActor [weak view] in
                    guard let data = try? await coordinator.imageData(for: photo, variant: .thumbnail),
                          !Task.isCancelled,
                          let image = UIImage(data: data) else {
                        if !Task.isCancelled { view?.showFallback() }
                        return
                    }
                    view?.show(image: image, for: marker.id)
                }
            case let .merchantImage(url):
                imageTasks[marker.id] = Task { @MainActor [weak view] in
                    let data = await RestaurantMapRemoteImageLoader.shared.data(for: url)
                    guard !Task.isCancelled, let data, let image = UIImage(data: data) else {
                        if !Task.isCancelled { view?.showFallback() }
                        return
                    }
                    view?.show(image: image, for: marker.id)
                }
            case .emoji, .fallback:
                break
            }
        }

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
private final class RestaurantMarkerAnnotationView: MKAnnotationView {
    private let visualContainer = UIView()
    private let imageView = UIImageView()
    private let emojiLabel = UILabel()
    private let statusBadge = UIImageView()
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
        emojiLabel.textAlignment = .center
        emojiLabel.adjustsFontSizeToFitWidth = true
        statusBadge.contentMode = .center
        statusBadge.tintColor = .white

        addSubview(visualContainer)
        visualContainer.addSubview(imageView)
        visualContainer.addSubview(emojiLabel)
        addSubview(statusBadge)
        isAccessibilityElement = true
    }

    required init?(coder: NSCoder) { nil }

    override func prepareForReuse() {
        super.prepareForReuse()
        representedRestaurantID = nil
        imageView.image = nil
        emojiLabel.text = nil
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
        emojiLabel.frame = visualContainer.bounds.insetBy(dx: 7, dy: 7)
        emojiLabel.font = .systemFont(ofSize: isSelected ? 27 : 23)
        statusBadge.frame = CGRect(x: diameter - 8, y: diameter - 10, width: 18, height: 18)
        statusBadge.layer.cornerRadius = 9
    }

    func configure(_ marker: RestaurantMapMarkerPresentation) {
        representedRestaurantID = marker.id
        markerStatus = marker.status
        distanceKilometers = marker.distanceKilometers
        fallbackEmoji = {
            if case let .emoji(value) = marker.visual { return value }
            return "🍽️"
        }()
        visualContainer.layer.borderColor = statusColor(marker.status).cgColor
        statusBadge.backgroundColor = statusColor(marker.status)
        statusBadge.image = UIImage(
            systemName: statusSymbol(marker.status),
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        )
        imageView.image = nil
        emojiLabel.text = fallbackEmoji
        accessibilityIdentifier = "restaurant-map-marker-\(marker.id.uuidString)"
        let rating = marker.averageRating.map { String(format: "，评分 %.1f", $0) } ?? "，未评分"
        accessibilityLabel = "\(marker.name)，\(marker.status.accessibilityTitle)，\(marker.visitCount) 次到访\(rating)"
        setNeedsLayout()
    }

    func show(image: UIImage, for restaurantID: UUID) {
        guard representedRestaurantID == restaurantID else { return }
        imageView.image = image
        emojiLabel.text = nil
    }

    func showFallback() {
        imageView.image = nil
        emojiLabel.text = fallbackEmoji
    }

    private func statusColor(_ status: RestaurantMapMarkerStatus) -> UIColor {
        switch status {
        case .visited: UIColor(red: 0.30, green: 0.42, blue: 0.53, alpha: 1)
        case .wantToGo: UIColor(red: 0.45, green: 0.57, blue: 0.67, alpha: 1)
        case .recommended: UIColor(red: 0.38, green: 0.49, blue: 0.61, alpha: 1)
        }
    }

    private func statusSymbol(_ status: RestaurantMapMarkerStatus) -> String {
        switch status {
        case .visited: "checkmark"
        case .wantToGo: "bookmark.fill"
        case .recommended: "sparkles"
        }
    }
}

@MainActor
private final class RestaurantClusterAnnotationView: MKAnnotationView {
    private let countLabel = UILabel()

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 48, height: 48)
        backgroundColor = UIColor(red: 0.30, green: 0.42, blue: 0.53, alpha: 0.94)
        layer.cornerRadius = 24
        layer.borderWidth = 3
        layer.borderColor = UIColor.white.withAlphaComponent(0.9).cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.18
        layer.shadowRadius = 5
        layer.shadowOffset = CGSize(width: 0, height: 2)
        collisionMode = .circle
        displayPriority = .defaultHigh
        countLabel.frame = bounds
        countLabel.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        countLabel.textAlignment = .center
        countLabel.textColor = .white
        countLabel.font = .systemFont(ofSize: 15, weight: .bold)
        addSubview(countLabel)
        isAccessibilityElement = true
    }

    required init?(coder: NSCoder) { nil }

    func configure(count: Int) {
        countLabel.text = String(count)
        accessibilityLabel = "附近 \(count) 家餐厅"
        accessibilityIdentifier = "restaurant-map-cluster-\(count)"
    }
}

private actor RestaurantMapRemoteImageLoader {
    static let shared = RestaurantMapRemoteImageLoader()
    private var cache: [URL: Data] = [:]
    private var requests: [URL: Task<Data?, Never>] = [:]
    private let maximumBytes = 8 * 1_024 * 1_024

    func data(for url: URL) async -> Data? {
        if let cached = cache[url] { return cached }
        if let request = requests[url] { return await request.value }
        let maximumBytes = self.maximumBytes
        let request = Task<Data?, Never> {
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  let response = response as? HTTPURLResponse,
                  (200 ... 299).contains(response.statusCode),
                  response.mimeType?.hasPrefix("image/") == true,
                  !data.isEmpty,
                  data.count <= maximumBytes else { return nil }
            return data
        }
        requests[url] = request
        let result = await request.value
        requests[url] = nil
        if let result {
            if cache.count >= 48, let oldest = cache.keys.first { cache[oldest] = nil }
            cache[url] = result
        }
        return result
    }
}
