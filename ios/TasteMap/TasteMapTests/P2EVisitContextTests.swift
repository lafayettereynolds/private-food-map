import Foundation
import SwiftData
import Testing
@testable import TasteMap

@Suite("P2-E Visit dining context", .serialized)
@MainActor
struct P2EVisitContextTests {
    @Test("Visit contract round-trips all P2-E fields and encodes nullable fields explicitly")
    func contractRoundTrip() throws {
        let visit = Visit(
            restaurantId: UUID(),
            rating: 4.5,
            valueRating: 5,
            environmentRating: 4,
            serviceRating: 3.5,
            note: "完整记录",
            myActualSpend: 120,
            totalPrice: 360,
            pricePerPerson: 120,
            visibility: .friends,
            paymentMode: .aa,
            queueDuration: .noWait,
            diningOccasions: [.friends, .other],
            diningOccasionText: "工作简餐",
            valueTags: ["合理"],
            environmentTags: ["舒适"],
            serviceTags: ["周到"],
            noiseLevel: .normal,
            diningDuration: .under30,
            portionLevel: .generous,
            transportConvenience: .veryConvenient,
            specialNotes: "现场取号",
            partySize: 3
        )
        let record = SyncRecordMapper.visitRecord(visit, restaurantRemoteID: "restaurant-p2e")
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(VisitSyncContractV1.self, from: data)

        #expect(decoded.visibility == .friends)
        #expect(decoded.totalPrice == 360)
        #expect(decoded.paymentMode == "aa")
        #expect(decoded.pricePerPerson == 120)
        #expect(decoded.queueDuration == "none")
        #expect(decoded.diningOccasions == ["friends", "other"])
        #expect(decoded.diningOccasionText == "工作简餐")
        #expect(decoded.valueTags == ["合理"])
        #expect(decoded.environmentTags == ["舒适"])
        #expect(decoded.serviceTags == ["周到"])
        #expect(decoded.noiseLevel == "normal")
        #expect(decoded.diningDuration == "under30")
        #expect(decoded.portionLevel == "generous")
        #expect(decoded.transportConvenience == "very_convenient")
        #expect(decoded.specialNotes == "现场取号")

        let minimal = SyncRecordMapper.visitRecord(
            Visit(restaurantId: UUID()),
            restaurantRemoteID: "restaurant-minimal"
        )
        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(minimal)) as? [String: Any]
        )
        for key in [
            "totalPrice", "paymentMode", "pricePerPerson", "queueDuration",
            "diningOccasionText", "noiseLevel", "diningDuration", "portionLevel",
            "transportConvenience", "specialNotes",
        ] {
            #expect(object[key] is NSNull)
        }
        for key in ["diningOccasions", "valueTags", "environmentTags", "serviceTags"] {
            #expect((object[key] as? [Any])?.isEmpty == true)
        }
    }

    @Test("Legacy payload defaults safely while invalid negative waiting data is rejected")
    func legacyContractCompatibility() throws {
        var object = try baseVisitJSONObject()
        for key in p2EKeys { object.removeValue(forKey: key) }
        let decoded = try JSONDecoder().decode(
            VisitSyncContractV1.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        #expect(decoded.visibility == .private)
        #expect(decoded.totalPrice == nil)
        #expect(decoded.queueDuration == nil)
        #expect(decoded.diningOccasions.isEmpty)
        #expect(decoded.valueTags.isEmpty)

        object = try baseVisitJSONObject()
        object["queueDuration"] = -1
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                VisitSyncContractV1.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }

        object = try baseVisitJSONObject()
        object["queueDuration"] = "legacy_two_hours"
        object["paymentMode"] = "legacy_coupon"
        let legacyEnum = try JSONDecoder().decode(
            VisitSyncContractV1.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        #expect(legacyEnum.queueDuration == "legacy_two_hours")
        #expect(legacyEnum.paymentMode == "legacy_coupon")
    }

    @Test("Queue nil and explicit no-wait remain distinct")
    func waitingSemantics() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let restaurant = insertRestaurant(container.mainContext)
        let store = LocalTasteMapStore(context: container.mainContext)
        let unrecorded = try store.createVisit(
            restaurantId: restaurant.id,
            draft: VisitDraft(queueDuration: nil)
        )
        let noWait = try store.createVisit(
            restaurantId: restaurant.id,
            draft: VisitDraft(queueDuration: .noWait)
        )
        #expect(unrecorded.queueDuration == nil)
        #expect(noWait.queueDuration == .noWait)
        #expect(noWait.queueDuration?.approximateMinutes == 0)
    }

    @Test("Create, edit, and clear P2-E fields preserve all P1/P2 relationships")
    func createEditClear() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let restaurant = insertRestaurant(context)
        let store = LocalTasteMapStore(context: context)
        let visit = try store.createVisit(restaurantId: restaurant.id, draft: completeDraft())
        let dish = Dish(restaurantId: restaurant.id, visitId: visit.id, name: "保留菜品")
        let photo = PhotoAsset(
            restaurantId: restaurant.id,
            visitId: visit.id,
            kind: .visit,
            fileName: "keep.jpg",
            mimeType: "image/jpeg",
            byteSize: 10
        )
        context.insert(dish)
        context.insert(photo)
        try context.save()

        #expect(visit.visibility == .friends)
        #expect(visit.queueDuration == .under60)
        #expect(visit.pricePerPerson == 120)
        #expect(visit.diningOccasions == [.friends, .other])
        #expect(visit.valueTags == ["合理"])

        var edit = VisitDraft(visit: visit)
        edit.visibility = .public
        edit.queueDuration = .noWait
        edit.paymentMode = nil
        edit.totalPrice = nil
        edit.diningOccasions = []
        edit.diningOccasionText = ""
        edit.valueTags = []
        edit.environmentTags = []
        edit.serviceTags = []
        edit.noiseLevel = nil
        edit.diningDuration = nil
        edit.portionLevel = nil
        edit.transportConvenience = nil
        edit.specialNotes = ""
        try store.update(visit, draft: edit)

        #expect(visit.visibility == .public)
        #expect(visit.queueDuration == .noWait)
        #expect(visit.paymentMode == nil)
        #expect(visit.totalPrice == nil)
        #expect(visit.pricePerPerson == nil)
        #expect(visit.diningOccasions.isEmpty)
        #expect(visit.diningOccasionText == nil)
        #expect(visit.valueTags.isEmpty && visit.environmentTags.isEmpty && visit.serviceTags.isEmpty)
        #expect(visit.noiseLevel == nil && visit.diningDuration == nil)
        #expect(visit.portionLevel == nil && visit.transportConvenience == nil)
        #expect(visit.specialNotes == nil)
        #expect(visit.rating == 4.5)
        #expect(visit.valueRating == 5 && visit.environmentRating == 4 && visit.serviceRating == 3.5)
        #expect(visit.myActualSpend == 120)
        #expect(visit.note == "保留 P1 备注")
        #expect(try context.fetch(FetchDescriptor<Dish>()).map(\.id) == [dish.id])
        #expect(try context.fetch(FetchDescriptor<PhotoAsset>()).map(\.id) == [photo.id])
        #expect(try context.fetch(FetchDescriptor<SyncMutation>()).filter { $0.entityType == .visit }.count == 1)
    }

    @Test("Unknown legacy enum values survive a native edit without crashing")
    func unknownEnumPreservation() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let restaurant = insertRestaurant(context)
        let visit = Visit(restaurantId: restaurant.id)
        visit.queueDurationRawValue = "legacy_long_wait"
        visit.paymentModeRawValue = "legacy_voucher"
        visit.diningOccasionRawValues = ["legacy_scene"]
        context.insert(visit)
        try context.save()

        var draft = VisitDraft(visit: visit)
        draft.note = "只编辑备注"
        try LocalTasteMapStore(context: context).update(visit, draft: draft)
        #expect(visit.queueDuration == nil)
        #expect(visit.queueDurationRawValue == "legacy_long_wait")
        #expect(visit.paymentMode == nil)
        #expect(visit.paymentModeRawValue == "legacy_voucher")
        #expect(visit.diningOccasionRawValues == ["legacy_scene"])
        #expect(visit.note == "只编辑备注")
    }

    @Test("Offline P2-E fields and queued mutation survive app restart")
    func restartPersistence() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("p2e.store")
        var container: ModelContainer? = try TasteMapPersistence.makeContainer(storageURL: url)
        let context = try #require(container?.mainContext)
        let restaurant = insertRestaurant(context)
        _ = try LocalTasteMapStore(context: context).createVisit(
            restaurantId: restaurant.id,
            draft: completeDraft()
        )
        container = nil

        let reopened = try TasteMapPersistence.makeContainer(storageURL: url)
        let visit = try #require(reopened.mainContext.fetch(FetchDescriptor<Visit>()).first)
        #expect(visit.visibility == .friends)
        #expect(visit.queueDuration == .under60)
        #expect(visit.diningOccasions == [.friends, .other])
        #expect(visit.totalPrice == 360)
        #expect(visit.paymentMode == .aa)
        #expect(visit.valueTags == ["合理"])
        #expect(try reopened.mainContext.fetch(FetchDescriptor<SyncMutation>()).contains {
            $0.entityType == .visit
        })
    }

    @Test("Fresh pull converges P2-E fields, duplicate sync is stable, conflict and tombstone remain entity-level")
    func syncConflictAndTombstone() async throws {
        let server = VersionedMemorySyncAPI()
        let first = try TasteMapPersistence.makeContainer(inMemory: true)
        let second = try TasteMapPersistence.makeContainer(inMemory: true)
        let store = LocalTasteMapStore(context: first.mainContext)
        let restaurant = try store.addToWantToGo(
            candidate: RestaurantCandidate(
                name: "P2-E 同步餐厅",
                address: "Apple Maps only",
                latitude: 30.25,
                longitude: 120.16,
                appleMapItemIdentifier: "apple-p2e-sync"
            ),
            among: []
        )
        let visit = try store.createVisit(restaurantId: restaurant.id, draft: completeDraft())
        try await SyncEngine(context: first.mainContext, api: server).synchronize()
        let versionAfterFirstSync = visit.serverVersion
        try await SyncEngine(context: first.mainContext, api: server).synchronize()
        #expect(visit.serverVersion == versionAfterFirstSync)

        try await SyncEngine(context: second.mainContext, api: server).synchronize()
        let pulled = try #require(second.mainContext.fetch(FetchDescriptor<Visit>()).first)
        #expect(pulled.queueDuration == .under60)
        #expect(pulled.visibility == .friends)
        #expect(pulled.totalPrice == 360)
        #expect(pulled.pricePerPerson == 120)
        #expect(pulled.diningOccasionText == "工作简餐")

        var firstEdit = VisitDraft(visit: visit)
        firstEdit.queueDuration = .noWait
        try store.update(visit, draft: firstEdit)
        try await SyncEngine(context: first.mainContext, api: server).synchronize()

        var staleEdit = VisitDraft(visit: pulled)
        staleEdit.visibility = .public
        try LocalTasteMapStore(context: second.mainContext).update(pulled, draft: staleEdit)
        try await SyncEngine(context: second.mainContext, api: server).synchronize()
        #expect(try second.mainContext.fetch(FetchDescriptor<SyncMutation>()).contains {
            $0.entityType == .visit && $0.state == .conflicted
        })

        try store.delete(visit)
        try await SyncEngine(context: first.mainContext, api: server).synchronize()
        try await SyncEngine(context: second.mainContext, api: server).synchronize()
        #expect(pulled.deletedAt != nil)
    }

    private var p2EKeys: [String] {
        [
            "visibility", "totalPrice", "paymentMode", "pricePerPerson", "queueDuration",
            "diningOccasions", "diningOccasionText", "valueTags", "environmentTags",
            "serviceTags", "noiseLevel", "diningDuration", "portionLevel",
            "transportConvenience", "specialNotes",
        ]
    }

    private func baseVisitJSONObject() throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(
            SyncRecordMapper.visitRecord(
                Visit(restaurantId: UUID()),
                restaurantRemoteID: "restaurant-p2e"
            )
        )) as? [String: Any])
    }

    private func completeDraft() -> VisitDraft {
        VisitDraft(
            diningMode: .dineIn,
            partySize: 3,
            rating: 4.5,
            valueRating: 5,
            environmentRating: 4,
            serviceRating: 3.5,
            myActualSpend: 120,
            totalPrice: 360,
            visibility: .friends,
            paymentMode: .aa,
            queueDuration: .under60,
            diningOccasions: [.friends, .other],
            diningOccasionText: "工作简餐",
            valueTags: ["合理"],
            environmentTags: ["舒适"],
            serviceTags: ["周到"],
            noiseLevel: .normal,
            diningDuration: .under30,
            portionLevel: .generous,
            transportConvenience: .veryConvenient,
            specialNotes: "现场取号",
            note: "保留 P1 备注"
        )
    }

    private func insertRestaurant(_ context: ModelContext) -> Restaurant {
        let restaurant = Restaurant(
            name: "P2-E 测试餐厅",
            address: "杭州",
            latitude: 30,
            longitude: 120,
            remoteID: "p2e-restaurant-\(UUID().uuidString.lowercased())"
        )
        context.insert(restaurant)
        try? context.save()
        return restaurant
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("taste-map-p2e-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
