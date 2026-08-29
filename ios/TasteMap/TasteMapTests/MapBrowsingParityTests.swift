import Foundation
import Testing
@testable import TasteMap

@Suite("02 Map browsing parity")
@MainActor
struct MapBrowsingParityTests {
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

    @Test("Marker visuals follow marker photo, merchant, local photo, emoji and fallback priority")
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
        #expect(result[merchantRestaurant.id] == .merchantImage(URL(string: "https://images.example.com/merchant.jpg")!))
        #expect(result[localRestaurant.id] == .photo(localOnlyPhoto.id))
        #expect(result[emojiRestaurant.id] == .emoji("🍜"))
        #expect(result[fallbackRestaurant.id] == .fallback)
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

    @Test("Native cluster presentation reports exact count and a useful expansion target")
    func clusterProjection() {
        let members = (0 ..< 100).map {
            presentation($0, latitude: 30.27 + Double($0 % 10) * 0.0001, longitude: 120.13 + Double($0 / 10) * 0.0001)
        }
        let cluster = RestaurantMapClusterPresentation(members: members)
        #expect(cluster.count == 100)
        #expect(cluster.expansionTarget != .unchanged)
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

    private func markers(
        _ items: [RestaurantBrowseItem],
        photos: [PhotoAsset] = [],
        segment: RestaurantBrowseSegment = .visited
    ) -> [RestaurantMapMarkerPresentation] {
        RestaurantMapMarkerBuilder.build(items: items, photos: photos, segment: segment)
    }

    private func presentation(_ value: Int, latitude: Double, longitude: Double) -> RestaurantMapMarkerPresentation {
        RestaurantMapMarkerPresentation(
            id: uuid(value), name: "餐厅 \(value)", latitude: latitude, longitude: longitude,
            status: .visited, visual: .fallback, visitCount: 0, averageRating: nil,
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
