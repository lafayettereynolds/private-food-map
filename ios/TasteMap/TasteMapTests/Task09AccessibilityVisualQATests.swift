import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import TasteMap

@Suite("Task 09 accessibility, locale, and Visual QA")
struct Task09AccessibilityVisualQATests {
    @Test("Chinese display dates are centralized without changing storage")
    func displayDateUsesChineseLocale() {
        let date = Date(timeIntervalSince1970: 1_788_105_600)
        let dateTime = TasteMapDisplayDate.abbreviatedDateTime(date)
        let dateOnly = TasteMapDisplayDate.abbreviatedDate(date)
        #expect(TasteMapDisplayDate.localeIdentifier == "zh_Hans_CN")
        #expect(!dateTime.localizedCaseInsensitiveContains("Aug"))
        #expect(!dateOnly.localizedCaseInsensitiveContains("September"))
        #expect(dateTime.contains("月"))
        #expect(dateOnly.contains("月"))
        #expect(TasteMapDisplayDate.yearMonth(date).contains("年"))
        #expect(TasteMapDisplayDate.monthDay(date).contains("月"))
    }

    @Test("Primary tabs preserve equal-width product layout until accessibility sizes")
    func primaryTabLayoutAdaptsAtAccessibilitySizes() {
        #expect(TasteMapPrimaryTabLayout.resolve(.large) == .equalWidth)
        #expect(TasteMapPrimaryTabLayout.resolve(.xxxLarge) == .equalWidth)
        #expect(TasteMapPrimaryTabLayout.resolve(.accessibility1) == .horizontallyScrollable)
        #expect(TasteMapPrimaryTabLayout.resolve(.accessibility5) == .horizontallyScrollable)
    }

    @Test("Visual QA runtime is isolated, offline, and never starts automatic services")
    func visualQARuntimeIsolation() {
        let runtime = TasteMapRuntimeConfiguration.resolve(
            environment: [TasteMapRuntimeConfiguration.visualQAEnvironmentKey: "rich"],
            arguments: []
        )
        #expect(runtime.tier == .visualQA)
        #expect(runtime.isolatesPersistentState)
        #expect(!runtime.allowsNetwork)
        #expect(!runtime.allowsAutomaticServices)
    }

    @Test("Rich demo has the locked deterministic acceptance scale")
    @MainActor
    func richDemoScale() {
        let counts = TasteMapVisualQAFixtures.counts(for: .rich)
        #expect(counts.visitedRestaurants == 90)
        #expect(counts.wantToGoRestaurants == 25)
        #expect(counts.visits == 275)
        #expect(counts.photos == 60)
        #expect(counts.dishes == 130)
        #expect(counts.companions == 10)
        #expect(counts.recommendationSources == 12)
        #expect(counts.lists == 7)
        #expect(TasteMapVisualQAMode.allCases.contains(.free))
        #expect(TasteMapVisualQAMode.allCases.contains(.missingPhoto))
        #expect(TasteMapVisualQAMode.allCases.contains(.longText))
    }

    @Test("Rich demo uses natural dense overlap instead of a separated marker wall")
    @MainActor
    func richDemoMapOverlap() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        try TasteMapVisualQAFixtures.insert(mode: .rich, into: container)
        let restaurants = try container.mainContext.fetch(FetchDescriptor<Restaurant>())
        let visited = restaurants.filter { $0.deletedAt == nil && $0.status == .visited }
        let snapshot = RestaurantBrowseBuilder.build(restaurants: visited, visits: [])
        let markers = RestaurantMapMarkerBuilder.build(
            items: snapshot.visited,
            photos: [],
            segment: .visited
        )
        let coordinateKeys = markers.map { "\($0.latitude):\($0.longitude)" }

        #expect(markers.count == 90)
        #expect(Set(coordinateKeys).count < markers.count)
        #expect(Dictionary(grouping: coordinateKeys, by: { $0 }).values.contains { $0.count > 1 })
    }

    @Test("Rich demo uses one real social graph for Profile, following list, and Discovery authors")
    @MainActor
    func richDemoSocialGraphConsistency() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        context.insert(UserProfile(
            tasteMapUserID: TasteMapVisualQAFixtures.userID,
            displayName: "Lafayette · 丰富美食档案",
            city: "杭州",
            avatarPreset: .polarBear,
            visibility: .public,
            syncStatus: .synced
        ))
        try TasteMapVisualQAFixtures.insert(mode: .rich, into: container)

        let expected = TasteMapVisualQAFixtures.socialStatistics
        let statistics = ProfileSocialStatisticsLoader.cached(
            context: context,
            currentUserID: TasteMapVisualQAFixtures.userID
        )
        let service = try TasteMapHybridBridgeService(
            container: container,
            ownerUserID: TasteMapVisualQAFixtures.userID
        )
        let dashboard = try service.profileDashboard()
        let store = LocalSocialStore(context: context)
        let followedIDs = Set(try store.cachedFollows(currentUserID: TasteMapVisualQAFixtures.userID)
            .filter { $0.deletedAt == nil && $0.followerUserID == TasteMapVisualQAFixtures.userID }
            .map(\.followedUserID))
        let followedProfiles = Set(try store.cachedProfiles()
            .filter { followedIDs.contains($0.tasteMapUserID) }
            .map(\.displayName))

        #expect(statistics == expected)
        #expect(dashboard.followingCount == expected.followingCount)
        #expect(dashboard.followerCount == expected.followerCount)
        #expect(followedIDs == Set(TasteMapVisualQAFixtures.socialFollowingUsers.map(\.userId)))
        #expect(followedProfiles == Set(["林夏", "陈一碗", "阿岚", "陆小满"]))
    }
}
