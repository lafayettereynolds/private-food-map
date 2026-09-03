import Foundation
import Testing
@testable import TasteMap

@Suite("02 Map browsing parity")
@MainActor
struct MapBrowsingParityTests {
    @Test("Restaurant score colors preserve the approved Legacy five-band language")
    func restaurantScoreColors() {
        #expect(RestaurantScoreColorPolicy.color(forTenPointScore: nil) == .init(hex: 0x9ea3a0))
        #expect(RestaurantScoreColorPolicy.color(forTenPointScore: 1) == .init(hex: 0x851522))
        #expect(RestaurantScoreColorPolicy.color(forTenPointScore: 2.9) == .init(hex: 0xcb4650))
        #expect(RestaurantScoreColorPolicy.color(forTenPointScore: 3) == .init(hex: 0xdfa04d))
        #expect(RestaurantScoreColorPolicy.color(forTenPointScore: 5) == .init(hex: 0x9178bd))
        #expect(RestaurantScoreColorPolicy.color(forTenPointScore: 7) == .init(hex: 0x6594d3))
        #expect(RestaurantScoreColorPolicy.color(forTenPointScore: 9) == .init(hex: 0x46a47b))
        #expect(RestaurantScoreColorPolicy.color(forTenPointScore: 10) == .init(hex: 0x176f49))
        #expect(RestaurantScoreColorPolicy.color(forFivePointRating: 4.5) == .init(hex: 0x46a47b))
    }

    @Test("Personal search matches every formal Web field and excludes tombstones")
    func fullFieldSearch() throws {
        let restaurant = makeRestaurant(1, name: "山岚小馆", status: .visited)
        restaurant.remoteRecordData = try restaurantRecord(
            restaurant,
            longTermNote: "炭火香气是长期偏好",
            markerEmoji: "🍜"
        )
        let other = makeRestaurant(2, name: "普通餐厅", status: .visited)
        other.city = "上海"
        other.address = "另一条路 2 号"
        let visit = Visit(
            id: uuid(101), restaurantId: restaurant.id, rating: nil,
            note: "喜欢窗边的位置", companionNames: ["阿宁"], syncStatus: .synced
        )
        let deletedVisit = Visit(
            id: uuid(102), restaurantId: restaurant.id, note: "不该检索到的文字",
            deletedAt: .now, syncStatus: .synced
        )
        let dish = Dish(
            id: uuid(201), restaurantId: restaurant.id, visitId: visit.id,
            name: "松露饺子", taste: "轻微烟熏", syncStatus: .synced
        )
        let snapshot = RestaurantBrowseBuilder.build(
            restaurants: [restaurant, other], visits: [visit, deletedVisit], dishes: [dish]
        )

        for query in ["山岚", "杭州", "测试路", "炭火香气", "窗边", "阿宁", "松露饺子", "烟熏"] {
            #expect(RestaurantBrowseSearch.filter(snapshot.visited, query: query).map(\.id) == [restaurant.id])
        }
        #expect(RestaurantBrowseSearch.filter(snapshot.visited, query: "不该检索到").isEmpty)
        #expect(RestaurantBrowseSearch.filter(snapshot.visited, query: "  松露  ").map(\.id) == [restaurant.id])
    }

    @Test("Visited, want-to-go and recommended marker status remain distinct")
    func markerStatuses() {
        let visited = makeRestaurant(1, name: "去过", status: .visited)
        let wanted = makeRestaurant(2, name: "想吃", status: .wantToGo)
        let snapshot = RestaurantBrowseBuilder.build(restaurants: [visited, wanted], visits: [])

        #expect(markers(snapshot.visited, segment: .visited).first?.status == .visited)
        #expect(markers(snapshot.wantToGo, segment: .wantToGo).first?.status == .wantToGo)
        #expect(markers(snapshot.visited, segment: .forYou).first?.status == .recommended)
    }

    @Test("Marker visuals use only current-owner photos or food emoji fallbacks")
    func visualPriority() throws {
        let markerRestaurant = makeRestaurant(1, name: "正式标记照片", status: .visited)
        let markerPhoto = photo(301, restaurant: markerRestaurant, kind: .restaurantMarker, remoteID: "marker-photo")
        let localPhoto = photo(302, restaurant: markerRestaurant, kind: .visit, remoteID: "visit-photo")
        localPhoto.createdAt = markerPhoto.createdAt.addingTimeInterval(10)
        markerRestaurant.remoteRecordData = try restaurantRecord(
            markerRestaurant,
            markerPhotoID: "marker-photo",
            merchantImageURL: "https://images.example.com/merchant.jpg",
            markerEmoji: "🍣"
        )

        let merchantRestaurant = makeRestaurant(2, name: "商户图", status: .visited)
        merchantRestaurant.remoteRecordData = try restaurantRecord(
            merchantRestaurant,
            merchantImageURL: "https://images.example.com/merchant.jpg",
            markerEmoji: "🍲"
        )

        let localRestaurant = makeRestaurant(3, name: "本地照片", status: .visited)
        let localOnlyPhoto = photo(303, restaurant: localRestaurant, kind: .visit, remoteID: "local-only")
        localRestaurant.remoteRecordData = try restaurantRecord(
            localRestaurant,
            merchantImageURL: "https://images.example.com/provider-must-not-mask-local.jpg",
            markerEmoji: "🍱"
        )

        let emojiRestaurant = makeRestaurant(4, name: "表情", status: .visited)
        emojiRestaurant.remoteRecordData = try restaurantRecord(emojiRestaurant, markerEmoji: "🍜")

        let fallbackRestaurant = makeRestaurant(5, name: "默认", status: .visited)
        let snapshot = RestaurantBrowseBuilder.build(
            restaurants: [markerRestaurant, merchantRestaurant, localRestaurant, emojiRestaurant, fallbackRestaurant],
            visits: [],
            photos: [markerPhoto, localPhoto, localOnlyPhoto]
        )
        let result = Dictionary(uniqueKeysWithValues: markers(
            snapshot.visited,
            photos: [markerPhoto, localPhoto, localOnlyPhoto]
        ).map { ($0.id, $0.visual) })

        #expect(result[markerRestaurant.id] == .photo(markerPhoto.id))
        #expect(result[merchantRestaurant.id] == .emoji("🍲"))
        #expect(result[localRestaurant.id] == .photo(localOnlyPhoto.id))
        #expect(snapshot.visited.first(where: { $0.id == localRestaurant.id })?.merchantImageURL?.host == "images.example.com")
        #expect(result[emojiRestaurant.id] == .emoji("🍜"))
        #expect(result[fallbackRestaurant.id] == .emoji("🍽️"))
    }

    @Test("Deleted, cross-restaurant and unsafe image references safely degrade")
    func unsafePhotosDegrade() throws {
        let restaurant = makeRestaurant(1, name: "安全降级", status: .visited)
        let other = makeRestaurant(2, name: "另一家", status: .visited)
        let deleted = photo(301, restaurant: restaurant, kind: .restaurantMarker, remoteID: "deleted")
        deleted.deletedAt = .now
        let crossRestaurant = photo(302, restaurant: other, kind: .restaurantMarker, remoteID: "cross")
        restaurant.remoteRecordData = try restaurantRecord(
            restaurant,
            markerPhotoID: "cross",
            merchantImageURL: "http://unsafe.example.com/photo.jpg",
            markerEmoji: "🍛"
        )
        let snapshot = RestaurantBrowseBuilder.build(
            restaurants: [restaurant, other], visits: [], photos: [deleted, crossRestaurant]
        )
        let visual = markers(snapshot.visited, photos: [deleted, crossRestaurant])
            .first(where: { $0.id == restaurant.id })?.visual
        #expect(visual == .emoji("🍛"))
    }

    @Test("Hybrid MapKit accepts owner photos and collapses public or provider descriptors to food emoji")
    func hybridMapVisualBoundary() {
        let restaurant = makeRestaurant(99, name: "日式食堂", status: .visited)
        let ownerPhoto = photo(399, restaurant: restaurant, kind: .restaurantMarker, remoteID: "owner-marker")
        let ownerDescriptor = TasteMapHybridImageDescriptor(
            kind: .ownerPhoto,
            photoID: ownerPhoto.remoteID,
            categoryVisualID: FoodCategoryVisualID.japaneseKorean.rawValue,
            accessibilityLabel: "本人实拍"
        )
        #expect(TasteMapHybridMapMarkerVisualPolicy.resolve(
            ownerDescriptor,
            fallbackEmoji: "🍣",
            restaurantName: restaurant.name,
            photosByID: [ownerPhoto.id: ownerPhoto]
        ) == .photo(ownerPhoto.id))

        for kind in [TasteMapHybridImageKind.publicUGC, .providerMerchant, .foodDiningFallback] {
            let descriptor = TasteMapHybridImageDescriptor(
                kind: kind,
                resourceURL: "https://images.example.test/must-not-render-on-personal-map.jpg",
                photoID: ownerPhoto.remoteID,
                categoryVisualID: FoodCategoryVisualID.japaneseKorean.rawValue,
                accessibilityLabel: "非个人地图图片"
            )
            #expect(TasteMapHybridMapMarkerVisualPolicy.resolve(
                descriptor,
                fallbackEmoji: "🍣",
                restaurantName: restaurant.name,
                photosByID: [ownerPhoto.id: ownerPhoto]
            ) == .emoji("🍣"))
        }
    }

    @Test("Invalid coordinates and deleted Restaurants never become markers")
    func invalidAndDeletedCoordinates() {
        let valid = makeRestaurant(1, name: "合法", status: .visited)
        let zero = makeRestaurant(2, name: "零坐标", status: .visited, latitude: 0, longitude: 0)
        let invalid = makeRestaurant(3, name: "越界", status: .visited, latitude: 91, longitude: 181)
        let deleted = makeRestaurant(4, name: "已删除", status: .visited)
        deleted.deletedAt = .now
        let snapshot = RestaurantBrowseBuilder.build(
            restaurants: [valid, zero, invalid, deleted], visits: []
        )
        #expect(markers(snapshot.visited).map(\.id) == [valid.id])
    }

    @Test("Marker selection and the formal Web want-to-go distance scale remain deterministic")
    func markerMetrics() {
        #expect(RestaurantMapMarkerRingPolicy.isDashed(status: .wantToGo))
        #expect(!RestaurantMapMarkerRingPolicy.isDashed(status: .visited))
        #expect(!RestaurantMapMarkerRingPolicy.isDashed(status: .recommended))
        #expect(RestaurantMapMarkerRingPolicy.wantedDashPattern == [3, 3])
        #expect(RestaurantMapMarkerRingPolicy.opacity(status: .wantToGo) == 0.82)
        #expect(RestaurantMapMarkerRingPolicy.opacity(status: .visited) == 1)
        #expect(RestaurantMapMarkerMetrics.diameter(
            status: .visited, distanceKilometers: nil, isSelected: false
        ) == 44)
        #expect(RestaurantMapMarkerMetrics.diameter(
            status: .visited, distanceKilometers: nil, isSelected: true
        ) == 52)
        #expect(RestaurantMapMarkerMetrics.wantedScale(distanceKilometers: 0) == 1.28)
        #expect(RestaurantMapMarkerMetrics.wantedScale(distanceKilometers: 2)
            > RestaurantMapMarkerMetrics.wantedScale(distanceKilometers: 10))
        #expect(RestaurantMapMarkerMetrics.wantedScale(distanceKilometers: 10)
            > RestaurantMapMarkerMetrics.wantedScale(distanceKilometers: 30))
        #expect(abs(RestaurantMapMarkerMetrics.wantedScale(distanceKilometers: 30) - 0.78) < 0.000_001)
        #expect(RestaurantMapMarkerMetrics.wantedScale(distanceKilometers: .nan) == 1)
        #expect(RestaurantMapMarkerMetrics.wantedScale(distanceKilometers: -1) == 1)
    }

    @Test("Zero, one and multiple point camera policies are deterministic")
    func cameraPolicy() throws {
        #expect(RestaurantMapCameraPolicy.target(for: []) == .unchanged)
        let one = presentation(1, latitude: 30.27, longitude: 120.13)
        #expect(RestaurantMapCameraPolicy.target(for: [one]) == .region(
            centerLatitude: 30.27,
            centerLongitude: 120.13,
            latitudeDelta: 0.04,
            longitudeDelta: 0.04
        ))
        let two = presentation(2, latitude: 31.23, longitude: 121.47)
        guard case let .region(centerLatitude, centerLongitude, latitudeDelta, longitudeDelta) =
            RestaurantMapCameraPolicy.target(for: [one, two]) else {
            Issue.record("Expected a multi-point region")
            return
        }
        #expect(centerLatitude == (30.27 + 31.23) / 2)
        #expect(centerLongitude == (120.13 + 121.47) / 2)
        #expect(latitudeDelta > 31.23 - 30.27)
        #expect(longitudeDelta > 121.47 - 120.13)
    }

    @Test("Coincident Restaurants remain independent at their natural source coordinate")
    func coordinateCollisionKeepsNaturalOverlap() {
        let restaurants = (0 ..< 100).map {
            makeRestaurant(
                1_000 + $0,
                name: "重叠餐厅 \($0)",
                status: .visited,
                latitude: 30.27,
                longitude: 120.13
            )
        }
        let snapshot = RestaurantBrowseBuilder.build(restaurants: restaurants, visits: [])
        let members = markers(snapshot.visited)
        #expect(members.count == 100)
        #expect(Set(members.map(\.id)).count == 100)
        #expect(Set(members.map { "\($0.latitude):\($0.longitude)" }).count == 1)
    }

    @Test("Restaurant layer order is selected, rating, visit count, then stable ID")
    func markerLayerPriorityContract() {
        let unrated = presentation(1, rating: nil, visitCount: 50)
        let lowerRated = presentation(2, rating: 4, visitCount: 20)
        let fewerVisits = presentation(3, rating: 4.5, visitCount: 2)
        let moreVisits = presentation(4, rating: 4.5, visitCount: 9)
        let selected = presentation(5, rating: 1, visitCount: 0)

        let backToFront = RestaurantMapMarkerLayerPolicy.orderedBackToFront(
            [selected, moreVisits, unrated, fewerVisits, lowerRated],
            selectedRestaurantID: selected.id
        )

        #expect(backToFront.map(\.id) == [
            unrated.id, lowerRated.id, fewerVisits.id, moreVisits.id, selected.id,
        ])
    }

    @Test("A 4.8 Restaurant renders above a coincident 4.2 Restaurant")
    func higherRatedCoincidentRestaurantIsFrontmost() {
        let lower = presentation(6, rating: 4.2, visitCount: 30)
        let higher = presentation(7, rating: 4.8, visitCount: 1)

        let backToFront = RestaurantMapMarkerLayerPolicy.orderedBackToFront(
            [higher, lower],
            selectedRestaurantID: nil
        )

        #expect(backToFront.map(\.id) == [lower.id, higher.id])
    }

    @Test("Unrated is distinct from zero and stable ID resolves complete ties")
    func markerLayerNilAndStableID() {
        let unrated = presentation(10, rating: nil, visitCount: 3)
        let ratedZero = presentation(11, rating: 0, visitCount: 0)
        let stableLower = presentation(12, rating: 4.5, visitCount: 3)
        let stableHigher = presentation(13, rating: 4.5, visitCount: 3)

        let backToFront = RestaurantMapMarkerLayerPolicy.orderedBackToFront(
            [stableHigher, ratedZero, stableLower, unrated],
            selectedRestaurantID: nil
        )

        #expect(backToFront.map(\.id) == [
            unrated.id, ratedZero.id, stableLower.id, stableHigher.id,
        ])
    }

    @Test("Selecting and deselecting only overrides the stable base order")
    func markerLayerSelectionRestoresBaseOrder() {
        let low = presentation(20, rating: 3, visitCount: 10)
        let high = presentation(21, rating: 5, visitCount: 1)
        let base = RestaurantMapMarkerLayerPolicy.orderedBackToFront(
            [high, low], selectedRestaurantID: nil
        )
        let selected = RestaurantMapMarkerLayerPolicy.orderedBackToFront(
            [high, low], selectedRestaurantID: low.id
        )
        let restored = RestaurantMapMarkerLayerPolicy.orderedBackToFront(
            [low, high], selectedRestaurantID: nil
        )

        #expect(base.map(\.id) == [low.id, high.id])
        #expect(selected.map(\.id) == [high.id, low.id])
        #expect(restored.map(\.id) == base.map(\.id))
    }

    @Test("Layer ordering remains deterministic across input and viewport refresh order")
    func markerLayerViewportStability() {
        let markers = (0..<90).map { index in
            presentation(
                100 + index,
                latitude: 30.27,
                longitude: 120.13,
                rating: index.isMultiple(of: 8) ? nil : Double(index % 10 + 1) / 2,
                visitCount: index % 12
            )
        }
        let expected = RestaurantMapMarkerLayerPolicy.orderedBackToFront(
            markers,
            selectedRestaurantID: nil
        ).map(\.id)
        let refreshed = RestaurantMapMarkerLayerPolicy.orderedBackToFront(
            Array(markers.reversed()),
            selectedRestaurantID: nil
        ).map(\.id)

        #expect(refreshed == expected)
        #expect(Set(markers.map { "\($0.latitude):\($0.longitude)" }).count == 1)
    }

    @Test("One thousand marker presentations build without repeated global scans")
    func markerPerformance() {
        let restaurants = (0 ..< 1_000).map { index in
            makeRestaurant(
                1_000 + index,
                name: "性能餐厅 \(index)",
                status: index.isMultiple(of: 5) ? .wantToGo : .visited,
                latitude: 30.2 + Double(index % 100) * 0.0001,
                longitude: 120.1 + Double(index / 100) * 0.0001
            )
        }
        let started = Date()
        let snapshot = RestaurantBrowseBuilder.build(restaurants: restaurants, visits: [])
        let visitedMarkers = markers(snapshot.visited)
        let wantedMarkers = markers(snapshot.wantToGo, segment: .wantToGo)
        let elapsed = Date().timeIntervalSince(started)

        #expect(visitedMarkers.count + wantedMarkers.count == 1_000)
        #expect(elapsed < 3, "1,000 marker projection took \(elapsed) seconds")
    }

    @Test("Padded viewport culling never aggregates or rewrites Restaurant markers")
    func viewportCulling() {
        let values = (0..<1_000).map { index in
            presentation(
                index,
                latitude: 30 + Double(index % 50) * 0.01,
                longitude: 120 + Double(index / 50) * 0.01
            )
        }
        let result = RestaurantMapViewportPolicy.visibleMarkers(
            values,
            in: RestaurantMapViewport(
                centerLatitude: 30.2,
                centerLongitude: 120.1,
                latitudeDelta: 0.1,
                longitudeDelta: 0.1
            )
        )
        #expect(!result.isEmpty)
        #expect(result.count < values.count)
        #expect(Set(result.map(\.id)).count == result.count)
        #expect(result.allSatisfy { marker in values.contains(marker) })
    }

    private func markers(
        _ items: [RestaurantBrowseItem],
        photos: [PhotoAsset] = [],
        segment: RestaurantBrowseSegment = .visited
    ) -> [RestaurantMapMarkerPresentation] {
        RestaurantMapMarkerBuilder.build(items: items, photos: photos, segment: segment)
    }

    private func presentation(
        _ value: Int,
        latitude: Double = 30.27,
        longitude: Double = 120.13,
        rating: Double? = nil,
        visitCount: Int = 0
    ) -> RestaurantMapMarkerPresentation {
        RestaurantMapMarkerPresentation(
            id: uuid(value), name: "餐厅 \(value)", latitude: latitude, longitude: longitude,
            status: .visited, visual: .category(.other), visitCount: visitCount, averageRating: rating,
            distanceKilometers: nil
        )
    }

    private func makeRestaurant(
        _ value: Int,
        name: String,
        status: RestaurantStatus,
        latitude: Double = 30.2741,
        longitude: Double = 120.1551
    ) -> Restaurant {
        Restaurant(
            id: uuid(value), name: name, address: "测试路 \(value) 号",
            latitude: latitude, longitude: longitude, city: "杭州",
            status: status, syncStatus: .synced
        )
    }

    private func photo(
        _ value: Int,
        restaurant: Restaurant,
        kind: PhotoAssetKind,
        remoteID: String
    ) -> PhotoAsset {
        PhotoAsset(
            id: uuid(value), restaurantId: restaurant.id, kind: kind,
            mimeType: "image/jpeg", byteSize: 128, uploadState: .uploaded,
            remoteID: remoteID, syncStatus: .synced
        )
    }

    private func restaurantRecord(
        _ restaurant: Restaurant,
        longTermNote: String = "",
        markerPhotoID: String? = nil,
        merchantImageURL: String? = nil,
        markerEmoji: String
    ) throws -> Data {
        let timestamp = "2026-08-29T12:00:00.000Z"
        return try JSONEncoder().encode(RestaurantJSONContractV1(
            id: restaurant.remoteID!, userId: "tm_map_test",
            placeIdentities: [try RestaurantPlaceIdentityContract(
                provider: .manual, externalId: "manual-\(restaurant.id.uuidString)",
                isPrimary: true, createdAt: timestamp, updatedAt: timestamp
            )],
            name: restaurant.name, address: restaurant.address, city: restaurant.city,
            latitude: restaurant.latitude, longitude: restaurant.longitude,
            status: restaurant.status == .visited ? .visited : .wantToGo,
            preferenceLevel: .normal,
            overallRating: nil, foodRating: nil, environmentRating: nil,
            serviceRating: nil, valueRating: nil, tags: [], longTermNote: longTermNote,
            pricePerPerson: nil, phone: nil, openingHours: nil,
            markerType: markerPhotoID == nil && merchantImageURL == nil ? .emoji : .image,
            markerPhotoId: markerPhotoID, merchantImageUrl: merchantImageURL,
            markerEmoji: markerEmoji, createdAt: timestamp, updatedAt: timestamp, deletedAt: nil
        ))
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}
