import Foundation
import SwiftData
import Testing
@testable import TasteMap

@Suite("P2-F companions and recommendation sources", .serialized)
@MainActor
struct P2FCompanionSourceTests {
    @Test("Multiple companions and one typed source round-trip in the Visit contract")
    func contractRoundTrip() throws {
        let visit = Visit(
            restaurantId: UUID(),
            companionIDs: ["companion-1", "companion-2"],
            companionNames: ["小王", "妈妈"],
            recommendationSourceID: "source-1",
            recommendationSourceType: .blogger,
            recommendationSourceText: "某美食博主"
        )
        let data = try JSONEncoder().encode(
            SyncRecordMapper.visitRecord(visit, restaurantRemoteID: "restaurant-1")
        )
        let decoded = try JSONDecoder().decode(VisitSyncContractV1.self, from: data)
        #expect(decoded.companions == ["小王", "妈妈"])
        #expect(decoded.companionIds == ["companion-1", "companion-2"])
        #expect(decoded.recommendationSourceId == "source-1")
        #expect(decoded.recommendationSourceType == "blogger")
        #expect(decoded.recommendationSourceText == "某美食博主")
    }

    @Test("Old Visit JSON defaults safely without P2-F fields")
    func legacyContract() throws {
        let visit = Visit(restaurantId: UUID())
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(
                SyncRecordMapper.visitRecord(visit, restaurantRemoteID: "restaurant-legacy")
            )) as? [String: Any]
        )
        for key in [
            "companions", "companionIds", "recommendationSourceId", "recommendationSourceType",
            "recommendationSourceUserId", "recommendationSourceText", "sharedMealId",
        ] { object.removeValue(forKey: key) }
        let decoded = try JSONDecoder().decode(
            VisitSyncContractV1.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        #expect(decoded.companions.isEmpty)
        #expect(decoded.companionIds.isEmpty)
        #expect(decoded.recommendationSourceId == nil)
        #expect(decoded.recommendationSourceText == nil)
    }

    @Test("Fresh client materializes legacy Web Visit people and source directories")
    func legacyWebDirectoryMaterialization() async throws {
        let server = P2FMemorySyncAPI()
        try server.seedLegacyWebVisit()
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        try await SyncEngine(context: container.mainContext, api: server).synchronize()

        let visit = try #require(container.mainContext.fetch(FetchDescriptor<Visit>()).first)
        #expect(visit.companionIDs == ["legacy-web-companion"])
        #expect(visit.companionNames == ["大学室友"])
        #expect(visit.recommendationSourceText == "某公众号")
        #expect(visit.recommendationSourceID != nil)
        #expect(try container.mainContext.fetch(FetchDescriptor<DiningCompanion>()).contains {
            $0.remoteID == "legacy-web-companion" && $0.displayName == "大学室友"
        })
        #expect(try container.mainContext.fetch(FetchDescriptor<RecommendationSource>()).contains {
            $0.displayName == "某公众号" && $0.sourceType == .blogger
        })

        var edit = VisitDraft(visit: visit)
        edit.note = "原生端可以继续编辑"
        try LocalTasteMapStore(context: container.mainContext).update(visit, draft: edit)
        #expect(visit.note == "原生端可以继续编辑")
    }

    @Test("Names trim and normalize conservatively without merging letter case")
    func conservativeDeduplication() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let store = LocalCompanionSourceStore(context: container.mainContext)
        let first = try store.findOrCreateCompanion(name: "  小王  ")
        let duplicate = try store.findOrCreateCompanion(name: "小王")
        let upper = try store.findOrCreateCompanion(name: "Alex")
        let lower = try store.findOrCreateCompanion(name: "alex")
        try container.mainContext.save()
        #expect(first.id == duplicate.id)
        #expect(upper.id != lower.id)
        #expect(try container.mainContext.fetch(FetchDescriptor<DiningCompanion>()).count == 3)
    }

    @Test("Create Visit materializes reusable directories and preserves every previous field")
    func createAndReuse() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let restaurant = insertRestaurant(context)
        let visit = try LocalTasteMapStore(context: context).createVisit(
            restaurantId: restaurant.id,
            draft: VisitDraft(
                partySize: 1,
                rating: 4.5,
                valueRating: 4,
                myActualSpend: 88,
                companionNames: ["小王", "妈妈"],
                recommendationSourceType: .blogger,
                recommendationSourceText: "某公众号",
                note: "其余字段保留"
            )
        )
        #expect(visit.companionNames == ["小王", "妈妈"])
        #expect(visit.companionIDs.count == 2)
        #expect(visit.partySize == 3)
        #expect(visit.recommendationSourceID != nil)
        #expect(visit.recommendationSourceType == .blogger)
        #expect(visit.rating == 4.5 && visit.valueRating == 4)
        #expect(visit.myActualSpend == 88 && visit.note == "其余字段保留")

        let mutations = try context.fetch(FetchDescriptor<SyncMutation>())
        #expect(mutations.filter { $0.entityType == .companion }.count == 2)
        #expect(mutations.filter { $0.entityType == .recommendationSource }.count == 1)
        #expect(mutations.filter { $0.entityType == .visit }.count == 1)
        let readyMutation = try SwiftDataSyncQueue(context: context).nextReadyMutation()
        let firstReady = try #require(readyMutation)
        #expect(firstReady.entityType != .visit)
    }

    @Test("Edit can remove one association without deleting entities or other Visit data")
    func removeAssociation() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let restaurant = insertRestaurant(context)
        let store = LocalTasteMapStore(context: context)
        let visit = try store.createVisit(
            restaurantId: restaurant.id,
            draft: VisitDraft(
                rating: 5,
                companionNames: ["小王", "妈妈"],
                recommendationSourceText: "同事推荐",
                note: "保留"
            )
        )
        var edit = VisitDraft(visit: visit)
        edit.companionIDs.removeFirst()
        edit.companionNames.removeFirst()
        edit.recommendationSourceID = nil
        edit.recommendationSourceTypeRawValue = nil
        edit.recommendationSourceText = ""
        try store.update(visit, draft: edit)
        #expect(visit.companionNames == ["妈妈"])
        #expect(visit.recommendationSourceID == nil)
        #expect(visit.rating == 5 && visit.note == "保留")
        #expect(try context.fetch(FetchDescriptor<DiningCompanion>()).count == 2)
        #expect(try context.fetch(FetchDescriptor<RecommendationSource>()).count == 1)
    }

    @Test("Rename keeps stable identity while tombstone keeps Visit snapshots readable")
    func renameAndTombstone() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let restaurant = insertRestaurant(context)
        let directory = LocalCompanionSourceStore(context: context)
        let companion = try directory.findOrCreateCompanion(name: "小王")
        let source = try directory.findOrCreateRecommendationSource(name: "小红书 @ABC", type: .xiaohongshu)
        try context.save()
        let visit = try LocalTasteMapStore(context: context).createVisit(
            restaurantId: restaurant.id,
            draft: VisitDraft(
                companionIDs: [try #require(companion.remoteID)],
                companionNames: [companion.displayName],
                recommendationSourceID: source.remoteID,
                recommendationSourceType: source.sourceType,
                recommendationSourceText: source.displayName
            )
        )
        try directory.rename(companion, to: "王宇")
        try directory.rename(source, to: "小红书 @TasteMap")
        #expect(companion.remoteID == visit.companionIDs[0])
        #expect(source.remoteID == visit.recommendationSourceID)
        #expect(visit.companionNames == ["小王"])
        #expect(visit.recommendationSourceText == "小红书 @ABC")

        companion.serverVersion = 1
        source.serverVersion = 1
        try directory.delete(companion)
        try directory.delete(source)
        #expect(companion.deletedAt != nil && source.deletedAt != nil)
        #expect(visit.companionNames == ["小王"])
        #expect(visit.recommendationSourceText == "小红书 @ABC")
    }

    @Test("Offline directory, Visit, and mutation queue survive app restart")
    func restartPersistence() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("p2f-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let storeURL = directoryURL.appendingPathComponent("p2f.store")
        var container: ModelContainer? = try TasteMapPersistence.makeContainer(storageURL: storeURL)
        let context = try #require(container?.mainContext)
        let restaurant = insertRestaurant(context)
        _ = try LocalTasteMapStore(context: context).createVisit(
            restaurantId: restaurant.id,
            draft: VisitDraft(
                companionNames: ["大学室友"],
                recommendationSourceText: "B站某博主"
            )
        )
        container = nil

        let reopened = try TasteMapPersistence.makeContainer(storageURL: storeURL)
        #expect(try reopened.mainContext.fetch(FetchDescriptor<DiningCompanion>()).first?.displayName == "大学室友")
        #expect(try reopened.mainContext.fetch(FetchDescriptor<RecommendationSource>()).first?.displayName == "B站某博主")
        let visit = try #require(reopened.mainContext.fetch(FetchDescriptor<Visit>()).first)
        #expect(visit.companionNames == ["大学室友"])
        #expect(visit.recommendationSourceText == "B站某博主")
        #expect(try reopened.mainContext.fetch(FetchDescriptor<SyncMutation>()).contains {
            $0.entityType == .companion || $0.entityType == .recommendationSource
        })
    }

    @Test("Two clients converge directories, associations, rename, and removal")
    func twoClientSync() async throws {
        let server = P2FMemorySyncAPI()
        let first = try TasteMapPersistence.makeContainer(inMemory: true)
        let second = try TasteMapPersistence.makeContainer(inMemory: true)
        let restaurant = insertRestaurant(first.mainContext)
        let visit = try LocalTasteMapStore(context: first.mainContext).createVisit(
            restaurantId: restaurant.id,
            draft: VisitDraft(
                companionNames: ["小王", "妈妈"],
                recommendationSourceType: .friend,
                recommendationSourceText: "朋友小李"
            )
        )
        try await SyncEngine(context: first.mainContext, api: server).synchronize()
        try await SyncEngine(context: second.mainContext, api: server).synchronize()
        let pulledVisit = try #require(second.mainContext.fetch(FetchDescriptor<Visit>()).first)
        #expect(pulledVisit.companionNames == ["小王", "妈妈"])
        #expect(pulledVisit.recommendationSourceText == "朋友小李")
        #expect(try second.mainContext.fetch(FetchDescriptor<DiningCompanion>()).count == 2)

        var edit = VisitDraft(visit: visit)
        edit.companionIDs.removeLast()
        edit.companionNames.removeLast()
        edit.recommendationSourceID = nil
        edit.recommendationSourceTypeRawValue = nil
        edit.recommendationSourceText = ""
        try LocalTasteMapStore(context: first.mainContext).update(visit, draft: edit)
        try await SyncEngine(context: first.mainContext, api: server).synchronize()
        try await SyncEngine(context: second.mainContext, api: server).synchronize()
        #expect(pulledVisit.companionNames == ["小王"])
        #expect(pulledVisit.recommendationSourceID == nil)
    }

    private func insertRestaurant(_ context: ModelContext) -> Restaurant {
        let restaurant = Restaurant(
            name: "P2-F 餐厅", address: "杭州", latitude: 30.2, longitude: 120.1,
            appleMapItemIdentifier: "apple-p2f"
        )
        context.insert(restaurant)
        try? context.save()
        return restaurant
    }
}

@MainActor
private final class P2FMemorySyncAPI: SyncAPI {
    private var restaurants: [String: RestaurantSyncRecordEnvelopeV1] = [:]
    private var visits: [String: VisitSyncRecordEnvelopeV1] = [:]
    private var companions: [String: DiningCompanionSyncRecordEnvelopeV1] = [:]
    private var sources: [String: RecommendationSourceSyncRecordEnvelopeV1] = [:]
    private var tombstones: [String: SyncTombstoneV1] = [:]
    private var receipts: [String: SyncMutationAcknowledgementV1] = [:]
    private var revision: Int64 = 0

    func seedLegacyWebVisit() throws {
        let at = "2026-08-28T08:00:00.000Z"
        let restaurantID = "legacy-web-restaurant"
        let restaurant = try RestaurantJSONContractV1(
            id: restaurantID,
            userId: "legacy-owner",
            placeIdentities: [try RestaurantPlaceIdentityContract(
                provider: .appleMaps,
                externalId: "legacy-web-apple-maps",
                isPrimary: true,
                createdAt: at,
                updatedAt: at
            )],
            name: "旧 Web 餐厅",
            address: "杭州",
            city: "杭州",
            latitude: 30.2,
            longitude: 120.1,
            status: .visited,
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
            createdAt: at,
            updatedAt: at,
            deletedAt: nil,
            isTestData: false
        )
        let visit = VisitSyncContractV1(
            schemaVersion: 1,
            id: "legacy-web-visit",
            userId: "legacy-owner",
            restaurantId: restaurantID,
            visitedAt: at,
            diningMode: .dineIn,
            visibility: .private,
            partySize: 2,
            totalPrice: nil,
            paymentMode: nil,
            pricePerPerson: nil,
            queueDuration: nil,
            diningOccasions: [],
            diningOccasionText: nil,
            rating: nil,
            valueRating: nil,
            environmentRating: nil,
            serviceRating: nil,
            valueTags: [],
            environmentTags: [],
            serviceTags: [],
            noiseLevel: nil,
            diningDuration: nil,
            portionLevel: nil,
            transportConvenience: nil,
            specialNotes: nil,
            companions: ["大学室友"],
            companionIds: ["legacy-web-companion"],
            recommendationSourceType: "blogger",
            recommendationSourceText: "某公众号",
            note: nil,
            myActualSpend: nil,
            createdAt: at,
            updatedAt: at,
            deletedAt: nil
        )
        restaurants[restaurantID] = .init(serverVersion: 1, record: restaurant)
        visits[visit.id] = .init(serverVersion: 1, record: visit)
        revision = 2
    }

    func push(_ request: SyncPushRequestV1) async throws -> SyncPushResponseV1 {
        var acknowledgements: [SyncMutationAcknowledgementV1] = []
        for mutation in request.mutations {
            if let existing = receipts[mutation.mutationId] {
                acknowledgements.append(.init(
                    mutationId: existing.mutationId, entityType: existing.entityType,
                    entityId: existing.entityId, status: existing.status, duplicate: true,
                    serverVersion: existing.serverVersion, revision: existing.revision,
                    conflictReason: existing.conflictReason
                ))
                continue
            }
            revision += 1
            let version = mutation.baseVersion + 1
            if let payload = mutation.payload {
                switch payload {
                case .restaurant(let record): restaurants[mutation.entityId] = .init(serverVersion: version, record: record)
                case .visit(let record): visits[mutation.entityId] = .init(serverVersion: version, record: record)
                case .companion(let record): companions[mutation.entityId] = .init(serverVersion: version, record: record)
                case .recommendationSource(let record): sources[mutation.entityId] = .init(serverVersion: version, record: record)
                case .dish, .visitDish, .photo, .profile,
                     .restaurantList, .restaurantListItem: break
                }
                tombstones.removeValue(forKey: "\(mutation.entityType.rawValue):\(mutation.entityId)")
            } else {
                switch mutation.entityType {
                case .restaurant: restaurants.removeValue(forKey: mutation.entityId)
                case .visit: visits.removeValue(forKey: mutation.entityId)
                case .companion: companions.removeValue(forKey: mutation.entityId)
                case .recommendationSource: sources.removeValue(forKey: mutation.entityId)
                case .dish, .visitDish, .photo, .profile,
                     .restaurantList, .restaurantListItem: break
                }
                let key = "\(mutation.entityType.rawValue):\(mutation.entityId)"
                tombstones[key] = .init(
                    entityType: mutation.entityType, entityId: mutation.entityId,
                    serverVersion: version, deletedAt: "2026-08-28T08:00:00.000Z"
                )
            }
            let acknowledgement = SyncMutationAcknowledgementV1(
                mutationId: mutation.mutationId, entityType: mutation.entityType,
                entityId: mutation.entityId, status: .applied, duplicate: false,
                serverVersion: version, revision: revision, conflictReason: nil
            )
            receipts[mutation.mutationId] = acknowledgement
            acknowledgements.append(acknowledgement)
        }
        return .init(apiVersion: 1, acknowledgements: acknowledgements, serverTime: "2026-08-28T08:00:00.000Z")
    }

    func pull(cursor: String, limit: Int) async throws -> SyncPullResponseV1 {
        SyncPullResponseV1(
            apiVersion: 1, schemaVersion: 1,
            restaurants: Array(restaurants.values), visits: Array(visits.values),
            companions: Array(companions.values), recommendationSources: Array(sources.values),
            tombstones: Array(tombstones.values), nextCursor: String(revision),
            hasMore: false, serverTime: "2026-08-28T08:00:00.000Z"
        )
    }
}
