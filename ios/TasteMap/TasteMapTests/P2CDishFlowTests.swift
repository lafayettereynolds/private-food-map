import Foundation
import SwiftData
import Testing
@testable import TasteMap

@Suite("P2-C Restaurant Dish recording", .serialized)
@MainActor
struct P2CDishFlowTests {
    @Test("VisitDish JSON has explicit required IDs and nullable tombstone")
    func visitDishContract() throws {
        let record = try VisitDishSyncContractV1(
            id: "visit-dish-1", userId: "client-claimed-owner",
            restaurantId: "restaurant-1", visitId: "visit-1", dishId: "dish-1",
            sortOrder: 0, createdAt: instant, updatedAt: instant, deletedAt: nil
        )
        let data = try JSONEncoder().encode(record)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object.keys.contains("deletedAt"))
        #expect(try JSONDecoder().decode(VisitDishSyncContractV1.self, from: data) == record)
        var missingNullable = object
        missingNullable.removeValue(forKey: "deletedAt")
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                VisitDishSyncContractV1.self,
                from: JSONSerialization.data(withJSONObject: missingNullable)
            )
        }
        #expect(throws: RichRecordContractError.invalidVisitDish) {
            _ = try VisitDishSyncContractV1(
                id: "visit-dish-1", userId: "owner", restaurantId: "restaurant-1",
                visitId: "visit-1", dishId: "", sortOrder: 0,
                createdAt: instant, updatedAt: instant, deletedAt: nil
            )
        }
    }

    @Test("Dish draft trims required name and preserves nullable rating and price")
    func draftValidation() throws {
        let draft = try DishDraft(name: "  招牌牛肉  ", taste: "  值得再点  ").validated()
        #expect(draft.name == "招牌牛肉")
        #expect(draft.taste == "值得再点")
        #expect(draft.rating == nil)
        #expect(draft.price == nil)
        #expect(throws: DishDraftError.missingName) { try DishDraft(name: " \n ").validated() }
        #expect(throws: DishDraftError.invalidRating) { try DishDraft(name: "菜", rating: 4.2).validated() }
        #expect(throws: DishDraftError.invalidPrice) { try DishDraft(name: "菜", price: -1).validated() }
    }

    @Test("One normalized Restaurant Dish is reused by multiple Visits")
    func normalizedReuseAcrossVisits() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let parents = insertParents(context)
        let store = LocalDishStore(context: context)

        _ = try store.reconcile(
            restaurantID: parents.restaurant.id,
            visitID: parents.first.id,
            drafts: [DishDraft(name: "  HOUSE　Beef  ", taste: "值得再点", rating: nil, price: 0)]
        )
        let dish = try #require(context.fetch(FetchDescriptor<Dish>()).first)
        _ = try store.reconcile(
            restaurantID: parents.restaurant.id,
            visitID: parents.second.id,
            drafts: [DishDraft(name: "house beef", rating: 4.5, price: 88)]
        )

        #expect(try context.fetch(FetchDescriptor<Dish>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<VisitDish>()).count == 2)
        #expect(dish.rating == 4.5)
        #expect(dish.price == 88)
        #expect(dish.remoteID == DishIdentity.dishRemoteID(
            restaurantRemoteID: try #require(parents.restaurant.remoteID),
            normalizedName: "house beef"
        ))
    }

    @Test("Editing updates the canonical Dish without changing Visit spend")
    func canonicalEditDoesNotChangeVisitSpend() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let parents = insertParents(context)
        parents.first.myActualSpend = 150
        let store = LocalDishStore(context: context)
        let draftID = UUID()
        let first = try store.reconcile(
            restaurantID: parents.restaurant.id,
            visitID: parents.first.id,
            drafts: [DishDraft(id: draftID, name: "寿司拼盘")]
        )
        let dish = try #require(first[draftID])
        _ = try store.reconcile(
            restaurantID: parents.restaurant.id,
            visitID: parents.first.id,
            drafts: [DishDraft(id: draftID, dishID: dish.id, name: "特选寿司拼盘", taste: "鱼很新鲜", rating: 5, price: 300)]
        )

        #expect(dish.name == "特选寿司拼盘")
        #expect(dish.taste == "鱼很新鲜")
        #expect(dish.rating == 5)
        #expect(dish.price == 300)
        #expect(parents.first.myActualSpend == 150)
    }

    @Test("Renaming into an existing name reuses its canonical Dish")
    func renameIntoExistingDish() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let parents = insertParents(context)
        let store = LocalDishStore(context: context)
        let firstDraftID = UUID()
        let secondDraftID = UUID()
        let firstResult = try store.reconcile(
            restaurantID: parents.restaurant.id,
            visitID: parents.first.id,
            drafts: [DishDraft(id: firstDraftID, name: "牛肉饭")]
        )
        let firstDish = try #require(firstResult[firstDraftID])
        let secondResult = try store.reconcile(
            restaurantID: parents.restaurant.id,
            visitID: parents.second.id,
            drafts: [DishDraft(id: secondDraftID, name: "寿司拼盘")]
        )
        let secondDish = try #require(secondResult[secondDraftID])

        _ = try store.reconcile(
            restaurantID: parents.restaurant.id,
            visitID: parents.first.id,
            drafts: [DishDraft(dishID: firstDish.id, name: "  寿司拼盘 ")]
        )

        let activeAssociations = try context.fetch(FetchDescriptor<VisitDish>())
            .filter { $0.deletedAt == nil }
        #expect(activeAssociations.count == 2)
        #expect(activeAssociations.allSatisfy { $0.dishId == secondDish.id })
        #expect(try context.fetch(FetchDescriptor<Dish>()).filter {
            $0.deletedAt == nil && DishIdentity.normalizedName($0.name) == "寿司拼盘"
        }.count == 1)
    }

    @Test("Reusing a retired name keeps remote IDs unique")
    func retiredNameGetsFreshRemoteID() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let parents = insertParents(context)
        let store = LocalDishStore(context: context)
        let originalResult = try store.reconcile(
            restaurantID: parents.restaurant.id,
            visitID: parents.first.id,
            drafts: [DishDraft(name: "原菜名")]
        )
        let original = try #require(originalResult.values.first)
        let originalRemoteID = try #require(original.remoteID)
        _ = try store.reconcile(
            restaurantID: parents.restaurant.id,
            visitID: parents.first.id,
            drafts: [DishDraft(dishID: original.id, name: "新菜名")]
        )

        let reusedResult = try store.reconcile(
            restaurantID: parents.restaurant.id,
            visitID: parents.second.id,
            drafts: [DishDraft(name: "原菜名")]
        )
        let reused = try #require(reusedResult.values.first)
        #expect(reused.id != original.id)
        #expect(reused.remoteID != originalRemoteID)
        #expect(try context.fetch(FetchDescriptor<Dish>()).count == 2)
    }

    @Test("Removing one Visit association keeps the Dish and other Visit history")
    func removingAssociationKeepsDish() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let parents = insertParents(context)
        let store = LocalDishStore(context: context)
        _ = try store.reconcile(
            restaurantID: parents.restaurant.id, visitID: parents.first.id,
            drafts: [DishDraft(name: "招牌牛肉")]
        )
        let dish = try #require(context.fetch(FetchDescriptor<Dish>()).first)
        _ = try store.reconcile(
            restaurantID: parents.restaurant.id, visitID: parents.second.id,
            drafts: [DishDraft(dishID: dish.id, name: dish.name)]
        )

        _ = try store.reconcile(
            restaurantID: parents.restaurant.id, visitID: parents.first.id, drafts: []
        )
        #expect(try context.fetch(FetchDescriptor<Dish>()).count == 1)
        let active = try context.fetch(FetchDescriptor<VisitDish>()).filter { $0.deletedAt == nil }
        #expect(active.count == 1)
        #expect(active.first?.visitId == parents.second.id)
    }

    @Test("Deleting a Visit removes only its associations")
    func deletingVisitKeepsOtherDishHistory() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let parents = insertParents(context)
        let store = LocalDishStore(context: context)
        _ = try store.reconcile(
            restaurantID: parents.restaurant.id, visitID: parents.first.id,
            drafts: [DishDraft(name: "炒饭")]
        )
        let dish = try #require(context.fetch(FetchDescriptor<Dish>()).first)
        _ = try store.reconcile(
            restaurantID: parents.restaurant.id, visitID: parents.second.id,
            drafts: [DishDraft(dishID: dish.id, name: dish.name)]
        )

        try LocalTasteMapStore(context: context).delete(parents.first)
        #expect(try context.fetch(FetchDescriptor<Dish>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<VisitDish>()).filter { $0.deletedAt == nil }.map(\.visitId) == [parents.second.id])
    }

    @Test("Synced association removal creates a tombstone mutation")
    func associationTombstone() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let parents = insertParents(context)
        let store = LocalDishStore(context: context)
        _ = try store.reconcile(
            restaurantID: parents.restaurant.id, visitID: parents.first.id,
            drafts: [DishDraft(name: "小火锅")]
        )
        let association = try #require(context.fetch(FetchDescriptor<VisitDish>()).first)
        association.serverVersion = 3
        association.syncStatus = .synced
        try SwiftDataSyncQueue(context: context).removeMutations(
            entityType: .visitDish,
            entityID: try #require(association.remoteID)
        )
        try context.save()

        try store.remove(association)
        #expect(association.deletedAt != nil)
        #expect(try context.fetch(FetchDescriptor<Dish>()).count == 1)
        let mutation = try #require(context.fetch(FetchDescriptor<SyncMutation>()).first {
            $0.entityType == .visitDish && $0.operation == .delete
        })
        #expect(mutation.baseVersion == 3)
    }

    @Test("Dish association and offline mutation queue survive restart")
    func restartPersistence() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("p2c.store")
        var container: ModelContainer? = try TasteMapPersistence.makeContainer(storageURL: url)
        let context = try #require(container?.mainContext)
        let parents = insertParents(context)
        _ = try LocalDishStore(context: context).reconcile(
            restaurantID: parents.restaurant.id, visitID: parents.first.id,
            drafts: [DishDraft(name: "离线保存的菜", taste: "重启仍在")]
        )
        container = nil

        let reopened = try TasteMapPersistence.makeContainer(storageURL: url)
        #expect(try reopened.mainContext.fetch(FetchDescriptor<Dish>()).first?.name == "离线保存的菜")
        #expect(try reopened.mainContext.fetch(FetchDescriptor<VisitDish>()).count == 1)
        #expect(try reopened.mainContext.fetch(FetchDescriptor<SyncMutation>()).contains { $0.entityType == .visitDish })
    }

    @Test("P2-B store opens with the additive VisitDish schema")
    func additiveSwiftDataSchema() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("p2b.store")
        let p2BSchema = Schema([
            Restaurant.self, Visit.self, Dish.self, PhotoAsset.self,
            SyncMutation.self, SyncCheckpoint.self,
        ])
        var oldContainer: ModelContainer? = try ModelContainer(
            for: p2BSchema,
            configurations: [ModelConfiguration("P2B", schema: p2BSchema, url: url, cloudKitDatabase: .none)]
        )
        let restaurant = Restaurant(
            name: "P2-B 保留餐厅", address: "杭州", latitude: 30, longitude: 120,
            remoteID: "p2b-restaurant"
        )
        let visit = Visit(restaurantId: restaurant.id, remoteID: "p2b-visit")
        let dish = Dish(
            restaurantId: restaurant.id, visitId: visit.id, name: "P2-B 菜品",
            remoteID: "p2b-dish", serverVersion: 1, syncStatus: .synced
        )
        oldContainer?.mainContext.insert(restaurant)
        oldContainer?.mainContext.insert(visit)
        oldContainer?.mainContext.insert(dish)
        try oldContainer?.mainContext.save()
        oldContainer = nil

        let migrated = try TasteMapPersistence.makeContainer(storageURL: url)
        try LocalDishStore(context: migrated.mainContext).bootstrapLegacyAssociations()
        #expect(try migrated.mainContext.fetch(FetchDescriptor<Dish>()).first?.name == "P2-B 菜品")
        #expect(try migrated.mainContext.fetch(FetchDescriptor<VisitDish>()).first?.remoteID == "legacy:p2b-dish:p2b-visit")
    }

    @Test("One PhotoAsset can represent a Dish without copying binary metadata")
    func dishPhotoRelationshipReusesAsset() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let parents = insertParents(context)
        let draftID = UUID()
        let mapping = try LocalDishStore(context: context).reconcile(
            restaurantID: parents.restaurant.id, visitID: parents.first.id,
            drafts: [DishDraft(id: draftID, name: "有照片的菜")]
        )
        let dish = try #require(mapping[draftID])
        let files = try LocalPhotoFileStore(rootURL: directory)
        let photoStore = LocalDishPhotoStore(context: context, photoFiles: files)
        let photo = try await photoStore.createLocalPhoto(
            data: Data([1, 2, 3]), mimeType: "image/jpeg", kind: .visit,
            restaurantId: parents.restaurant.id, visitId: parents.first.id
        )
        let originalID = photo.id
        let originalPath = photo.localFileRelativePath

        try photoStore.setDishRelationship(photo, dish: dish)
        #expect(try context.fetch(FetchDescriptor<PhotoAsset>()).count == 1)
        #expect(photo.id == originalID)
        #expect(photo.localFileRelativePath == originalPath)
        #expect(photo.kind == .dish)
        #expect(photo.dishId == dish.id)
    }

    @Test("Restaurant detail groups legacy duplicates and sorts by frequency then recency")
    func restaurantDetailPresentation() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let parents = insertParents(context)
        parents.first.visitedAt = Date(timeIntervalSince1970: 100)
        parents.second.visitedAt = Date(timeIntervalSince1970: 200)
        let canonical = Dish(
            restaurantId: parents.restaurant.id, visitId: parents.first.id,
            name: "牛肉饭", remoteID: "dish-one"
        )
        let legacyDuplicate = Dish(
            restaurantId: parents.restaurant.id, visitId: parents.second.id,
            name: " 牛肉饭 ", remoteID: "dish-two"
        )
        context.insert(canonical)
        context.insert(legacyDuplicate)
        context.insert(VisitDish(
            restaurantId: parents.restaurant.id, visitId: parents.first.id,
            dishId: canonical.id, remoteID: "association-one"
        ))
        context.insert(VisitDish(
            restaurantId: parents.restaurant.id, visitId: parents.second.id,
            dishId: legacyDuplicate.id, remoteID: "association-two"
        ))
        try context.save()

        let summaries = RestaurantDishPresentation.summaries(
            restaurantID: parents.restaurant.id,
            dishes: [canonical, legacyDuplicate],
            associations: try context.fetch(FetchDescriptor<VisitDish>()),
            visits: [parents.first, parents.second], photos: []
        )
        #expect(summaries.count == 1)
        #expect(summaries.first?.visitCount == 2)
        #expect(summaries.first?.latestVisit?.id == parents.second.id)
    }

    @Test("Sync pushes parents before Dish association and hydrates a fresh client")
    func syncRoundTripAndTwoClientEdit() async throws {
        let source = try TasteMapPersistence.makeContainer(inMemory: true)
        let sourceContext = source.mainContext
        let local = LocalTasteMapStore(context: sourceContext)
        let restaurant = try local.restaurant(for: candidate(), among: [])
        let visit = try local.createVisit(restaurantId: restaurant.id)
        _ = try LocalDishStore(context: sourceContext).reconcile(
            restaurantID: restaurant.id, visitID: visit.id,
            drafts: [DishDraft(name: "共享菜品", taste: "第一台设备", rating: nil, price: nil)]
        )
        let api = P2CDishSyncAPI()
        try await SyncEngine(context: sourceContext, api: api).synchronize()
        #expect(api.pushOrder == [.restaurant, .visit, .dish, .visitDish])

        let second = try TasteMapPersistence.makeContainer(inMemory: true)
        try await SyncEngine(context: second.mainContext, api: api).synchronize()
        let secondDish = try #require(second.mainContext.fetch(FetchDescriptor<Dish>()).first)
        let secondVisit = try #require(second.mainContext.fetch(FetchDescriptor<Visit>()).first)
        let secondRestaurant = try #require(second.mainContext.fetch(FetchDescriptor<Restaurant>()).first)
        #expect(try second.mainContext.fetch(FetchDescriptor<VisitDish>()).count == 1)

        _ = try LocalDishStore(context: second.mainContext).reconcile(
            restaurantID: secondRestaurant.id, visitID: secondVisit.id,
            drafts: [DishDraft(dishID: secondDish.id, name: secondDish.name, taste: "第二台设备更新", rating: 4.5)]
        )
        try await SyncEngine(context: second.mainContext, api: api).synchronize()
        try await SyncEngine(context: sourceContext, api: api).synchronize()
        #expect(try sourceContext.fetch(FetchDescriptor<Dish>()).first?.taste == "第二台设备更新")
        #expect(try sourceContext.fetch(FetchDescriptor<Dish>()).first?.rating == 4.5)
    }

    private func insertParents(
        _ context: ModelContext
    ) -> (restaurant: Restaurant, first: Visit, second: Visit) {
        let restaurant = Restaurant(
            name: "P2-C 测试餐厅", address: "杭州", latitude: 30, longitude: 120,
            remoteID: "p2c-restaurant"
        )
        let first = Visit(restaurantId: restaurant.id, remoteID: "p2c-visit-1")
        let second = Visit(restaurantId: restaurant.id, remoteID: "p2c-visit-2")
        context.insert(restaurant)
        context.insert(first)
        context.insert(second)
        try? context.save()
        return (restaurant, first, second)
    }

    private func candidate() -> RestaurantCandidate {
        RestaurantCandidate(
            name: "P2-C Apple Maps 餐厅", address: "杭州中山路 1 号",
            latitude: 30.25, longitude: 120.16,
            appleMapItemIdentifier: "p2c-apple-only"
        )
    }

    private var instant: String { "2026-08-28T08:00:00.000Z" }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("taste-map-p2c-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

@MainActor
private final class P2CDishSyncAPI: SyncAPI {
    private(set) var pushOrder: [SyncEntityType] = []
    private var restaurants: [String: RestaurantSyncRecordEnvelopeV1] = [:]
    private var visits: [String: VisitSyncRecordEnvelopeV1] = [:]
    private var dishes: [String: DishSyncRecordEnvelopeV1] = [:]
    private var visitDishes: [String: VisitDishSyncRecordEnvelopeV1] = [:]
    private var tombstones: [String: SyncTombstoneV1] = [:]
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
            pushOrder.append(mutation.entityType)
            revision += 1
            let version = mutation.baseVersion + 1
            if let payload = mutation.payload {
                switch payload {
                case .restaurant(let record):
                    restaurants[mutation.entityId] = .init(serverVersion: version, record: record)
                case .visit(let record):
                    visits[mutation.entityId] = .init(serverVersion: version, record: record)
                case .dish(let record):
                    dishes[mutation.entityId] = .init(serverVersion: version, record: record)
                case .visitDish(let record):
                    visitDishes[mutation.entityId] = .init(serverVersion: version, record: record)
                case .photo:
                    break
                case .companion, .recommendationSource, .profile,
                     .restaurantList, .restaurantListItem:
                    break
                }
                tombstones.removeValue(forKey: mutation.entityId)
            } else {
                switch mutation.entityType {
                case .restaurant: restaurants.removeValue(forKey: mutation.entityId)
                case .visit: visits.removeValue(forKey: mutation.entityId)
                case .dish: dishes.removeValue(forKey: mutation.entityId)
                case .visitDish: visitDishes.removeValue(forKey: mutation.entityId)
                case .photo: break
                case .companion, .recommendationSource, .profile,
                     .restaurantList, .restaurantListItem: break
                }
                tombstones[mutation.entityId] = SyncTombstoneV1(
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
            return acknowledgement
        }
        return SyncPushResponseV1(
            apiVersion: 1, acknowledgements: acknowledgements,
            serverTime: "2026-08-28T08:00:00.000Z"
        )
    }

    func pull(cursor: String, limit: Int) async throws -> SyncPullResponseV1 {
        let isCurrent = cursor == String(revision)
        return SyncPullResponseV1(
            apiVersion: 1, schemaVersion: 1,
            restaurants: isCurrent ? [] : Array(restaurants.values),
            visits: isCurrent ? [] : Array(visits.values),
            dishes: isCurrent ? [] : Array(dishes.values),
            visitDishes: isCurrent ? [] : Array(visitDishes.values),
            tombstones: isCurrent ? [] : Array(tombstones.values),
            nextCursor: String(revision), hasMore: false,
            serverTime: "2026-08-28T08:00:00.000Z"
        )
    }
}
