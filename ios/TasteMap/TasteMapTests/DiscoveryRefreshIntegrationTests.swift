import Foundation
import SwiftData
import Testing
@testable import TasteMap

@MainActor
struct DiscoveryRefreshIntegrationTests {
    @Test func transportDiagnosticsOnlyAllowNonContentCorrelationFields() {
        #expect(DiscoveryTransportObserver.safeRay("a38986f5fbb9fbdc-AMS") == "a38986f5fbb9fbdc-AMS")
        for invalid in [nil, "", "Bearer private-token", "a38986f5fbb9fbdc-AMS\nowner=private", "https://private.example/path"] as [String?] {
            #expect(DiscoveryTransportObserver.safeRay(invalid) == "unavailable")
        }
        #expect(DiscoveryTransportObserver.safeProtocol("h3") == "h3")
        #expect(DiscoveryTransportObserver.safeProtocol("h2") == "h2")
        #expect(DiscoveryTransportObserver.safeProtocol(nil) == "unknown")
        #expect(DiscoveryTransportObserver.safeProtocol("private-content") == "unknown")
    }

    @Test func recommendationReasonEvidenceDecodesWithoutInventingLegacyEvidence() throws {
        let decoder = JSONDecoder()
        let full = try decoder.decode(DiscoveryReasonV1.self, from: Data(#"{"code":"HIGH_CUISINE_MATCH","text":"真实历史依据","evidence":{"sampleCount":6,"referenceRestaurantID":"place:known","dimensions":["粤菜","清淡"],"meanOutOfTen":8.25,"windowDays":30}}"#.utf8))
        #expect(full.evidence?.sampleCount == 6)
        #expect(full.evidence?.referenceRestaurantID == "place:known")
        #expect(full.evidence?.dimensions == ["粤菜", "清淡"])
        #expect(full.evidence?.meanOutOfTen == 8.25)
        #expect(full.evidence?.windowDays == 30)
        let partial = try decoder.decode(DiscoveryReasonV1.self, from: Data(#"{"code":"HISTORY","text":"依据","evidence":{"sampleCount":2}}"#.utf8))
        #expect(partial.evidence?.sampleCount == 2)
        #expect(partial.evidence?.referenceRestaurantID == nil && partial.evidence?.meanOutOfTen == nil)
        let legacyData = Data(#"{"code":"HISTORY","text":"过去 6 家餐厅平均 8.2 分"}"#.utf8)
        #expect(try decoder.decode(DiscoveryReasonV1.self, from: legacyData).evidence == nil)
        #expect(try decoder.decode(TasteMapHybridDiscoveryReasonDTO.self, from: legacyData).evidence == nil)
    }

    @Test func recommendationReasonEvidenceSurvivesRemoteCacheAndBridgeProjection() throws {
        var evidence = TasteMapHybridDiscoveryReasonEvidenceDTO(sampleCount: 4,
            referenceRestaurantID: "place:reference", dimensions: ["面食"], meanOutOfTen: 8.5, windowDays: 7)
        evidence.source = "owner_history"
        evidence.participants = [.init(restaurantID: "place:reference", restaurantName: "本人记录的面馆",
            restaurantRecordIDs: ["owner-restaurant-1"], visitIDs: ["owner-visit-1"],
            fields: .init(tags: ["面食"], ratingCount: 2, meanOutOfTen: 8.5, referenceRatingOutOfTen: 9,
                visitCount: 2, firstVisitedAt: "2026-08-01", lastVisitedAt: "2026-08-20", recordedPricePerPerson: nil, priceCurrency: nil))]
        evidence.participantCount = 1
        evidence.participantsTruncated = false
        evidence.missingFields = ["complete_visit_list", "price_currency"]
        let reason = DiscoveryReasonV1(code: "HIGH_CUISINE_MATCH", text: "四家真实面食记录", evidence: evidence)
        let remote = page(name: "证据餐厅", reasons: [reason])
        let roundTrip = try JSONDecoder().decode(DiscoveryPageV1.self, from: JSONEncoder().encode(remote))
        #expect(roundTrip.items.first?.reasons.first?.evidence == evidence)
        let container = try TasteMapPersistence.makeContainer(inMemory: true, configurationName: "ReasonEvidenceProjection")
        let store = LocalDiscoveryStore(context: container.mainContext)
        try store.replaceCache(page: roundTrip, currentUserID: owner, trendWindowDays: 7)
        let cached = try store.cachedPage(mode: .forYou, city: "杭州", currentUserID: owner, trendWindowDays: 7)
        #expect(cached?.cards.first?.reasons.first?.evidence == evidence)
        #expect(try store.cachedPage(mode: .forYou, city: "杭州", currentUserID: "tm_other_owner", trendWindowDays: 7) == nil)
        let service = try TasteMapHybridBridgeService(container: container, ownerUserID: owner)
        #expect(try service.discoveryPageSource(roundTrip).items.first?.reasons.first?.evidence == evidence)
        let projected = try service.contentSnapshot().discovery.forYou.first?.reasons.first
        #expect(projected?.evidence == evidence)
        #expect(projected?.text == reason.text && projected?.code == reason.code)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try #require(projected))) as? [String: Any]
        let encodedEvidence = try #require(json?["evidence"] as? [String: Any])
        #expect(Set(encodedEvidence.keys) == ["sampleCount", "referenceRestaurantID", "dimensions", "meanOutOfTen", "windowDays", "source", "participants", "participantCount", "participantsTruncated", "missingFields"])
        #expect(projected?.evidence?.participants?.first?.visitIDs == ["owner-visit-1"])
    }

    @Test func protectedCardsRemainBlockedForDeniedAndUnknownAccessRegardlessOfCachedContentOrError() {
        for access: PremiumAccessDecision in [.denied, .loading] {
            #expect(DiscoveryContentAccessPolicy.blocksCards(mode: .similarTaste, access: access))
        }
        #expect(!DiscoveryContentAccessPolicy.blocksCards(mode: .similarTaste, access: .allowed))
        #expect(!DiscoveryContentAccessPolicy.blocksCards(mode: .forYou, access: .denied))
    }
    @Test func evidenceAvailabilityIsSuccessfulOwnerScopedAndRevokedWithAccess() async throws {
        let coordinator = TasteMapDiscoveryRefreshCoordinator()
        let evidence = TasteMapDiscoveryEvidenceAvailabilityDTO(personalRatedRestaurantCount: 7,
            personalScoreStandardDeviationOutOfTen: 1.2, personalEvidence: "eligible", localDirectRestaurantCount: 0)
        let scope = TasteMapDiscoveryRefreshCoordinator.Scope(ownerUserID: "evidence-owner", mode: "similar_taste", city: "杭州", windowDays: 7)
        _ = await coordinator.refresh(scope: scope, force: true, isCurrent: { true },
            load: { evidence }, save: { _ in }, generatedAt: { _ in "accepted" },
            evidenceAvailability: { $0 }, cachedGeneratedAt: { nil })
        #expect(coordinator.evidenceSnapshot(ownerUserID: "evidence-owner", city: "杭州", windowDays: 7)["similar_taste"] == evidence)
        #expect(coordinator.evidenceSnapshot(ownerUserID: "other", city: "杭州", windowDays: 7).isEmpty)
        #expect(coordinator.evidenceSnapshot(ownerUserID: "evidence-owner", city: "上海", windowDays: 7).isEmpty)
        _ = await coordinator.refresh(scope: scope, force: true, isCurrent: { true },
            load: { () throws -> TasteMapDiscoveryEvidenceAvailabilityDTO in throw URLError(.notConnectedToInternet) },
            save: { _ in }, generatedAt: { _ in "unused" }, evidenceAvailability: { $0 }, cachedGeneratedAt: { "accepted" })
        #expect(coordinator.evidenceSnapshot(ownerUserID: "evidence-owner", city: "杭州", windowDays: 7)["similar_taste"] == evidence)
        _ = await coordinator.refresh(scope: scope, force: true, isCurrent: { true },
            load: { () throws -> TasteMapDiscoveryEvidenceAvailabilityDTO in
                throw TasteMapDiscoveryHTTPError(status: 403, code: nil, message: "denied")
            }, save: { _ in }, generatedAt: { _ in "unused" }, evidenceAvailability: { $0 }, cachedGeneratedAt: { "accepted" })
        #expect(coordinator.evidenceSnapshot(ownerUserID: "evidence-owner", city: "杭州", windowDays: 7).isEmpty)
        coordinator.reset()
        #expect(coordinator.evidenceSnapshot(ownerUserID: "evidence-owner", city: "杭州", windowDays: 7).isEmpty)
    }

    @Test func emptyEvidenceDistinguishesPersonalQuantityVariationAndCityCoverageWithoutPayment() throws {
        func evidence(_ count: Int, _ sd: Double, _ state: String) -> TasteMapDiscoveryEvidenceAvailabilityDTO {
            .init(personalRatedRestaurantCount: count, personalScoreStandardDeviationOutOfTen: sd,
                  personalEvidence: state, localDirectRestaurantCount: 0)
        }
        #expect(evidence(2, 1, "insufficient").similarTasteEmptyMessage.contains("还需至少 3 家"))
        #expect(evidence(5, 0, "insufficient").similarTasteEmptyMessage.contains("不需要为了匹配而刻意改分"))
        #expect(evidence(8, 1, "eligible").similarTasteEmptyMessage.contains("当前城市"))
        #expect(evidence(2, 1, "insufficient").recoveryAction == "record")
        #expect(evidence(8, 1, "eligible").recoveryAction == "city")
        #expect(evidence(8, 1, "insufficient").recoveryAction == "retry")
        #expect(evidence(8, 1, "insufficient").emptyTitle == "暂未找到可展示的同味推荐")
        #expect(evidence(2, 0, "eligible").similarTasteEmptyMessage == TasteMapDiscoveryEvidenceAvailabilityDTO.unknownMessage)
        let legacy = try JSONDecoder().decode(DiscoveryPageV1.self, from: Data(#"{"apiVersion":1,"mode":"similar_taste","city":"杭州","personalizationConfidence":"insufficient","generatedAt":"old","items":[],"nextCursor":null}"#.utf8))
        #expect(legacy.evidenceAvailability == nil)
    }

    private let owner = "tm_discovery_refresh_test"
    private var scope: TasteMapDiscoveryRefreshCoordinator.Scope {
        .init(ownerUserID: owner, mode: "for_you", city: "杭州", windowDays: 7)
    }

    @Test func committedRefreshReplacesRegisteredDiscoveryValuesAnd403NeverProjectsProtectedCache() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true, configurationName: "DiscoveryRefreshProjection")
        let writer = ModelContext(container)
        writer.autosaveEnabled = false
        let store = LocalDiscoveryStore(context: writer)
        try store.replaceCache(page: page(name: "旧缓存餐厅"), currentUserID: owner, trendWindowDays: 7)
        let service = try TasteMapHybridBridgeService(container: container, ownerUserID: owner)
        #expect(try service.contentSnapshot().discovery.forYou.first?.restaurant.name == "旧缓存餐厅")

        let coordinator = TasteMapDiscoveryRefreshCoordinator()
        let automaticScope = TasteMapDiscoveryRefreshCoordinator.Scope(ownerUserID: owner, mode: "for_you", city: "", windowDays: 7)
        let nextWriter = ModelContext(container)
        nextWriter.autosaveEnabled = false
        let nextStore = LocalDiscoveryStore(context: nextWriter)
        _ = await coordinator.refresh(scope: automaticScope, force: true, isCurrent: { true },
            load: { page(name: "新提交餐厅") },
            save: { try nextStore.replaceCache(page: $0, currentUserID: owner, trendWindowDays: 7) },
            generatedAt: { $0.generatedAt }, resolvedCity: { $0.city }, cachedGeneratedAt: { "old" })
        service.discoveryRefreshStatus = coordinator.snapshot(ownerUserID: owner, city: "", windowDays: 7)
        #expect(try service.contentSnapshot().discovery.forYou.first?.restaurant.name == "新提交餐厅")
        #expect(try service.contentSnapshot().discovery.refreshStatus?["for_you"]?.state == .fresh)

        _ = await coordinator.refresh(scope: automaticScope, force: true, isCurrent: { true },
            load: { () async throws -> DiscoveryPageV1 in
                throw TasteMapDiscoveryHTTPError.decode(status: 403, data: Data(#"{"error":"Forbidden"}"#.utf8))
            }, save: { _ in Issue.record("Forbidden request cannot write cache") },
            generatedAt: { $0.generatedAt }, cachedGeneratedAt: { "old" })
        service.discoveryRefreshStatus = coordinator.snapshot(ownerUserID: owner, city: "", windowDays: 7)
        let restricted = try service.contentSnapshot()
        #expect(restricted.discovery.forYou.isEmpty)
        #expect(restricted.discovery.refreshStatus?["for_you"]?.state == .restricted)
        #expect(try nextStore.cachedPage(mode: .forYou, city: "杭州", currentUserID: owner, trendWindowDays: 7) != nil)
        #expect(try TasteMapHybridBridgeService(container: container, ownerUserID: "tm_other_owner").contentSnapshot().discovery.forYou.isEmpty)
    }

    @Test func capacityFailurePreservesCommittedCacheAndUnrelatedUnsavedEditorContext() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true, configurationName: "DiscoveryCapacityDraft")
        let cacheContext = ModelContext(container)
        cacheContext.autosaveEnabled = false
        let store = LocalDiscoveryStore(context: cacheContext)
        try store.replaceCache(page: page(name: "可保留缓存"), currentUserID: owner, trendWindowDays: 7)
        let editor = ModelContext(container)
        editor.autosaveEnabled = false
        let draft = Restaurant(ownerUserID: owner, name: "未保存草稿", address: "杭州", latitude: 30.2, longitude: 120.1)
        editor.insert(draft)
        let coordinator = TasteMapDiscoveryRefreshCoordinator()
        _ = await coordinator.refresh(scope: scope, force: true, isCurrent: { true },
            load: { () async throws -> DiscoveryPageV1 in
                throw TasteMapDiscoveryHTTPError.decode(status: 503, data: Data(#"{"code":"DISCOVERY_AGGREGATE_CAPACITY","error":"capacity"}"#.utf8))
            }, save: { try store.replaceCache(page: $0, currentUserID: owner, trendWindowDays: 7) },
            generatedAt: { $0.generatedAt }, cachedGeneratedAt: {
                try store.cachedPage(mode: .forYou, city: "杭州", currentUserID: owner, trendWindowDays: 7).map { ISO8601DateFormatter().string(from: $0.updatedAt) }
            })
        let service = try TasteMapHybridBridgeService(container: container, ownerUserID: owner)
        service.discoveryRefreshStatus = coordinator.snapshot(ownerUserID: owner, city: "杭州", windowDays: 7)
        let snapshot = try service.contentSnapshot()
        #expect(snapshot.discovery.forYou.first?.restaurant.name == "可保留缓存")
        #expect(snapshot.discovery.refreshStatus?["for_you"]?.issue?.code == "DISCOVERY_AGGREGATE_CAPACITY")
        #expect(editor.hasChanges && draft.name == "未保存草稿")
        #expect(try ModelContext(container).fetch(FetchDescriptor<Restaurant>()).isEmpty)
    }

    private func page(name: String, reasons: [DiscoveryReasonV1] = []) -> DiscoveryPageV1 {
        let restaurant = DiscoveryRestaurantProjectionV1(globalKey: "place:refresh", placeIdentities: [],
            name: name, address: "杭州地址", city: "杭州", latitude: 30.2, longitude: 120.1,
            tags: [], pricePerPerson: nil, merchantImageUrl: nil, markerEmoji: "", photo: nil)
        let rating = DiscoveryRatingProjectionV1(value: nil, sampleCount: 0)
        let card = DiscoveryCardV1(id: "refresh", mode: .forYou, restaurant: restaurant, viewerState: .none,
            ratings: .init(mine: rating, community: rating, friends: rating, similarTaste: rating),
            reasons: reasons, sourceUser: nil, similarity: nil, trend: nil, cacheScope: .public, rank: 1, score: 0)
        return .init(apiVersion: 1, mode: .forYou, city: "杭州", personalizationConfidence: .insufficient,
            generatedAt: "2026-09-06T00:00:00Z", items: [card], nextCursor: nil)
    }
}
