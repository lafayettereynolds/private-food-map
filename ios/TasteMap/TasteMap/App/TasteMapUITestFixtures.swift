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

    static var usesDiscoveryFixture: Bool {
        ProcessInfo.processInfo.environment[discoveryEnvironmentKey] == "1"
    }

    static var usesDiscoveryOfflineFixture: Bool {
        ProcessInfo.processInfo.environment[discoveryOfflineEnvironmentKey] == "1"
    }

    static var usesProfileFixture: Bool {
        ProcessInfo.processInfo.environment[profileEnvironmentKey] == "1"
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
        guard usesProfileFixture || usesDiscoveryFixture else { return }
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
}
#endif
