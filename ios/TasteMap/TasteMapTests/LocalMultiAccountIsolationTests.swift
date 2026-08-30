import Foundation
import SwiftData
import Testing
@testable import TasteMap

@Suite("Local multi-account isolation")
@MainActor
struct LocalMultiAccountIsolationTests {
    private let userA = "tm_account_a"
    private let userB = "tm_account_b"

    @Test("A to B to A projections isolate Map, List, Profile, Search and child records")
    func projectionsAreAccountScoped() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let a = graph(owner: userA, name: "A 私人餐厅")
        let b = graph(owner: userB, name: "B 私人餐厅")
        insert(a, into: context)
        insert(b, into: context)
        try context.save()

        let all = try fetchedGraph(context)
        let snapshotA = ProfileOwnedContentScope.capture(
            currentUserID: userA,
            restaurants: all.restaurants, visits: all.visits, photos: all.photos,
            dishes: all.dishes, visitDishes: all.visitDishes
        )
        let snapshotB = ProfileOwnedContentScope.capture(
            currentUserID: userB,
            restaurants: all.restaurants, visits: all.visits, photos: all.photos,
            dishes: all.dishes, visitDishes: all.visitDishes
        )
        let returnedA = ProfileOwnedContentScope.capture(
            currentUserID: userA,
            restaurants: all.restaurants, visits: all.visits, photos: all.photos,
            dishes: all.dishes, visitDishes: all.visitDishes
        )

        #expect(snapshotA.restaurants.map(\.name) == ["A 私人餐厅"])
        #expect(snapshotB.restaurants.map(\.name) == ["B 私人餐厅"])
        #expect(returnedA.restaurants.map(\.name) == ["A 私人餐厅"])
        #expect(snapshotA.visits.count == 1 && snapshotA.photos.count == 1)
        #expect(snapshotB.dishes.count == 1 && snapshotB.visitDishes.count == 1)
        #expect(RestaurantDeduplicator.match(
            for: RestaurantCandidate(
                name: "B 私人餐厅", address: "B Road", latitude: 30, longitude: 120
            ),
            in: snapshotA.restaurants
        ) == nil)
    }

    @Test("Writes and mutation queue inherit the authenticated Taste Map owner")
    func writesAndQueueAreScoped() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let store = LocalTasteMapStore(context: context)
        let restaurant = try store.addToWantToGo(
            candidate: RestaurantCandidate(
                name: "Apple-only", address: "West Lake", latitude: 30, longitude: 120,
                appleMapItemIdentifier: "apple-only-account-a"
            ),
            among: [],
            actorUserID: userA
        )
        let visit = try store.createVisit(
            restaurantId: restaurant.id,
            draft: VisitDraft(note: "A only"),
            actorUserID: userA
        )

        #expect(restaurant.ownerUserID == userA)
        #expect(visit.ownerUserID == userA)
        let aMutations = try SwiftDataSyncQueue(context: context, ownerUserID: userA).allMutations()
        let bMutations = try SwiftDataSyncQueue(context: context, ownerUserID: userB).allMutations()
        #expect(aMutations.count == 2)
        #expect(bMutations.isEmpty)
        #expect(aMutations.allSatisfy { $0.ownerUserID == userA })
    }

    @Test("Account delete removes only current rows, photos, queues and checkpoints")
    func accountDeletionPreservesOtherAccount() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let a = graph(owner: userA, name: "A")
        let b = graph(owner: userB, name: "B")
        a.photo.localFileRelativePath = "originals/a.jpg"
        b.photo.localFileRelativePath = "originals/b.jpg"
        insert(a, into: context)
        insert(b, into: context)
        context.insert(SyncMutation(
            ownerUserID: userA, entityType: .visit, entityID: "visit-a",
            operation: .upsert, payload: Data("{}".utf8), baseVersion: 0
        ))
        context.insert(SyncMutation(
            ownerUserID: userB, entityType: .visit, entityID: "visit-b",
            operation: .upsert, payload: Data("{}".utf8), baseVersion: 0
        ))
        context.insert(SyncCheckpoint(ownerUserID: userA, cursor: "10"))
        context.insert(SyncCheckpoint(ownerUserID: userB, cursor: "20"))
        try context.save()
        let files = AccountIsolationPhotoFileStore(paths: ["originals/a.jpg", "originals/b.jpg"])

        _ = try await LocalAccountDataPurger(context: context, photoFileStore: files)
            .purgeCurrentAccount(userID: userA)

        #expect(try context.fetch(FetchDescriptor<Restaurant>()).map(\.ownerUserID) == [userB])
        #expect(try context.fetch(FetchDescriptor<Visit>()).map(\.ownerUserID) == [userB])
        #expect(try context.fetch(FetchDescriptor<Dish>()).map(\.ownerUserID) == [userB])
        #expect(try context.fetch(FetchDescriptor<PhotoAsset>()).map(\.ownerUserID) == [userB])
        #expect(try context.fetch(FetchDescriptor<SyncMutation>()).map(\.ownerUserID) == [userB])
        #expect(try context.fetch(FetchDescriptor<SyncCheckpoint>()).map(\.ownerUserID) == [userB])
        #expect(await files.remainingPaths() == ["originals/b.jpg"])
    }

    @Test("Ownership migration claims guest, maps server evidence and quarantines unknown legacy rows")
    func evidenceBasedMigration() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let guest = Restaurant(
            ownerUserID: LocalAccountOwner.guest,
            name: "Guest", address: "", latitude: 0, longitude: 0
        )
        let proven = Restaurant(
            ownerUserID: LocalAccountOwner.legacyQuarantine,
            name: "Proven B", address: "", latitude: 0, longitude: 0
        )
        proven.remoteRecordData = try restaurantRecordData(for: proven, owner: userB)
        let unknown = Restaurant(
            ownerUserID: LocalAccountOwner.legacyQuarantine,
            name: "Unknown", address: "", latitude: 0, longitude: 0
        )
        let guestVisit = Visit(
            ownerUserID: LocalAccountOwner.legacyQuarantine,
            restaurantId: guest.id
        )
        context.insert(guest)
        context.insert(proven)
        context.insert(unknown)
        context.insert(guestVisit)
        try context.save()

        try LocalAccountOwnershipMigrator(context: context).activate(userID: userA)
        #expect(guest.ownerUserID == userA)
        #expect(guestVisit.ownerUserID == userA)
        #expect(proven.ownerUserID == LocalAccountOwner.legacyQuarantine)
        #expect(unknown.ownerUserID == LocalAccountOwner.legacyQuarantine)

        try LocalAccountOwnershipMigrator(context: context).activate(userID: userB)
        #expect(proven.ownerUserID == userB)
        #expect(unknown.ownerUserID == LocalAccountOwner.legacyQuarantine)
    }

    @Test("Two-account ownership and pending queues survive process restart")
    func restartPersistence() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TasteMap-Account-Isolation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("accounts.store")
        var container: ModelContainer? = try TasteMapPersistence.makeContainer(storageURL: url)
        let context = try #require(container?.mainContext)
        let a = graph(owner: userA, name: "Persist A")
        let b = graph(owner: userB, name: "Persist B")
        insert(a, into: context)
        insert(b, into: context)
        context.insert(SyncMutation(
            ownerUserID: userB, entityType: .restaurant, entityID: "persist-b",
            operation: .upsert, payload: Data("{}".utf8), baseVersion: 0
        ))
        try context.save()
        container = nil

        let reopened = try TasteMapPersistence.makeContainer(storageURL: url)
        let restaurants = try reopened.mainContext.fetch(FetchDescriptor<Restaurant>())
        #expect(restaurants.filter { $0.ownerUserID == userA }.map(\.name) == ["Persist A"])
        #expect(restaurants.filter { $0.ownerUserID == userB }.map(\.name) == ["Persist B"])
        #expect(try SwiftDataSyncQueue(
            context: reopened.mainContext,
            ownerUserID: userA
        ).allMutations().isEmpty)
        #expect(try SwiftDataSyncQueue(
            context: reopened.mainContext,
            ownerUserID: userB
        ).allMutations().count == 1)
    }

    @Test("A tombstone is scoped to its owner and cannot delete another account projection")
    func tombstoneIsAccountScoped() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let restaurantA = Restaurant(
            ownerUserID: userA,
            name: "A shared place",
            address: "A",
            latitude: 30,
            longitude: 120,
            remoteID: "shared-provider-neutral-id",
            serverVersion: 3,
            syncStatus: .synced
        )
        let restaurantB = Restaurant(
            ownerUserID: userB,
            name: "B shared place",
            address: "B",
            latitude: 30,
            longitude: 120,
            remoteID: "shared-provider-neutral-id",
            serverVersion: 5,
            syncStatus: .synced
        )
        context.insert(restaurantA)
        context.insert(restaurantB)
        try context.save()

        try LocalTasteMapStore(context: context).delete(restaurantA, actorUserID: userA)

        #expect(restaurantA.deletedAt != nil)
        #expect(restaurantB.deletedAt == nil)
        #expect(restaurantB.name == "B shared place")
        let aQueue = try SwiftDataSyncQueue(context: context, ownerUserID: userA).allMutations()
        let bQueue = try SwiftDataSyncQueue(context: context, ownerUserID: userB).allMutations()
        #expect(aQueue.count == 1)
        #expect(aQueue.first?.operation == .delete)
        #expect(bQueue.isEmpty)
    }

    private func graph(owner: String, name: String) -> AccountGraph {
        let restaurant = Restaurant(
            ownerUserID: owner,
            name: name, address: "\(name) Road", latitude: 30, longitude: 120,
            remoteID: "restaurant-\(owner)", serverVersion: 1, syncStatus: .synced
        )
        let visit = Visit(
            ownerUserID: owner, restaurantId: restaurant.id,
            remoteID: "visit-\(owner)", serverVersion: 1, syncStatus: .synced
        )
        let dish = Dish(
            ownerUserID: owner, restaurantId: restaurant.id, visitId: visit.id,
            name: "Dish \(owner)", remoteID: "dish-\(owner)",
            serverVersion: 1, syncStatus: .synced
        )
        let visitDish = VisitDish(
            ownerUserID: owner, restaurantId: restaurant.id,
            visitId: visit.id, dishId: dish.id,
            remoteID: "visit-dish-\(owner)", serverVersion: 1, syncStatus: .synced
        )
        let photo = PhotoAsset(
            ownerUserID: owner, restaurantId: restaurant.id, visitId: visit.id,
            dishId: dish.id, kind: .dish, mimeType: "image/jpeg", byteSize: 3,
            remoteID: "photo-\(owner)", serverVersion: 1, syncStatus: .synced
        )
        return AccountGraph(
            restaurant: restaurant, visit: visit, dish: dish,
            visitDish: visitDish, photo: photo
        )
    }

    private func insert(_ graph: AccountGraph, into context: ModelContext) {
        context.insert(graph.restaurant)
        context.insert(graph.visit)
        context.insert(graph.dish)
        context.insert(graph.visitDish)
        context.insert(graph.photo)
    }

    private func fetchedGraph(_ context: ModelContext) throws -> (
        restaurants: [Restaurant], visits: [Visit], dishes: [Dish],
        visitDishes: [VisitDish], photos: [PhotoAsset]
    ) {
        (
            try context.fetch(FetchDescriptor<Restaurant>()),
            try context.fetch(FetchDescriptor<Visit>()),
            try context.fetch(FetchDescriptor<Dish>()),
            try context.fetch(FetchDescriptor<VisitDish>()),
            try context.fetch(FetchDescriptor<PhotoAsset>())
        )
    }

    private func restaurantRecordData(for restaurant: Restaurant, owner: String) throws -> Data {
        let date = SyncRecordMapper.dateString(.now)
        let contract = try RestaurantJSONContractV1(
            id: restaurant.remoteID ?? restaurant.id.uuidString.lowercased(),
            userId: owner,
            placeIdentities: [try RestaurantPlaceIdentityContract(
                provider: .manual, externalId: "migration:\(restaurant.id.uuidString)",
                isPrimary: true, createdAt: date, updatedAt: date
            )],
            amapPoiId: nil, name: restaurant.name, address: restaurant.address,
            city: "", latitude: restaurant.latitude, longitude: restaurant.longitude,
            status: .visited, preferenceLevel: .normal,
            overallRating: nil, foodRating: nil, environmentRating: nil,
            serviceRating: nil, valueRating: nil, tags: [], longTermNote: "",
            pricePerPerson: nil, phone: nil, openingHours: nil, markerType: .emoji,
            markerPhotoId: nil, merchantImageUrl: nil, markerEmoji: "🍽️",
            createdAt: date, updatedAt: date, deletedAt: nil
        )
        return try JSONEncoder().encode(contract)
    }
}

@MainActor
private struct AccountGraph {
    let restaurant: Restaurant
    let visit: Visit
    let dish: Dish
    let visitDish: VisitDish
    let photo: PhotoAsset
}

private actor AccountIsolationPhotoFileStore: LocalPhotoFileStoring {
    private var paths: Set<String>
    init(paths: Set<String>) { self.paths = paths }
    func save(_ data: Data, photoID: UUID, mimeType: String) throws -> String {
        try save(data, photoID: photoID, mimeType: mimeType, variant: .original)
    }
    func save(
        _ data: Data,
        photoID: UUID,
        mimeType: String,
        variant: LocalPhotoFileVariant
    ) throws -> String {
        let path = "\(variant.rawValue)/\(photoID.uuidString).jpg"
        paths.insert(path)
        return path
    }
    func load(relativePath: String) throws -> Data {
        guard paths.contains(relativePath) else { throw LocalPhotoFileStoreError.fileMissing }
        return Data()
    }
    func delete(relativePath: String) { paths.remove(relativePath) }
    func fileExists(relativePath: String) -> Bool { paths.contains(relativePath) }
    func cleanupOrphans(retaining relativePaths: Set<String>) { paths.formIntersection(relativePaths) }
    func remainingPaths() -> Set<String> { paths }
}
