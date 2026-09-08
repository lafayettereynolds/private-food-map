import Foundation
import SwiftData
import Testing
@testable import TasteMap

@Suite("P1-C Visit core flow", .serialized)
@MainActor
struct VisitCoreFlowTests {
    @Test("Visit Draft validates nullable and invalid values")
    func draftValidation() throws {
        #expect(try VisitDraft().validated().partySize == nil)
        #expect(try VisitDraft.partySize(from: "") == nil)
        #expect(try VisitDraft.spend(from: "") == nil)
        #expect(try VisitDraft.spend(from: "128.50", locale: Locale(identifier: "en_US")) == Decimal(string: "128.50"))
        #expect(throws: VisitDraftValidationError.invalidPartySize) {
            try VisitDraft.partySize(from: "0")
        }
        #expect(throws: VisitDraftValidationError.invalidPartySize) {
            try VisitDraft.partySize(from: "1.5")
        }
        #expect(throws: VisitDraftValidationError.negativeSpend) {
            try VisitDraft.spend(from: "-1", locale: Locale(identifier: "en_US"))
        }
        #expect(throws: VisitDraftValidationError.invalidRating) {
            try VisitDraft(rating: 4.2).validated()
        }
    }

    @Test("Complete and minimal Visit creation use one draft path")
    func createCompleteAndMinimalVisits() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let restaurant = makeRestaurant(status: .wantToGo)
        context.insert(restaurant)
        try context.save()
        let store = LocalTasteMapStore(context: context)
        let moment = Date(timeIntervalSince1970: 1_787_592_000)

        let complete = try store.createVisit(
            restaurantId: restaurant.id,
            draft: VisitDraft(
                visitedAt: moment,
                diningMode: .takeout,
                partySize: 3,
                rating: 4.5,
                myActualSpend: 126.5,
                note: "完整记录"
            )
        )
        let minimal = try store.createVisit(restaurantId: restaurant.id, draft: VisitDraft())

        #expect(complete.visitedAt == moment)
        #expect(complete.diningMode == .takeout)
        #expect(complete.partySize == 3)
        #expect(complete.rating == 4.5)
        #expect(complete.myActualSpend == Decimal(string: "126.5"))
        #expect(complete.note == "完整记录")
        #expect(minimal.id != complete.id)
        #expect(minimal.rating == nil)
        #expect(minimal.myActualSpend == nil)
        #expect(minimal.partySize == nil)
        #expect(minimal.diningMode == .dineIn)
        #expect(restaurant.status == .visited)
        #expect(try context.fetch(FetchDescriptor<Restaurant>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<Visit>()).count == 2)
    }

    @Test("Editing can change and clear every P1-C field without changing identity")
    func editAndClearFields() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let restaurant = makeRestaurant()
        let visit = Visit(
            restaurantId: restaurant.id,
            rating: 4,
            note: "原备注",
            myActualSpend: 80,
            diningMode: .dineIn,
            partySize: 2,
            createdAt: Date(timeIntervalSince1970: 10),
            remoteID: "visit-edit-core",
            serverVersion: 2,
            syncStatus: .synced
        )
        context.insert(restaurant)
        context.insert(visit)
        try context.save()
        let originalID = visit.id
        let originalRemoteID = visit.remoteID
        let originalRestaurantID = visit.restaurantId
        let originalCreatedAt = visit.createdAt

        try LocalTasteMapStore(context: context).update(
            visit,
            draft: VisitDraft(
                visitedAt: Date(timeIntervalSince1970: 20),
                diningMode: .takeout,
                partySize: 4,
                rating: 5,
                myActualSpend: 160,
                note: "更新备注"
            )
        )
        #expect(visit.diningMode == .takeout)
        #expect(visit.partySize == 4)
        #expect(visit.rating == 5)
        #expect(visit.myActualSpend == 160)
        #expect(visit.note == "更新备注")

        try LocalTasteMapStore(context: context).update(
            visit,
            draft: VisitDraft(
                visitedAt: visit.visitedAt,
                diningMode: .dineIn,
                partySize: nil,
                rating: nil,
                myActualSpend: nil,
                note: ""
            )
        )
        #expect(visit.id == originalID)
        #expect(visit.remoteID == originalRemoteID)
        #expect(visit.restaurantId == originalRestaurantID)
        #expect(visit.createdAt == originalCreatedAt)
        #expect(visit.diningMode == .dineIn)
        #expect(visit.partySize == nil)
        #expect(visit.rating == nil)
        #expect(visit.myActualSpend == nil)
        #expect(visit.note == nil)
        #expect(try context.fetch(FetchDescriptor<Visit>()).count == 1)
    }

    @Test("Deleting the last Visit deletes Restaurant and queues its tombstone")
    func deletingLastVisitRemovesVisitedMembership() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let restaurant = makeRestaurant()
        let visit = Visit(restaurantId: restaurant.id, remoteID: "last-visit", serverVersion: 1, syncStatus: .synced)
        context.insert(restaurant)
        context.insert(visit)
        try context.save()
        #expect(RestaurantVisitStatePolicy.partition(restaurants: [restaurant], visits: [visit]).visited.count == 1)
        let deletedRestaurantID = try LocalTasteMapStore(context: context).delete(visit)
        #expect(deletedRestaurantID == restaurant.id)
        let remaining = try context.fetch(FetchDescriptor<Visit>())
        let partition = RestaurantVisitStatePolicy.partition(restaurants: [restaurant], visits: remaining)
        #expect(partition.visited.isEmpty)
        #expect(partition.wantToGo.isEmpty)
        #expect(restaurant.deletedAt != nil)
        #expect(try context.fetch(FetchDescriptor<Restaurant>()).count == 1)
        let reopened = ModelContext(container)
        #expect(try reopened.fetch(FetchDescriptor<Restaurant>()).allSatisfy { $0.deletedAt != nil })
        let deletes = try SwiftDataSyncQueue(context: reopened, ownerUserID: restaurant.ownerUserID).allMutations()
        #expect(deletes.contains { $0.entityType == .visit && $0.operation == .delete && $0.entityID == "last-visit" })
        #expect(deletes.contains { $0.entityType == .restaurant && $0.operation == .delete && $0.entityID == restaurant.remoteID })
        #expect(RestaurantVisitStatePolicy.partition(
            restaurants: try reopened.fetch(FetchDescriptor<Restaurant>()),
            visits: try reopened.fetch(FetchDescriptor<Visit>())
        ).visited.isEmpty)
    }

    @Test("Repeated Visits produce one visited Restaurant and stale zero-Visit status produces none")
    func visitMembershipCountsRestaurantsNotVisits() {
        let restaurant = makeRestaurant()
        let visits = (0..<3).map { _ in Visit(restaurantId: restaurant.id) }
        #expect(RestaurantVisitStatePolicy.partition(restaurants: [restaurant], visits: visits).visited.count == 1)
        #expect(RestaurantVisitStatePolicy.partition(restaurants: [restaurant], visits: []).visited.isEmpty)
    }

    @Test("Soft delete hides only the selected Visit and keeps Restaurant visited")
    func softDeleteAndStatistics() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let restaurant = makeRestaurant()
        let deleted = Visit(
            restaurantId: restaurant.id,
            rating: 1,
            myActualSpend: 999,
            remoteID: "visit-delete-core",
            serverVersion: 2,
            syncStatus: .synced
        )
        let retained = Visit(
            restaurantId: restaurant.id,
            rating: 4.5,
            myActualSpend: 100,
            remoteID: "visit-retained-core",
            serverVersion: 1,
            syncStatus: .synced
        )
        context.insert(restaurant)
        context.insert(deleted)
        context.insert(retained)
        try context.save()

        try LocalTasteMapStore(context: context).delete(deleted)
        let presentation = RestaurantDetailPresentation(
            restaurantID: restaurant.id,
            visits: try context.fetch(FetchDescriptor<Visit>())
        )

        #expect(deleted.deletedAt != nil)
        #expect(presentation.activeVisits.map(\.id) == [retained.id])
        #expect(presentation.visitCount == 1)
        #expect(presentation.averageRating == 4.5)
        #expect(presentation.totalSpend == 100)
        #expect(restaurant.status == .visited)
        #expect(restaurant.deletedAt == nil)
    }

    @Test("Offline create survives restart with its queued mutation and fields")
    func offlinePersistenceAndQueue() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TasteMapP1C-\(UUID().uuidString)")
            .appendingPathExtension("store")
        defer { removeStoreFiles(at: storeURL) }
        let restaurantID: UUID
        let visitID: UUID

        do {
            let container = try persistentContainer(at: storeURL)
            let context = container.mainContext
            let restaurant = makeRestaurant(status: .wantToGo)
            restaurantID = restaurant.id
            context.insert(restaurant)
            try context.save()
            let visit = try LocalTasteMapStore(context: context).createVisit(
                restaurantId: restaurant.id,
                draft: VisitDraft(
                    diningMode: .takeout,
                    partySize: nil,
                    rating: nil,
                    myActualSpend: nil,
                    note: "离线记录"
                )
            )
            visitID = visit.id
        }

        let reopened = try persistentContainer(at: storeURL)
        let context = reopened.mainContext
        let restaurant = try #require(context.fetch(FetchDescriptor<Restaurant>()).first { $0.id == restaurantID })
        let visit = try #require(context.fetch(FetchDescriptor<Visit>()).first { $0.id == visitID })
        let mutations = try context.fetch(FetchDescriptor<SyncMutation>())

        #expect(restaurant.status == .visited)
        #expect(visit.diningMode == .takeout)
        #expect(visit.partySize == nil)
        #expect(visit.rating == nil)
        #expect(visit.myActualSpend == nil)
        #expect(visit.note == "离线记录")
        #expect(mutations.contains { $0.entityType == .visit && $0.entityID == visit.remoteID })
    }

    @Test("Restaurant deletion after failed uploads survives reopening the persistent store")
    func restaurantDeleteSurvivesReopen() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TasteMapDeleteReopen-\(UUID().uuidString)")
            .appendingPathExtension("store")
        defer { removeStoreFiles(at: storeURL) }
        let restaurantID: UUID
        do {
            let container = try persistentContainer(at: storeURL)
            let context = container.mainContext
            let restaurant = makeRestaurant()
            restaurant.serverVersion = 0
            restaurantID = restaurant.id
            context.insert(restaurant)
            let queue = SwiftDataSyncQueue(context: context, ownerUserID: restaurant.ownerUserID)
            let upload = try queue.enqueueUpsert(entityType: .restaurant,
                entityID: restaurant.remoteID!, baseVersion: 0,
                payload: SyncRecordMapper.restaurantPayload(restaurant))
            upload.retryCount = 35
            upload.lastError = "retryable:http_500"
            upload.nextRetryAt = .distantFuture
            try LocalTasteMapStore(context: context).delete(restaurant)
        }
        let reopened = try persistentContainer(at: storeURL)
        let restaurants = try reopened.mainContext.fetch(FetchDescriptor<Restaurant>())
        let deleted = try #require(restaurants.first { $0.id == restaurantID })
        #expect(deleted.deletedAt != nil)
        #expect(RestaurantVisitStatePolicy.partition(restaurants: restaurants, visits: []).visited.isEmpty)
        let mutations = try reopened.mainContext.fetch(FetchDescriptor<SyncMutation>())
        #expect(mutations.contains { $0.operation == .delete && $0.entityID == deleted.remoteID })
    }

    @Test("Offline edit coalesces its Visit mutation and offline delete cannot affect another Visit")
    func offlineEditAndDelete() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let restaurant = makeRestaurant()
        context.insert(restaurant)
        try context.save()
        let store = LocalTasteMapStore(context: context)
        let first = try store.createVisit(restaurantId: restaurant.id, draft: VisitDraft())
        let second = try store.createVisit(restaurantId: restaurant.id, draft: VisitDraft(rating: 4))

        try store.update(first, draft: VisitDraft(diningMode: .takeout, partySize: 2, note: "离线编辑"))
        let firstMutations = try context.fetch(FetchDescriptor<SyncMutation>())
            .filter { $0.entityType == .visit && $0.entityID == first.remoteID }
        #expect(firstMutations.count == 1)
        let payload = try #require(firstMutations.first?.payload)
        let contract = try JSONDecoder().decode(VisitSyncContractV1.self, from: payload)
        #expect(contract.diningMode == .takeout)
        #expect(contract.partySize == 2)

        try store.delete(first)
        let remainingVisits = try context.fetch(FetchDescriptor<Visit>())
        let remainingMutations = try context.fetch(FetchDescriptor<SyncMutation>())
        #expect(!remainingVisits.contains { $0.id == first.id })
        #expect(remainingVisits.contains { $0.id == second.id })
        #expect(!remainingMutations.contains {
            $0.entityType == .visit && $0.entityID == first.remoteID
        })
    }

    private func makeRestaurant(status: RestaurantStatus = .visited) -> Restaurant {
        Restaurant(
            name: "P1-C 测试餐厅",
            address: "Development local only",
            latitude: 30.259,
            longitude: 120.168,
            appleMapItemIdentifier: "apple-p1c-core",
            city: "杭州",
            status: status,
            remoteID: "restaurant-p1c-core",
            syncStatus: .pending
        )
    }

    private func persistentContainer(at url: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "TasteMapP1CTests",
            schema: TasteMapPersistence.schema,
            url: url,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: TasteMapPersistence.schema,
            configurations: [configuration]
        )
    }

    private func removeStoreFiles(at url: URL) {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(atPath: url.path + "-shm")
        try? FileManager.default.removeItem(atPath: url.path + "-wal")
    }
}
