import Foundation
import CoreGraphics
import MapKit
import UIKit
import Testing
@testable import TasteMap

@Suite("02 Map browsing parity")
@MainActor
struct MapBrowsingParityTests {
    @Test("Map scopes retain independent filters/search and reset only their own query")
    func independentMapScopeQueries() {
        var queries = PersonalRestaurantScopeQueries()
        queries.current.filters.city = "杭州"
        queries.current.search = "面馆"
        queries.scope = .wantToGo
        #expect(queries.current.filters.status == .wantToGo)
        #expect(queries.current.filters.city == nil)
        #expect(queries.current.search.isEmpty)
        queries.current.filters.city = "上海"
        queries.scope = .forYou
        #expect(queries.current.filters.activeFilterCount == 0)
        queries.scope = .visited
        #expect(queries.current.filters.city == "杭州")
        #expect(queries.current.search == "面馆")
        queries.current.filters.resetKeepingStatus()
        queries.scope = .wantToGo
        #expect(queries.current.filters.city == "上海")
    }
    @Test("Minimum-rating choices cover 1–10 and preserve the Discovery qualification shortcut")
    func completeMinimumRatingChoices() {
        #expect(TasteMapRatingFilterOptions.thresholdsOutOfTen == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
        #expect(TasteMapRatingFilterOptions.discoveryThresholdsOutOfTen == [1, 2, 3, 4, 5, 6, 7, 7.5, 8, 9, 10])
        #expect(TasteMapRatingFilterOptions.label(for: 1) == "1 分以上")
        #expect(TasteMapRatingFilterOptions.label(for: 10) == "10 分")
        #expect(TasteMapRatingFilterOptions.label(for: 7.5) == "7.5 分以上")
    }

    @Test("Taste data progress counts rated Restaurants once and uses exact stage copy")
    func tasteDataProgress() {
        let first = uuid(801)
        let second = uuid(802)
        let deleted = uuid(803)
        let unrated = uuid(804)
        let invalid = uuid(805)
        let progress = TasteDataProgressPolicy.resolve(
            activeRestaurantIDs: [first, second, deleted, unrated, invalid],
            visits: [
                .init(restaurantID: first, rating: 4.5, isDeleted: false),
                .init(restaurantID: first, rating: 5, isDeleted: false),
                .init(restaurantID: second, rating: 0.5, isDeleted: false),
                .init(restaurantID: deleted, rating: 4, isDeleted: true),
                .init(restaurantID: unrated, rating: nil, isDeleted: false),
                .init(restaurantID: invalid, rating: 4.2, isDeleted: false),
            ]
        )
        #expect(progress.ratedRestaurantCount == 2)
        #expect(progress.target == 5)
        #expect(progress.remaining == 3)

        let stages: [(Int, Int, String)] = [
            (5, 5, "开始形成你的口味判断"),
            (7, 10, "再评分 3 家，推荐和分析会更准确"),
            (10, 10, "推荐和分析正在变得更准确"),
            (13, 15, "再评分 2 家，口味分析会更完整"),
            (15, 15, "口味分析正在变得更完整"),
            (18, 20, "再评分 2 家，口味判断会更稳定"),
            (20, 20, "口味数据已较稳定"),
            (24, 20, "口味数据已较稳定"),
        ]
        for (count, target, message) in stages {
            let stage = TasteDataProgressPolicy.resolve(ratedRestaurantCount: count)
            #expect(stage.displayCount == min(count, 20))
            #expect(stage.target == target)
            #expect(stage.message == message)
            #expect(!stage.message.contains("再评分 0 家"))
        }
    }

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
        #expect(RestaurantScoreColorPolicy.score(forFivePointRating: 4.5) == 9.0)
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

    @Test("An owner-selected Emoji immediately replaces an old photo and merchant image on Personal Map")
    func ownerEmojiOverridesOldImages() throws {
        let restaurant = makeRestaurant(41, name: "头像切换餐厅", status: .visited)
        let oldPhoto = photo(341, restaurant: restaurant, kind: .restaurantMarker, remoteID: "old-marker")
        restaurant.remoteRecordData = try restaurantRecord(
            restaurant,
            markerPhotoID: nil,
            merchantImageURL: "https://images.example.com/provider.jpg",
            markerEmoji: "🍽️",
            markerType: .emoji
        )

        let snapshot = RestaurantBrowseBuilder.build(
            restaurants: [restaurant], visits: [], photos: [oldPhoto]
        )
        let marker = try #require(markers(snapshot.visited, photos: [oldPhoto]).first)
        #expect(marker.visual == .emoji("🍽️"))
        #expect(marker.fallbackMerchantImageURL == nil)
        #expect(!marker.allowsRemoteImages)
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

    @Test("A retained Hybrid descriptor cannot select a deleted owner photo on Personal Map")
    func retainedDeletedPhotoFallsBack() {
        let restaurant = makeRestaurant(98, name: "日式食堂", status: .visited)
        let image = photo(398, restaurant: restaurant, kind: .visit, remoteID: "retained-photo")
        let descriptor = TasteMapHybridImageDescriptor(kind: .ownerPhoto,
            photoID: image.remoteID, categoryVisualID: FoodCategoryVisualID.japaneseKorean.rawValue,
            accessibilityLabel: "本人实拍")
        let retained = [image.id: image]
        func resolve() -> RestaurantMapMarkerVisual {
            TasteMapHybridMapMarkerVisualPolicy.resolve(descriptor, fallbackEmoji: "🍣",
                restaurantName: restaurant.name, photosByID: retained)
        }
        #expect(resolve() == .photo(image.id))
        image.deletedAt = .now
        #expect(resolve() == .emoji("🍣"))
        image.deletedAt = nil
        image.binaryDeletedAt = .now
        #expect(resolve() == .emoji("🍣"))
        image.binaryDeletedAt = nil
        image.uploadState = .deleted
        #expect(resolve() == .emoji("🍣"))
    }

    @Test("Owner avatar glyphs survive both map projections without moving the restaurant")
    func explicitOwnerAvatarIsNotFoodCategorySanitized() throws {
        let restaurant = makeRestaurant(42, name: "川正元麻辣香锅", status: .visited)
        let oldPhoto = photo(342, restaurant: restaurant, kind: .restaurantMarker, remoteID: "old-avatar")
        for emoji in ["🐸", "🍽️", "🇨🇳", "👩🏽‍🍳"] {
            restaurant.remoteRecordData = try restaurantRecord(restaurant, markerPhotoID: nil,
                merchantImageURL: nil, markerEmoji: emoji, markerType: .emoji)
            let snapshot = RestaurantBrowseBuilder.build(restaurants: [restaurant], visits: [], photos: [oldPhoto])
            let marker = try #require(markers(snapshot.visited, photos: [oldPhoto]).first)
            #expect(marker.visual == .emoji(emoji))
            #expect(marker.latitude == restaurant.latitude)
            #expect(marker.longitude == restaurant.longitude)
            #expect(marker.imageResolution.isFallbackOnly)
            let descriptor = TasteMapHybridImageDescriptor(kind: .foodCategoryVisual,
                preferredEmoji: emoji, accessibilityLabel: "本人餐厅头像")
            #expect(TasteMapHybridMapMarkerVisualPolicy.resolve(descriptor, fallbackEmoji: "🌶️",
                restaurantName: restaurant.name, photosByID: [oldPhoto.id: oldPhoto]) == .emoji(emoji))
        }
        let unauthorized = TasteMapHybridImageDescriptor(kind: .publicUGC,
            preferredEmoji: "🐸", accessibilityLabel: "非本人图片")
        #expect(TasteMapHybridMapMarkerVisualPolicy.resolve(unauthorized, fallbackEmoji: "🌶️",
            restaurantName: restaurant.name, photosByID: [:]) == .emoji("🌶️"))
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

    @Test("Pending destinations are four points larger without changing visited or anchor geometry")
    func markerMetrics() {
        #expect(RestaurantMapMarkerShape.resolve(status: .wantToGo) == .treasureChest)
        #expect(RestaurantMapMarkerShape.resolve(status: .visited) == .circle)
        #expect(RestaurantMapMarkerShape.resolve(status: .recommended) == .treasureChest)
        #expect(RestaurantMapMarkerRingPolicy.isUnvisited(status: .wantToGo))
        #expect(RestaurantMapMarkerRingPolicy.isUnvisited(status: .recommended))
        #expect(!RestaurantMapMarkerRingPolicy.isUnvisited(status: .visited))
        #expect(RestaurantMapMarkerRingPolicy.unvisitedDashPattern == [3, 3])
        #expect(RestaurantMapMarkerRingPolicy.outerWhiteRingWidth == 2)
        #expect(RestaurantMapMarkerRingPolicy.outerHairlineWidth == 0.75)
        #expect(RestaurantMapMarkerRingPolicy.opacity(status: .wantToGo) == 0.82)
        #expect(RestaurantMapMarkerRingPolicy.opacity(status: .recommended) == 0.82)
        #expect(RestaurantMapMarkerRingPolicy.opacity(status: .visited) == 1)
        #expect(RestaurantMapMarkerMetrics.diameter(
            status: .visited, distanceKilometers: nil, isSelected: false
        ) == 28)
        #expect(RestaurantMapMarkerMetrics.diameter(
            status: .visited, distanceKilometers: nil, isSelected: true
        ) == 32)
        #expect(RestaurantMapMarkerMetrics.diameter(
            status: .visited, distanceKilometers: nil, isSelected: false, densityStyle: .city
        ) == 26)
        #expect(RestaurantMapMarkerMetrics.diameter(
            status: .visited, distanceKilometers: nil, isSelected: false, densityStyle: .region
        ) == 25)
        #expect(RestaurantMapMarkerMetrics.diameter(
            status: .visited, distanceKilometers: nil, isSelected: false, densityStyle: .world
        ) == 10)
        let nearStyle = RestaurantMapMarkerDensityStyle.resolve(latitudeDelta: 0.005)
        let middleStyle = RestaurantMapMarkerDensityStyle.resolve(latitudeDelta: 0.10)
        let farStyle = RestaurantMapMarkerDensityStyle.resolve(latitudeDelta: 0.80)
        let worldStyle = RestaurantMapMarkerDensityStyle.resolve(latitudeDelta: 80)
        #expect(nearStyle == .venue)
        #expect(middleStyle.baseDiameter < nearStyle.baseDiameter)
        #expect(middleStyle.baseDiameter > farStyle.baseDiameter)
        #expect(RestaurantMapMarkerDensityStyle.groupingProgress(latitudeDelta: 0.006) == 0)
        #expect(RestaurantMapMarkerDensityStyle.groupingProgress(latitudeDelta: 0.8) == 0)
        #expect(RestaurantMapMarkerDensityStyle.groupingProgress(latitudeDelta: 1.2) > 0)
        #expect(RestaurantMapMarkerDensityStyle.groupingProgress(latitudeDelta: 1.2) < 1)
        #expect(RestaurantMapMarkerDensityStyle.groupingProgress(latitudeDelta: 2.4) == 1)
        #expect(worldStyle == .world)
        for style in [nearStyle, middleStyle, farStyle, worldStyle] {
            for selected in [false, true] {
                let visited = RestaurantMapMarkerMetrics.diameter(
                    status: .visited, distanceKilometers: nil, isSelected: selected, densityStyle: style
                )
                for status: RestaurantMapMarkerStatus in [.wantToGo, .recommended] {
                    for distance: Double? in [nil, 0, 2, 30, 300, .nan, -1] {
                        let diameter = RestaurantMapMarkerMetrics.diameter(
                            status: status, distanceKilometers: distance, isSelected: selected, densityStyle: style
                        )
                        #expect(abs(diameter - visited - style.unvisitedIncrease) < 0.000_001)
                        let outer = diameter + RestaurantMapMarkerRingPolicy.outerWhiteRingWidth * 2
                        #expect(outer >= 15 && outer <= (selected ? 40 : 36))
                        #expect(outer < Double(TasteMapDesignTokens.Control.minimumHitTarget))
                    }
                }
            }
        }
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

    @Test("Coincident Restaurants preserve independent stored coordinates before visual layout")
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

    @Test("Higher-rated Restaurants stay in front even when their recommendation rank is lower")
    func recommendationMarkerLayerPriorityContract() {
        let first = presentation(51, rating: nil, visitCount: 0, recommendationRank: 1)
        let later = presentation(52, rating: 5, visitCount: 999, recommendationRank: 12)

        let backToFront = RestaurantMapMarkerLayerPolicy.orderedBackToFront(
            [first, later], selectedRestaurantID: nil
        )
        let selected = RestaurantMapMarkerLayerPolicy.orderedBackToFront(
            [first, later], selectedRestaurantID: first.id
        )
        #expect(backToFront.map(\.id) == [first.id, later.id])
        #expect(selected.map(\.id) == [later.id, first.id])
        let equalRatingFirstRank = presentation(53, rating: 5, visitCount: 0, recommendationRank: 1)
        #expect(RestaurantMapMarkerLayerPolicy.orderedBackToFront(
            [later, equalRatingFirstRank], selectedRestaurantID: nil
        ).last?.id == equalRatingFirstRank.id)
    }

    @Test("MapKit receives distinct stable ranks, not only a temporary Core Animation order")
    func mapKitOwnsStableAnnotationPriority() {
        let views = (1...300).map { rank in
            let view = RestaurantMarkerAnnotationView(annotation: nil, reuseIdentifier: "layer-test")
            view.setLayerPriority(rank: rank, count: 300)
            return view
        }
        #expect(Set(views.map { $0.zPriority.rawValue }).count == 300)
        for index in 1..<views.count {
            #expect(views[index].zPriority.rawValue > views[index - 1].zPriority.rawValue)
        }
        for view in views {
            #expect(view.zPriority.rawValue > 100 && view.zPriority.rawValue < 900)
            #expect(view.selectedZPriority.rawValue == 950)
        }
        let selected = views[0]
        selected.isSelected = true
        selected.setLayerPriority(rank: 1, count: 300)
        #expect(selected.selectedZPriority.rawValue == 950)
        selected.prepareForReuse()
        #expect(selected.zPriority == .defaultUnselected)
        #expect(selected.selectedZPriority == .defaultSelected)
        selected.isSelected = false
        selected.setLayerPriority(rank: 4, count: 300)
        #expect(selected.zPriority == views[3].zPriority)
    }

    @Test("The actual circle stays centered inside a fixed 44-point anchor through zoom selection and reuse")
    func markerCircleAnchorIsIndependentOfSize() throws {
        let marker = presentation(61, latitude: 30.27, longitude: 120.13, rating: 4.8)
        let annotation = MKPointAnnotation()
        annotation.coordinate = CLLocationCoordinate2D(latitude: marker.latitude, longitude: marker.longitude)
        let view = RestaurantMarkerAnnotationView(annotation: annotation, reuseIdentifier: "anchor-test")
        _ = view.configure(marker)
        let projectedCoordinate = CGPoint(x: 104.5, y: 207.25)
        view.center = projectedCoordinate
        for delta in [0.006, 0.02, 0.04, 0.08, 0.8, 2.4, 8, 30, 80, 0.006] {
            for selected in [false, true, false] {
                view.isSelected = selected
                view.setDensityStyle(.resolve(latitudeDelta: delta))
                view.setNeedsLayout()
                view.layoutIfNeeded()
                #expect(view.centerOffset == .zero)
                #expect(view.transform == .identity)
                #expect(view.center == projectedCoordinate)
                #expect(view.frame.midX == projectedCoordinate.x)
                #expect(view.frame.midY == projectedCoordinate.y)
                #expect(view.bounds.size == CGSize(width: 44, height: 44))
                let visibleCircle = try #require(view.layer.shadowPath?.boundingBoxOfPath)
                #expect(visibleCircle.midX == view.bounds.midX)
                #expect(visibleCircle.midY == view.bounds.midY)
                #expect(visibleCircle.width >= 14)
                #expect(visibleCircle.width <= (selected ? 36 : 32))
                #expect(visibleCircle.width < view.bounds.width)
                #expect(annotation.coordinate.latitude == marker.latitude)
                #expect(annotation.coordinate.longitude == marker.longitude)
            }
        }
        view.prepareForReuse()
        _ = view.configure(presentation(62, rating: nil))
        view.layoutIfNeeded()
        #expect(view.centerOffset == .zero)
        #expect(view.center == projectedCoordinate)
        #expect(view.bounds.size == CGSize(width: 44, height: 44))
    }

    @Test("A same-coordinate street stack retains every Restaurant and their actual coordinate")
    func sameCoordinateStreetStackPreservesEveryRestaurant() {
        let markers = (100 ... 189).map {
            presentation($0, rating: 5 - Double($0 % 50) / 10, visitCount: 190 - $0)
        }
        let points = Dictionary(uniqueKeysWithValues: markers.map {
            ($0.id, CGPoint(x: 200, y: 300))
        })
        let street = RestaurantMapRegionalGroupingPolicy.groups(
            for: markers, screenPoints: points, requiredCenterDistance: 50, latitudeDelta: 0.006
        )
        #expect(street.count == 1)
        #expect(street.first?.count == 90)
        #expect(Set(street.flatMap { $0.map(\.id) }) == Set(markers.map(\.id)))
        #expect(RestaurantMapRegionalGroupingPolicy.isCoincident(street.first ?? []))
        #expect(street.flatMap { $0 }.allSatisfy { $0.latitude == 30.27 && $0.longitude == 120.13 })
        let wide = RestaurantMapRegionalGroupingPolicy.groups(
            for: markers, screenPoints: points, requiredCenterDistance: 50, latitudeDelta: 3.0
        )
        #expect(wide.count == 1)
        #expect(wide.first?.count == 90)
        #expect(wide.first?.first?.id == RestaurantMapMarkerLayerPolicy.orderedBackToFront(
            markers, selectedRestaurantID: nil
        ).last?.id)
    }

    @Test("Wider-area Restaurant representatives reversibly restore every city Restaurant without losing members")
    func progressiveRegionalRestaurantZoomSequence() {
        let markers = (0 ..< 8).map {
            presentation(200 + $0, latitude: 30.2 + Double($0) * 0.002,
                         longitude: 120.1 + Double($0) * 0.001,
                         rating: 5 - Double($0) * 0.3, visitCount: $0)
        }
        let deltas = [0.006, 0.08, 0.8, 1, 1.2, 1.6, 2.4, 4, 8]
        func groups(_ delta: Double) -> [[RestaurantMapMarkerPresentation]] {
            // Camera projection draws locations closer at wider zoom. Every
            // representative retains real Restaurants, never Visit duplicates.
            let points = Dictionary(uniqueKeysWithValues: markers.enumerated().map { index, marker in
                (marker.id, CGPoint(x: 100 + Double(index * index) * 15 / delta, y: 200))
            })
            return RestaurantMapRegionalGroupingPolicy.groups(
                for: markers, screenPoints: points,
                requiredCenterDistance: RestaurantMapMarkerDensityStyle.resolve(latitudeDelta: delta).regionalGroupingDistance,
                latitudeDelta: delta
            )
        }
        let snapshots = deltas.map(groups)
        let counts = snapshots.map(\.count)
        #expect(counts.first == 8)
        #expect(counts.last == 1)
        #expect(Set(counts).count >= 4)
        for index in counts.indices.dropFirst() { #expect(counts[index] <= counts[index - 1]) }
        for snapshot in snapshots {
            #expect(Set(snapshot.flatMap { $0.map(\.id) }) == Set(markers.map(\.id)))
            #expect(snapshot.reduce(0) { $0 + $1.count } == markers.count)
            for group in snapshot {
                #expect(group.first?.id == RestaurantMapMarkerLayerPolicy.orderedBackToFront(
                    group, selectedRestaurantID: nil
                ).last?.id)
                for member in group {
                    let original = markers.first { $0.id == member.id }
                    #expect(member.latitude == original?.latitude)
                    #expect(member.longitude == original?.longitude)
                }
            }
        }
        for (delta, snapshot) in zip(deltas, snapshots).reversed() {
            #expect(groups(delta).map { $0.map(\.id) } == snapshot.map { $0.map(\.id) })
        }
        #expect(snapshots.last?.first?.first?.id == markers.first?.id)
    }

    @Test("City Restaurants keep independent coordinates even when their projected circles overlap")
    func cityRestaurantsStayIndependentAndRegionUsesRealFavorite() {
        let favorite = presentation(301, latitude: 30.2700, rating: 4.9, visitCount: 2)
        let frequent = presentation(302, latitude: 30.2710, rating: 4.6, visitCount: 99)
        let unrated = presentation(303, latitude: 30.2720, rating: nil, visitCount: 120)
        let separate = presentation(304, latitude: 30.2800, rating: 4.0, visitCount: 1)
        let markers = [unrated, separate, frequent, favorite]
        let points = [
            favorite.id: CGPoint(x: 100, y: 100),
            frequent.id: CGPoint(x: 104, y: 103),
            unrated.id: CGPoint(x: 98, y: 106),
            separate.id: CGPoint(x: 190, y: 180),
        ]

        let venueGroups = RestaurantMapRegionalGroupingPolicy.groups(
            for: markers,
            screenPoints: points,
            requiredCenterDistance: 30,
            latitudeDelta: 0.006
        )
        #expect(venueGroups.count == 4)
        #expect(venueGroups.allSatisfy { $0.count == 1 })

        let cityGroups = RestaurantMapRegionalGroupingPolicy.groups(
            for: markers.reversed(),
            screenPoints: points,
            requiredCenterDistance: 30,
            latitudeDelta: 0.08
        )
        #expect(cityGroups.map(\.count).sorted() == [1, 1, 1, 1])
        #expect(cityGroups.reduce(0) { $0 + $1.count } == 4)
        #expect(Set(cityGroups.flatMap { $0.map(\.id) }) == Set(markers.map(\.id)))
        for streetSpan in [0.001, 0.006, 0.02, 0.08, 0.4, 0.8] {
            let street = RestaurantMapRegionalGroupingPolicy.groups(
                for: markers, screenPoints: points, requiredCenterDistance: 50,
                latitudeDelta: streetSpan
            )
            #expect(street.count == markers.count)
            #expect(street.allSatisfy { $0.count == 1 })
        }

        let regionalGroups = RestaurantMapRegionalGroupingPolicy.groups(
            for: markers.reversed(),
            screenPoints: points,
            requiredCenterDistance: 30,
            latitudeDelta: 1.5
        )
        #expect(regionalGroups.count == 2)
        let nearbyGroup = regionalGroups.first { $0.count == 3 }
        #expect(nearbyGroup?.first?.id == favorite.id)
        #expect(Set(nearbyGroup?.map(\.id) ?? []) == Set([favorite.id, frequent.id, unrated.id]))

        let translatedPoints = points.mapValues {
            CGPoint(x: $0.x + 73, y: $0.y - 41)
        }
        let pannedGroups = RestaurantMapRegionalGroupingPolicy.groups(
            for: markers,
            screenPoints: translatedPoints,
            requiredCenterDistance: 30,
            latitudeDelta: 1.5
        )
        #expect(pannedGroups.map { $0.map(\.id) } == regionalGroups.map { $0.map(\.id) })

        let countryGroups = RestaurantMapRegionalGroupingPolicy.groups(
            for: markers,
            screenPoints: points,
            requiredCenterDistance: 140,
            latitudeDelta: 8
        )
        #expect(countryGroups.count == 1)
        #expect(countryGroups.first?.first?.id == favorite.id)
    }

    @Test("Distinct city coordinates never form proximity stacks, regardless of overlap, pan or zoom")
    func distinctCoordinatesRemainIndependentThroughCityZoom() {
        let leader = presentation(311, latitude: 30.2700, rating: 5)
        let nearby = presentation(312, latitude: 30.2703, rating: 4.5)
        let chainOnly = presentation(313, latitude: 30.2706, rating: 4)
        let visuallySeparate = presentation(314, latitude: 30.2702, rating: 3.5)
        let markers = [chainOnly, visuallySeparate, nearby, leader]
        let points = [
            leader.id: CGPoint(x: 100, y: 100),
            nearby.id: CGPoint(x: 110, y: 100),
            chainOnly.id: CGPoint(x: 120, y: 100),
            visuallySeparate.id: CGPoint(x: 200, y: 100),
        ]
        let groups = RestaurantMapRegionalGroupingPolicy.groups(
            for: markers, screenPoints: points, requiredCenterDistance: 35, latitudeDelta: 0.006
        )
        #expect(groups.map(\.count) == [1, 1, 1, 1])
        #expect(groups.first?.map(\.id) == [leader.id])
        let zoomed = RestaurantMapRegionalGroupingPolicy.groups(
            for: markers, screenPoints: points.mapValues { CGPoint(x: $0.x * 4, y: $0.y * 4) },
            requiredCenterDistance: 35, latitudeDelta: 0.0015
        )
        #expect(zoomed.allSatisfy { $0.count == 1 })
        #expect(zoomed.map { $0.map(\.id) } == groups.map { $0.map(\.id) })
        let fullyOverlapping = RestaurantMapRegionalGroupingPolicy.groups(
            for: markers, screenPoints: points.mapValues { _ in CGPoint(x: 100, y: 100) },
            requiredCenterDistance: 35, latitudeDelta: 0.8
        )
        #expect(fullyOverlapping.map { $0.map(\.id) } == groups.map { $0.map(\.id) })
        #expect(!RestaurantMapRegionalGroupingPolicy.isCoincident([leader, nearby]))
        #expect(Set(groups.flatMap { $0.map(\.id) }) == Set(markers.map(\.id)))
        #expect(groups.reduce(0) { $0 + $1.count } == markers.count)
        for member in groups.flatMap({ $0 }) {
            let original = markers.first { $0.id == member.id }
            #expect(member.latitude == original?.latitude)
            #expect(member.longitude == original?.longitude)
        }
        let panned = RestaurantMapRegionalGroupingPolicy.groups(
            for: markers.reversed(),
            screenPoints: points.mapValues { CGPoint(x: $0.x - 71, y: $0.y + 53) },
            requiredCenterDistance: 35, latitudeDelta: 0.006
        )
        #expect(panned.map { $0.map(\.id) } == groups.map { $0.map(\.id) })
        let exactCoordinatesWithoutProjection = RestaurantMapRegionalGroupingPolicy.groups(
            for: [leader, presentation(315, latitude: leader.latitude, longitude: leader.longitude)],
            screenPoints: [:], requiredCenterDistance: 35, latitudeDelta: 0.006
        )
        #expect(exactCoordinatesWithoutProjection.count == 1)
        #expect(exactCoordinatesWithoutProjection.first?.count == 2)
    }

    @Test("Representatives and exact-coordinate stacks retain Restaurant identity without quantity numbers")
    func restaurantGroupsNeverShowQuantityNumbers() {
        let marker = presentation(305, rating: 4.8)
        let view = RestaurantMarkerAnnotationView(annotation: nil, reuseIdentifier: "group-test")
        _ = view.configure(marker)
        view.setGroup(count: 12, stacked: false)
        #expect(view.accessibilityLabel?.contains(marker.name) == true)
        #expect(view.accessibilityLabel?.contains("区域代表餐厅，放大查看") == true)
        #expect(view.accessibilityLabel?.contains("12 家餐厅") == false)
        #expect(view.subviews.compactMap { ($0 as? UILabel)?.text }.contains("12") == false)
        #expect(view.bounds.size == CGSize(width: 44, height: 44))
        view.setGroup(count: 7, stacked: true)
        #expect(view.accessibilityLabel?.contains(marker.name) == true)
        #expect(view.accessibilityLabel?.contains("此处有重叠餐厅，查看列表") == true)
        #expect(view.accessibilityLabel?.contains("7 家餐厅") == false)
        #expect(view.subviews.compactMap { ($0 as? UILabel)?.text }.contains("7") == false)
        #expect(view.bounds.size == CGSize(width: 44, height: 44))
        view.setGroup(count: 1, stacked: false)
        #expect(view.accessibilityLabel?.contains(marker.name) == true)
        #expect(view.accessibilityLabel?.contains("放大查看") == false)
        #expect(view.centerOffset == .zero)
    }

    @Test("Exact-coordinate stacks show distinct real member images while the front circle stays geographically anchored")
    func exactCoordinateStackUsesRealMemberImages() throws {
        func image(_ color: UIColor) -> UIImage {
            UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
                color.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
            }
        }
        func imageViews(in root: UIView) -> [UIImageView] {
            (root as? UIImageView).map { [$0] } ?? root.subviews.flatMap { imageViews(in: $0) }
        }
        let leader = presentation(321, rating: 5)
        let members = [presentation(322, rating: 4.5), presentation(323, rating: 4), presentation(324, rating: 3.5)]
        let annotation = MKPointAnnotation()
        annotation.coordinate = CLLocationCoordinate2D(latitude: leader.latitude, longitude: leader.longitude)
        let view = RestaurantMarkerAnnotationView(annotation: annotation, reuseIdentifier: "real-stack")
        _ = view.configure(leader)
        let images = [image(.red), image(.green), image(.blue), image(.yellow)]
        view.finishImageLoad(images[0], for: leader, generation: view.imageGeneration)
        view.setGroup(count: 4, stacked: true)
        let layers = view.setStackMembers(members)
        #expect(layers.count == 2)
        #expect(layers.map { $0.1.id } == members.prefix(2).map(\.id))
        for (index, pair) in layers.enumerated() {
            let (backView, member) = pair
            _ = backView.configure(member)
            backView.finishImageLoad(images[index + 1], for: member, generation: backView.imageGeneration)
            #expect(backView.isAccessibilityElement == false)
            #expect(backView.accessibilityElementsHidden)
            #expect(backView.isUserInteractionEnabled == false)
            #expect(imageViews(in: backView).first?.image === images[index + 1])
        }
        #expect(Set(imageViews(in: view).compactMap(\.image).map(ObjectIdentifier.init)).count == 3)
        let anchor = CGPoint(x: 124.5, y: 308.25)
        view.center = anchor
        let offsets = TasteMapDesignTokens.MapRestaurantMarker.stackBackOffsets
        for span in [0.006, 0.08, 0.8, 2.4, 0.006] {
            view.setDensityStyle(.resolve(latitudeDelta: span))
            view.setNeedsLayout()
            view.layoutIfNeeded()
            let frontCircle = try #require(view.layer.shadowPath?.boundingBoxOfPath)
            #expect(frontCircle.midX == view.bounds.midX)
            #expect(frontCircle.midY == view.bounds.midY)
            #expect(view.center == anchor)
            #expect(view.centerOffset == .zero)
            #expect(view.bounds.size == CGSize(width: 44, height: 44))
            for (index, backView) in view.stackMemberViews.enumerated() {
                #expect(backView.center == CGPoint(
                    x: view.bounds.midX + offsets[index].width,
                    y: view.bounds.midY + offsets[index].height
                ))
                #expect(backView.centerOffset == .zero)
            }
            #expect(annotation.coordinate.latitude == leader.latitude)
            #expect(annotation.coordinate.longitude == leader.longitude)
        }
        let oldBackViews = view.stackMemberViews
        let oldGenerations = oldBackViews.map(\.imageGeneration)
        view.prepareForReuse()
        #expect(view.stackMemberViews.isEmpty)
        #expect(imageViews(in: view).allSatisfy { $0.image == nil })
        for (index, backView) in oldBackViews.enumerated() {
            #expect(backView.superview == nil)
            #expect(backView.imageGeneration > oldGenerations[index])
            backView.finishImageLoad(images[index + 1], for: members[index], generation: oldGenerations[index])
            #expect(imageViews(in: backView).allSatisfy { $0.image == nil })
        }
    }

    @Test("Stale image successes and failures cannot replace a reused or changed stack member")
    func stackImageCompletionRequiresCurrentIdentityAndGeneration() throws {
        func marker(photoID: Int) -> RestaurantMapMarkerPresentation {
            RestaurantMapMarkerPresentation(
                id: uuid(331), name: "成员真实图片", latitude: 30.27, longitude: 120.13,
                status: .visited, visual: .category(.other),
                publicPhotoID: uuid(photoID).uuidString, allowsRemoteImages: true,
                visitCount: 1, averageRating: 4.5, distanceKilometers: nil
            )
        }
        func imageViews(in root: UIView) -> [UIImageView] {
            (root as? UIImageView).map { [$0] } ?? root.subviews.flatMap { imageViews(in: $0) }
        }
        let view = RestaurantMarkerAnnotationView(annotation: nil, reuseIdentifier: "stack-image-identity")
        let original = marker(photoID: 901)
        let changed = marker(photoID: 902)
        let oldImage = UIImage()
        let currentImage = UIImage()
        #expect(view.configure(original))
        let oldGeneration = view.imageGeneration
        view.finishImageLoad(oldImage, for: original, generation: oldGeneration)
        #expect(view.configure(changed))
        let generation = view.imageGeneration
        #expect(generation > oldGeneration)
        view.finishImageLoad(currentImage, for: changed, generation: generation)
        let imageView = try #require(imageViews(in: view).first)
        #expect(imageView.image === currentImage)
        view.finishImageLoad(oldImage, for: original, generation: generation)
        view.finishImageLoad(nil, for: original, generation: generation)
        view.finishImageLoad(oldImage, for: changed, generation: oldGeneration)
        view.finishImageLoad(nil, for: changed, generation: oldGeneration)
        #expect(imageView.image === currentImage)
        #expect(view.configure(changed) == false)
        #expect(view.imageGeneration == generation)
        view.prepareForReuse()
        view.finishImageLoad(oldImage, for: changed, generation: generation)
        #expect(imageView.image == nil)
    }

    @Test("Marker diameter follows every zoom step continuously and stays visually bounded")
    func markerZoomScaleIsContinuousAndBounded() {
        let deltas = [0.001, 0.008, 0.02, 0.08, 0.35, 1.5, 8, 80]
        let diameters = deltas.map {
            RestaurantMapMarkerDensityStyle.resolve(latitudeDelta: $0).baseDiameter
        }
        #expect(diameters.first == 28)
        #expect(diameters.last == 10)
        #expect(diameters.allSatisfy { (10 ... 28).contains($0) })
        for index in diameters.indices.dropFirst() {
            #expect(diameters[index] <= diameters[index - 1])
        }
        #expect(Set(diameters).count > 4)
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

    @Test("Current user marker anchors its distinct avatar bubble through a pointer tip")
    func currentUserMarkerGeometry() {
        let metrics = TasteMapDesignTokens.MapLocationMarker.self
        #expect(metrics.height > metrics.bubbleDiameter)
        #expect(metrics.haloDiameter > metrics.bubbleDiameter)
        #expect(metrics.pointerOuterSide > metrics.pointerInnerSide)
        #expect(metrics.pointerCenterY > metrics.bubbleDiameter / 2)
        #expect(metrics.centerOffsetY == -(metrics.height / 2))
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
        visitCount: Int = 0,
        recommendationRank: Int? = nil
    ) -> RestaurantMapMarkerPresentation {
        RestaurantMapMarkerPresentation(
            id: uuid(value), name: "餐厅 \(value)", latitude: latitude, longitude: longitude,
            status: .visited, visual: .category(.other), recommendationRank: recommendationRank,
            visitCount: visitCount, averageRating: rating,
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
        markerEmoji: String,
        markerType: RestaurantJSONContractV1.RestaurantMarkerTypeContract? = nil
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
            markerType: markerType ?? (markerPhotoID == nil && merchantImageURL == nil ? .emoji : .image),
            markerPhotoId: markerPhotoID, merchantImageUrl: merchantImageURL,
            markerEmoji: markerEmoji, createdAt: timestamp, updatedAt: timestamp, deletedAt: nil
        ))
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}
