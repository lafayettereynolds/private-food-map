#if DEBUG
import Foundation
import SwiftData
import UIKit

/// Compilation-gated, deterministic data for hands-on product review in one
/// Simulator. It never creates an auth credential and never talks to a server.
enum TasteMapVisualQAMode: String, CaseIterable, Sendable {
    case empty
    case normal
    case rich
    case veryRich = "very-rich"
    case denseMall = "dense-mall"
    case longText = "long-text"
    case missingPhoto = "missing-photo"
    case error
    case offline
    case free

    var usesRichLibrary: Bool {
        switch self {
        case .empty: false
        case .normal: true
        case .rich, .veryRich, .denseMall, .longText, .missingPhoto, .error, .offline, .free: true
        }
    }

    var forcesNetworkFailureState: Bool { self == .error || self == .offline }
}

@MainActor
enum TasteMapVisualQAFixtures {
    static let userID = TasteMapUITestFixtures.profileUserID

    /// The same people appear in the Hybrid Discovery `following` feed, the
    /// Profile count and the Native following list. Keeping this as an actual
    /// cached relationship graph prevents Visual QA from presenting posts by
    /// people whom the fixture account apparently does not follow.
    static let socialFollowingUsers: [SocialUserSummaryV1] = [
        .init(
            userId: "tm_demo_0", displayName: "林夏", bio: "分享真实到访与餐厅口味", city: "杭州",
            avatarPhotoId: nil, avatarPresetId: .otter
        ),
        .init(
            userId: "tm_demo_2", displayName: "陈一碗", bio: "分享真实到访与餐厅口味", city: "杭州",
            avatarPhotoId: nil, avatarPresetId: .fox
        ),
        .init(
            userId: "tm_demo_4", displayName: "阿岚", bio: "分享真实到访与餐厅口味", city: "杭州",
            avatarPhotoId: nil, avatarPresetId: .otter
        ),
        .init(
            userId: "tm_demo_6", displayName: "陆小满", bio: "分享真实到访与餐厅口味", city: "成都",
            avatarPhotoId: nil, avatarPresetId: .fox
        ),
    ]

    static let socialFollowerOnlyUser = SocialUserSummaryV1(
        userId: "tm_visual_follower", displayName: "小周", bio: "喜欢记录城市小馆", city: "上海",
        avatarPhotoId: nil, avatarPresetId: .rabbit
    )

    static let socialStatistics = ProfileSocialStatistics(
        friendCount: 2,
        followingCount: socialFollowingUsers.count,
        followerCount: 3
    )

    struct Counts: Equatable, Sendable {
        let visitedRestaurants: Int
        let wantToGoRestaurants: Int
        let visits: Int
        let photos: Int
        let dishes: Int
        let companions: Int
        let recommendationSources: Int
        let lists: Int
    }

    static func counts(for mode: TasteMapVisualQAMode) -> Counts {
        switch mode {
        case .empty:
            .init(visitedRestaurants: 0, wantToGoRestaurants: 0, visits: 0,
                  photos: 0, dishes: 0, companions: 0, recommendationSources: 0, lists: 0)
        case .normal:
            .init(visitedRestaurants: 24, wantToGoRestaurants: 8, visits: 60,
                  photos: 18, dishes: 32, companions: 5, recommendationSources: 6, lists: 4)
        case .veryRich:
            .init(visitedRestaurants: 180, wantToGoRestaurants: 50, visits: 600,
                  photos: 120, dishes: 240, companions: 10, recommendationSources: 12, lists: 8)
        case .denseMall:
            .init(visitedRestaurants: 18, wantToGoRestaurants: 0, visits: 36,
                  photos: 12, dishes: 24, companions: 4, recommendationSources: 4, lists: 2)
        case .rich, .longText, .missingPhoto, .error, .offline, .free:
            .init(visitedRestaurants: 90, wantToGoRestaurants: 25, visits: 275,
                  photos: 60, dishes: 130, companions: 10, recommendationSources: 12, lists: 7)
        }
    }

    static func photoRootURL(for mode: TasteMapVisualQAMode) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TasteMapVisualQA", isDirectory: true)
            .appendingPathComponent(mode.rawValue, isDirectory: true)
            .appendingPathComponent("Photos", isDirectory: true)
    }

    static func insert(mode: TasteMapVisualQAMode, into container: ModelContainer) throws {
        guard mode.usesRichLibrary else { return }
        let context = container.mainContext
        let counts = counts(for: mode)
        let baseDate = Date(timeIntervalSince1970: 1_788_105_600) // 2026-08-29, deterministic.

        insertSocialGraph(into: context, now: baseDate)

        let companionNames = ["小林", "妈妈", "阿宁", "Luca", "小周", "可可", "阿岚", "Marco", "佳佳", "老陈"]
        let companions: [DiningCompanion] = (0..<counts.companions).map { index in
            DiningCompanion(
                id: uuid(30_000 + index), ownerUserId: userID,
                displayName: companionNames[index % companionNames.count],
                linkedTasteMapUserId: index < 4 ? "tm_visual_friend_\(index)" : nil,
                createdAt: baseDate.addingTimeInterval(Double(-index) * 86_400),
                updatedAt: baseDate, syncStatus: .synced
            )
        }
        companions.forEach(context.insert)

        let sourceDefinitions: [(String, RecommendationSourceType)] = [
            ("朋友小林", .friend), ("小红书收藏夹", .xiaohongshu), ("抖音探店", .douyin),
            ("大众点评榜单", .dianping), ("杭州食事通讯", .blogger), ("路过发现", .self),
            ("同事阿宁", .friend), ("周末散步", .self), ("城市美食杂志", .blogger),
            ("朋友群", .friend), ("旅行攻略", .other), ("店主推荐", .other),
        ]
        let sources: [RecommendationSource] = (0..<counts.recommendationSources).map { index in
            let definition = sourceDefinitions[index % sourceDefinitions.count]
            return RecommendationSource(
                id: uuid(31_000 + index), ownerUserId: userID,
                displayName: definition.0, sourceType: definition.1,
                createdAt: baseDate.addingTimeInterval(Double(-index) * 86_400),
                updatedAt: baseDate, syncStatus: .synced
            )
        }
        sources.forEach(context.insert)

        let names = [
            "青岚寿司", "雨巷火锅", "野火烧鸟", "小满食堂", "云边面馆", "桂雨咖啡",
            "春日泰味", "湖畔西餐", "山茶烘焙", "巷口饺子", "河岸牛排馆", "月白甜品",
            "烟火小炒", "松风居酒屋", "南山素食", "白露粤菜", "秋水韩餐", "麦田披萨",
        ]
        let cuisines = [
            ["日料", "安静"], ["火锅", "朋友聚餐"], ["烧烤", "夜宵"], ["江浙菜", "家庭聚餐"],
            ["面食", "一个人"], ["咖啡", "早午餐"], ["泰国菜", "约会"], ["西餐", "牛排"],
            ["烘焙", "甜点"], ["饺子", "本地小馆"], ["西餐", "约会"], ["甜点", "下午茶"],
        ]
        let cities = ["杭州", "杭州", "杭州", "上海", "杭州", "北京", "成都", "广州"]
        // Stable, organic dining anchors replace the old evenly spaced grid.
        // Each anchor intentionally receives repeated and near-coincident
        // Restaurants so Rich Visual QA exercises the dense-area non-overlap
        // layout instead of passing only widely separated easy cases.
        let mapAnchors: [(latitude: Double, longitude: Double)] = [
            (30.2741, 120.1551), (30.2676, 120.1474), (30.2819, 120.1628),
            (30.2598, 120.1692), (30.2893, 120.1431), (30.2527, 120.1518),
            (30.2772, 120.1776), (30.2951, 120.1589), (30.2644, 120.1327),
            (30.2848, 120.1864), (30.2469, 120.1745), (30.3016, 120.1388),
            (30.2713, 120.1912), (30.2561, 120.1239), (30.3102, 120.1698),
            (30.2397, 120.1436), (30.2924, 120.1991), (30.3190, 120.1507),
        ]
        let overlapOffsets: [(latitude: Double, longitude: Double)] = [
            (0, 0), (0, 0), (0.000_16, -0.000_10),
            (-0.000_12, 0.000_15), (0.000_08, 0.000_18),
        ]
        // Very Rich intentionally puts at least ten of the first 90 records at
        // each mall-like anchor so the iOS fixture exercises real same-place
        // density even when a consumer applies a 90-item presentation cap.
        let activeMapAnchors: [(latitude: Double, longitude: Double)] = switch mode {
        case .denseMall: [mapAnchors[0]]
        case .veryRich: Array(mapAnchors.prefix(9))
        default: mapAnchors
        }
        let restaurantCount = counts.visitedRestaurants + counts.wantToGoRestaurants
        // Spread owner photos across the library so Map and list screenshots
        // exercise owner-photo and category-visual markers at the same time.
        let orderedPhotoRestaurantIndexes = Array(stride(from: 0, to: restaurantCount, by: 2))
            + Array(stride(from: 1, to: restaurantCount, by: 2))
        let photoRestaurantIndexes = Array(orderedPhotoRestaurantIndexes.prefix(counts.photos))
        let photoSlotByRestaurant = Dictionary(uniqueKeysWithValues:
            photoRestaurantIndexes.enumerated().map { ($0.element, $0.offset) }
        )
        let nonPhotoRestaurantIndexes = (0..<restaurantCount).filter {
            photoSlotByRestaurant[$0] == nil
        }
        let publicPhotoRestaurantIndexes = Set(nonPhotoRestaurantIndexes.prefix(20))
        let providerImageRestaurantIndexes = Set(nonPhotoRestaurantIndexes.dropFirst(20).prefix(20))
        var restaurants: [Restaurant] = []
        restaurants.reserveCapacity(restaurantCount)
        for index in 0..<restaurantCount {
            let status: RestaurantStatus = index < counts.visitedRestaurants ? .visited : .wantToGo
            let isLong = mode == .longText && index.isMultiple(of: 7)
            let baseName = names[index % names.count]
            let name = isLong ? "\(baseName)·湖滨银泰限定季节料理与炭火烧物体验店" : "\(baseName) \(index / names.count + 1)"
            let city = cities[index % cities.count]
            let id = uuid(32_000 + index)
            let hasImageFixture = mode != .missingPhoto
            let localPhotoID = hasImageFixture
                ? photoSlotByRestaurant[index].map { uuid(35_000 + $0) }
                : nil
            let publicPhotoID = hasImageFixture
                && publicPhotoRestaurantIndexes.contains(index)
                ? uuid(45_000 + index).uuidString.lowercased()
                : nil
            let providerImageURL = hasImageFixture
                && providerImageRestaurantIndexes.contains(index)
                ? "https://visual-qa.invalid/restaurants/\(index).jpg"
                : nil
            let tags = cuisines[index % cuisines.count]
            let anchor = activeMapAnchors[index % activeMapAnchors.count]
            let overlap = overlapOffsets[(index / activeMapAnchors.count) % overlapOffsets.count]
            let restaurant = Restaurant(
                id: id, ownerUserID: userID, name: name,
                address: "\(city)市美食街 \(index + 1) 号\(isLong ? "（靠近湖滨步行街与地铁换乘通道）" : "")",
                latitude: anchor.latitude + overlap.latitude,
                longitude: anchor.longitude + overlap.longitude,
                appleMapItemIdentifier: index.isMultiple(of: 3) ? "apple-visual-qa-\(index)" : nil,
                city: city, status: status,
                createdAt: baseDate.addingTimeInterval(Double(-index * 2) * 86_400),
                updatedAt: baseDate, remoteID: id.uuidString.lowercased(),
                serverVersion: 1, lastSyncedAt: baseDate, syncStatus: .synced,
                remoteRecordData: try restaurantContract(
                    id: id, index: index, name: name, city: city, status: status,
                    tags: tags,
                    markerPhotoID: localPhotoID?.uuidString.lowercased() ?? publicPhotoID,
                    merchantImageURL: providerImageURL
                )
            )
            restaurants.append(restaurant)
            context.insert(restaurant)
        }

        var visits: [Visit] = []
        visits.reserveCapacity(counts.visits)
        for index in 0..<counts.visits {
            let restaurant = restaurants[index % max(1, counts.visitedRestaurants)]
            let companion = companions[index % max(1, companions.count)]
            let source = sources[index % max(1, sources.count)]
            // QA meals span actual local dining periods, not a single UTC base hour.
            let day = Calendar.current.startOfDay(for: baseDate.addingTimeInterval(Double(-index * 3) * 86_400))
            let date = Calendar.current.date(byAdding: .hour, value: [8, 12, 15, 19, 23][index % 5], to: day) ?? day
            let visit = Visit(
                id: uuid(34_000 + index), ownerUserID: userID, restaurantId: restaurant.id,
                visitedAt: date, rating: index.isMultiple(of: 7) ? nil : Double(7 + index % 4) / 2,
                valueRating: index.isMultiple(of: 2) ? Double(7 + index % 3) / 2 : nil,
                environmentRating: index.isMultiple(of: 3) ? Double(8 + index % 3) / 2 : nil,
                serviceRating: index.isMultiple(of: 4) ? Double(7 + index % 4) / 2 : nil,
                note: index.isMultiple(of: 9)
                    ? "这次点了几道季节菜，火候和节奏都很稳；适合和熟悉的朋友慢慢吃，也愿意为了招牌菜再来一次。"
                    : (index.isMultiple(of: 5) ? nil : "值得记录的一顿饭。"),
                myActualSpend: index.isMultiple(of: 6) ? nil : Decimal(58 + (index % 12) * 27),
                totalPrice: Decimal(120 + (index % 10) * 55),
                pricePerPerson: Decimal(60 + (index % 8) * 22),
                diningMode: index.isMultiple(of: 11) ? .takeout : .dineIn,
                visibility: index.isMultiple(of: 4) ? .public : .friends,
                paymentMode: [.aa, .myTreat, .treated, .separate][index % 4],
                queueDuration: [.noWait, .under15, .under30, .under60][index % 4],
                diningOccasions: [[.solo], [.friends], [.date], [.family], [.celebration]][index % 5],
                valueTags: [index.isMultiple(of: 2) ? "值得再去" : "份量合适"],
                environmentTags: [index.isMultiple(of: 3) ? "安静舒服" : "有烟火气"],
                serviceTags: [index.isMultiple(of: 4) ? "细心" : "节奏自然"],
                noiseLevel: [.quiet, .normal, .loud][index % 3],
                diningDuration: [.under60, .under90, .under120][index % 3],
                portionLevel: [.small, .normal, .generous][index % 3],
                transportConvenience: [.veryConvenient, .convenient, .normal][index % 3],
                companionIDs: index.isMultiple(of: 5) ? [] : [companion.remoteID ?? companion.id.uuidString.lowercased()],
                companionNames: index.isMultiple(of: 5) ? [] : [companion.displayName],
                recommendationSourceID: source.remoteID,
                recommendationSourceType: source.sourceType,
                recommendationSourceText: source.displayName,
                partySize: index.isMultiple(of: 5) ? 1 : 2 + index % 5,
                createdAt: date, updatedAt: date, remoteID: uuid(34_000 + index).uuidString.lowercased(),
                serverVersion: 1, lastSyncedAt: baseDate, syncStatus: .synced
            )
            visits.append(visit)
            context.insert(visit)
        }

        for index in 0..<counts.dishes {
            let visit = visits[index % max(1, visits.count)]
            let dish = Dish(
                id: uuid(36_000 + index), ownerUserID: userID,
                restaurantId: visit.restaurantId, visitId: visit.id,
                name: ["炭烤鸡腿葱串", "季节刺身拼盘", "番茄牛腩锅", "龙井虾仁", "焦糖布丁", "黑松露薯条"][index % 6],
                taste: ["咸鲜炭香", "清爽鲜甜", "浓郁温暖", "清鲜", "柔滑微苦", "香脆"][index % 6],
                rating: Double(7 + index % 4) / 2, price: Decimal(28 + index % 8 * 12),
                sortOrder: index % 5, createdAt: visit.visitedAt, updatedAt: visit.visitedAt,
                serverVersion: 1, lastSyncedAt: baseDate, syncStatus: .synced
            )
            context.insert(dish)
            context.insert(VisitDish(
                id: uuid(37_000 + index), ownerUserID: userID,
                restaurantId: visit.restaurantId, visitId: visit.id, dishId: dish.id,
                sortOrder: index % 5, createdAt: visit.visitedAt, updatedAt: visit.visitedAt,
                serverVersion: 1, lastSyncedAt: baseDate, syncStatus: .synced
            ))
        }

        if mode != .missingPhoto {
            for index in 0..<counts.photos {
                let restaurant = restaurants[photoRestaurantIndexes[index]]
                let visit = visits.first(where: { $0.restaurantId == restaurant.id })
                let id = uuid(35_000 + index)
                let path = "display/\(id.uuidString.lowercased()).jpg"
                context.insert(PhotoAsset(
                    id: id, ownerUserID: userID, restaurantId: restaurant.id,
                    visitId: visit?.id, kind: index.isMultiple(of: 3) ? .restaurantMarker : .visit,
                    fileName: "visual-qa-restaurant-\(index + 1).jpg", mimeType: "image/jpeg",
                    byteSize: 180_000, width: 1_200, height: 900, sortOrder: index % 3,
                    visibility: index.isMultiple(of: 4) ? .public : .friends,
                    localFileRelativePath: path, displayFileRelativePath: path,
                    thumbnailFileRelativePath: "thumbnails/\(id.uuidString.lowercased()).jpg",
                    uploadState: .uploaded, createdAt: baseDate, updatedAt: baseDate,
                    serverVersion: 1, lastSyncedAt: baseDate, syncStatus: .synced
                ))
            }
        }

        try insertLists(count: counts.lists, restaurants: restaurants, context: context, now: baseDate, longText: mode == .longText)
        try context.save()
    }

    private static func insertSocialGraph(into context: ModelContext, now: Date) {
        for user in socialFollowingUsers + [socialFollowerOnlyUser] {
            context.insert(CachedSocialProfile(
                tasteMapUserID: user.userId,
                displayName: user.displayName,
                bio: user.bio,
                city: user.city,
                avatarPhotoID: user.avatarPhotoId,
                avatarPreset: user.avatarPresetId,
                fetchedAt: now
            ))
        }

        for user in socialFollowingUsers {
            context.insert(CachedFollow(
                relationshipID: "follow:\(userID):\(user.userId)",
                currentUserID: userID,
                followerUserID: userID,
                followedUserID: user.userId,
                createdAt: now,
                updatedAt: now,
                serverVersion: 1
            ))
        }

        let mutualUsers = Array(socialFollowingUsers.prefix(2))
        for user in mutualUsers {
            context.insert(CachedFollow(
                relationshipID: "follow:\(user.userId):\(userID)",
                currentUserID: userID,
                followerUserID: user.userId,
                followedUserID: userID,
                createdAt: now,
                updatedAt: now,
                serverVersion: 1
            ))
            context.insert(CachedFriendship(
                relationshipID: "friendship:\(userID):\(user.userId)",
                currentUserID: userID,
                requesterUserID: userID,
                addresseeUserID: user.userId,
                state: .friends,
                createdAt: now,
                updatedAt: now,
                serverVersion: 1
            ))
        }

        context.insert(CachedFollow(
            relationshipID: "follow:\(socialFollowerOnlyUser.userId):\(userID)",
            currentUserID: userID,
            followerUserID: socialFollowerOnlyUser.userId,
            followedUserID: userID,
            createdAt: now,
            updatedAt: now,
            serverVersion: 1
        ))
    }

    static func preparePhotoFiles(mode: TasteMapVisualQAMode) throws {
        guard mode.usesRichLibrary, mode != .missingPhoto else { return }
        let root = photoRootURL(for: mode)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: root.appendingPathComponent("display"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: root.appendingPathComponent("thumbnails"), withIntermediateDirectories: true)
        for index in 0..<counts(for: mode).photos {
            let id = uuid(35_000 + index)
            let data = restaurantPhoto(index: index)
            try data.write(to: root.appendingPathComponent("display/\(id.uuidString.lowercased()).jpg"), options: .atomic)
            try data.write(to: root.appendingPathComponent("thumbnails/\(id.uuidString.lowercased()).jpg"), options: .atomic)
        }
    }

    static func restaurantImage(stableKey: String) -> UIImage? {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in stableKey.utf8 {
            hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return UIImage(data: restaurantPhoto(index: Int(hash % 4)))
    }

    private static func insertLists(
        count: Int, restaurants: [Restaurant], context: ModelContext, now: Date, longText: Bool
    ) throws {
        guard !restaurants.isEmpty else { return }
        let titles = ["杭州反复回访", "周末约会餐厅", "深夜也想吃", "江浙菜私藏", "咖啡与甜点", "朋友聚餐", "下一次旅行"]
        for listIndex in 0..<count {
            let id = uuid(38_000 + listIndex)
            let itemCount = listIndex == 0 ? 0 : min(restaurants.count, listIndex == count - 1 ? 14 : 4 + listIndex)
            let list = RestaurantList(
                id: id, remoteID: id.uuidString.lowercased(), ownerUserID: userID,
                title: longText && listIndex == 1 ? "适合在一个很长很长的周末里和朋友慢慢探索的餐厅清单" : titles[listIndex % titles.count],
                listDescription: "按真实到访、想吃理由和当时的记忆整理。",
                visibility: [.private, .friends, .public][listIndex % 3],
                isRanked: listIndex.isMultiple(of: 2), coverMode: .automatic,
                activeItemCount: itemCount,
                previewRestaurantIDs: restaurants.prefix(min(4, itemCount)).map { $0.remoteID ?? $0.id.uuidString.lowercased() },
                createdAt: now.addingTimeInterval(Double(-listIndex) * 86_400), updatedAt: now,
                serverVersion: 1, lastSyncedAt: now, syncStatus: .synced
            )
            let previews = try restaurants.prefix(min(4, itemCount)).enumerated().map { offset, restaurant in
                try listPlace(for: restaurant, index: offset)
            }
            list.previewRestaurants = previews
            context.insert(list)
            for itemIndex in 0..<itemCount {
                let restaurant = restaurants[(listIndex * 7 + itemIndex) % restaurants.count]
                let snapshot = try listPlace(for: restaurant, index: itemIndex)
                context.insert(try RestaurantListItem(
                    id: uuid(39_000 + listIndex * 100 + itemIndex),
                    ownerUserID: userID, listID: id, listRemoteID: id.uuidString.lowercased(),
                    restaurantReferenceID: restaurant.remoteID ?? restaurant.id.uuidString.lowercased(),
                    localRestaurantID: restaurant.id, restaurantGlobalKey: snapshot.globalKey,
                    restaurantSnapshot: snapshot, position: itemIndex,
                    note: itemIndex == 0 ? "最能代表这张食单的一家。" : "",
                    createdAt: now, updatedAt: now, serverVersion: 1,
                    lastSyncedAt: now, syncStatus: .synced
                ))
            }
        }
    }

    private static func restaurantContract(
        id: UUID, index: Int, name: String, city: String, status: RestaurantStatus,
        tags: [String], markerPhotoID: String?, merchantImageURL: String?
    ) throws -> Data {
        let timestamp = "2026-08-29T12:00:00.000Z"
        let provider: RestaurantPlaceProvider = index.isMultiple(of: 3) ? .appleMaps : (index.isMultiple(of: 5) ? .amap : .manual)
        let identity = try RestaurantPlaceIdentityContract(
            provider: provider, externalId: "\(provider.rawValue)-visual-qa-\(index)", isPrimary: true,
            createdAt: timestamp, updatedAt: timestamp
        )
        return try JSONEncoder().encode(RestaurantJSONContractV1(
            id: id.uuidString.lowercased(), userId: userID, placeIdentities: [identity],
            name: name, address: "\(city)市美食街 \(index + 1) 号", city: city,
            latitude: 30.238 + Double(index % 15) * 0.0042,
            longitude: 120.118 + Double((index / 15) % 15) * 0.0045,
            status: status == .wantToGo ? .wantToGo : .visited,
            preferenceLevel: index.isMultiple(of: 7) ? .favorite : .like,
            overallRating: nil, foodRating: nil, environmentRating: nil,
            serviceRating: nil, valueRating: nil, tags: tags,
            longTermNote: "招牌菜稳定，适合按当日心情再来。",
            pricePerPerson: Double(68 + index % 8 * 32), phone: "+86 571 88\(String(format: "%06d", index))",
            openingHours: "周一至周日 11:00–22:30", markerType: markerPhotoID == nil ? .emoji : .image,
            markerPhotoId: markerPhotoID, merchantImageUrl: merchantImageURL,
            markerEmoji: ["🍣", "🍲", "🍜", "☕️", "🥟", "🥩"][index % 6],
            createdAt: timestamp, updatedAt: timestamp, deletedAt: nil, isTestData: true
        ))
    }

    private static func listPlace(for restaurant: Restaurant, index: Int) throws -> RestaurantListPlaceContractV1 {
        let contract = restaurant.remoteRecordData.flatMap { try? JSONDecoder().decode(RestaurantJSONContractV1.self, from: $0) }
        let listIdentities = (contract?.placeIdentities ?? []).map {
            RestaurantListPlaceIdentityContractV1(
                provider: $0.provider, externalId: $0.externalId, isPrimary: $0.isPrimary
            )
        }
        return try RestaurantListPlaceContractV1(
            globalKey: "visual-qa:\(restaurant.id.uuidString.lowercased())",
            restaurantId: restaurant.remoteID ?? restaurant.id.uuidString.lowercased(),
            placeIdentities: listIdentities,
            name: restaurant.name, address: restaurant.address, city: restaurant.city,
            latitude: restaurant.latitude, longitude: restaurant.longitude,
            markerPhotoId: contract?.markerPhotoId, merchantImageUrl: contract?.merchantImageUrl,
            markerEmoji: contract?.markerEmoji ?? "🍽️"
        )
    }

    private static func restaurantPhoto(index: Int) -> Data {
        let approvedRestaurantStyleAssets = [
            "FoodHeroChinese", "FoodHeroJapanese", "FoodHeroHotpotGrill",
            "FoodHeroWestern", "FoodHeroCafe", "FoodHeroMixed",
        ]
        guard let image = UIImage(named: approvedRestaurantStyleAssets[index % approvedRestaurantStyleAssets.count]) else {
            return Data()
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1_200, height: 900), format: format)
        return renderer.image { context in
            UIColor(red: 0.965, green: 0.957, blue: 0.937, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1_200, height: 900))
            let scale = max(1_200 / image.size.width, 900 / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(
                x: (1_200 - size.width) / 2,
                y: (900 - size.height) / 2,
                width: size.width,
                height: size.height
            ))
        }.jpegData(compressionQuality: 0.86) ?? Data()
    }

    private static func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", value))!
    }
}
#endif
