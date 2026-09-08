import Foundation
import Testing
@testable import TasteMap

@Suite("Recommendation preference append-only sync", .serialized)
@MainActor
struct RecommendationPreferenceSyncTests {
    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "tastemap.preference-sync-test.\(UUID().uuidString)")!
    }
    private func vote(_ aliases: Set<String>, context: String? = "everyday_fast_food") -> RestaurantRecommendationIntentVote {
        .init(aliases: aliases, brandID: nil, context: context)
    }
    private func remote(_ id: String, aliases: [String], context: String?) -> RecommendationPreferenceEvent {
        .init(eventID: id, aliases: aliases.sorted(), source: "legacy_intent", occurredAt: nil,
              intent: .init(classifierVersion: 1, brandID: nil, context: context))
    }

    @Test func localQueueSurvivesUnavailableServerAndRetriesSameIDsWithoutReplacingUnsentEvents() async throws {
        let defaults = isolatedDefaults()
        let owner = "tm_one"
        try RecommendationPreferenceLedger.capture(owner: owner, excluded: ["place:a"], votes: [vote(["place:a"])],
            explicitAliases: ["place:a"], defaults: defaults)
        let first = try RecommendationPreferenceLedger.load(owner: owner, defaults: defaults)
        #expect(first.pending.count == 1 && first.events.first?.source == "explicit_dismissal")
        let api = PreferenceAPIFake(owner: owner)
        api.fail = true
        await RecommendationPreferenceSync(api: api, defaults: defaults).synchronize(owner: owner, isCurrent: { true })
        #expect(try RecommendationPreferenceLedger.load(owner: owner, defaults: defaults).pending == first.pending)
        api.fail = false
        api.onPush = {
            try RecommendationPreferenceLedger.capture(owner: owner, excluded: ["place:a", "place:b"],
                votes: [vote(["place:a"]), vote(["place:b"])], explicitAliases: ["place:b"], defaults: defaults)
        }
        await RecommendationPreferenceSync(api: api, defaults: defaults).synchronize(owner: owner, isCurrent: { true })
        let merged = try RecommendationPreferenceLedger.load(owner: owner, defaults: defaults)
        #expect(merged.pending.isEmpty && merged.events.count == 2)
        #expect(api.sent.first?.first?.eventID == first.events.first?.eventID)
        #expect(api.sent.count == 2)
        #expect(merged.cursor == "owner-cursor")
    }

    @Test func pullUnionIsOwnerBoundAndDuplicateAliasesDoNotCastAnotherIntentVote() throws {
        let defaults = isolatedDefaults()
        try RecommendationPreferenceLedger.capture(owner: "tm_one", excluded: ["local:a", "place:b"],
            votes: [vote(["local:a"])], defaults: defaults)
        let event = remote("remote-a", aliases: ["local:a", "global:a"], context: "everyday_fast_food")
        let pull = RecommendationPreferencePull(apiVersion: 1, ownerID: "tm_one", events: [event], cursor: "c1", hasMore: false)
        try RecommendationPreferenceLedger.merge(pull, owner: "tm_one", defaults: defaults)
        try RecommendationPreferenceLedger.merge(pull, owner: "tm_one", defaults: defaults)
        let value = try RecommendationPreferenceLedger.values(owner: "tm_one", defaults: defaults)
        #expect(value.excluded == ["local:a", "global:a", "place:b"])
        #expect(value.votes.count == 1)
        #expect(value.votes.first?.aliases == ["local:a", "global:a"])
        #expect(try RecommendationPreferenceLedger.values(owner: "tm_two", defaults: defaults).excluded.isEmpty)
        #expect(throws: (any Error).self) { try RecommendationPreferenceLedger.merge(pull, owner: "tm_two", defaults: defaults) }
        // Separate old exclusion IDs are not made aliases of one restaurant.
        let state = try RecommendationPreferenceLedger.load(owner: "tm_one", defaults: defaults)
        #expect(state.events.first { $0.aliases.contains("place:b") }?.aliases == ["place:b"])
        #expect(state.events.first { $0.aliases.contains("place:b") }?.intent == nil)
    }

    @Test func accountSwitchDiscardsResponseAndWrongOwnerAcknowledgmentNeverClearsPending() async throws {
        let defaults = isolatedDefaults()
        try RecommendationPreferenceLedger.capture(owner: "tm_one", excluded: ["place:a"], votes: [], defaults: defaults)
        let api = PreferenceAPIFake(owner: "tm_one")
        var current = true
        api.onPull = { current = false }
        await RecommendationPreferenceSync(api: api, defaults: defaults).synchronize(owner: "tm_one", isCurrent: { current })
        let state = try RecommendationPreferenceLedger.load(owner: "tm_one", defaults: defaults)
        #expect(state.cursor == nil && state.pending.count == 1 && api.sent.isEmpty)
        let ack = RecommendationPreferencePush(apiVersion: 1, ownerID: "tm_other", receipts: [.init(eventID: state.events[0].eventID, revision: 1)])
        #expect(throws: (any Error).self) {
            try RecommendationPreferenceLedger.acknowledge(ack, sent: state.events, owner: "tm_one", defaults: defaults)
        }
        #expect(try RecommendationPreferenceLedger.load(owner: "tm_one", defaults: defaults).pending == state.pending)
    }

    @Test func conflictingClassificationsSuppressLearningAndLegacyPayloadUsesExplicitNulls() throws {
        let defaults = isolatedDefaults()
        try RecommendationPreferenceLedger.merge(.init(apiVersion: 1, ownerID: "tm_one", events: [
            remote("one", aliases: ["a"], context: "everyday_fast_food"),
            remote("two", aliases: ["a", "b"], context: "snack_takeaway")
        ], cursor: "c1", hasMore: false), owner: "tm_one", defaults: defaults)
        let values = try RecommendationPreferenceLedger.values(owner: "tm_one", defaults: defaults)
        #expect(values.votes.count == 1 && values.votes[0].context == nil)
        let event = RecommendationPreferenceEvent(eventID: "old", aliases: ["local:old"], source: "legacy_exclusion", occurredAt: nil, intent: nil)
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(event)) as? [String: Any])
        #expect(json["occurredAt"] is NSNull && json["intent"] is NSNull)
    }
}

@MainActor
private final class PreferenceAPIFake: RecommendationPreferenceAPI {
    let owner: String
    var fail = false
    var sent: [[RecommendationPreferenceEvent]] = []
    var onPush: (() throws -> Void)?
    var onPull: (() -> Void)?
    init(owner: String) { self.owner = owner }
    func pull(owner: String, cursor: String?) async throws -> RecommendationPreferencePull {
        if fail { throw URLError(.notConnectedToInternet) }
        onPull?()
        return .init(apiVersion: 1, ownerID: self.owner, events: [], cursor: "owner-cursor", hasMore: false)
    }
    func push(owner: String, events: [RecommendationPreferenceEvent]) async throws -> RecommendationPreferencePush {
        sent.append(events)
        let callback = onPush; onPush = nil; try callback?()
        return .init(apiVersion: 1, ownerID: self.owner, receipts: events.map { .init(eventID: $0.eventID, revision: 1) })
    }
}
