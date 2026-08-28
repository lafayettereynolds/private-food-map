#if DEBUG
import Foundation
import SwiftData
import UIKit

@MainActor
enum TasteMapUITestFixtures {
    static let detailRestaurantID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    static let detailLaunchArgument = "-p1b-restaurant-detail-fixture"
    static let persistentLaunchArgument = "-p1d-persistent-offline-fixture"
    static let resetPersistentLaunchArgument = "-p1d-reset-persistent-offline-fixture"
    static let persistentConfigurationName = "TasteMapP1DUITests"
    static let persistentEnvironmentKey = "TASTEMAP_P1D_UI_TEST"
    static let resetEnvironmentKey = "TASTEMAP_P1D_RESET"
    static let photoEnvironmentKey = "TASTEMAP_P2B_UI_TEST"
    static let photoFailureEnvironmentKey = "TASTEMAP_P2B_UPLOAD_FAILURE_UI_TEST"
    static let profileEnvironmentKey = "TASTEMAP_P3A_PROFILE_UI_TEST"
    static let profileUserID = "tm_p3a_ui_fixture"
    static let discoveryEnvironmentKey = "TASTEMAP_P3C_DISCOVERY_UI_TEST"
    static let discoveryOfflineEnvironmentKey = "TASTEMAP_P3C_DISCOVERY_OFFLINE_UI_TEST"
    static let communityEnvironmentKey = "TASTEMAP_P3D_COMMUNITY_UI_TEST"
    static let communityOfflineEnvironmentKey = "TASTEMAP_P3D_COMMUNITY_OFFLINE_UI_TEST"
    static let analysisEnvironmentKey = "TASTEMAP_P4A_ANALYSIS_UI_TEST"
    static let companionAnalysisEnvironmentKey = "TASTEMAP_P4B_COMPANION_UI_TEST"
    static let recommendationSourceAnalysisEnvironmentKey = "TASTEMAP_P4C_SOURCE_UI_TEST"

    static var usesAnalysisFixture: Bool {
        ProcessInfo.processInfo.environment[analysisEnvironmentKey] == "1"
            || usesCompanionAnalysisFixture
            || usesRecommendationSourceAnalysisFixture
    }

    static var usesCompanionAnalysisFixture: Bool {
        ProcessInfo.processInfo.environment[companionAnalysisEnvironmentKey] == "1"
    }

    static var usesRecommendationSourceAnalysisFixture: Bool {
        ProcessInfo.processInfo.environment[recommendationSourceAnalysisEnvironmentKey] == "1"
    }

    static var usesCommunityFixture: Bool {
        ProcessInfo.processInfo.environment[communityEnvironmentKey] == "1"
            || usesCommunityOfflineFixture
    }

    static var usesCommunityOfflineFixture: Bool {
        ProcessInfo.processInfo.environment[communityOfflineEnvironmentKey] == "1"
    }

    static var usesDiscoveryFixture: Bool {
        ProcessInfo.processInfo.environment[discoveryEnvironmentKey] == "1"
    }

    static var usesDiscoveryOfflineFixture: Bool {
        ProcessInfo.processInfo.environment[discoveryOfflineEnvironmentKey] == "1"
    }

    static var usesProfileFixture: Bool {
        ProcessInfo.processInfo.environment[profileEnvironmentKey] == "1"
            || usesAnalysisFixture
    }

    static var usesPhotoFixture: Bool {
        ProcessInfo.processInfo.environment[photoEnvironmentKey] == "1"
    }

    static var requestsPhotoFailureFixture: Bool {
        ProcessInfo.processInfo.environment[photoFailureEnvironmentKey] == "1"
    }

    static func samplePhotoData() -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: 1_200, height: 900),
            format: format
        ).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1_200, height: 900))
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 180, y: 150, width: 840, height: 600))
        }
        return image.jpegData(compressionQuality: 0.9) ?? Data()
    }

    static var usesPersistentFixture: Bool {
        ProcessInfo.processInfo.environment[persistentEnvironmentKey] == "1"
            || ProcessInfo.processInfo.arguments.contains(persistentLaunchArgument)
    }

    static var requestsPersistentFixtureReset: Bool {
        ProcessInfo.processInfo.environment[resetEnvironmentKey] == "1"
            || ProcessInfo.processInfo.arguments.contains(resetPersistentLaunchArgument)
    }

    static var persistentStoreURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "TasteMapP1DUITests.store")
    }

    static func insertRestaurantDetailFixture(into container: ModelContainer) throws {
        let restaurant = Restaurant(
            id: detailRestaurantID,
            name: "P1-B 想吃餐厅",
            address: "杭州市上城区湖滨路 18 号",
            latitude: 30.259,
            longitude: 120.168,
            appleMapItemIdentifier: "apple-ui-test-p1b",
            city: "杭州",
            status: .wantToGo,
            syncStatus: .synced
        )
        container.mainContext.insert(restaurant)
        try container.mainContext.save()
    }

    static func preparePersistentOfflineFixture(
        in container: ModelContainer,
        reset: Bool
    ) throws {
        let context = container.mainContext
        if reset {
            for source in try context.fetch(FetchDescriptor<RecommendationSource>()) {
                context.delete(source)
            }
            for companion in try context.fetch(FetchDescriptor<DiningCompanion>()) {
                context.delete(companion)
            }
            for photo in try context.fetch(FetchDescriptor<PhotoAsset>()) {
                context.delete(photo)
            }
            for association in try context.fetch(FetchDescriptor<VisitDish>()) {
                context.delete(association)
            }
            for dish in try context.fetch(FetchDescriptor<Dish>()) {
                context.delete(dish)
            }
            for mutation in try context.fetch(FetchDescriptor<SyncMutation>()) {
                context.delete(mutation)
            }
            for profile in try context.fetch(FetchDescriptor<UserProfile>()) {
                context.delete(profile)
            }
            for checkpoint in try context.fetch(FetchDescriptor<SyncCheckpoint>()) {
                context.delete(checkpoint)
            }
            for visit in try context.fetch(FetchDescriptor<Visit>()) {
                context.delete(visit)
            }
            for restaurant in try context.fetch(FetchDescriptor<Restaurant>()) {
                context.delete(restaurant)
            }
            try context.save()
        }

        let existing = try context.fetch(FetchDescriptor<Restaurant>())
            .first { $0.id == detailRestaurantID }
        guard existing == nil else { return }
        context.insert(Restaurant(
            id: detailRestaurantID,
            name: "P1-D 离线验收餐厅",
            address: "杭州市上城区湖滨路 18 号",
            latitude: 30.259,
            longitude: 120.168,
            appleMapItemIdentifier: "apple-ui-test-p1d",
            city: "杭州",
            status: .wantToGo,
            syncStatus: .synced
        ))
        try context.save()
    }

    static func insertProfileFixture(into container: ModelContainer) throws {
        guard usesProfileFixture || usesDiscoveryFixture || usesCommunityFixture || usesAnalysisFixture else { return }
        let context = container.mainContext
        if try context.fetch(FetchDescriptor<UserProfile>())
            .contains(where: { $0.tasteMapUserID == profileUserID }) { return }
        context.insert(UserProfile(
            tasteMapUserID: profileUserID,
            displayName: "P3-A 初始用户",
            bio: "正在建立自己的美食身份。",
            city: "杭州",
            avatarPreset: .polarBear,
            visibility: .private,
            serverVersion: 1,
            syncStatus: .synced
        ))
        try context.save()
    }

    static func discoveryPage(mode: DiscoveryModeV1, window: Int) -> DiscoveryPageV1 {
        let source = DiscoveryPublicUserProjectionV1(
            userId: "tm_p3c_source", displayName: "同味小林", bio: "公开探店记录",
            city: "杭州", avatarPhotoId: nil, avatarPresetId: .penguin,
            friendshipId: nil, friendshipState: .none, isFollowing: false
        )
        let items = (0..<4).map { index -> DiscoveryCardV1 in
            let projection = DiscoveryRestaurantProjectionV1(
                globalKey: "place:p3c-ui-\(index)",
                placeIdentities: [.init(provider: .appleMaps, externalId: "apple-p3c-ui-\(index)", isPrimary: true)],
                name: index == 0 ? "P3-C 发现寿司店" : "P3-C 真实餐厅 \(index + 1)",
                address: "西湖区发现路 \(index + 1) 号", city: "杭州",
                latitude: 30.25, longitude: 120.16, tags: ["日料"], pricePerPerson: 128,
                merchantImageUrl: nil, markerEmoji: index == 0 ? "🍣" : "🍲", photo: nil
            )
            let reason: DiscoveryReasonV1
            switch mode {
            case .forYou: reason = .init(code: "TASTE_TAG_MATCH", text: "符合你常给高分的日料口味")
            case .similarTaste: reason = .init(code: "SIMILAR_USERS", text: "基于 5 家共同评分餐厅，同味用户给过高分")
            case .trending: reason = .init(code: "TRENDING_UNIQUE_USERS", text: "近 \(window) 天有 8 位用户到访")
            }
            return DiscoveryCardV1(
                id: "\(mode.rawValue):\(projection.globalKey)", mode: mode,
                restaurant: projection, viewerState: .none,
                ratings: .init(mine: .init(value: nil, sampleCount: 0),
                               community: .init(value: 4.6, sampleCount: 8),
                               friends: .init(value: 4.8, sampleCount: 2),
                               similarTaste: .init(value: 4.7, sampleCount: 3)),
                reasons: [reason], sourceUser: mode == .trending ? nil : source,
                similarity: mode == .similarTaste ? .init(percent: 91, sharedRestaurantCount: 5) : nil,
                trend: mode == .trending ? .init(windowDays: window, uniqueVisitorCount: 8, wantToGoCount: 3) : nil,
                cacheScope: .public, rank: index + 1, score: Double(100 - index)
            )
        }
        return DiscoveryPageV1(
            apiVersion: 1, mode: mode, city: "杭州", personalizationConfidence: .high,
            generatedAt: ISO8601DateFormatter().string(from: .now), items: items, nextCursor: nil
        )
    }

    static func communityPage(scope: CommunityFeedScopeV1) -> CommunityFeedPageV1 {
        let users = [
            PublicContentUserV1(
                userId: "tm_p3d_friend", displayName: "常去小馆的阿岚", bio: "把每次好好吃饭都记下来。",
                city: "杭州", avatarPhotoId: nil, avatarPresetId: .otter,
                friendshipId: "friendship:tm_p3a_ui_fixture:tm_p3d_friend",
                friendshipState: .friends, isFollowing: true
            ),
            PublicContentUserV1(
                userId: "tm_p3d_public", displayName: "一个名字很长很长的公开探店用户",
                bio: "寻找真正值得再去一次的小店。", city: "上海", avatarPhotoId: nil,
                avatarPresetId: .penguin, friendshipId: nil, friendshipState: .none,
                isFollowing: scope == .following
            )
        ]
        let formatter = ISO8601DateFormatter()
        let items = (0..<4).map { index -> PublicContentItemV1 in
            let user = users[index % users.count]
            let eventAt = formatter.string(from: Date(timeIntervalSince1970: 1_777_500_000 - Double(index * 3_600)))
            let restaurant = PublicContentRestaurantV1(
                globalKey: "place:p3d-ui-\(index)",
                placeIdentities: [.init(provider: .appleMaps, externalId: "apple-p3d-ui-\(index)", isPrimary: true)],
                name: index == 0 ? "云边小馆·湖滨店" : "社区真实餐厅 \(index + 1)",
                address: "湖滨路 \(index + 18) 号", city: index.isMultiple(of: 2) ? "杭州" : "上海",
                latitude: 30.25, longitude: 120.16, tags: ["本帮菜", "适合朋友聚餐"],
                pricePerPerson: 136, merchantImageUrl: nil,
                markerEmoji: index.isMultiple(of: 2) ? "🍲" : "🍣", photo: nil
            )
            let visit = PublicVisitV1(
                id: "visit-p3d-ui-\(index)", ownerUserId: user.userId,
                restaurantGlobalKey: restaurant.globalKey, visitedAt: eventAt,
                rating: index == 1 ? nil : 4.5,
                note: index == 2
                    ? "这是一段用于验证较长内容的真实到访备注。菜的火候很稳，朋友们都愿意下次再来；即使文字变长，卡片也应该保持清楚、自然，并且不能泄露消费、饭搭子或推荐来源。"
                    : "热气腾腾，味道很稳，适合和朋友慢慢吃。",
                visibility: user.friendshipState == .friends ? .friends : .public,
                photos: [], updatedAt: eventAt
            )
            return PublicContentItemV1(
                id: "visit:\(visit.id)", kind: .visit, eventAt: eventAt, updatedAt: eventAt,
                user: user, restaurant: restaurant, visit: visit,
                viewerState: index == 3 ? .visited : .none,
                cacheScope: user.friendshipState == .friends ? .friends : .public
            )
        }
        return CommunityFeedPageV1(
            apiVersion: 1, scope: scope, generatedAt: formatter.string(from: .now),
            items: items, nextCursor: nil
        )
    }

    static func insertPhotoFailureFixture(into container: ModelContainer) throws {
        let context = container.mainContext
        let restaurant = try context.fetch(FetchDescriptor<Restaurant>())
            .first { $0.id == detailRestaurantID }
        guard let restaurant else { return }
        restaurant.status = .visited
        let visit = Visit(restaurantId: restaurant.id, syncStatus: .pending)
        let photo = PhotoAsset(
            restaurantId: restaurant.id,
            visitId: visit.id,
            kind: .visit,
            fileName: "upload-failure-ui-test.jpg",
            mimeType: "image/jpeg",
            byteSize: 128_000,
            width: 1_200,
            height: 900,
            uploadState: .failed,
            uploadLastError: "网络暂时不可用",
            syncStatus: .pending
        )
        context.insert(visit)
        context.insert(photo)
        try context.save()
    }

    static func insertTasteProfileAnalysisFixture(into container: ModelContainer) throws {
        guard usesAnalysisFixture else { return }
        let context = container.mainContext
        let companion = DiningCompanion(
            id: uuid(4_001), ownerUserId: profileUserID, displayName: "小林", syncStatus: .synced
        )
        let secondCompanion = DiningCompanion(
            id: uuid(4_003), ownerUserId: profileUserID, displayName: "妈妈", syncStatus: .synced
        )
        let source = RecommendationSource(
            id: uuid(4_002), ownerUserId: profileUserID, displayName: "朋友推荐",
            sourceType: .friend, syncStatus: .synced
        )
        context.insert(companion)
        context.insert(secondCompanion)
        context.insert(source)

        let definitions: [(UUID, String, [String], RestaurantStatus)] = [
            (uuid(4_101), "山葵小料理", ["日料", "居酒屋", "安静"], .visited),
            (uuid(4_102), "红炉火锅", ["火锅", "川菜", "朋友聚餐"], .visited),
            (uuid(4_103), "树影咖啡", ["咖啡", "甜点", "早午餐"], .visited),
            (uuid(4_104), "河岸牛排馆", ["西餐", "牛排", "约会"], .visited),
            (uuid(4_105), "云朵寿喜烧", ["日料", "寿喜烧", "朋友聚餐"], .wantToGo),
            (uuid(4_106), "巷口炉端烧", ["烧烤", "日料", "朋友聚餐"], .wantToGo),
        ]
        var restaurants: [Restaurant] = []
        for (index, definition) in definitions.enumerated() {
            let restaurant = Restaurant(
                id: definition.0, name: definition.1,
                address: "杭州市西湖区真实路 \(index + 1) 号",
                latitude: 30.25 + Double(index) * 0.001,
                longitude: 120.16 + Double(index) * 0.001,
                appleMapItemIdentifier: "apple-p4a-ui-\(index)", city: "杭州",
                status: definition.3, syncStatus: .synced,
                remoteRecordData: try restaurantContractData(
                    id: definition.0, name: definition.1, tags: definition.2,
                    status: definition.3, index: index
                )
            )
            context.insert(restaurant)
            restaurants.append(restaurant)
        }

        var firstVisitByRestaurant: [UUID: UUID] = [:]
        let sequence = [0, 0, 1, 0, 2, 1, 3, 0, 2, 1, 0, 3, 1, 2]
        for (index, restaurantIndex) in sequence.enumerated() {
            let restaurant = restaurants[restaurantIndex]
            let date = Calendar.current.date(byAdding: .day, value: -index * 9, to: .now) ?? .now
            let visit = Visit(
                id: uuid(4_200 + index), restaurantId: restaurant.id, visitedAt: date,
                rating: index % 5 == 3 ? nil : [4.0, 4.5, 5.0][index % 3],
                valueRating: index.isMultiple(of: 2) ? 4 : nil,
                environmentRating: index.isMultiple(of: 3) ? 4.5 : nil,
                serviceRating: index.isMultiple(of: 4) ? 4 : nil,
                note: "P4-A 真实结构视觉验收记录",
                myActualSpend: [Decimal(188), 236, 128, 68, 398][index % 5],
                diningOccasions: [index.isMultiple(of: 3) ? .friends : .solo],
                valueTags: ["值得再去"], environmentTags: [index.isMultiple(of: 2) ? "舒服" : "热闹"],
                serviceTags: ["细心"], noiseLevel: .normal,
                companionIDs: [companion.remoteID ?? companion.id.uuidString.lowercased()]
                    + (index.isMultiple(of: 3) ? [secondCompanion.remoteID ?? secondCompanion.id.uuidString.lowercased()] : []),
                companionNames: [companion.displayName]
                    + (index.isMultiple(of: 3) ? [secondCompanion.displayName] : []),
                recommendationSourceID: source.remoteID,
                recommendationSourceType: .friend,
                createdAt: date, updatedAt: date, syncStatus: .synced
            )
            context.insert(visit)
            firstVisitByRestaurant[restaurant.id] = firstVisitByRestaurant[restaurant.id] ?? visit.id
        }
        if let originVisit = firstVisitByRestaurant[restaurants[0].id] {
            let dish = Dish(
                id: uuid(4_501), restaurantId: restaurants[0].id, visitId: originVisit,
                name: "炭烤鸡腿葱串", taste: "咸鲜炭香", rating: 4.5, syncStatus: .synced
            )
            context.insert(dish)
            for visitID in try context.fetch(FetchDescriptor<Visit>())
                .filter({ $0.restaurantId == restaurants[0].id }).map(\.id) {
                context.insert(VisitDish(
                    restaurantId: restaurants[0].id, visitId: visitID,
                    dishId: dish.id, syncStatus: .synced
                ))
            }
        }
        if usesCompanionAnalysisFixture {
            let linkedUserID = "tm_p4b_linked_friend"
            companion.linkedTasteMapUserId = linkedUserID
            context.insert(CachedSocialProfile(
                tasteMapUserID: linkedUserID,
                displayName: "小林的公开资料名",
                city: "杭州",
                avatarPreset: .otter
            ))
            context.insert(CachedFriendship(
                relationshipID: "friendship:p4b-ui",
                currentUserID: profileUserID,
                requesterUserID: profileUserID,
                addresseeUserID: linkedUserID,
                state: .friends
            ))
        }
        if usesRecommendationSourceAnalysisFixture {
            try insertRecommendationSourceFixture(into: context)
        }
        try context.save()
    }

    private static func insertRecommendationSourceFixture(into context: ModelContext) throws {
        let plans: [(Int, String, RecommendationSourceType, [Double], Int)] = [
            (4_700, "小林的私藏清单", .friend, [4.5, 5, 4.5, 4, 4.5, 5, 4], 2),
            (4_701, "城市胃口研究所", .blogger, [4, 3.5, 4, 3.5, 4, 3.5, 4], 3),
            (4_702, "深夜刷到的收藏夹", .other, [2, 2.5, 3, 2, 2.5, 3, 2], 0),
        ]
        var item = 0
        for (sourceIndex, plan) in plans.enumerated() {
            let source = RecommendationSource(
                id: uuid(plan.0), ownerUserId: profileUserID, displayName: plan.1,
                sourceType: plan.2, remoteID: "p4c-source-\(sourceIndex)", syncStatus: .synced
            )
            context.insert(source)
            for (ratingIndex, rating) in plan.3.enumerated() {
                item += 1
                let restaurantID = uuid(4_800 + item)
                let date = Calendar.current.date(
                    byAdding: .day, value: -(sourceIndex * 35 + ratingIndex * 7 + 2), to: .now
                ) ?? .now
                let restaurant = Restaurant(
                    id: restaurantID,
                    name: ["野火烧鸟", "青梅小馆", "雨巷火锅", "白露面包房", "木心寿司", "南山牛排", "小满食堂"][ratingIndex]
                        + " · \(sourceIndex + 1)",
                    address: "杭州市西湖区来源路 \(item) 号",
                    latitude: 30.20 + Double(item) * 0.001,
                    longitude: 120.10 + Double(item) * 0.001,
                    appleMapItemIdentifier: "apple-p4c-ui-\(item)",
                    city: "杭州", status: .visited,
                    createdAt: date, updatedAt: date, syncStatus: .synced
                )
                context.insert(restaurant)
                let visit = Visit(
                    id: uuid(5_000 + item * 3), restaurantId: restaurantID,
                    visitedAt: date, rating: rating,
                    valueRating: max(0.5, rating - 0.5),
                    environmentRating: rating,
                    serviceRating: min(5, rating + 0.5),
                    recommendationSourceID: source.remoteID,
                    recommendationSourceType: source.sourceType,
                    recommendationSourceText: source.displayName,
                    createdAt: date, updatedAt: date, syncStatus: .synced
                )
                context.insert(visit)
                if plan.4 > 0 && ratingIndex.isMultiple(of: plan.4) {
                    let repeatDate = Calendar.current.date(byAdding: .day, value: 10, to: date) ?? date
                    context.insert(Visit(
                        id: uuid(5_001 + item * 3), restaurantId: restaurantID,
                        visitedAt: repeatDate, rating: rating,
                        recommendationSourceID: source.remoteID,
                        recommendationSourceType: source.sourceType,
                        recommendationSourceText: source.displayName,
                        createdAt: repeatDate, updatedAt: repeatDate, syncStatus: .synced
                    ))
                }
            }
        }
    }

    private static func restaurantContractData(
        id: UUID,
        name: String,
        tags: [String],
        status: RestaurantStatus = .visited,
        index: Int
    ) throws -> Data {
        let timestamp = "2026-08-28T00:00:00.000Z"
        let identity = try RestaurantPlaceIdentityContract(
            provider: .appleMaps, externalId: "apple-p4a-ui-\(index)", isPrimary: true,
            createdAt: timestamp, updatedAt: timestamp
        )
        let contract = try RestaurantJSONContractV1(
            id: id.uuidString.lowercased(), userId: profileUserID,
            placeIdentities: [identity], name: name,
            address: "杭州市西湖区真实路 \(index + 1) 号", city: "杭州",
            latitude: 30.25, longitude: 120.16,
            status: status == .wantToGo ? .wantToGo : .visited,
            preferenceLevel: .like, overallRating: nil, foodRating: nil,
            environmentRating: nil, serviceRating: nil, valueRating: nil,
            tags: tags, longTermNote: "", pricePerPerson: nil, phone: nil,
            openingHours: nil, markerType: .emoji, markerPhotoId: nil,
            merchantImageUrl: nil, markerEmoji: "🍽️", createdAt: timestamp,
            updatedAt: timestamp, deletedAt: nil, isTestData: true
        )
        return try JSONEncoder().encode(contract)
    }

    private static func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}
#endif
