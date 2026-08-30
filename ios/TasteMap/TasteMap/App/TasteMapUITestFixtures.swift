#if DEBUG
import CoreLocation
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
    static let monthlyRecapEnvironmentKey = "TASTEMAP_P4D_MONTHLY_UI_TEST"
    static let annualRecapEnvironmentKey = "TASTEMAP_P4E_ANNUAL_UI_TEST"
    static let restaurantListsEnvironmentKey = "TASTEMAP_P4F_LISTS_UI_TEST"
    static let restaurantListsPrivateEnvironmentKey = "TASTEMAP_P4F_LISTS_PRIVATE_UI_TEST"
    static let restaurantRouletteEnvironmentKey = "TASTEMAP_P4G_ROULETTE_UI_TEST"
    static let restaurantRouletteEmptyEnvironmentKey = "TASTEMAP_P4G_ROULETTE_EMPTY_UI_TEST"
    static let restaurantRouletteSingleEnvironmentKey = "TASTEMAP_P4G_ROULETTE_SINGLE_UI_TEST"
    static let restaurantRouletteLargeEnvironmentKey = "TASTEMAP_P4G_ROULETTE_LARGE_UI_TEST"
    static let premiumEnvironmentKey = "TASTEMAP_P4H_PREMIUM_UI_TEST"
    static let settingsEnvironmentKey = "TASTEMAP_F1B3_SETTINGS_UI_TEST"
    static let restaurantAcquisitionEnvironmentKey = "TASTEMAP_RESTAURANT_ACQUISITION_UI_TEST"
    static let restaurantAcquisitionDeniedEnvironmentKey = "TASTEMAP_RESTAURANT_ACQUISITION_DENIED_UI_TEST"
    static let f2ABrowsingEnvironmentKey = "TASTEMAP_F2A_BROWSING_UI_TEST"
    static let f2BFiltersEnvironmentKey = "TASTEMAP_F2B_FILTERS_UI_TEST"
    static let f3ADetailEnvironmentKey = "TASTEMAP_F3A_DETAIL_UI_TEST"
    static let onThisDayEnvironmentKey = "TASTEMAP_F7A_ON_THIS_DAY_UI_TEST"
    static let coreParityInitialTabEnvironmentKey = "TASTEMAP_CORE_PARITY_INITIAL_TAB"

    static var coreParityInitialTab: AppTab? {
        guard let value = ProcessInfo.processInfo.environment[coreParityInitialTabEnvironmentKey]
        else { return nil }
        return AppTab(rawValue: value)
    }

    static var usesOnThisDayFixture: Bool {
        ProcessInfo.processInfo.environment[onThisDayEnvironmentKey] == "1"
    }

    static var onThisDayContextOverride: OnThisDayContext? {
        guard usesOnThisDayFixture else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_Hans_CN")
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let referenceDate = calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 29, hour: 12)
        )!
        return OnThisDayContext(referenceDate: referenceDate, calendar: calendar)
    }

    static var usesF3ADetailFixture: Bool {
        ProcessInfo.processInfo.environment[f3ADetailEnvironmentKey] == "1"
    }

    static var usesF2ABrowsingFixture: Bool {
        ProcessInfo.processInfo.environment[f2ABrowsingEnvironmentKey] == "1"
    }

    static var usesF2BFiltersFixture: Bool {
        ProcessInfo.processInfo.environment[f2BFiltersEnvironmentKey] == "1"
    }

    static var usesRestaurantAcquisitionFixture: Bool {
        ProcessInfo.processInfo.environment[restaurantAcquisitionEnvironmentKey] == "1"
            || ProcessInfo.processInfo.environment[restaurantAcquisitionDeniedEnvironmentKey] == "1"
    }

    static var restaurantAcquisitionDependencies: RestaurantAcquisitionDependencies {
        RestaurantAcquisitionDependencies(
            searchService: RestaurantAcquisitionFixtureSearch(),
            linkResolver: RestaurantAcquisitionFixtureLinkResolver(),
            locationProvider: RestaurantAcquisitionFixtureLocation(
                denied: ProcessInfo.processInfo.environment[restaurantAcquisitionDeniedEnvironmentKey] == "1"
            )
        )
    }

    static var premiumOverride: DevelopmentPremiumOverride? {
        let value = ProcessInfo.processInfo.environment[premiumEnvironmentKey]
        if value == DevelopmentPremiumOverride.free.rawValue { return .free }
        if value == DevelopmentPremiumOverride.premium.rawValue { return .premium }
        // Existing P4 analytics UI fixtures predate entitlement gating and
        // intentionally exercise the complete analysis experience.
        return usesAnalysisFixture || usesDiscoveryFixture ? .premium : nil
    }

    static var usesSettingsFixture: Bool {
        ProcessInfo.processInfo.environment[settingsEnvironmentKey] == "1"
    }

    static var settingsPermissionOverride: SettingsPermissionSnapshot? {
        guard usesSettingsFixture else { return nil }
        return SettingsPermissionSnapshot(location: .denied, photoAddOnly: .limited)
    }

    static var settingsSyncPresentationOverride: SyncPresentation? {
        guard usesSettingsFixture else { return nil }
        return SyncPresentation(
            phase: .pending,
            pendingCount: 2,
            pendingPhotoCount: 1,
            failedPhotoCount: 0,
            conflictCount: 0,
            lastSyncedAt: Date(timeIntervalSince1970: 1_788_000_000)
        )
    }

    private enum RestaurantRouletteFixtureMode {
        case standard
        case empty
        case single
        case large
    }

    static var usesRestaurantRouletteFixture: Bool {
        restaurantRouletteFixtureMode != nil
    }

    private static var restaurantRouletteFixtureMode: RestaurantRouletteFixtureMode? {
        let environment = ProcessInfo.processInfo.environment
        if environment[restaurantRouletteEmptyEnvironmentKey] == "1" { return .empty }
        if environment[restaurantRouletteSingleEnvironmentKey] == "1" { return .single }
        if environment[restaurantRouletteLargeEnvironmentKey] == "1" { return .large }
        if environment[restaurantRouletteEnvironmentKey] == "1" { return .standard }
        return nil
    }

    static var usesRestaurantListsFixture: Bool {
        ProcessInfo.processInfo.environment[restaurantListsEnvironmentKey] == "1"
            || ProcessInfo.processInfo.environment[restaurantListsPrivateEnvironmentKey] == "1"
    }

    static var restaurantListsFixtureIsPrivate: Bool {
        ProcessInfo.processInfo.environment[restaurantListsPrivateEnvironmentKey] == "1"
    }

    static var usesAnalysisFixture: Bool {
        ProcessInfo.processInfo.environment[analysisEnvironmentKey] == "1"
            || usesCompanionAnalysisFixture
            || usesRecommendationSourceAnalysisFixture
            || usesMonthlyRecapFixture
            || usesAnnualRecapFixture
    }

    static var usesCompanionAnalysisFixture: Bool {
        ProcessInfo.processInfo.environment[companionAnalysisEnvironmentKey] == "1"
    }

    static var usesRecommendationSourceAnalysisFixture: Bool {
        ProcessInfo.processInfo.environment[recommendationSourceAnalysisEnvironmentKey] == "1"
    }

    static var usesMonthlyRecapFixture: Bool {
        ProcessInfo.processInfo.environment[monthlyRecapEnvironmentKey] == "1"
    }

    static var usesAnnualRecapFixture: Bool {
        ProcessInfo.processInfo.environment[annualRecapEnvironmentKey] == "1"
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
            || usesSettingsFixture
            || usesAnalysisFixture
            || usesRestaurantListsFixture
            || usesRestaurantRouletteFixture
            || usesF2ABrowsingFixture
            || usesF2BFiltersFixture
            || usesOnThisDayFixture
    }

    static var profileSocialStatisticsOverride: ProfileSocialStatistics? {
        guard usesProfileFixture else { return nil }
        return .init(friendCount: 12, followingCount: 18, followerCount: 9)
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
        container.mainContext.insert(UserProfile(
            tasteMapUserID: "tm_f3a_ui_fixture",
            displayName: "Restaurant Fixture",
            city: "杭州",
            syncStatus: .synced
        ))
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
        let timestamp = SyncRecordMapper.dateString(restaurant.updatedAt)
        restaurant.remoteRecordData = try JSONEncoder().encode(RestaurantJSONContractV1(
            id: restaurant.remoteID ?? restaurant.id.uuidString.lowercased(),
            userId: "tm_f3a_ui_fixture",
            placeIdentities: [try RestaurantPlaceIdentityContract(
                provider: .appleMaps,
                externalId: "apple-ui-test-p1b",
                isPrimary: true,
                createdAt: timestamp,
                updatedAt: timestamp
            )],
            name: restaurant.name,
            address: restaurant.address,
            city: restaurant.city,
            latitude: restaurant.latitude,
            longitude: restaurant.longitude,
            status: .wantToGo,
            preferenceLevel: .normal,
            overallRating: nil,
            foodRating: nil,
            environmentRating: nil,
            serviceRating: nil,
            valueRating: nil,
            tags: ["江浙菜"],
            longTermNote: "适合周末在湖边慢慢吃。",
            pricePerPerson: 168,
            phone: "+86 571-1234-5678",
            openingHours: "周一至周日 11:00–22:00",
            markerType: .emoji,
            markerPhotoId: nil,
            merchantImageUrl: nil,
            markerEmoji: "🍲",
            createdAt: timestamp,
            updatedAt: timestamp,
            deletedAt: nil,
            isTestData: true
        ))
        container.mainContext.insert(restaurant)
        try container.mainContext.save()
    }

    static func preparePersistentOfflineFixture(
        in container: ModelContainer,
        reset: Bool
    ) throws {
        let context = container.mainContext
        if reset {
            for item in try context.fetch(FetchDescriptor<CachedPublicRestaurantListItem>()) {
                context.delete(item)
            }
            for list in try context.fetch(FetchDescriptor<CachedPublicRestaurantList>()) {
                context.delete(list)
            }
            for item in try context.fetch(FetchDescriptor<RestaurantListItem>()) {
                context.delete(item)
            }
            for list in try context.fetch(FetchDescriptor<RestaurantList>()) {
                context.delete(list)
            }
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

        // P4-G owns its isolated Restaurant/Visit set. Avoid inserting the
        // generic P1-D restaurant again when the same offline store relaunches.
        if usesRestaurantRouletteFixture { return }

        let existing = try context.fetch(FetchDescriptor<Restaurant>())
            .first { $0.id == detailRestaurantID }
        guard existing == nil else { return }
        let restaurant = Restaurant(
            id: detailRestaurantID,
            name: "P1-D 离线验收餐厅",
            address: "杭州市上城区湖滨路 18 号",
            latitude: 30.259,
            longitude: 120.168,
            appleMapItemIdentifier: "apple-ui-test-p1d",
            city: "杭州",
            status: .wantToGo,
            syncStatus: .synced
        )
        if BackupImportDevelopmentFixture.current != nil {
            let timestamp = SyncRecordMapper.dateString(restaurant.updatedAt)
            restaurant.remoteRecordData = try JSONEncoder().encode(RestaurantJSONContractV1(
                id: restaurant.remoteID ?? restaurant.id.uuidString.lowercased(),
                userId: profileUserID,
                placeIdentities: [try RestaurantPlaceIdentityContract(
                    provider: .appleMaps,
                    externalId: "apple-ui-test-p1d",
                    isPrimary: true,
                    createdAt: timestamp,
                    updatedAt: timestamp
                )],
                name: restaurant.name,
                address: restaurant.address,
                city: restaurant.city,
                latitude: restaurant.latitude,
                longitude: restaurant.longitude,
                status: .wantToGo,
                preferenceLevel: .normal,
                overallRating: nil,
                foodRating: nil,
                environmentRating: nil,
                serviceRating: nil,
                valueRating: nil,
                tags: [],
                longTermNote: "",
                pricePerPerson: nil,
                phone: nil,
                openingHours: nil,
                markerType: .emoji,
                markerPhotoId: nil,
                merchantImageUrl: nil,
                markerEmoji: "🍽️",
                createdAt: timestamp,
                updatedAt: timestamp,
                deletedAt: nil,
                isTestData: true
            ))
        }
        context.insert(restaurant)
        if usesRestaurantListsFixture {
            for index in 1..<5 {
                context.insert(Restaurant(
                    id: uuid(8_000 + index),
                    name: ["P4-F 青岚寿司", "P4-F 雨巷火锅", "P4-F 野火烧鸟", "P4-F 小满食堂"][index - 1],
                    address: "杭州市西湖区榜单路 \(index) 号",
                    latitude: 30.25 + Double(index) * 0.001,
                    longitude: 120.16 + Double(index) * 0.001,
                    appleMapItemIdentifier: "apple-p4f-ui-\(index)",
                    city: "杭州", status: index.isMultiple(of: 2) ? .wantToGo : .visited,
                    syncStatus: .synced
                ))
            }
        }
        try context.save()
    }

    static func restaurantListPublicSummary(ownerUserID: String = "tm_p3d_friend") -> PublicListSummaryDTO {
        PublicListSummaryDTO(
            id: "p4f-public-ui-list", title: "P4-F 阿岚的杭州小馆",
            description: "适合慢慢吃，也愿意带朋友再来的店。",
            visibility: .public, isRanked: true, coverMode: .automatic,
            customCoverPhotoId: nil, restaurantCount: 3,
            previewRestaurants: [
                .init(globalKey: "apple_maps:p4f-public-1", name: "云边小馆", photoId: nil, merchantImageUrl: nil, markerEmoji: "🍲"),
                .init(globalKey: "apple_maps:p4f-public-2", name: "野火烧鸟", photoId: nil, merchantImageUrl: nil, markerEmoji: "🍢"),
                .init(globalKey: "apple_maps:p4f-public-3", name: "青岚寿司", photoId: nil, merchantImageUrl: nil, markerEmoji: "🍣"),
            ],
            owner: .init(
                userId: ownerUserID, displayName: "常去小馆的阿岚",
                avatarPhotoId: nil, avatarPresetId: .otter
            ),
            updatedAt: "2026-08-28T12:00:00.000Z"
        )
    }

    static func restaurantListPublicPage(ownerUserID: String) throws -> PublicListSummaryPageDTO {
        if restaurantListsFixtureIsPrivate {
            throw SyncAPIError.server(status: 403, message: "List is private")
        }
        let summary = restaurantListPublicSummary(ownerUserID: ownerUserID)
        return .init(apiVersion: 1, items: [summary], nextCursor: nil, generatedAt: summary.updatedAt)
    }

    static func restaurantListPublicDetail() throws -> PublicListDetailDTO {
        if restaurantListsFixtureIsPrivate {
            throw SyncAPIError.server(status: 403, message: "List is private")
        }
        let summary = restaurantListPublicSummary()
        let items = try (0..<3).map { index in
            let globalKey = "apple_maps:p4f-public-\(index + 1)"
            return PublicListItemDTO(
                id: "p4f-public-ui-item-\(index)", position: index,
                note: index == 0 ? "招牌菜值得专程来。" : "",
                restaurant: try RestaurantListPlaceContractV1(
                    globalKey: globalKey, restaurantId: "p4f-public-restaurant-\(index)",
                    placeIdentities: [.init(
                        provider: .appleMaps, externalId: "p4f-public-\(index + 1)", isPrimary: true
                    )],
                    name: ["云边小馆", "野火烧鸟", "青岚寿司"][index],
                    address: "杭州市西湖区公开路 \(index + 1) 号", city: "杭州",
                    latitude: 30.25, longitude: 120.16,
                    markerPhotoId: nil, merchantImageUrl: nil,
                    markerEmoji: ["🍲", "🍢", "🍣"][index]
                )
            )
        }
        return .init(apiVersion: 1, list: summary, items: items, nextCursor: nil, generatedAt: summary.updatedAt)
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

    static func insertOnThisDayFixture(into container: ModelContainer) throws {
        guard usesOnThisDayFixture else { return }
        let context = container.mainContext
        let restaurantID = uuid(14_001)
        let restaurant = Restaurant(
            id: restaurantID,
            name: "那年今日 · 湖畔小馆",
            address: "杭州市西湖区回忆路 29 号",
            latitude: 30.251,
            longitude: 120.165,
            appleMapItemIdentifier: "apple-f7a-ui-memory",
            city: "杭州",
            status: .visited,
            syncStatus: .synced,
            remoteRecordData: try restaurantContractData(
                id: restaurantID,
                name: "那年今日 · 湖畔小馆",
                tags: ["江浙菜", "朋友聚餐"],
                index: 14_001
            )
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let visitedAt = calendar.date(
            from: DateComponents(year: 2025, month: 8, day: 29, hour: 19, minute: 20)
        )!
        let visit = Visit(
            id: uuid(14_002),
            restaurantId: restaurantID,
            visitedAt: visitedAt,
            rating: 4.5,
            note: "去年今天和小林在湖边吃了一顿很舒服的晚饭。",
            myActualSpend: 268,
            companionNames: ["小林"],
            recommendationSourceType: .friend,
            recommendationSourceText: "朋友小林",
            createdAt: visitedAt,
            updatedAt: visitedAt,
            syncStatus: .synced
        )
        let dish = Dish(
            id: uuid(14_003),
            restaurantId: restaurantID,
            visitId: visit.id,
            name: "龙井虾仁",
            sortOrder: 0,
            createdAt: visitedAt,
            updatedAt: visitedAt,
            syncStatus: .synced
        )
        context.insert(restaurant)
        context.insert(visit)
        context.insert(dish)
        context.insert(VisitDish(
            id: uuid(14_004),
            restaurantId: restaurantID,
            visitId: visit.id,
            dishId: dish.id,
            sortOrder: 0,
            createdAt: visitedAt,
            updatedAt: visitedAt,
            syncStatus: .synced
        ))
        try context.save()
    }

    static func insertF2ABrowsingFixture(into container: ModelContainer) throws {
        guard usesF2ABrowsingFixture else { return }
        let context = container.mainContext
        let recentID = uuid(10_001)
        let wantedID = uuid(10_002)
        let deletedID = uuid(10_003)
        let recent = Restaurant(
            id: recentID,
            name: "F2-A 很长但仍需完整可读的江南季节料理餐厅",
            address: "文三路 88 号",
            latitude: 30.27,
            longitude: 120.13,
            city: "杭州",
            status: .visited,
            createdAt: Date(timeIntervalSince1970: 1_778_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_778_000_000),
            syncStatus: .synced
        )
        let wanted = Restaurant(
            id: wantedID,
            name: "F2-A 想吃小馆",
            address: "愚园路 19 号",
            latitude: 31.22,
            longitude: 121.44,
            city: "上海",
            status: .wantToGo,
            createdAt: Date(timeIntervalSince1970: 1_778_100_000),
            updatedAt: Date(timeIntervalSince1970: 1_778_100_000),
            syncStatus: .synced
        )
        let deleted = Restaurant(
            id: deletedID,
            name: "F2-A 已删除餐厅",
            address: "不会显示",
            latitude: 30.20,
            longitude: 120.10,
            city: "杭州",
            status: .visited,
            deletedAt: Date(timeIntervalSince1970: 1_778_300_000),
            syncStatus: .synced
        )
        context.insert(recent)
        context.insert(wanted)
        context.insert(deleted)

        let firstVisit = Visit(
            id: uuid(10_101),
            restaurantId: recentID,
            visitedAt: Date(timeIntervalSince1970: 1_778_200_000),
            rating: 4.5,
            note: "F2-A 第一条真实足迹，菜品轻盈，适合慢慢吃。",
            companionNames: ["小林"],
            recommendationSourceType: .friend,
            syncStatus: .synced
        )
        let nilRatingVisit = Visit(
            id: uuid(10_102),
            restaurantId: recentID,
            visitedAt: Date(timeIntervalSince1970: 1_778_250_000),
            rating: nil,
            note: "F2-A 未评分足迹",
            syncStatus: .synced
        )
        let deletedVisit = Visit(
            id: uuid(10_103),
            restaurantId: recentID,
            visitedAt: Date(timeIntervalSince1970: 1_778_260_000),
            rating: 2,
            deletedAt: Date(timeIntervalSince1970: 1_778_270_000),
            syncStatus: .synced
        )
        let orphanedByRestaurant = Visit(
            id: uuid(10_104),
            restaurantId: deletedID,
            visitedAt: Date(timeIntervalSince1970: 1_778_280_000),
            rating: 5,
            syncStatus: .synced
        )
        context.insert(firstVisit)
        context.insert(nilRatingVisit)
        context.insert(deletedVisit)
        context.insert(orphanedByRestaurant)

        let dish = Dish(
            id: uuid(10_201),
            restaurantId: recentID,
            visitId: firstVisit.id,
            name: "炭烤时蔬",
            rating: 4.5,
            syncStatus: .synced
        )
        context.insert(dish)
        context.insert(VisitDish(
            id: uuid(10_202),
            restaurantId: recentID,
            visitId: firstVisit.id,
            dishId: dish.id,
            syncStatus: .synced
        ))
        try context.save()
    }

    static func insertF2BFiltersFixture(into container: ModelContainer) throws {
        guard usesF2BFiltersFixture else { return }
        let context = container.mainContext
        let matching = Restaurant(
            id: uuid(11_001),
            name: "F2-B 命中外卖餐厅",
            address: "西湖区筛选路 1 号",
            latitude: 30.2741,
            longitude: 120.1551,
            city: "杭州",
            status: .visited,
            createdAt: .now.addingTimeInterval(-86_400 * 30),
            syncStatus: .synced
        )
        let excluded = Restaurant(
            id: uuid(11_002),
            name: "F2-B 排除到店餐厅",
            address: "静安区筛选路 2 号",
            latitude: 31.2304,
            longitude: 121.4737,
            city: "上海",
            status: .visited,
            createdAt: .now.addingTimeInterval(-86_400 * 20),
            syncStatus: .synced
        )
        context.insert(matching)
        context.insert(excluded)
        context.insert(Visit(
            id: uuid(11_101),
            restaurantId: matching.id,
            visitedAt: .now.addingTimeInterval(-86_400 * 10),
            rating: 4.5,
            pricePerPerson: 150,
            diningMode: .takeout,
            queueDuration: .noWait,
            diningOccasions: [.friends],
            companionNames: ["小林"],
            recommendationSourceType: .friend,
            syncStatus: .synced
        ))
        context.insert(Visit(
            id: uuid(11_102),
            restaurantId: matching.id,
            visitedAt: .now.addingTimeInterval(-86_400 * 15),
            rating: 4.5,
            diningMode: .takeout,
            syncStatus: .synced
        ))
        context.insert(Visit(
            id: uuid(11_103),
            restaurantId: excluded.id,
            visitedAt: .now.addingTimeInterval(-86_400 * 5),
            rating: 3,
            pricePerPerson: 80,
            diningMode: .dineIn,
            queueDuration: nil,
            diningOccasions: [.business],
            companionNames: ["阿宁"],
            recommendationSourceType: .dianping,
            syncStatus: .synced
        ))
        try context.save()
    }

    static func insertRestaurantRouletteFixture(into container: ModelContainer) throws {
        guard let mode = restaurantRouletteFixtureMode else { return }
        let context = container.mainContext

        let fixtureIDs = Set((9_000...9_130).map(uuid))
        if mode != .empty,
           try context.fetch(FetchDescriptor<Restaurant>()).contains(where: {
               fixtureIDs.contains($0.id)
           }) {
            return
        }

        for visit in try context.fetch(FetchDescriptor<Visit>()) {
            context.delete(visit)
        }
        for photo in try context.fetch(FetchDescriptor<PhotoAsset>()) {
            context.delete(photo)
        }
        for restaurant in try context.fetch(FetchDescriptor<Restaurant>()) {
            context.delete(restaurant)
        }
        try context.save()

        let count: Int
        switch mode {
        case .empty: count = 0
        case .single: count = 1
        case .standard: count = 8
        case .large: count = 120
        }

        let names = [
            "青岚寿司", "雨巷火锅", "野火烧鸟", "小满食堂",
            "云边面馆", "桂雨咖啡", "春日泰味", "湖畔西餐",
        ]
        for index in 0..<count {
            let id = uuid(9_000 + index)
            let status: RestaurantStatus = index.isMultiple(of: 2) ? .wantToGo : .visited
            let name = count > names.count
                ? "候选餐厅 \(index + 1)"
                : names[index % names.count]
            let restaurant = Restaurant(
                id: id,
                name: name,
                address: "杭州市西湖区转盘路 \(index + 1) 号",
                latitude: 30.20 + Double(index % 50) * 0.001,
                longitude: 120.10 + Double(index % 50) * 0.001,
                appleMapItemIdentifier: "apple-p4g-ui-\(index)",
                city: "杭州",
                status: status,
                createdAt: Date(timeIntervalSince1970: 1_777_500_000 + Double(index)),
                updatedAt: Date(timeIntervalSince1970: 1_777_500_000 + Double(index)),
                syncStatus: .synced,
                remoteRecordData: try restaurantContractData(
                    id: id,
                    name: name,
                    tags: index.isMultiple(of: 3) ? ["日料", "朋友聚餐"] : ["本地小馆"],
                    status: status,
                    index: 200 + index
                )
            )
            context.insert(restaurant)
            if status == .visited {
                context.insert(Visit(
                    id: uuid(9_500 + index),
                    restaurantId: id,
                    visitedAt: Date(timeIntervalSince1970: 1_777_600_000 + Double(index)),
                    rating: 3.5 + Double(index % 4) * 0.5,
                    note: "P4-G 本地轮盘验收记录",
                    createdAt: Date(timeIntervalSince1970: 1_777_600_000 + Double(index)),
                    updatedAt: Date(timeIntervalSince1970: 1_777_600_000 + Double(index)),
                    syncStatus: .synced
                ))
            }
        }
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
                reasons: [
                    reason,
                    .init(code: "COMMUNITY_QUALITY", text: "当前城市的公开评分样本稳定"),
                ], sourceUser: mode == .trending ? nil : source,
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
            let photos: [PublicContentPhotoV1] = index == 0
                ? (0..<3).map {
                    .init(
                        photoId: String(format: "00000000-0000-4000-8000-%012d", 7_000 + $0),
                        variant: .thumbnail
                    )
                }
                : []
            let visit = PublicVisitV1(
                id: "visit-p3d-ui-\(index)", ownerUserId: user.userId,
                restaurantGlobalKey: restaurant.globalKey, visitedAt: eventAt,
                rating: index == 1 ? nil : 4.5,
                note: index == 2
                    ? "这是一段用于验证较长内容的真实到访备注。菜的火候很稳，朋友们都愿意下次再来；即使文字变长，卡片也应该保持清楚、自然，并且不能泄露消费、饭搭子或推荐来源。"
                    : "热气腾腾，味道很稳，适合和朋友慢慢吃。",
                visibility: user.friendshipState == .friends ? .friends : .public,
                photos: photos, updatedAt: eventAt
            )
            return PublicContentItemV1(
                id: index == 1 ? "want:place:p3d-ui-1" : "visit:\(visit.id)",
                kind: index == 1 ? .wantToGo : .visit,
                eventAt: eventAt, updatedAt: eventAt,
                user: user, restaurant: restaurant, visit: index == 1 ? nil : visit,
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
        if usesMonthlyRecapFixture {
            try insertMonthlyRecapFixture(
                into: context,
                companion: companion,
                secondCompanion: secondCompanion,
                source: source
            )
        }
        if usesAnnualRecapFixture {
            try insertAnnualRecapFixture(
                into: context, companion: companion,
                secondCompanion: secondCompanion
            )
        }
        try context.save()
    }

    private static func insertAnnualRecapFixture(
        into context: ModelContext,
        companion: DiningCompanion,
        secondCompanion: DiningCompanion
    ) throws {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: .now)
        let previousYear = currentYear - 1
        let sourceDefinitions: [(UUID, String, RecommendationSourceType, [Double])] = [
            (uuid(7_001), "年度朋友私藏", .friend, [4.5, 5, 4.5, 4, 4.5, 5]),
            (uuid(7_002), "年度踩坑收藏夹", .other, [2, 2.5, 2, 3, 2.5, 2]),
        ]
        var item = 0
        for (sourceIndex, definition) in sourceDefinitions.enumerated() {
            let source = RecommendationSource(
                id: definition.0, ownerUserId: profileUserID,
                displayName: definition.1, sourceType: definition.2,
                remoteID: "p4e-source-\(sourceIndex)", syncStatus: .synced
            )
            context.insert(source)
            for (ratingIndex, rating) in definition.3.enumerated() {
                item += 1
                let restaurantID = uuid(7_100 + item)
                let month = 1 + ((sourceIndex * 6 + ratingIndex) % max(1, calendar.component(.month, from: .now)))
                let date = calendar.date(from: DateComponents(
                    year: currentYear, month: month, day: 4 + ratingIndex * 3, hour: 19
                )) ?? .now
                let tags = sourceIndex == 0
                    ? (month <= 6 ? ["日料", "寿司"] : ["火锅", "朋友聚餐"])
                    : (month <= 6 ? ["咖啡", "甜点"] : ["西餐", "约会"])
                let name = sourceIndex == 0 ? "P4-E 年度高光店 \(ratingIndex + 1)" : "P4-E 年度踩坑店 \(ratingIndex + 1)"
                let restaurant = Restaurant(
                    id: restaurantID, name: name,
                    address: "杭州市年度路 \(item) 号",
                    latitude: 30.18 + Double(item) * 0.001,
                    longitude: 120.08 + Double(item) * 0.001,
                    appleMapItemIdentifier: "apple-p4e-ui-\(item)", city: "杭州",
                    status: .visited, createdAt: date, updatedAt: date,
                    syncStatus: .synced,
                    remoteRecordData: try restaurantContractData(
                        id: restaurantID, name: name, tags: tags,
                        status: .visited, index: 100 + item
                    )
                )
                context.insert(restaurant)
                context.insert(Visit(
                    id: uuid(7_300 + item), restaurantId: restaurantID,
                    visitedAt: min(date, .now), rating: rating,
                    myActualSpend: item.isMultiple(of: 5) ? nil : Decimal(120 + item * 14),
                    diningOccasions: [item.isMultiple(of: 2) ? .friends : .solo],
                    companionIDs: [companion.remoteID ?? companion.id.uuidString.lowercased()]
                        + (item.isMultiple(of: 4) ? [secondCompanion.remoteID ?? secondCompanion.id.uuidString.lowercased()] : []),
                    companionNames: [companion.displayName]
                        + (item.isMultiple(of: 4) ? [secondCompanion.displayName] : []),
                    recommendationSourceID: source.remoteID,
                    recommendationSourceType: source.sourceType,
                    recommendationSourceText: source.displayName,
                    createdAt: min(date, .now), updatedAt: min(date, .now),
                    syncStatus: .synced
                ))
            }
        }
        for index in 0..<8 {
            let restaurantID = uuid(7_500 + (index % 4))
            if index < 4 {
                let restaurant = Restaurant(
                    id: restaurantID, name: "P4-E 去年餐厅 \(index + 1)",
                    address: "杭州市往年路 \(index + 1) 号",
                    latitude: 30.30 + Double(index) * 0.001,
                    longitude: 120.20 + Double(index) * 0.001,
                    appleMapItemIdentifier: "apple-p4e-past-\(index)", city: "杭州",
                    status: .visited, syncStatus: .synced,
                    remoteRecordData: try restaurantContractData(
                        id: restaurantID, name: "P4-E 去年餐厅 \(index + 1)",
                        tags: index.isMultiple(of: 2) ? ["火锅"] : ["日料"],
                        status: .visited, index: 140 + index
                    )
                )
                context.insert(restaurant)
            }
            let date = calendar.date(from: DateComponents(
                year: previousYear, month: 1 + index, day: 8, hour: 18
            )) ?? .now
            context.insert(Visit(
                id: uuid(7_600 + index), restaurantId: restaurantID,
                visitedAt: date, rating: 4 + Double(index % 2) * 0.5,
                myActualSpend: Decimal(136 + index * 18),
                companionIDs: [secondCompanion.remoteID ?? secondCompanion.id.uuidString.lowercased()],
                companionNames: [secondCompanion.displayName],
                createdAt: date, updatedAt: date, syncStatus: .synced
            ))
        }
    }

    static func addAnnualRecapFixtureVisit(in context: ModelContext) throws {
        guard usesAnnualRecapFixture else { return }
        let visitID = uuid(7_999)
        guard try context.fetch(FetchDescriptor<Visit>()).allSatisfy({ $0.id != visitID }) else { return }
        guard let restaurant = try context.fetch(FetchDescriptor<Restaurant>())
            .first(where: { $0.id == uuid(7_101) }) else { return }
        context.insert(Visit(
            id: visitID, restaurantId: restaurant.id, visitedAt: .now,
            rating: 4.5, note: "P4-E UI 新增年度到访", myActualSpend: 188,
            createdAt: .now, updatedAt: .now, syncStatus: .pending
        ))
        try context.save()
    }

    private static func insertMonthlyRecapFixture(
        into context: ModelContext,
        companion: DiningCompanion,
        secondCompanion: DiningCompanion,
        source: RecommendationSource
    ) throws {
        let calendar = Calendar.current
        let currentStart = calendar.date(from: calendar.dateComponents([.year, .month], from: .now)) ?? .now
        let previousStart = calendar.date(byAdding: .month, value: -1, to: currentStart) ?? currentStart
        let restaurantDefinitions: [(UUID, String, [String])] = [
            (uuid(6_000), "P4-D 月度寿司屋", ["日料", "寿司"]),
            (uuid(6_001), "P4-D 熟客火锅", ["火锅", "朋友聚餐"]),
            (uuid(6_002), "P4-D 新店咖啡", ["咖啡", "甜点"]),
        ]
        var restaurants: [Restaurant] = []
        for (index, definition) in restaurantDefinitions.enumerated() {
            let restaurant = Restaurant(
                id: definition.0, name: definition.1,
                address: "杭州市西湖区月度路 \(index + 1) 号",
                latitude: 30.24 + Double(index) * 0.001,
                longitude: 120.15 + Double(index) * 0.001,
                appleMapItemIdentifier: "apple-p4d-ui-\(index)", city: "杭州",
                status: .visited,
                createdAt: index == 2 ? currentStart : previousStart,
                updatedAt: .now, syncStatus: .synced,
                remoteRecordData: try restaurantContractData(
                    id: definition.0, name: definition.1, tags: definition.2,
                    status: .visited, index: 70 + index
                )
            )
            context.insert(restaurant)
            restaurants.append(restaurant)
        }

        let previousPlan = [0, 1, 0, 1, 1]
        for (index, restaurantIndex) in previousPlan.enumerated() {
            let date = calendar.date(byAdding: .day, value: 2 + index * 4, to: previousStart) ?? previousStart
            context.insert(Visit(
                id: uuid(6_100 + index), restaurantId: restaurants[restaurantIndex].id,
                visitedAt: date, rating: [4.0, 3.5, 4.0, 4.0, 4.5][index],
                myActualSpend: Decimal(120 + index * 18),
                companionIDs: [secondCompanion.remoteID ?? secondCompanion.id.uuidString.lowercased()],
                companionNames: [secondCompanion.displayName],
                recommendationSourceID: source.remoteID,
                recommendationSourceType: source.sourceType,
                recommendationSourceText: source.displayName,
                createdAt: date, updatedAt: date, syncStatus: .synced
            ))
        }

        let currentPlan = [0, 0, 1, 2, 0, 1, 2, 2]
        for (index, restaurantIndex) in currentPlan.enumerated() {
            let date = min(
                calendar.date(byAdding: .day, value: 1 + index * 3, to: currentStart) ?? currentStart,
                .now
            )
            context.insert(Visit(
                id: uuid(6_120 + index), restaurantId: restaurants[restaurantIndex].id,
                visitedAt: date, rating: [4.5, 5, 4, 4.5, 4.5, 4, 4.5, 5][index],
                note: index.isMultiple(of: 3) ? "P4-D 月度高光记录" : nil,
                myActualSpend: index == 7 ? nil : Decimal(168 + index * 16),
                diningOccasions: [index.isMultiple(of: 2) ? .friends : .solo],
                companionIDs: [companion.remoteID ?? companion.id.uuidString.lowercased()]
                    + (index.isMultiple(of: 4) ? [secondCompanion.remoteID ?? secondCompanion.id.uuidString.lowercased()] : []),
                companionNames: [companion.displayName]
                    + (index.isMultiple(of: 4) ? [secondCompanion.displayName] : []),
                recommendationSourceID: source.remoteID,
                recommendationSourceType: source.sourceType,
                recommendationSourceText: source.displayName,
                createdAt: date, updatedAt: date, syncStatus: .synced
            ))
        }
    }

    static func addMonthlyRecapFixtureVisit(in context: ModelContext) throws {
        guard usesMonthlyRecapFixture else { return }
        let visitID = uuid(6_199)
        guard try context.fetch(FetchDescriptor<Visit>()).allSatisfy({ $0.id != visitID }) else { return }
        let restaurantID = uuid(6_000)
        context.insert(Visit(
            id: visitID, restaurantId: restaurantID, visitedAt: .now,
            rating: 4.5, note: "P4-D UI 新增到访",
            myActualSpend: 198, createdAt: .now, updatedAt: .now,
            syncStatus: .pending
        ))
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

private struct RestaurantAcquisitionFixtureSearch: RestaurantSearching {
    func search(query: String) async throws -> [RestaurantCandidate] {
        try await search(query: query, scope: RestaurantSearchScope())
    }

    func search(query: String, scope: RestaurantSearchScope) async throws -> [RestaurantCandidate] {
        guard !query.localizedCaseInsensitiveContains("没有结果") else { return [] }
        let city = scope.city.isEmpty ? "杭州" : scope.city
        return [RestaurantCandidate(
            id: UUID(uuidString: "ac000002-0000-0000-0000-000000000002")!,
            name: "\(city) · \(query)",
            address: "\(city)测试路 28 号",
            city: city,
            district: "测试区",
            latitude: city == "上海" ? 31.2304 : 30.2741,
            longitude: city == "上海" ? 121.4737 : 120.1551,
            appleMapItemIdentifier: "apple-acquisition-search-\(city)"
        )]
    }

    func nearby(center: RestaurantCoordinate, radiusMeters: Double) async throws -> [RestaurantCandidate] {
        [RestaurantCandidate(
            id: UUID(uuidString: "ac000001-0000-0000-0000-000000000001")!,
            name: "V1 附近小馆",
            address: "杭州市西湖区附近路 3 号",
            city: "杭州",
            district: "西湖区",
            latitude: center.latitude + 0.001,
            longitude: center.longitude + 0.001,
            appleMapItemIdentifier: "apple-acquisition-nearby",
            distanceMeters: 146
        )]
    }

    func locationContext(for coordinate: RestaurantCoordinate) async throws -> RestaurantLocationContext {
        RestaurantLocationContext(city: "杭州", district: "西湖区", address: "杭州 · 西湖区 · 测试位置")
    }

    func coordinate(for address: String, city: String) async throws -> RestaurantCoordinate {
        RestaurantCoordinate(latitude: 30.281, longitude: 120.139)
    }
}

@MainActor
private struct RestaurantAcquisitionFixtureLinkResolver: ExternalRestaurantLinkResolving {
    func resolve(text: String, currentCity: String) async throws -> ExternalRestaurantLinkResponseV1 {
        let isAmap = text.localizedCaseInsensitiveContains("amap")
        let provider: RestaurantPlaceProvider = isAmap ? .amap : .appleMaps
        return ExternalRestaurantLinkResponseV1(
            apiVersion: 1,
            sourceType: isAmap ? .amap : .appleMaps,
            sourceHost: isAmap ? "uri.amap.com" : "maps.apple.com",
            confidence: .high,
            matchType: "single",
            candidates: [ExternalRestaurantCandidateV1(
                restaurantId: nil,
                amapPoiId: isAmap ? "B0ACQUISITION" : nil,
                name: isAmap ? "V1 高德链接餐厅" : "V1 Apple 链接餐厅",
                address: "杭州市上城区链接路 8 号",
                city: currentCity.isEmpty ? "杭州" : currentCity,
                latitude: 30.262,
                longitude: 120.171,
                merchantImageUrl: nil,
                phone: nil,
                openingHours: nil,
                placeIdentities: [.init(
                    provider: provider,
                    externalId: isAmap ? "B0ACQUISITION" : "apple-acquisition-link",
                    isPrimary: true
                )]
            )],
            searchFallback: nil,
            sourceSuggestion: isAmap ? "高德地图" : "Apple 地图",
            message: "已识别餐厅，请确认后继续。"
        )
    }
}

@MainActor
private final class RestaurantAcquisitionFixtureLocation: RestaurantLocationProviding {
    let authorizationStatus: CLAuthorizationStatus
    let accuracyAuthorization: CLAccuracyAuthorization = .fullAccuracy
    private let denied: Bool

    init(denied: Bool) {
        self.denied = denied
        authorizationStatus = denied ? .denied : .authorizedWhenInUse
    }

    func requestCurrentLocation() async throws -> CLLocation {
        if denied { throw RestaurantLocationError.permissionDenied }
        return CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 30.2741, longitude: 120.1551),
            altitude: 0,
            horizontalAccuracy: 8,
            verticalAccuracy: 10,
            timestamp: Date()
        )
    }
}
#endif
