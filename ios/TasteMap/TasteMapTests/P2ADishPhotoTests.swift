import Foundation
import SwiftData
import Testing
@testable import TasteMap

@Suite("P2-A Dish and Photo foundation")
@MainActor
struct P2ADishPhotoTests {
    @Test("Dish JSON preserves nullable fields and rejects invalid data")
    func dishContract() throws {
        let record = try DishSyncContractV1(
            id: "dish-1", userId: "local", restaurantId: "restaurant-1", visitId: "visit-1",
            name: "寿喜烧", taste: "甜香", rating: nil, price: nil, photoId: nil, sortOrder: 0,
            createdAt: instant, updatedAt: instant, deletedAt: nil
        )
        let data = try JSONEncoder().encode(record)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object.keys.contains("rating"))
        #expect(object.keys.contains("price"))
        #expect(object.keys.contains("photoId"))
        #expect(object.keys.contains("deletedAt"))
        #expect(try JSONDecoder().decode(DishSyncContractV1.self, from: data) == record)
        #expect(throws: RichRecordContractError.invalidDish) {
            _ = try DishSyncContractV1(
                id: "dish-1", userId: "local", restaurantId: "restaurant-1", visitId: "visit-1",
                name: "", taste: "", rating: 4.2, price: nil, photoId: nil, sortOrder: 0,
                createdAt: instant, updatedAt: instant, deletedAt: nil
            )
        }
        var missingNullable = object
        missingNullable.removeValue(forKey: "rating")
        let missingData = try JSONSerialization.data(withJSONObject: missingNullable)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(DishSyncContractV1.self, from: missingData)
        }
        #expect(throws: RichRecordContractError.invalidDish) {
            _ = try DishSyncContractV1(
                id: "dish-1", userId: "local", restaurantId: "restaurant-1", visitId: "visit-1",
                name: "寿喜烧", taste: "", rating: nil, price: .infinity, photoId: nil, sortOrder: 0,
                createdAt: instant, updatedAt: "not-a-date", deletedAt: nil
            )
        }
    }

    @Test("Photo JSON separates Photo ID from provider identity")
    func photoContract() throws {
        let record = try photoRecord()
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(PhotoSyncContractV1.self, from: data)
        #expect(decoded.id == "photo-1")
        #expect(decoded.storageProvider == .googleDrive)
        #expect(decoded.storageKey == "drive-file-id")
        #expect(decoded.id != decoded.storageKey)

        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["temporarySignedURL"] = "https://temporary.example/photo"
        let unknown = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: RichRecordContractError.invalidPhoto) {
            _ = try JSONDecoder().decode(PhotoSyncContractV1.self, from: unknown)
        }
    }

    @Test("Dish local create edit delete remains offline-first and deduplicates its mutation")
    func localDishFlow() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let parents = insertParents(context)
        let files = try LocalPhotoFileStore(rootURL: temporaryDirectory())
        let store = LocalDishPhotoStore(context: context, photoFiles: files)

        let dish = try store.createDish(
            restaurantId: parents.restaurant.id,
            visitId: parents.visit.id,
            name: "寿喜烧",
            rating: 4.5,
            price: 88
        )
        try store.update(dish, name: "招牌寿喜烧", taste: "甜香", rating: 5, price: 98, sortOrder: 1)
        #expect(dish.name == "招牌寿喜烧")
        #expect(try context.fetch(FetchDescriptor<SyncMutation>()).filter { $0.entityType == .dish }.count == 1)

        try store.delete(dish)
        #expect(try context.fetch(FetchDescriptor<Dish>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<SyncMutation>()).filter { $0.entityType == .dish }.isEmpty)
    }

    @Test("Dish, photo metadata, upload retry state, and sandbox file survive restart")
    func photoRestartPersistence() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("taste-map.store")
        let files = try LocalPhotoFileStore(rootURL: directory.appendingPathComponent("photo-files"))
        var container: ModelContainer? = try TasteMapPersistence.makeContainer(storageURL: databaseURL)
        let firstContext = try #require(container?.mainContext)
        let parents = insertParents(firstContext)
        let store = LocalDishPhotoStore(context: firstContext, photoFiles: files)
        let dish = try store.createDish(
            restaurantId: parents.restaurant.id,
            visitId: parents.visit.id,
            name: "重启后仍在的菜",
            rating: nil
        )
        let photo = try await store.createLocalPhoto(
            data: Data([0xFF, 0xD8, 0xFF]), mimeType: "image/jpeg", kind: .dish,
            restaurantId: parents.restaurant.id, visitId: parents.visit.id, dishId: dish.id,
            fileName: "meal.jpg", width: 1200, height: 900
        )
        try store.queueUpload(photo)
        try store.markUploadFailed(photo, reason: "offline")
        let path = try #require(photo.localFileRelativePath)
        #expect(await files.fileExists(relativePath: path))
        #expect(photo.uploadState == .failed)
        #expect(photo.uploadRetryCount == 1)
        container = nil

        let reopened = try TasteMapPersistence.makeContainer(storageURL: databaseURL)
        let restoredDish = try #require(reopened.mainContext.fetch(FetchDescriptor<Dish>()).first)
        let restored = try #require(reopened.mainContext.fetch(FetchDescriptor<PhotoAsset>()).first)
        #expect(restoredDish.name == "重启后仍在的菜")
        #expect(restored.dishId == restoredDish.id)
        #expect(restored.localFileRelativePath == path)
        #expect(restored.uploadState == .failed)
        #expect(restored.uploadRetryCount == 1)
        #expect(restored.uploadLastError == "offline")
        #expect(try await files.load(relativePath: path) == Data([0xFF, 0xD8, 0xFF]))
    }

    @Test("Photo upload retry state persists and Visit save does not depend on upload")
    func photoUploadState() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let parents = insertParents(context)
        let files = try LocalPhotoFileStore(rootURL: temporaryDirectory())
        let store = LocalDishPhotoStore(context: context, photoFiles: files)
        let photo = try await store.createLocalPhoto(
            data: Data([1, 2, 3]), mimeType: "image/png", kind: .visit,
            restaurantId: parents.restaurant.id, visitId: parents.visit.id
        )
        try store.queueUpload(photo)
        try store.markUploadFailed(photo, reason: "offline")
        #expect(photo.uploadState == .failed)
        #expect(photo.uploadRetryCount == 1)
        #expect(try context.fetch(FetchDescriptor<Visit>()).contains { $0.id == parents.visit.id })
        #expect(try context.fetch(FetchDescriptor<SyncMutation>()).allSatisfy { $0.entityType != .photo })
    }

    @Test("Photo tombstone sync is independent from retained local file cleanup")
    func photoTombstoneAndCleanup() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let parents = insertParents(context)
        let files = try LocalPhotoFileStore(rootURL: directory)
        let store = LocalDishPhotoStore(context: context, photoFiles: files)
        let photo = try await store.createLocalPhoto(
            data: Data([1, 2, 3]), mimeType: "image/png", kind: .visit,
            restaurantId: parents.restaurant.id, visitId: parents.visit.id
        )
        try store.markUploaded(photo, reference: StoredPhotoReference(
            storageProvider: .googleDrive,
            storageKey: "provider-file-id",
            providerAccountId: "account-id",
            thumbnailStorageKey: nil,
            metadata: PhotoMetadata(
                contentType: "image/png", pixelWidth: nil, pixelHeight: nil,
                byteSize: 3, originalFileName: nil, createdAt: .now
            )
        ))
        photo.serverVersion = 1
        let path = try #require(photo.localFileRelativePath)

        try store.delete(photo)
        #expect(photo.deletedAt != nil)
        #expect(photo.uploadState == .deleted)
        #expect(await files.fileExists(relativePath: path))
        #expect(try context.fetch(FetchDescriptor<SyncMutation>()).contains {
            $0.entityType == .photo && $0.operation == .delete
        })

        try await store.cleanupLocalFiles(retainingTombstonesFor: 0)
        #expect(photo.localFileRelativePath == nil)
        #expect(await files.fileExists(relativePath: path) == false)
        #expect(photo.deletedAt != nil)
    }

    @Test("Sync orders Restaurant, Visit, Dish, Photo and hydrates a fresh store")
    func syncRoundTrip() async throws {
        let source = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = source.mainContext
        let parents = insertParents(context)
        let files = try LocalPhotoFileStore(rootURL: temporaryDirectory())
        let local = LocalDishPhotoStore(context: context, photoFiles: files)
        let dish = try local.createDish(
            restaurantId: parents.restaurant.id, visitId: parents.visit.id,
            name: "寿喜烧", taste: "甜香", rating: 4.5, price: 88
        )
        let photo = try await local.createLocalPhoto(
            data: Data([1, 2, 3]), mimeType: "image/heic", kind: .dish,
            restaurantId: parents.restaurant.id, visitId: parents.visit.id, dishId: dish.id
        )
        try local.markUploaded(photo, reference: StoredPhotoReference(
            storageProvider: .googleDrive,
            storageKey: "drive-file-id",
            providerAccountId: "drive-account",
            thumbnailStorageKey: nil,
            metadata: PhotoMetadata(
                contentType: "image/heic", pixelWidth: 1200, pixelHeight: 900,
                byteSize: 3, originalFileName: "meal.heic", createdAt: .now
            )
        ))
        for mutation in try context.fetch(FetchDescriptor<SyncMutation>()) {
            mutation.timestamp = Date(timeIntervalSince1970: Double(10 - mutation.entityType.dependencyPriority))
        }
        try context.save()
        let api = RichRecordSyncAPI()
        try await SyncEngine(context: context, api: api).synchronize()
        #expect(api.pushOrder == [.restaurant, .visit, .dish, .visitDish, .photo])
        #expect(try context.fetch(FetchDescriptor<SyncMutation>()).isEmpty)
        #expect(dish.serverVersion == 1)
        #expect(photo.serverVersion == 1)

        let destination = try TasteMapPersistence.makeContainer(inMemory: true)
        try await SyncEngine(context: destination.mainContext, api: api).synchronize()
        let downloadedRestaurants = try destination.mainContext.fetch(FetchDescriptor<Restaurant>())
        let downloadedVisits = try destination.mainContext.fetch(FetchDescriptor<Visit>())
        let downloadedDishes = try destination.mainContext.fetch(FetchDescriptor<Dish>())
        let downloadedVisitDishes = try destination.mainContext.fetch(FetchDescriptor<VisitDish>())
        let downloadedPhotos = try destination.mainContext.fetch(FetchDescriptor<PhotoAsset>())
        #expect(downloadedRestaurants.count == 1)
        #expect(downloadedVisits.count == 1)
        #expect(downloadedDishes.first?.name == "寿喜烧")
        #expect(downloadedVisitDishes.count == 1)
        let downloadedPhoto = try #require(downloadedPhotos.first)
        #expect(downloadedPhoto.storageKey == "drive-file-id")
        #expect(downloadedPhoto.localFileRelativePath == nil)
    }

    @Test("P1 store opens with the additive P2-A schema")
    func additiveSchemaMigration() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("legacy-p1.store")
        let p1Schema = Schema([Restaurant.self, Visit.self, SyncMutation.self, SyncCheckpoint.self])
        var oldContainer: ModelContainer? = try ModelContainer(
            for: p1Schema,
            configurations: [ModelConfiguration("TasteMap", schema: p1Schema, url: url, cloudKitDatabase: .none)]
        )
        let restaurant = Restaurant(name: "保留餐厅", address: "杭州", latitude: 30, longitude: 120)
        oldContainer?.mainContext.insert(restaurant)
        try oldContainer?.mainContext.save()
        oldContainer = nil

        let migrated = try TasteMapPersistence.makeContainer(storageURL: url)
        let restaurants = try migrated.mainContext.fetch(FetchDescriptor<Restaurant>())
        let dishes = try migrated.mainContext.fetch(FetchDescriptor<Dish>())
        let photos = try migrated.mainContext.fetch(FetchDescriptor<PhotoAsset>())
        #expect(restaurants.first?.name == "保留餐厅")
        #expect(dishes.isEmpty)
        #expect(photos.isEmpty)
    }

    private var instant: String { "2026-08-27T08:00:00.000Z" }

    private func photoRecord() throws -> PhotoSyncContractV1 {
        try PhotoSyncContractV1(
            id: "photo-1", userId: "local", restaurantId: "restaurant-1", visitId: "visit-1",
            dishId: "dish-1", kind: .dish, storageProvider: .googleDrive,
            storageKey: "drive-file-id", providerAccountId: "drive-account",
            thumbnailStorageKey: nil, fileName: "meal.heic", mimeType: "image/heic",
            byteSize: 1024, width: 1200, height: 900, sortOrder: 0, visibility: .private,
            createdAt: instant, updatedAt: instant, deletedAt: nil
        )
    }

    private func insertParents(_ context: ModelContext) -> (restaurant: Restaurant, visit: Visit) {
        let restaurant = Restaurant(
            name: "测试餐厅", address: "杭州", latitude: 30, longitude: 120,
            remoteID: UUID().uuidString.lowercased()
        )
        let visit = Visit(
            restaurantId: restaurant.id,
            remoteID: UUID().uuidString.lowercased()
        )
        context.insert(restaurant)
        context.insert(visit)
        try? context.save()
        return (restaurant, visit)
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("taste-map-p2a-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

@MainActor
private final class RichRecordSyncAPI: SyncAPI {
    var pushOrder: [SyncEntityType] = []
    private var restaurants: [String: RestaurantSyncRecordEnvelopeV1] = [:]
    private var visits: [String: VisitSyncRecordEnvelopeV1] = [:]
    private var dishes: [String: DishSyncRecordEnvelopeV1] = [:]
    private var visitDishes: [String: VisitDishSyncRecordEnvelopeV1] = [:]
    private var photos: [String: PhotoSyncRecordEnvelopeV1] = [:]
    private var revision: Int64 = 0

    func push(_ request: SyncPushRequestV1) async throws -> SyncPushResponseV1 {
        var acknowledgements: [SyncMutationAcknowledgementV1] = []
        for mutation in request.mutations {
            pushOrder.append(mutation.entityType)
            let version = mutation.baseVersion + 1
            revision += 1
            if let payload = mutation.payload {
                switch payload {
                case .restaurant(let record):
                    restaurants[mutation.entityId] = RestaurantSyncRecordEnvelopeV1(serverVersion: version, record: record)
                case .visit(let record):
                    visits[mutation.entityId] = VisitSyncRecordEnvelopeV1(serverVersion: version, record: record)
                case .dish(let record):
                    dishes[mutation.entityId] = DishSyncRecordEnvelopeV1(serverVersion: version, record: record)
                case .visitDish(let record):
                    visitDishes[mutation.entityId] = VisitDishSyncRecordEnvelopeV1(serverVersion: version, record: record)
                case .photo(let record):
                    photos[mutation.entityId] = PhotoSyncRecordEnvelopeV1(serverVersion: version, record: record)
                case .companion, .recommendationSource:
                    break
                }
            }
            acknowledgements.append(SyncMutationAcknowledgementV1(
                mutationId: mutation.mutationId,
                entityType: mutation.entityType,
                entityId: mutation.entityId,
                status: .applied,
                duplicate: false,
                serverVersion: version,
                revision: revision,
                conflictReason: nil
            ))
        }
        return SyncPushResponseV1(apiVersion: 1, acknowledgements: acknowledgements, serverTime: "2026-08-27T08:00:00.000Z")
    }

    func pull(cursor: String, limit: Int) async throws -> SyncPullResponseV1 {
        let includeRecords = cursor == "0"
        return SyncPullResponseV1(
            apiVersion: 1,
            schemaVersion: 1,
            restaurants: includeRecords ? Array(restaurants.values) : [],
            visits: includeRecords ? Array(visits.values) : [],
            dishes: includeRecords ? Array(dishes.values) : [],
            visitDishes: includeRecords ? Array(visitDishes.values) : [],
            photos: includeRecords ? Array(photos.values) : [],
            tombstones: [],
            nextCursor: String(revision),
            hasMore: false,
            serverTime: "2026-08-27T08:00:00.000Z"
        )
    }
}
