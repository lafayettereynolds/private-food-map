import Foundation
import SwiftData
import Testing
@testable import TasteMap

@Suite("P2-D multidimensional Visit ratings", .serialized)
@MainActor
struct P2DRatingTests {
    @Test("Shared contract encodes every nil rating explicitly")
    func contractNilRatings() throws {
        let record = SyncRecordMapper.visitRecord(
            Visit(restaurantId: UUID(), rating: nil),
            restaurantRemoteID: "restaurant"
        )
        let data = try JSONEncoder().encode(record)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["rating", "valueRating", "environmentRating", "serviceRating"] {
            #expect(object[key] is NSNull)
        }
        let decoded = try JSONDecoder().decode(VisitSyncContractV1.self, from: data)
        #expect(decoded.rating == nil)
        #expect(decoded.valueRating == nil)
        #expect(decoded.environmentRating == nil)
        #expect(decoded.serviceRating == nil)
    }

    @Test("Shared contract supports complete, partial, and rating boundaries")
    func contractCompleteAndBoundaries() throws {
        for payload in [
            try visitJSON(rating: 4.5, value: 5, environment: nil, service: 0.5),
            try visitJSON(rating: 0.5, value: 0.5, environment: 0.5, service: 0.5),
            try visitJSON(rating: 5, value: 5, environment: 5, service: 5),
        ] {
            let record = try JSONDecoder().decode(VisitSyncContractV1.self, from: payload)
            #expect(Visit.validatedRating(record.rating) == record.rating)
            #expect(Visit.validatedRating(record.valueRating) == record.valueRating)
            #expect(Visit.validatedRating(record.environmentRating) == record.environmentRating)
            #expect(Visit.validatedRating(record.serviceRating) == record.serviceRating)
        }
    }

    @Test("Shared contract rejects invalid multidimensional ratings")
    func contractRejectsInvalidRatings() throws {
        for (field, value) in [("valueRating", 0.0), ("environmentRating", 5.5), ("serviceRating", 4.2)] {
            var object = try #require(JSONSerialization.jsonObject(with: visitJSON()) as? [String: Any])
            object[field] = value
            let data = try JSONSerialization.data(withJSONObject: object)
            #expect(throws: DecodingError.self) {
                _ = try JSONDecoder().decode(VisitSyncContractV1.self, from: data)
            }
        }
    }

    @Test("Legacy Visit payload without detailed ratings decodes as nil")
    func legacyContractCompatibility() throws {
        var object = try #require(JSONSerialization.jsonObject(with: visitJSON()) as? [String: Any])
        object.removeValue(forKey: "valueRating")
        object.removeValue(forKey: "environmentRating")
        object.removeValue(forKey: "serviceRating")
        let decoded = try JSONDecoder().decode(
            VisitSyncContractV1.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        #expect(decoded.valueRating == nil)
        #expect(decoded.environmentRating == nil)
        #expect(decoded.serviceRating == nil)
    }

    @Test("Visit create allows overall-only, partial, and complete ratings")
    func visitCreateStates() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let restaurant = insertRestaurant(context)
        let store = LocalTasteMapStore(context: context)
        let overallOnly = try store.createVisit(
            restaurantId: restaurant.id,
            draft: VisitDraft(rating: 4.5)
        )
        let partial = try store.createVisit(
            restaurantId: restaurant.id,
            draft: VisitDraft(rating: 4, valueRating: 5, serviceRating: 3.5)
        )
        let complete = try store.createVisit(
            restaurantId: restaurant.id,
            draft: VisitDraft(rating: 4, valueRating: 4, environmentRating: 4.5, serviceRating: 5)
        )
        #expect(overallOnly.valueRating == nil && overallOnly.environmentRating == nil && overallOnly.serviceRating == nil)
        #expect(partial.valueRating == 5 && partial.environmentRating == nil && partial.serviceRating == 3.5)
        #expect(complete.valueRating == 4 && complete.environmentRating == 4.5 && complete.serviceRating == 5)
    }

    @Test("Editing and clearing one dimension preserves Visit, Dish, Photo, and other fields")
    func editPreservesRelatedData() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let restaurant = insertRestaurant(context)
        let store = LocalTasteMapStore(context: context)
        let visit = try store.createVisit(
            restaurantId: restaurant.id,
            draft: VisitDraft(
                diningMode: .takeout, partySize: 2, rating: 4.5,
                valueRating: 5, environmentRating: 4, serviceRating: 3.5,
                myActualSpend: 128, note: "保留备注"
            )
        )
        let dish = Dish(restaurantId: restaurant.id, visitId: visit.id, name: "保留菜品")
        let photo = PhotoAsset(
            restaurantId: restaurant.id, visitId: visit.id, kind: .visit,
            fileName: "keep.jpg", mimeType: "image/jpeg", byteSize: 10
        )
        context.insert(dish)
        context.insert(photo)
        try context.save()

        var edit = VisitDraft(visit: visit)
        edit.environmentRating = nil
        edit.serviceRating = 4.5
        try store.update(visit, draft: edit)

        #expect(visit.valueRating == 5)
        #expect(visit.environmentRating == nil)
        #expect(visit.serviceRating == 4.5)
        #expect(visit.rating == 4.5)
        #expect(visit.diningMode == .takeout)
        #expect(visit.partySize == 2)
        #expect(visit.myActualSpend == 128)
        #expect(visit.note == "保留备注")
        #expect(try context.fetch(FetchDescriptor<Dish>()).map(\.id) == [dish.id])
        #expect(try context.fetch(FetchDescriptor<PhotoAsset>()).map(\.id) == [photo.id])
    }

    @Test("Restaurant aggregation ignores nil and tombstoned Visits")
    func restaurantAggregation() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let restaurant = insertRestaurant(context)
        let oldest = Visit(
            restaurantId: restaurant.id, visitedAt: Date(timeIntervalSince1970: 100),
            valueRating: 4, environmentRating: nil, serviceRating: 3
        )
        let newest = Visit(
            restaurantId: restaurant.id, visitedAt: Date(timeIntervalSince1970: 300),
            valueRating: 5, environmentRating: 4.5, serviceRating: nil
        )
        let deleted = Visit(
            restaurantId: restaurant.id, visitedAt: Date(timeIntervalSince1970: 400),
            valueRating: 0.5, environmentRating: 0.5, serviceRating: 0.5,
            deletedAt: Date(timeIntervalSince1970: 500)
        )
        let allNil = Visit(restaurantId: restaurant.id, visitedAt: Date(timeIntervalSince1970: 200))
        [oldest, newest, deleted, allNil].forEach(context.insert)
        let summaries = RatingStatistics.summaries(for: [oldest, newest, deleted, allNil])

        let value = try #require(summaries.first { $0.dimension == .value })
        #expect(value.average == 4.5)
        #expect(value.count == 2)
        #expect(value.latest == 5)
        #expect(value.latestAt == newest.visitedAt)
        let environment = try #require(summaries.first { $0.dimension == .environment })
        #expect(environment.average == 4.5 && environment.count == 1)
        let service = try #require(summaries.first { $0.dimension == .service })
        #expect(service.average == 3 && service.count == 1)
        #expect(RatingStatistics.summaries(for: [allNil]).isEmpty)
    }

    @Test("Detailed ratings and offline mutation survive restart")
    func persistenceRestart() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("p2d.store")
        var container: ModelContainer? = try TasteMapPersistence.makeContainer(storageURL: url)
        let context = try #require(container?.mainContext)
        let restaurant = insertRestaurant(context)
        _ = try LocalTasteMapStore(context: context).createVisit(
            restaurantId: restaurant.id,
            draft: VisitDraft(rating: 4.5, valueRating: 5, environmentRating: nil, serviceRating: 3.5)
        )
        container = nil

        let reopened = try TasteMapPersistence.makeContainer(storageURL: url)
        let visit = try #require(reopened.mainContext.fetch(FetchDescriptor<Visit>()).first)
        #expect(visit.rating == 4.5)
        #expect(visit.valueRating == 5)
        #expect(visit.environmentRating == nil)
        #expect(visit.serviceRating == 3.5)
        #expect(try reopened.mainContext.fetch(FetchDescriptor<SyncMutation>()).contains {
            $0.entityType == .visit
        })
    }

    @Test("Sync hydrates detailed ratings on a fresh client and keeps entity-level conflict")
    func syncRoundTripAndConflict() async throws {
        let first = try TasteMapPersistence.makeContainer(inMemory: true)
        let restaurant = insertRestaurant(first.mainContext)
        let visit = try LocalTasteMapStore(context: first.mainContext).createVisit(
            restaurantId: restaurant.id,
            draft: VisitDraft(rating: 4.5, valueRating: 5, environmentRating: nil, serviceRating: 3.5)
        )
        let api = P2DRatingSyncAPI()
        try await SyncEngine(context: first.mainContext, api: api).synchronize()

        let second = try TasteMapPersistence.makeContainer(inMemory: true)
        try await SyncEngine(context: second.mainContext, api: api).synchronize()
        let secondVisit = try #require(second.mainContext.fetch(FetchDescriptor<Visit>()).first)
        #expect(secondVisit.rating == 4.5)
        #expect(secondVisit.valueRating == 5)
        #expect(secondVisit.environmentRating == nil)
        #expect(secondVisit.serviceRating == 3.5)

        var firstEdit = VisitDraft(visit: visit)
        firstEdit.environmentRating = 4.5
        try LocalTasteMapStore(context: first.mainContext).update(visit, draft: firstEdit)
        try await SyncEngine(context: first.mainContext, api: api).synchronize()

        var staleEdit = VisitDraft(visit: secondVisit)
        staleEdit.serviceRating = 4
        try LocalTasteMapStore(context: second.mainContext).update(secondVisit, draft: staleEdit)
        try await SyncEngine(context: second.mainContext, api: api).synchronize()
        let conflict = try #require(second.mainContext.fetch(FetchDescriptor<SyncMutation>()).first {
            $0.entityType == .visit
        })
        #expect(conflict.state == .conflicted)
        #expect(secondVisit.syncStatus == .failed)
    }

    private func insertRestaurant(_ context: ModelContext) -> Restaurant {
        let restaurant = Restaurant(
            name: "P2-D 测试餐厅", address: "杭州", latitude: 30, longitude: 120,
            remoteID: "p2d-restaurant"
        )
        context.insert(restaurant)
        try? context.save()
        return restaurant
    }

    private func visitJSON(
        rating: Double? = nil,
        value: Double? = nil,
        environment: Double? = nil,
        service: Double? = nil
    ) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "id": "p2d-visit",
            "userId": "owner",
            "restaurantId": "p2d-restaurant",
            "visitedAt": "2026-08-28T00:00:00.000Z",
            "diningMode": "dine_in",
            "partySize": NSNull(),
            "rating": rating as Any? ?? NSNull(),
            "valueRating": value as Any? ?? NSNull(),
            "environmentRating": environment as Any? ?? NSNull(),
            "serviceRating": service as Any? ?? NSNull(),
            "note": NSNull(),
            "myActualSpend": NSNull(),
            "createdAt": "2026-08-28T00:00:00.000Z",
            "updatedAt": "2026-08-28T00:00:00.000Z",
            "deletedAt": NSNull(),
        ])
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("taste-map-p2d-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

@MainActor
private final class P2DRatingSyncAPI: SyncAPI {
    private var restaurants: [String: RestaurantSyncRecordEnvelopeV1] = [:]
    private var visits: [String: VisitSyncRecordEnvelopeV1] = [:]
    private var receipts: [String: SyncMutationAcknowledgementV1] = [:]
    private var revision: Int64 = 0

    func push(_ request: SyncPushRequestV1) async throws -> SyncPushResponseV1 {
        let acknowledgements = request.mutations.map { mutation in
            if let receipt = receipts[mutation.mutationId] {
                return SyncMutationAcknowledgementV1(
                    mutationId: receipt.mutationId, entityType: receipt.entityType,
                    entityId: receipt.entityId, status: receipt.status, duplicate: true,
                    serverVersion: receipt.serverVersion, revision: receipt.revision,
                    conflictReason: receipt.conflictReason
                )
            }
            let currentVersion: Int64 = switch mutation.entityType {
            case .restaurant: restaurants[mutation.entityId]?.serverVersion ?? 0
            case .visit: visits[mutation.entityId]?.serverVersion ?? 0
            default: 0
            }
            guard mutation.baseVersion == currentVersion else {
                return SyncMutationAcknowledgementV1(
                    mutationId: mutation.mutationId, entityType: mutation.entityType,
                    entityId: mutation.entityId, status: .conflict, duplicate: false,
                    serverVersion: currentVersion, revision: nil,
                    conflictReason: "server_version_mismatch"
                )
            }
            revision += 1
            let version = currentVersion + 1
            if let payload = mutation.payload {
                switch payload {
                case .restaurant(let record):
                    restaurants[mutation.entityId] = .init(serverVersion: version, record: record)
                case .visit(let record):
                    visits[mutation.entityId] = .init(serverVersion: version, record: record)
                default: break
                }
            }
            let receipt = SyncMutationAcknowledgementV1(
                mutationId: mutation.mutationId, entityType: mutation.entityType,
                entityId: mutation.entityId, status: .applied, duplicate: false,
                serverVersion: version, revision: revision, conflictReason: nil
            )
            receipts[mutation.mutationId] = receipt
            return receipt
        }
        return SyncPushResponseV1(
            apiVersion: 1, acknowledgements: acknowledgements,
            serverTime: "2026-08-28T00:00:00.000Z"
        )
    }

    func pull(cursor: String, limit: Int) async throws -> SyncPullResponseV1 {
        let current = cursor == String(revision)
        return SyncPullResponseV1(
            apiVersion: 1, schemaVersion: 1,
            restaurants: current ? [] : Array(restaurants.values),
            visits: current ? [] : Array(visits.values),
            tombstones: [], nextCursor: String(revision), hasMore: false,
            serverTime: "2026-08-28T00:00:00.000Z"
        )
    }
}
