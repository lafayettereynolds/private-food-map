import Foundation
import SwiftData
import Testing
@testable import TasteMap

@Suite(.serialized)
@MainActor
struct RestaurantRecommendationIntentTests {
    private typealias Policy = RestaurantRecommendationIntentPolicy

    @Test func reliableBrandBoundariesAndExplicitContextsOnly() {
        for name in ["KFC", " ＫＦＣ（杭州店） ", "肯德基 · 西湖店", "肯德基-湖滨店"] {
            #expect(Policy.classify(name: name, tags: []).brandID == "kfc")
        }
        #expect(Policy.classify(name: "McDonald’s (Downtown)", tags: []).brandID == "mcdonalds")
        #expect(Policy.classify(name: "绝味鸭脖（西湖店）", tags: []).context == "snack_takeaway")
        for name in ["肯德基杭州店", "KFCafe", "肯德基旁的家常菜", "老王推荐麦当劳", "特色小吃", "火锅"] {
            let result = Policy.classify(name: name, tags: ["小吃", "快餐", "川菜", "低价"])
            #expect(result.brandID == nil && result.context == nil)
        }
        #expect(Policy.classify(name: "日常饭馆", tags: ["日常快餐"]).context == "everyday_fast_food")
        #expect(Policy.classify(name: "外带店", tags: ["snack_takeaway"]).context == "snack_takeaway")
        #expect(Policy.classify(name: "信息冲突", tags: ["日常快餐", "小吃外带"]).context == nil)
    }

    @Test func brandBlocksOnlyKnownBrandAndContextIsStablePriorityNotFiltering() {
        let feedback = RestaurantRecommendationIntentFeedback(brandIDs: ["kfc"], contextCounts: ["everyday_fast_food": 2])
        #expect(!Policy.permits(name: "肯德基（另一分店）", tags: [], feedback: feedback))
        #expect(Policy.permits(name: "麦当劳（另一分店）", tags: [], feedback: feedback))
        #expect(Policy.permits(name: "特色小吃", tags: ["小吃"], feedback: feedback))
        let names = ["McDonald's (A)", "特色小吃", "火锅", "麦当劳（B）", "绝味鸭脖（C）"]
        let sorted = Policy.stablePriority(names, feedback: feedback) { ($0, []) }
        #expect(sorted == ["特色小吃", "火锅", "绝味鸭脖（C）", "McDonald's (A)", "麦当劳（B）"])
        #expect(sorted.count == names.count)
        #expect(Policy.stablePriority(names, feedback: .init(contextCounts: ["everyday_fast_food": 1])) { ($0, []) } == names)
    }

    @Test func aliasReconciliationDeduplicatesTransitiveHistoricalVotes() {
        let votes: [RestaurantRecommendationIntentVote] = [
            .init(aliases: ["a"], brandID: "kfc", context: "everyday_fast_food"),
            .init(aliases: ["b"], brandID: "kfc", context: "everyday_fast_food"),
            .init(aliases: ["c"], brandID: "mcdonalds", context: "everyday_fast_food")
        ]
        let reconciled = Policy.reconcile(votes, groups: [["a", "provider:1"], ["provider:1", "b"]])
        #expect(reconciled.count == 2)
        #expect(reconciled[0].aliases == ["a", "b", "provider:1"])
        #expect(Policy.feedback(reconciled).contextCounts == ["everyday_fast_food": 2])
    }

    @Test func persistedVotesAreOwnerIsolatedAndAliasesVoteOnlyOnce() throws {
        let suite = "RecommendationIntentTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let metadata: [RestaurantRecommendationIntentMetadata] = [
            .init(aliases: ["local-a", "apple_maps:1"], name: "肯德基（A）", tags: []),
            .init(aliases: ["local-b", "apple_maps:2"], name: "McDonald’s (B)", tags: [])
        ]
        let first = try RestaurantRecommendationPreferences.snapshot(ownerID: "a", context: context, adding: "local-a",
            authorizedSessionMetadata: metadata, defaults: defaults)
        #expect(first.intentFeedback.brandIDs == ["kfc"])
        #expect(first.intentFeedback.contextCounts == ["everyday_fast_food": 1])
        let alias = try RestaurantRecommendationPreferences.snapshot(ownerID: "a", context: context, adding: "APPLE_MAPS:1",
            authorizedSessionMetadata: metadata, defaults: defaults)
        #expect(alias.intentFeedback == first.intentFeedback)
        let second = try RestaurantRecommendationPreferences.snapshot(ownerID: "a", context: context, adding: "local-b",
            authorizedSessionMetadata: metadata, defaults: defaults)
        #expect(second.intentFeedback.brandIDs == ["kfc", "mcdonalds"])
        #expect(second.intentFeedback.contextCounts == ["everyday_fast_food": 2])
        let reopened = try RestaurantRecommendationPreferences.snapshot(ownerID: "a", context: context, defaults: defaults)
        #expect(reopened.intentFeedback == second.intentFeedback)
        let foreign = try RestaurantRecommendationPreferences.snapshot(ownerID: "b", context: context, defaults: defaults)
        #expect(foreign.excludedIDs.isEmpty && foreign.intentFeedback == .init())
    }

    @Test func legacyExclusionsExpandButNeverBackfillLearning() throws {
        let suite = "RecommendationIntentTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["legacy"], forKey: "tastemap.recommendation-exclusions.v1.owner")
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let metadata: [RestaurantRecommendationIntentMetadata] = [.init(aliases: ["legacy", "provider:legacy"], name: "KFC (Legacy)", tags: [])]
        let result = try RestaurantRecommendationPreferences.snapshot(ownerID: "owner", context: ModelContext(container), adding: "provider:legacy",
            authorizedSessionMetadata: metadata, defaults: defaults)
        #expect(result.excludedIDs == ["legacy", "provider:legacy"])
        #expect(result.intentFeedback == .init())
        #expect(defaults.object(forKey: "tastemap.recommendation-intent.v1.owner") == nil)
    }

    @Test func unidentifiedVoteDoesNotLearnLaterAndUnknownIDIsRejected() throws {
        let suite = "RecommendationIntentTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = ModelContext(container)
        _ = try RestaurantRecommendationPreferences.snapshot(ownerID: "owner", context: context, adding: "a",
            authorizedSessionMetadata: [.init(aliases: ["a"], name: "餐厅", tags: [])], defaults: defaults)
        let later = try RestaurantRecommendationPreferences.snapshot(ownerID: "owner", context: context, adding: "provider:a",
            authorizedSessionMetadata: [.init(aliases: ["a", "provider:a"], name: "KFC (A)", tags: [])], defaults: defaults)
        #expect(later.intentFeedback == .init())
        #expect(throws: (any Error).self) {
            try RestaurantRecommendationPreferences.snapshot(ownerID: "owner", context: context, adding: "guessed", defaults: defaults)
        }
    }

    @Test func corruptPreferencesFailClosedWithoutOverwriting() throws {
        let suite = "RecommendationIntentTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = "tastemap.recommendation-intent.v1.owner"
        let invalid = Data("not-json".utf8)
        defaults.set(invalid, forKey: key)
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        #expect(throws: (any Error).self) {
            try RestaurantRecommendationPreferences.snapshot(ownerID: "owner", context: ModelContext(container), adding: "a",
                authorizedSessionMetadata: [.init(aliases: ["a"], name: "KFC", tags: [])], defaults: defaults)
        }
        #expect(defaults.data(forKey: key) == invalid)
        #expect(defaults.object(forKey: "tastemap.recommendation-exclusions.v1.owner") == nil)
    }

#if DEBUG
    @Test func sessionMetadataUsesSameOwnerAndRevocationAuthorityAsCityDetail() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let service = try TasteMapHybridBridgeService(container: container, ownerUserID: "tm_qa")
        let session = TasteMapDiscoveryCitySession()
        _ = try await session.page(ownerUserID: "tm_qa", request: .init(mode: "for_you", city: "上海", windowDays: 7), isCurrent: { true }) { city, cursor in
            try service.debugCitySource(mode: "for_you", city: city, cursor: cursor, windowDays: 7)
        }
        #expect(!session.recommendationIntentMetadata(ownerUserID: "tm_qa").isEmpty)
        #expect(session.recommendationIntentMetadata(ownerUserID: "other").isEmpty)
        _ = try await session.page(ownerUserID: "tm_qa", request: .init(mode: "for_you", city: "上海", windowDays: 7), isCurrent: { true }) { _, _ in
            throw SyncAPIError.server(status: 403, message: "revoked")
        }
        #expect(session.recommendationIntentMetadata(ownerUserID: "tm_qa").isEmpty)
    }
#endif
}
