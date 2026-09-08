import CoreLocation
import CoreGraphics
import Foundation

enum RestaurantMapMarkerStatus: String, Equatable {
    case visited
    case wantToGo
    case recommended

    var accessibilityTitle: String {
        switch self {
        case .visited: "去过"
        case .wantToGo: "想吃"
        case .recommended: "推荐"
        }
    }
}

/// Restores the established Web distinction for places the viewer has not
/// visited: wanted and recommended Restaurants share the quiet neutral dashed
/// shell, while visited Restaurants keep the score-colored solid ring.
enum RestaurantMapMarkerRingPolicy {
    static let unvisitedOpacity = 0.82
    static let unvisitedDashPattern = [3.0, 3.0]
    static let outerWhiteRingWidth = 2.0
    static let outerHairlineWidth = 0.75

    static func isUnvisited(status: RestaurantMapMarkerStatus) -> Bool {
        status != .visited
    }

    static func isDashed(status: RestaurantMapMarkerStatus) -> Bool {
        isUnvisited(status: status)
    }

    static func opacity(status: RestaurantMapMarkerStatus) -> Double {
        isUnvisited(status: status) ? unvisitedOpacity : 1
    }
}

enum RestaurantMapMarkerVisual: Equatable {
    case photo(UUID)
    case category(FoodCategoryVisualID)
    case emoji(String)
}

struct RestaurantMapMarkerPresentation: Identifiable, Equatable {
    let id: UUID
    let name: String
    let latitude: Double
    let longitude: Double
    let status: RestaurantMapMarkerStatus
    let visual: RestaurantMapMarkerVisual
    let publicPhotoID: String?
    let fallbackMerchantImageURL: URL?
    let allowsRemoteImages: Bool
    let recommendationRank: Int?
    let visitCount: Int
    let averageRating: Double?
    let distanceKilometers: Double?

    init(
        id: UUID,
        name: String,
        latitude: Double,
        longitude: Double,
        status: RestaurantMapMarkerStatus,
        visual: RestaurantMapMarkerVisual,
        publicPhotoID: String? = nil,
        fallbackMerchantImageURL: URL? = nil,
        allowsRemoteImages: Bool = false,
        recommendationRank: Int? = nil,
        visitCount: Int,
        averageRating: Double?,
        distanceKilometers: Double?
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.status = status
        self.visual = visual
        self.publicPhotoID = publicPhotoID
        self.fallbackMerchantImageURL = fallbackMerchantImageURL
        self.allowsRemoteImages = allowsRemoteImages
        self.recommendationRank = recommendationRank
        self.visitCount = visitCount
        self.averageRating = averageRating
        self.distanceKilometers = distanceKilometers
    }

    var imageResolution: RestaurantImageResolution {
        let localPhotoID: UUID?
        switch visual {
        case .photo(let id):
            localPhotoID = id
        case .category, .emoji:
            localPhotoID = nil
        }
        return RestaurantImagePriorityPolicy.resolution(
            localUserPhotoID: localPhotoID,
            publicOrCachedPhotoID: allowsRemoteImages ? publicPhotoID : nil,
            providerMerchantImageURL: allowsRemoteImages ? fallbackMerchantImageURL : nil
        )
    }
}

/// A MapKit-independent viewport value keeps large-library culling testable
/// without creating an MKMapView. It never aggregates Restaurants: every
/// returned value is still the original, independently selectable marker.
struct RestaurantMapViewport: Equatable, Sendable {
    let centerLatitude: Double
    let centerLongitude: Double
    let latitudeDelta: Double
    let longitudeDelta: Double
}

enum RestaurantMapViewportPolicy {
    static let prefetchPadding = 1.35

    static func visibleMarkers(
        _ markers: [RestaurantMapMarkerPresentation],
        in viewport: RestaurantMapViewport,
        selectedRestaurantID: UUID? = nil,
        padding: Double = prefetchPadding
    ) -> [RestaurantMapMarkerPresentation] {
        guard viewport.centerLatitude.isFinite,
              viewport.centerLongitude.isFinite,
              viewport.latitudeDelta.isFinite,
              viewport.longitudeDelta.isFinite,
              viewport.latitudeDelta > 0,
              viewport.longitudeDelta > 0 else {
            return markers
        }

        let safePadding = max(1, padding)
        let latitudeRadius = min(90, viewport.latitudeDelta * safePadding / 2)
        let longitudeRadius = min(180, viewport.longitudeDelta * safePadding / 2)
        return markers.filter { marker in
            if marker.id == selectedRestaurantID { return true }
            guard abs(marker.latitude - viewport.centerLatitude) <= latitudeRadius else {
                return false
            }
            guard longitudeRadius < 180 else { return true }
            return wrappedLongitudeDistance(
                marker.longitude,
                viewport.centerLongitude
            ) <= longitudeRadius
        }
    }

    private static func wrappedLongitudeDistance(_ left: Double, _ right: Double) -> Double {
        let raw = abs(left - right).truncatingRemainder(dividingBy: 360)
        return min(raw, 360 - raw)
    }
}

@MainActor
enum RestaurantMapMarkerBuilder {
    static func build(
        items: [RestaurantBrowseItem],
        photos: [PhotoAsset],
        segment: RestaurantBrowseSegment,
        currentLocation: CLLocation? = nil
    ) -> [RestaurantMapMarkerPresentation] {
        var activePhotosByReference: [String: PhotoAsset] = [:]
        for photo in photos where isActive(photo) {
            activePhotosByReference[photo.id.uuidString.lowercased()] = photo
            if let remoteID = trimmed(photo.remoteID) {
                activePhotosByReference[remoteID.lowercased()] = photo
            }
        }

        let markers: [RestaurantMapMarkerPresentation] = items.compactMap { item in
            let restaurant = item.restaurant
            guard restaurant.deletedAt == nil,
                  RestaurantMapCoordinatePolicy.isValid(
                    latitude: restaurant.latitude,
                    longitude: restaurant.longitude
                  ) else { return nil }

            let record = restaurant.remoteRecordData.flatMap {
                try? JSONDecoder().decode(RestaurantJSONContractV1.self, from: $0)
            }
            let usesOwnerEmoji = record?.markerType == .emoji
            let referencedMarkerPhoto = trimmed(record?.markerPhotoId).flatMap {
                activePhotosByReference[$0.lowercased()]
            }.flatMap { photo in
                photo.restaurantId == restaurant.id && photo.kind == .restaurantMarker ? photo : nil
            }
            let localPhoto = usesOwnerEmoji ? nil : (
                referencedMarkerPhoto ?? item.photo.flatMap { photo in
                    isActive(photo) && photo.restaurantId == restaurant.id ? photo : nil
                }
            )
            let visual: RestaurantMapMarkerVisual
            if let photoID = localPhoto?.id {
                visual = .photo(photoID)
            } else if usesOwnerEmoji,
                      let emoji = RestaurantOwnerAvatarEmojiPolicy.normalized(record?.markerEmoji) {
                visual = .emoji(emoji)
            } else {
                visual = .emoji(FoodCategoryEmojiResolver.resolve(
                    name: restaurant.name,
                    tags: record?.tags ?? [],
                    preferredEmoji: record?.markerEmoji
                ))
            }

            return RestaurantMapMarkerPresentation(
                id: restaurant.id,
                name: restaurant.name,
                latitude: restaurant.latitude,
                longitude: restaurant.longitude,
                status: status(for: restaurant, segment: segment),
                visual: visual,
                publicPhotoID: nil,
                fallbackMerchantImageURL: usesOwnerEmoji
                    ? nil
                    : RestaurantImagePriorityPolicy.safeHTTPSURL(record?.merchantImageUrl),
                allowsRemoteImages: !usesOwnerEmoji
                    && RestaurantImagePriorityPolicy.safeHTTPSURL(record?.merchantImageUrl) != nil,
                visitCount: item.visitCount,
                averageRating: item.averageRating,
                distanceKilometers: distanceKilometers(
                    from: currentLocation,
                    to: restaurant,
                    status: status(for: restaurant, segment: segment)
                )
            )
        }
        // Preserve the provider/source coordinate exactly. Overlapping
        // Restaurants remain independent annotations and are resolved by the
        // deterministic layer policy at render time, not by synthetic offsets.
        return markers
    }

    private static func status(
        for restaurant: Restaurant,
        segment: RestaurantBrowseSegment
    ) -> RestaurantMapMarkerStatus {
        if segment == .forYou { return .recommended }
        return restaurant.status == .wantToGo ? .wantToGo : .visited
    }

    private static func isActive(_ photo: PhotoAsset) -> Bool {
        photo.deletedAt == nil && photo.binaryDeletedAt == nil && photo.uploadState != .deleted
    }

    private static func distanceKilometers(
        from currentLocation: CLLocation?,
        to restaurant: Restaurant,
        status: RestaurantMapMarkerStatus
    ) -> Double? {
        guard status == .wantToGo,
              let currentLocation,
              RestaurantMapCoordinatePolicy.isValid(
                latitude: currentLocation.coordinate.latitude,
                longitude: currentLocation.coordinate.longitude
              ) else { return nil }
        let restaurantLocation = CLLocation(
            latitude: restaurant.latitude,
            longitude: restaurant.longitude
        )
        return currentLocation.distance(from: restaurantLocation) / 1_000
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
}

/// One shared back-to-front contract for every Restaurant annotation.
///
/// Layer order never changes coordinates or moves markers to avoid overlap.
/// Recommendation rank
/// is used only for the shared For You projection; personal markers continue
/// to use rating and visit count. An unrated Restaurant is a distinct semantic
/// state below rated Restaurants, rather than a fabricated zero-star score.
enum RestaurantMapMarkerLayerPolicy {
    /// MapKit owns annotation compositing during camera updates. Distinct,
    /// bounded priorities preserve our ordering inside that compositor too.
    static func mapKitPriority(rank: Int, count: Int) -> Float {
        100 + 800 * Float(max(0, rank)) / Float(max(count, rank) + 1)
    }

    static func orderedBackToFront(
        _ markers: [RestaurantMapMarkerPresentation],
        selectedRestaurantID: UUID?
    ) -> [RestaurantMapMarkerPresentation] {
        markers.sorted { left, right in
            isLowerPriority(
                left,
                than: right,
                selectedRestaurantID: selectedRestaurantID
            )
        }
    }

    static func layerRanks(
        _ markers: [RestaurantMapMarkerPresentation],
        selectedRestaurantID: UUID?
    ) -> [UUID: Int] {
        Dictionary(uniqueKeysWithValues: orderedBackToFront(
            markers,
            selectedRestaurantID: selectedRestaurantID
        ).enumerated().map { index, marker in
            (marker.id, index + 1)
        })
    }

    private static func isLowerPriority(
        _ left: RestaurantMapMarkerPresentation,
        than right: RestaurantMapMarkerPresentation,
        selectedRestaurantID: UUID?
    ) -> Bool {
        let leftSelected = left.id == selectedRestaurantID
        let rightSelected = right.id == selectedRestaurantID
        if leftSelected != rightSelected { return !leftSelected }

        let leftRating = finiteRating(left.averageRating)
        let rightRating = finiteRating(right.averageRating)
        switch (leftRating, rightRating) {
        case let (.some(left), .some(right)) where left != right:
            return left < right
        case (.none, .some):
            return true
        case (.some, .none):
            return false
        default:
            break
        }

        let leftRecommendationRank = positiveRank(left.recommendationRank)
        let rightRecommendationRank = positiveRank(right.recommendationRank)
        switch (leftRecommendationRank, rightRecommendationRank) {
        case let (.some(left), .some(right)) where left != right:
            return left > right
        case (.none, .some):
            return true
        case (.some, .none):
            return false
        default:
            break
        }

        let leftVisitCount = max(0, left.visitCount)
        let rightVisitCount = max(0, right.visitCount)
        if leftVisitCount != rightVisitCount {
            return leftVisitCount < rightVisitCount
        }

        return left.id.uuidString.lowercased() < right.id.uuidString.lowercased()
    }

    private static func finiteRating(_ rating: Double?) -> Double? {
        guard let rating, rating.isFinite else { return nil }
        return rating
    }

    private static func positiveRank(_ rank: Int?) -> Int? {
        guard let rank, rank > 0 else { return nil }
        return rank
    }
}

/// Mercator latitude span varies during north/south pans even at the same
/// projected zoom. Advance marker sizing/grouping only when zoom or size changes.
struct RestaurantMapMarkerViewportScale {
    private var projectedSize: CGSize?
    private var viewportSize: CGSize?
    private var latitudeDelta: Double?
    private(set) var revision = 0

    mutating func resolve(latitudeDelta: Double, projectedSize: CGSize, viewportSize: CGSize) -> Double {
        guard projectedSize.width > 0, projectedSize.height > 0,
              viewportSize.width > 0, viewportSize.height > 0,
              latitudeDelta.isFinite, latitudeDelta > 0 else { return self.latitudeDelta ?? latitudeDelta }
        if let previous = self.projectedSize, self.viewportSize == viewportSize,
           abs(previous.width - projectedSize.width) <= max(1, previous.width) * 0.000_001,
           abs(previous.height - projectedSize.height) <= max(1, previous.height) * 0.000_001,
           let previousLatitudeDelta = self.latitudeDelta {
            return previousLatitudeDelta
        }
        self.projectedSize = projectedSize
        self.viewportSize = viewportSize
        self.latitudeDelta = latitudeDelta
        revision += 1
        return latitudeDelta
    }
}

/// Size changes continuously around the exact geographic anchor. At wider
/// regional scales, naturally overlapping Restaurants progressively yield
/// to a real favorite representative; close city browsing keeps every marker.
struct RestaurantMapMarkerDensityStyle: Equatable {
    let zoomProgress: Double
    var farZoomProgress: Double = 0

    static let venue = Self(zoomProgress: 0)
    static let city = Self(zoomProgress: 0.5)
    static let region = Self(zoomProgress: 0.75)
    static let world = Self(zoomProgress: 1, farZoomProgress: 1)
    // Keep every Restaurant throughout city browsing. Only a much wider
    // regional view progressively settles on real Restaurant representatives.
    static let regionalAggregationMinimumLatitudeDelta = 0.8
    static let regionalAggregationFullLatitudeDelta = 2.4

    static func resolve(latitudeDelta: Double) -> Self {
        let nearDelta = 0.008
        let farDelta = 1.50
        let finiteDelta = latitudeDelta.isFinite ? latitudeDelta : farDelta
        let clampedDelta = min(farDelta, max(nearDelta, finiteDelta))
        let progress = log(clampedDelta / nearDelta) / log(farDelta / nearDelta)
        let tokens = TasteMapDesignTokens.MapRestaurantMarker.self
        let farProgress = min(1, max(0, log(max(tokens.farScaleStartLatitudeDelta, finiteDelta)
            / tokens.farScaleStartLatitudeDelta)
            / log(tokens.farScaleFullLatitudeDelta / tokens.farScaleStartLatitudeDelta)))
        return Self(zoomProgress: progress, farZoomProgress: farProgress)
    }

    /// A continuous overlap radius avoids replacing a whole city at one zoom
    /// threshold. Nearby points merge first; wider groups form as we zoom out.
    static func groupingProgress(latitudeDelta: Double) -> Double {
        guard latitudeDelta.isFinite,
              latitudeDelta > regionalAggregationMinimumLatitudeDelta else { return 0 }
        return min(1, log(latitudeDelta / regionalAggregationMinimumLatitudeDelta)
            / log(regionalAggregationFullLatitudeDelta / regionalAggregationMinimumLatitudeDelta))
    }

    var baseDiameter: Double {
        let tokens = TasteMapDesignTokens.MapRestaurantMarker.self
        let cityDiameter = tokens.maximumDiameter
            - (tokens.maximumDiameter - tokens.minimumDiameter) * zoomProgress
        return cityDiameter + (tokens.farMinimumDiameter - cityDiameter) * farZoomProgress
    }

    var selectionIncrease: Double {
        let tokens = TasteMapDesignTokens.MapRestaurantMarker.self
        let cityIncrease = tokens.maximumSelectionIncrease
            - (tokens.maximumSelectionIncrease - tokens.minimumSelectionIncrease) * zoomProgress
        return cityIncrease + (tokens.farSelectionIncrease - cityIncrease) * farZoomProgress
    }

    var unvisitedIncrease: Double {
        let tokens = TasteMapDesignTokens.MapRestaurantMarker.self
        return tokens.unvisitedDiameterIncrease
            + (tokens.farUnvisitedDiameterIncrease - tokens.unvisitedDiameterIncrease) * farZoomProgress
    }

    var regionalGroupingDistance: CGFloat {
        // Only controls when overlapping visuals consolidate. It must never
        // be used as a displacement or a minimum distance between coordinates.
        // Far-distance visual sizing must not change the approved grouping.
        let tokens = TasteMapDesignTokens.MapRestaurantMarker.self
        let cityDiameter = tokens.maximumDiameter
            - (tokens.maximumDiameter - tokens.minimumDiameter) * zoomProgress
        return CGFloat((cityDiameter * 1.14 + 7).rounded(.up))
    }
}

/// Zoom-scaled geographic grouping for iOS MapKit. Screen points are projected
/// exclusively from stored coordinates and compared by relative distance, so
/// a pure pan cannot change membership. The first member is the same stable,
/// highest-priority real Restaurant used by the marker layer policy.
enum RestaurantMapRegionalGroupingPolicy {
    /// Exact provider coordinates, not a guessed building/category match.
    static func isCoincident(_ group: [RestaurantMapMarkerPresentation]) -> Bool {
        guard let first = group.first else { return false }
        return group.allSatisfy { $0.latitude == first.latitude && $0.longitude == first.longitude }
    }

    static func groups(
        for markers: [RestaurantMapMarkerPresentation],
        screenPoints: [UUID: CGPoint],
        requiredCenterDistance: CGFloat,
        latitudeDelta: Double
    ) -> [[RestaurantMapMarkerPresentation]] {
        // Original coordinates are immutable: overlap is natural, not a cue
        // to move a Restaurant into an invented free slot. Wider zooms only
        // change which real Restaurant represents each connected group.
        let ordered = Array(RestaurantMapMarkerLayerPolicy.orderedBackToFront(
            markers,
            // Selection affects z-order, never which Restaurant represents a
            // region. This keeps the favorite leader stable after returning
            // from detail or repeatedly zooming the same area.
            selectedRestaurantID: nil
        ).reversed())
        let progress = RestaurantMapMarkerDensityStyle.groupingProgress(latitudeDelta: latitudeDelta)
        guard progress > 0 else {
            var stacks: [[RestaurantMapMarkerPresentation]] = []
            for marker in ordered {
                if let index = stacks.firstIndex(where: { stack in
                    guard let leader = stack.first else { return false }
                    return isCoincident([leader, marker])
                }) {
                    stacks[index].append(marker)
                } else {
                    stacks.append([marker])
                }
            }
            return stacks
        }
        let threshold = max(0, requiredCenterDistance) * progress

        var remaining = Set(ordered.map(\.id))
        var result: [[RestaurantMapMarkerPresentation]] = []
        for seed in ordered where remaining.contains(seed.id) {
            remaining.remove(seed.id)
            var group = [seed]
            var searchIndex = 0
            while searchIndex < group.count {
                let current = group[searchIndex]
                for candidate in ordered where remaining.contains(candidate.id) {
                    guard let currentPoint = screenPoints[current.id],
                          let candidatePoint = screenPoints[candidate.id] else { continue }
                    if hypot(
                        currentPoint.x - candidatePoint.x,
                        currentPoint.y - candidatePoint.y
                    ) < threshold {
                        remaining.remove(candidate.id)
                        group.append(candidate)
                    }
                }
                searchIndex += 1
            }
            result.append(group)
        }
        return result
    }
}

/// Cache grouping identity without caching a second copy of Restaurant data.
/// A photo, name or status can change while the map and membership stay still.
struct RestaurantMapRegionalGroupingSnapshot {
    private let memberIDsByRepresentativeID: [UUID: [UUID]]
    let visibleRepresentativeIDs: Set<UUID>

    init(groups: [[RestaurantMapMarkerPresentation]]) {
        visibleRepresentativeIDs = Set(groups.compactMap { $0.first?.id })
        memberIDsByRepresentativeID = Dictionary(uniqueKeysWithValues: groups.compactMap { group in
            guard let representative = group.first, group.count > 1 else { return nil }
            return (representative.id, group.map(\.id))
        })
    }

    func members(
        for representativeID: UUID,
        resolve: (UUID) -> RestaurantMapMarkerPresentation?
    ) -> [RestaurantMapMarkerPresentation]? {
        memberIDsByRepresentativeID[representativeID]?.compactMap(resolve)
    }
}

enum RestaurantMapCoordinatePolicy {
    static func isValid(latitude: Double, longitude: Double) -> Bool {
        latitude.isFinite
            && longitude.isFinite
            && (-90 ... 90).contains(latitude)
            && (-180 ... 180).contains(longitude)
            && !(latitude == 0 && longitude == 0)
    }
}

enum RestaurantMapMarkerMetrics {
    static let baseDiameter = TasteMapDesignTokens.MapRestaurantMarker.maximumDiameter
    static let selectionIncrease = TasteMapDesignTokens.MapRestaurantMarker.maximumSelectionIncrease

    static func diameter(
        status: RestaurantMapMarkerStatus,
        distanceKilometers: Double?,
        isSelected: Bool,
        densityStyle: RestaurantMapMarkerDensityStyle = .venue
    ) -> Double {
        // Pending destinations stay slightly larger at every zoom, even without GPS.
        // Distance is metadata, not a reason to shrink a place the user can try.
        let emphasis = RestaurantMapMarkerRingPolicy.isUnvisited(status: status)
            ? densityStyle.unvisitedIncrease : 0
        return densityStyle.baseDiameter + emphasis + (isSelected ? densityStyle.selectionIncrease : 0)
    }
}

enum RestaurantMapCameraTarget: Equatable {
    case unchanged
    case region(
        centerLatitude: Double,
        centerLongitude: Double,
        latitudeDelta: Double,
        longitudeDelta: Double
    )
}

enum RestaurantMapCameraPolicy {
    static let singlePointSpan = 0.04
    static let minimumMultiPointSpan = 0.025
    static let resultPadding = 1.35

    static func target(for markers: [RestaurantMapMarkerPresentation]) -> RestaurantMapCameraTarget {
        guard let first = markers.first else { return .unchanged }
        guard markers.count > 1 else {
            return .region(
                centerLatitude: first.latitude,
                centerLongitude: first.longitude,
                latitudeDelta: singlePointSpan,
                longitudeDelta: singlePointSpan
            )
        }

        var minimumLatitude = first.latitude
        var maximumLatitude = first.latitude
        var minimumLongitude = first.longitude
        var maximumLongitude = first.longitude
        for marker in markers.dropFirst() {
            minimumLatitude = min(minimumLatitude, marker.latitude)
            maximumLatitude = max(maximumLatitude, marker.latitude)
            minimumLongitude = min(minimumLongitude, marker.longitude)
            maximumLongitude = max(maximumLongitude, marker.longitude)
        }
        let latitudeDelta = max(minimumMultiPointSpan, maximumLatitude - minimumLatitude) * resultPadding
        let longitudeDelta = max(minimumMultiPointSpan, maximumLongitude - minimumLongitude) * resultPadding
        return .region(
            centerLatitude: (minimumLatitude + maximumLatitude) / 2,
            centerLongitude: (minimumLongitude + maximumLongitude) / 2,
            latitudeDelta: min(170, latitudeDelta),
            longitudeDelta: min(360, longitudeDelta)
        )
    }
}

enum RestaurantMapRenderState: Equatable {
    case loading
    case ready
    case failed(String)
}
