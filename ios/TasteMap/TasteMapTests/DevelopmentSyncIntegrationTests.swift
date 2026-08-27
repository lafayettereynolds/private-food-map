import Foundation
import SwiftData
import Testing
import UIKit
@testable import TasteMap

@Suite("Development Worker Sync", .serialized)
@MainActor
struct DevelopmentSyncIntegrationTests {
    @Test("iOS auth client reaches the Development Apple verification boundary")
    func developmentAuthBoundary() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["TASTEMAP_RUN_DEV_SYNC_TESTS"] == "1" else { return }
        let client = URLSessionAuthAPIClient(configuration: .current())
        let challenge = try await client.challenge()

        #expect(challenge.apiVersion == AuthV1Contract.apiVersion)
        #expect(!challenge.state.isEmpty)
        #expect(!challenge.nonce.isEmpty)
        await #expect(throws: AuthClientError.self) {
            _ = try await client.exchangeAppleToken(
                identityToken: "not-a-jwt",
                state: challenge.state,
                nonce: challenge.nonce,
                givenName: nil,
                familyName: nil
            )
        }
    }

    @Test("iOS API client round-trips through Development Worker and D1")
    func developmentRoundTrip() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["TASTEMAP_RUN_DEV_SYNC_TESTS"] == "1" else { return }
        let configuration = APIConfiguration.current()
        #expect(configuration.environment == .development)
        #expect(configuration.baseURL?.absoluteString == "https://api-dev.tastemap.cn")

        let runID = UUID().uuidString.lowercased()
        let userID = "ios-p0b2a:\(runID)"
        let restaurantID = "restaurant-\(runID)"
        let visitID = "visit-\(runID)"
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let client = URLSessionSyncAPIClient(
            configuration: configuration,
            authorization: DevelopmentSyncAuthorization(testUserID: userID)
        )

        let restaurant = try RestaurantJSONContractV1(
            id: restaurantID,
            userId: "forged-client-user",
            placeIdentities: [try RestaurantPlaceIdentityContract(
                provider: .appleMaps,
                externalId: "apple-maps-\(runID)",
                isPrimary: true,
                createdAt: timestamp,
                updatedAt: timestamp
            )],
            name: "P0-B2-A iOS Apple Maps Restaurant",
            address: "Development D1 only",
            city: "Development",
            latitude: 37.3349,
            longitude: -122.009,
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
            createdAt: timestamp,
            updatedAt: timestamp,
            deletedAt: nil,
            isTestData: true
        )
        let restaurantMutation = SyncMutationRequestV1(
            mutationId: "\(runID):restaurant-create",
            entityType: .restaurant,
            entityId: restaurantID,
            operation: .upsert,
            baseVersion: 0,
            clientTimestamp: timestamp,
            payload: .restaurant(restaurant)
        )

        let restaurantAck = try #require(try await client.push(
            SyncPushRequestV1(mutations: [restaurantMutation])
        ).acknowledgements.first)
        #expect(restaurantAck.status == .applied)
        #expect(restaurantAck.serverVersion == 1)

        let duplicateAck = try #require(try await client.push(
            SyncPushRequestV1(mutations: [restaurantMutation])
        ).acknowledgements.first)
        #expect(duplicateAck.duplicate)
        #expect(duplicateAck.serverVersion == 1)

        let visit = VisitSyncContractV1(
            schemaVersion: SyncV1Contract.schemaVersion,
            id: visitID,
            userId: "forged-client-user",
            restaurantId: restaurantID,
            visitedAt: timestamp,
            diningMode: .dineIn,
            visibility: .private,
            partySize: nil,
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
            note: "P0-B2-A real Development D1 test",
            myActualSpend: nil,
            createdAt: timestamp,
            updatedAt: timestamp,
            deletedAt: nil
        )
        let visitAck = try #require(try await client.push(SyncPushRequestV1(mutations: [
            SyncMutationRequestV1(
                mutationId: "\(runID):visit-create",
                entityType: .visit,
                entityId: visitID,
                operation: .upsert,
                baseVersion: 0,
                clientTimestamp: timestamp,
                payload: .visit(visit)
            )
        ])).acknowledgements.first)
        #expect(visitAck.status == .applied)

        let initial = try await client.pull(cursor: "0", limit: 200)
        let pulledRestaurant = try #require(initial.restaurants.first { $0.record.id == restaurantID })
        let pulledVisit = try #require(initial.visits.first { $0.record.id == visitID })
        #expect(pulledRestaurant.record.amapPoiId == nil)
        #expect(pulledRestaurant.record.placeIdentities.first?.provider == .appleMaps)
        #expect(pulledRestaurant.record.userId == userID)
        #expect(pulledVisit.record.restaurantId == restaurantID)
        #expect(pulledVisit.record.userId == userID)

        let unchanged = try await client.pull(cursor: initial.nextCursor, limit: 200)
        #expect(unchanged.restaurants.isEmpty)
        #expect(unchanged.visits.isEmpty)
        #expect(unchanged.tombstones.isEmpty)

        _ = try await client.push(SyncPushRequestV1(mutations: [
            deletion(runID: runID, suffix: "visit-delete", type: .visit, id: visitID, version: visitAck.serverVersion),
            deletion(runID: runID, suffix: "restaurant-delete", type: .restaurant, id: restaurantID, version: restaurantAck.serverVersion)
        ]))
        let deleted = try await client.pull(cursor: initial.nextCursor, limit: 200)
        #expect(deleted.tombstones.contains { $0.entityType == .visit && $0.entityId == visitID })
        #expect(deleted.tombstones.contains { $0.entityType == .restaurant && $0.entityId == restaurantID })
    }

    @Test("iOS want-to-go local-first flow round-trips through Development Worker and D1")
    func developmentWantToGoRoundTrip() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["TASTEMAP_RUN_DEV_SYNC_TESTS"] == "1" else { return }
        let configuration = APIConfiguration.current()
        #expect(configuration.environment == .development)
        #expect(configuration.baseURL?.absoluteString == "https://api-dev.tastemap.cn")

        let runID = UUID().uuidString.lowercased()
        let client = URLSessionSyncAPIClient(
            configuration: configuration,
            authorization: DevelopmentSyncAuthorization(testUserID: "ios-p1a:\(runID)")
        )
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let store = LocalTasteMapStore(context: context)
        let restaurant = try store.addToWantToGo(
            candidate: RestaurantCandidate(
                name: "P1-A Development Wishlist Restaurant",
                address: "Development D1 only",
                latitude: 37.3349,
                longitude: -122.009,
                appleMapItemIdentifier: "apple-p1a-\(runID)"
            ),
            among: []
        )

        try await SyncEngine(context: context, api: client).synchronize()

        #expect(restaurant.status == .wantToGo)
        #expect(restaurant.serverVersion == 1)
        #expect(restaurant.syncStatus == .synced)
        #expect(try context.fetch(FetchDescriptor<Visit>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<SyncMutation>()).isEmpty)

        try store.delete(restaurant)
        try await SyncEngine(context: context, api: client).synchronize()
        #expect(restaurant.deletedAt != nil)
        #expect(restaurant.serverVersion == 2)
    }

    @Test("P1-B Restaurant edit preserves identity through Development Worker and D1")
    func developmentRestaurantDetailEditRoundTrip() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["TASTEMAP_RUN_DEV_SYNC_TESTS"] == "1" else { return }
        let runID = UUID().uuidString.lowercased()
        let client = URLSessionSyncAPIClient(
            configuration: .current(),
            authorization: DevelopmentSyncAuthorization(testUserID: "ios-p1b:\(runID)")
        )
        let sourceContainer = try TasteMapPersistence.makeContainer(inMemory: true)
        let sourceContext = sourceContainer.mainContext
        let sourceStore = LocalTasteMapStore(context: sourceContext)
        let restaurant = try sourceStore.addToWantToGo(
            candidate: RestaurantCandidate(
                name: "P1-B Development Detail Restaurant",
                address: "Development D1 identity protection",
                latitude: 30.259,
                longitude: 120.168,
                appleMapItemIdentifier: "apple-p1b-\(runID)"
            ),
            among: []
        )

        try await SyncEngine(context: sourceContext, api: client).synchronize()
        #expect(restaurant.serverVersion == 1)

        try sourceStore.updateBasics(
            restaurant,
            name: "P1-B Edited Restaurant",
            city: "Hangzhou"
        )
        try await SyncEngine(context: sourceContext, api: client).synchronize()

        #expect(restaurant.serverVersion == 2)
        #expect(restaurant.syncStatus == .synced)
        #expect(restaurant.appleMapItemIdentifier == "apple-p1b-\(runID)")
        #expect(try sourceContext.fetch(FetchDescriptor<Restaurant>()).count == 1)

        let receivingContainer = try TasteMapPersistence.makeContainer(inMemory: true)
        let receivingContext = receivingContainer.mainContext
        try await SyncEngine(context: receivingContext, api: client).synchronize()
        let pulled = try #require(receivingContext.fetch(FetchDescriptor<Restaurant>()).first)
        #expect(pulled.remoteID == restaurant.remoteID)
        #expect(pulled.name == "P1-B Edited Restaurant")
        #expect(pulled.city == "Hangzhou")
        #expect(pulled.appleMapItemIdentifier == "apple-p1b-\(runID)")
        #expect(try receivingContext.fetch(FetchDescriptor<Restaurant>()).count == 1)
        #expect(try receivingContext.fetch(FetchDescriptor<Visit>()).isEmpty)

        try sourceStore.delete(restaurant)
        try await SyncEngine(context: sourceContext, api: client).synchronize()
        #expect(restaurant.deletedAt != nil)
        #expect(restaurant.serverVersion == 3)
    }

    @Test("P1-C complete Visit fields round-trip through Development Worker and D1")
    func developmentVisitCoreRoundTrip() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["TASTEMAP_RUN_DEV_SYNC_TESTS"] == "1" else { return }
        let runID = UUID().uuidString.lowercased()
        let client = URLSessionSyncAPIClient(
            configuration: .current(),
            authorization: DevelopmentSyncAuthorization(testUserID: "ios-p1c:\(runID)")
        )
        let sourceContainer = try TasteMapPersistence.makeContainer(inMemory: true)
        let sourceContext = sourceContainer.mainContext
        let sourceStore = LocalTasteMapStore(context: sourceContext)
        let restaurant = try sourceStore.addToWantToGo(
            candidate: RestaurantCandidate(
                name: "P1-C Development Visit Restaurant",
                address: "Development D1 only",
                latitude: 30.259,
                longitude: 120.168,
                appleMapItemIdentifier: "apple-p1c-\(runID)"
            ),
            among: []
        )
        let visitedAt = Date(timeIntervalSince1970: 1_787_592_000)
        let visit = try sourceStore.createVisit(
            restaurantId: restaurant.id,
            draft: VisitDraft(
                visitedAt: visitedAt,
                diningMode: .takeout,
                partySize: nil,
                rating: nil,
                myActualSpend: nil,
                note: "P1-C nullable create"
            )
        )

        try await SyncEngine(context: sourceContext, api: client).synchronize()
        #expect(restaurant.status == .visited)
        #expect(visit.serverVersion == 1)

        try sourceStore.update(
            visit,
            draft: VisitDraft(
                visitedAt: visitedAt,
                diningMode: .dineIn,
                partySize: 3,
                rating: 4.5,
                myActualSpend: 156.5,
                note: "P1-C complete update"
            )
        )
        try await SyncEngine(context: sourceContext, api: client).synchronize()
        #expect(visit.serverVersion == 2)

        let receivingContainer = try TasteMapPersistence.makeContainer(inMemory: true)
        let receivingContext = receivingContainer.mainContext
        try await SyncEngine(context: receivingContext, api: client).synchronize()
        let pulledRestaurant = try #require(receivingContext.fetch(FetchDescriptor<Restaurant>()).first)
        let pulledVisit = try #require(receivingContext.fetch(FetchDescriptor<Visit>()).first)
        #expect(pulledVisit.restaurantId == pulledRestaurant.id)
        #expect(pulledVisit.visitedAt == visitedAt)
        #expect(pulledVisit.diningMode == .dineIn)
        #expect(pulledVisit.partySize == 3)
        #expect(pulledVisit.rating == 4.5)
        #expect(pulledVisit.myActualSpend == Decimal(string: "156.5"))
        #expect(pulledVisit.note == "P1-C complete update")
        #expect(try receivingContext.fetch(FetchDescriptor<Visit>()).count == 1)

        try sourceStore.delete(visit)
        try await SyncEngine(context: sourceContext, api: client).synchronize()
        #expect(visit.deletedAt != nil)
        #expect(visit.serverVersion == 3)
        try sourceStore.delete(restaurant)
        try await SyncEngine(context: sourceContext, api: client).synchronize()
        #expect(restaurant.deletedAt != nil)
    }

    @Test("P1-D two clients preserve offline conflicts and converge on Development D1 tombstones")
    func developmentTwoClientOfflineConflictRoundTrip() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["TASTEMAP_RUN_DEV_SYNC_TESTS"] == "1" else { return }
        let runID = UUID().uuidString.lowercased()
        let client = URLSessionSyncAPIClient(
            configuration: .current(),
            authorization: DevelopmentSyncAuthorization(testUserID: "ios-p1d:\(runID)")
        )
        let containerA = try TasteMapPersistence.makeContainer(inMemory: true)
        let containerB = try TasteMapPersistence.makeContainer(inMemory: true)
        let contextA = containerA.mainContext
        let contextB = containerB.mainContext
        let storeA = LocalTasteMapStore(context: contextA)
        let restaurantA = try storeA.addToWantToGo(
            candidate: RestaurantCandidate(
                name: "P1-D Development Two Client Restaurant",
                address: "Development D1 only",
                latitude: 30.259,
                longitude: 120.168,
                appleMapItemIdentifier: "apple-p1d-\(runID)"
            ),
            among: []
        )

        try await SyncEngine(context: contextA, api: client).synchronize()
        try await SyncEngine(context: contextB, api: client).synchronize()
        let restaurantB = try #require(contextB.fetch(FetchDescriptor<Restaurant>()).first)
        #expect(restaurantB.status == .wantToGo)
        #expect(restaurantB.appleMapItemIdentifier == "apple-p1d-\(runID)")

        let visitA = try storeA.createVisit(
            restaurantId: restaurantA.id,
            draft: VisitDraft(rating: nil, note: "P1-D first visit")
        )
        try await SyncEngine(context: contextA, api: client).synchronize()
        try await SyncEngine(context: contextB, api: client).synchronize()
        let visitB = try #require(contextB.fetch(FetchDescriptor<Visit>()).first)
        #expect(restaurantB.status == .visited)
        #expect(visitB.restaurantId == restaurantB.id)

        try storeA.update(visitA, draft: VisitDraft(rating: 4.5, note: "P1-D server edit"))
        try await SyncEngine(context: contextA, api: client).synchronize()
        try LocalTasteMapStore(context: contextB).update(
            visitB,
            draft: VisitDraft(diningMode: .takeout, rating: 5, note: "P1-D offline edit")
        )
        try await SyncEngine(context: contextB, api: client).synchronize()

        #expect(try contextB.fetch(FetchDescriptor<SyncMutation>()).first?.state == .conflicted)
        #expect(visitB.note == "P1-D offline edit")
        #expect(visitB.rating == 5)

        try storeA.delete(visitA)
        try await SyncEngine(context: contextA, api: client).synchronize()
        try await SyncEngine(context: contextB, api: client).synchronize()
        #expect(visitB.deletedAt != nil)
        #expect(visitB.serverVersion == 3)

        try storeA.delete(restaurantA)
        try await SyncEngine(context: contextA, api: client).synchronize()
        try await SyncEngine(context: contextB, api: client).synchronize()
        #expect(restaurantB.deletedAt != nil)

        let remote = try await client.pull(cursor: "0", limit: 200)
        #expect(remote.tombstones.contains { $0.entityType == .visit && $0.entityId == visitA.remoteID })
        #expect(remote.tombstones.contains { $0.entityType == .restaurant && $0.entityId == restaurantA.remoteID })
        #expect(!remote.visits.contains { $0.record.id == visitA.remoteID })
        #expect(!remote.restaurants.contains { $0.record.id == restaurantA.remoteID })
    }

    @Test("P2-A Dish and Photo metadata round-trip through Development Worker and D1")
    func developmentDishPhotoRoundTrip() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["TASTEMAP_RUN_DEV_SYNC_TESTS"] == "1" else { return }
        let runID = UUID().uuidString.lowercased()
        let userID = "ios-p2a:\(runID)"
        let client = URLSessionSyncAPIClient(
            configuration: .current(),
            authorization: DevelopmentSyncAuthorization(testUserID: userID)
        )
        let otherClient = URLSessionSyncAPIClient(
            configuration: .current(),
            authorization: DevelopmentSyncAuthorization(testUserID: "ios-p2a-other:\(runID)")
        )
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let p1Store = LocalTasteMapStore(context: context)
        let restaurant = try p1Store.addToWantToGo(
            candidate: RestaurantCandidate(
                name: "P2-A Development Dish Photo Restaurant",
                address: "Development D1 metadata test only",
                latitude: 30.259,
                longitude: 120.168,
                appleMapItemIdentifier: "apple-p2a-\(runID)"
            ),
            among: []
        )
        let visit = try p1Store.createVisit(
            restaurantId: restaurant.id,
            draft: VisitDraft(rating: nil, note: "P2-A contract test")
        )
        let fileDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("taste-map-p2a-dev-\(runID)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: fileDirectory) }
        let photoFiles = try LocalPhotoFileStore(rootURL: fileDirectory)
        let richStore = LocalDishPhotoStore(context: context, photoFiles: photoFiles)
        let dish = try richStore.createDish(
            restaurantId: restaurant.id,
            visitId: visit.id,
            name: "Development 寿喜烧",
            taste: "甜香",
            rating: 4.5,
            price: 88
        )
        let photo = try await richStore.createLocalPhoto(
            data: Data([0xFF, 0xD8, 0xFF]),
            mimeType: "image/jpeg",
            kind: .dish,
            restaurantId: restaurant.id,
            visitId: visit.id,
            dishId: dish.id,
            fileName: "p2a-contract-test.jpg",
            width: 3,
            height: 1
        )
        try richStore.markUploaded(photo, reference: StoredPhotoReference(
            storageProvider: .googleDrive,
            storageKey: "p2a-contract-test:\(runID)",
            providerAccountId: "development-contract-test",
            thumbnailStorageKey: nil,
            metadata: PhotoMetadata(
                contentType: "image/jpeg", pixelWidth: 3, pixelHeight: 1,
                byteSize: 3, originalFileName: "p2a-contract-test.jpg", createdAt: .now
            )
        ))

        try await SyncEngine(context: context, api: client).synchronize()
        #expect(dish.serverVersion == 1)
        #expect(photo.serverVersion == 1)
        #expect(try context.fetch(FetchDescriptor<SyncMutation>()).isEmpty)

        let freshContainer = try TasteMapPersistence.makeContainer(inMemory: true)
        try await SyncEngine(context: freshContainer.mainContext, api: client).synchronize()
        let pulledDish = try #require(freshContainer.mainContext.fetch(FetchDescriptor<Dish>()).first)
        let pulledPhoto = try #require(freshContainer.mainContext.fetch(FetchDescriptor<PhotoAsset>()).first)
        #expect(pulledDish.name == "Development 寿喜烧")
        #expect(pulledPhoto.storageProvider == .googleDrive)
        #expect(pulledPhoto.storageKey == "p2a-contract-test:\(runID)")
        #expect(pulledPhoto.localFileRelativePath == nil)

        let isolated = try await otherClient.pull(cursor: "0", limit: 200)
        #expect(!isolated.dishes.contains { $0.record.id == dish.remoteID })
        #expect(!isolated.photos.contains { $0.record.id == photo.remoteID })

        try richStore.delete(photo)
        try richStore.delete(dish)
        try p1Store.delete(visit)
        try await SyncEngine(context: context, api: client).synchronize()
        try p1Store.delete(restaurant)
        try await SyncEngine(context: context, api: client).synchronize()
        let remote = try await client.pull(cursor: "0", limit: 200)
        #expect(remote.tombstones.contains { $0.entityType == .photo && $0.entityId == photo.remoteID })
        #expect(remote.tombstones.contains { $0.entityType == .dish && $0.entityId == dish.remoteID })
        #expect(remote.tombstones.contains { $0.entityType == .visit && $0.entityId == visit.remoteID })
        #expect(remote.tombstones.contains { $0.entityType == .restaurant && $0.entityId == restaurant.remoteID })
    }

    @Test("P2-C iOS SwiftData Dish associations round-trip through Development Worker and D1")
    func developmentVisitDishRoundTrip() async throws {
#if !TASTEMAP_DEVELOPMENT_INTEGRATION
        guard ProcessInfo.processInfo.environment["TASTEMAP_RUN_DEV_SYNC_TESTS"] == "1" else { return }
#endif
        let runID = UUID().uuidString.lowercased()
        let userID = "ios-p2c:\(runID)"
        let client = URLSessionSyncAPIClient(
            configuration: .current(),
            authorization: DevelopmentSyncAuthorization(testUserID: userID)
        )
        let otherClient = URLSessionSyncAPIClient(
            configuration: .current(),
            authorization: DevelopmentSyncAuthorization(testUserID: "ios-p2c-other:\(runID)")
        )
        let sourceContainer = try TasteMapPersistence.makeContainer(inMemory: true)
        let receivingContainer = try TasteMapPersistence.makeContainer(inMemory: true)
        let sourceContext = sourceContainer.mainContext
        let receivingContext = receivingContainer.mainContext
        let visitStore = LocalTasteMapStore(context: sourceContext)
        let dishStore = LocalDishStore(context: sourceContext)

        let restaurant = try visitStore.addToWantToGo(
            candidate: RestaurantCandidate(
                name: "P2-C Development Dish Restaurant",
                address: "Development D1 only",
                latitude: 30.259,
                longitude: 120.168,
                appleMapItemIdentifier: "apple-p2c-\(runID)"
            ),
            among: []
        )
        let firstVisit = try visitStore.createVisit(
            restaurantId: restaurant.id,
            draft: VisitDraft(note: "P2-C first Visit")
        )
        let secondVisit = try visitStore.createVisit(
            restaurantId: restaurant.id,
            draft: VisitDraft(note: "P2-C second Visit")
        )
        let firstDraftID = UUID()
        let mapping = try dishStore.reconcile(
            restaurantID: restaurant.id,
            visitID: firstVisit.id,
            drafts: [DishDraft(
                id: firstDraftID,
                name: "  招牌牛肉  ",
                taste: "值得再点",
                rating: 4.5,
                price: 88
            )]
        )
        let dish = try #require(mapping[firstDraftID])
        _ = try dishStore.reconcile(
            restaurantID: restaurant.id,
            visitID: secondVisit.id,
            drafts: [DishDraft(dishID: dish.id, name: dish.name, taste: dish.taste, rating: dish.rating, price: dish.price)]
        )

        try await SyncEngine(context: sourceContext, api: client).synchronize()
        #expect(dish.serverVersion == 1)
        #expect(try sourceContext.fetch(FetchDescriptor<VisitDish>()).filter { $0.deletedAt == nil }.count == 2)
        #expect(try sourceContext.fetch(FetchDescriptor<SyncMutation>()).isEmpty)

        try await SyncEngine(context: receivingContext, api: client).synchronize()
        let receivedDish = try #require(receivingContext.fetch(FetchDescriptor<Dish>()).first)
        let receivedAssociations = try receivingContext.fetch(FetchDescriptor<VisitDish>())
            .filter { $0.deletedAt == nil }
        #expect(receivedDish.remoteID == dish.remoteID)
        #expect(receivedDish.name == "招牌牛肉")
        #expect(receivedAssociations.count == 2)
        #expect(Set(receivedAssociations.map(\.dishId)).count == 1)

        let receivingVisit = try #require(receivingContext.fetch(FetchDescriptor<Visit>())
            .first { $0.remoteID == firstVisit.remoteID })
        _ = try LocalDishStore(context: receivingContext).reconcile(
            restaurantID: try #require(receivingContext.fetch(FetchDescriptor<Restaurant>()).first).id,
            visitID: receivingVisit.id,
            drafts: [DishDraft(
                dishID: receivedDish.id,
                name: receivedDish.name,
                taste: "第二台客户端更新",
                rating: nil,
                price: nil
            )]
        )
        try await SyncEngine(context: receivingContext, api: client).synchronize()
        try await SyncEngine(context: sourceContext, api: client).synchronize()
        #expect(dish.taste == "第二台客户端更新")
        #expect(dish.rating == nil)
        #expect(dish.price == nil)
        #expect(dish.serverVersion == 2)

        let isolated = try await otherClient.pull(cursor: "0", limit: 200)
        #expect(!isolated.dishes.contains { $0.record.id == dish.remoteID })
        #expect(!isolated.visitDishes.contains { $0.record.dishId == dish.remoteID })

        _ = try dishStore.reconcile(
            restaurantID: restaurant.id,
            visitID: secondVisit.id,
            drafts: []
        )
        try await SyncEngine(context: sourceContext, api: client).synchronize()
        try await SyncEngine(context: receivingContext, api: client).synchronize()
        #expect(try sourceContext.fetch(FetchDescriptor<Dish>()).first?.deletedAt == nil)
        #expect(try receivingContext.fetch(FetchDescriptor<VisitDish>()).filter { $0.deletedAt == nil }.count == 1)

        _ = try dishStore.reconcile(
            restaurantID: restaurant.id,
            visitID: firstVisit.id,
            drafts: []
        )
        try await SyncEngine(context: sourceContext, api: client).synchronize()
        let fileDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("taste-map-p2c-dev-\(runID)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: fileDirectory) }
        try LocalDishPhotoStore(
            context: sourceContext,
            photoFiles: LocalPhotoFileStore(rootURL: fileDirectory)
        ).delete(dish)
        try await SyncEngine(context: sourceContext, api: client).synchronize()
        try visitStore.delete(firstVisit)
        try visitStore.delete(secondVisit)
        try await SyncEngine(context: sourceContext, api: client).synchronize()
        try visitStore.delete(restaurant)
        try await SyncEngine(context: sourceContext, api: client).synchronize()

        let cleanup = try await client.pull(cursor: "0", limit: 200)
        #expect(cleanup.tombstones.contains { $0.entityType == .dish && $0.entityId == dish.remoteID })
        #expect(cleanup.tombstones.filter { $0.entityType == .visitDish }.count == 2)
        #expect(cleanup.tombstones.contains { $0.entityType == .visit && $0.entityId == firstVisit.remoteID })
        #expect(cleanup.tombstones.contains { $0.entityType == .visit && $0.entityId == secondVisit.remoteID })
        #expect(cleanup.tombstones.contains { $0.entityType == .restaurant && $0.entityId == restaurant.remoteID })
    }

    @Test("P2-D multidimensional ratings round-trip through Development Worker and D1")
    func developmentMultidimensionalRatingRoundTrip() async throws {
#if !TASTEMAP_DEVELOPMENT_INTEGRATION
        guard ProcessInfo.processInfo.environment["TASTEMAP_RUN_DEV_SYNC_TESTS"] == "1" else { return }
#endif
        let runID = UUID().uuidString.lowercased()
        let userID = "ios-p2d:\(runID)"
        let client = URLSessionSyncAPIClient(
            configuration: .current(),
            authorization: DevelopmentSyncAuthorization(testUserID: userID)
        )
        let otherClient = URLSessionSyncAPIClient(
            configuration: .current(),
            authorization: DevelopmentSyncAuthorization(testUserID: "ios-p2d-other:\(runID)")
        )
        let source = try TasteMapPersistence.makeContainer(inMemory: true)
        let receiving = try TasteMapPersistence.makeContainer(inMemory: true)
        let store = LocalTasteMapStore(context: source.mainContext)
        let restaurant = try store.addToWantToGo(
            candidate: RestaurantCandidate(
                name: "P2-D Development Rating Restaurant",
                address: "Development D1 only",
                latitude: 30.259,
                longitude: 120.168,
                appleMapItemIdentifier: "apple-p2d-\(runID)"
            ),
            among: []
        )
        let visit = try store.createVisit(
            restaurantId: restaurant.id,
            draft: VisitDraft(
                rating: 4.5,
                valueRating: 5,
                environmentRating: nil,
                serviceRating: 3.5,
                note: "P2-D partial ratings"
            )
        )

        try await SyncEngine(context: source.mainContext, api: client).synchronize()
        #expect(visit.serverVersion == 1)
        try await SyncEngine(context: receiving.mainContext, api: client).synchronize()
        let pulled = try #require(receiving.mainContext.fetch(FetchDescriptor<Visit>()).first)
        #expect(pulled.rating == 4.5)
        #expect(pulled.valueRating == 5)
        #expect(pulled.environmentRating == nil)
        #expect(pulled.serviceRating == 3.5)

        var edit = VisitDraft(visit: visit)
        edit.valueRating = nil
        edit.environmentRating = 4
        try store.update(visit, draft: edit)
        try await SyncEngine(context: source.mainContext, api: client).synchronize()
        try await SyncEngine(context: receiving.mainContext, api: client).synchronize()
        #expect(pulled.valueRating == nil)
        #expect(pulled.environmentRating == 4)
        #expect(pulled.serviceRating == 3.5)
        #expect(pulled.serverVersion == 2)

        let isolated = try await otherClient.pull(cursor: "0", limit: 200)
        #expect(!isolated.visits.contains { $0.record.id == visit.remoteID })

        try store.delete(visit)
        try await SyncEngine(context: source.mainContext, api: client).synchronize()
        try store.delete(restaurant)
        try await SyncEngine(context: source.mainContext, api: client).synchronize()
        let cleanup = try await client.pull(cursor: "0", limit: 200)
        #expect(cleanup.tombstones.contains { $0.entityType == .visit && $0.entityId == visit.remoteID })
        #expect(cleanup.tombstones.contains { $0.entityType == .restaurant && $0.entityId == restaurant.remoteID })
    }

    @Test("P2-E dining context round-trips through Development Worker and D1")
    func developmentDiningContextRoundTrip() async throws {
#if !TASTEMAP_DEVELOPMENT_INTEGRATION
        guard ProcessInfo.processInfo.environment["TASTEMAP_RUN_DEV_SYNC_TESTS"] == "1" else { return }
#endif
        let runID = UUID().uuidString.lowercased()
        let userID = "ios-p2e:\(runID)"
        let client = URLSessionSyncAPIClient(
            configuration: .current(),
            authorization: DevelopmentSyncAuthorization(testUserID: userID)
        )
        let otherClient = URLSessionSyncAPIClient(
            configuration: .current(),
            authorization: DevelopmentSyncAuthorization(testUserID: "ios-p2e-other:\(runID)")
        )
        let source = try TasteMapPersistence.makeContainer(inMemory: true)
        let receiving = try TasteMapPersistence.makeContainer(inMemory: true)
        let store = LocalTasteMapStore(context: source.mainContext)
        let restaurant = try store.addToWantToGo(
            candidate: RestaurantCandidate(
                name: "P2-E Development Context Restaurant",
                address: "Development D1 only",
                latitude: 30.259,
                longitude: 120.168,
                appleMapItemIdentifier: "apple-p2e-\(runID)"
            ),
            among: []
        )
        let visit = try store.createVisit(
            restaurantId: restaurant.id,
            draft: VisitDraft(
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
                note: "P2-E Development round-trip"
            )
        )

        try await SyncEngine(context: source.mainContext, api: client).synchronize()
        #expect(visit.serverVersion == 1)
        #expect(visit.syncStatus == .synced)
        try await SyncEngine(context: receiving.mainContext, api: client).synchronize()
        let pulled = try #require(receiving.mainContext.fetch(FetchDescriptor<Visit>()).first)
        #expect(pulled.visibility == .friends)
        #expect(pulled.totalPrice == 360)
        #expect(pulled.myActualSpend == 120)
        #expect(pulled.pricePerPerson == 120)
        #expect(pulled.paymentMode == .aa)
        #expect(pulled.queueDuration == .noWait)
        #expect(pulled.diningOccasions == [.friends, .other])
        #expect(pulled.diningOccasionText == "工作简餐")
        #expect(pulled.valueTags == ["合理"])
        #expect(pulled.environmentTags == ["舒适"])
        #expect(pulled.serviceTags == ["周到"])
        #expect(pulled.noiseLevel == .normal)
        #expect(pulled.diningDuration == .under30)
        #expect(pulled.portionLevel == .generous)
        #expect(pulled.transportConvenience == .veryConvenient)
        #expect(pulled.specialNotes == "现场取号")

        var clear = VisitDraft(visit: visit)
        clear.visibility = .private
        clear.totalPrice = nil
        clear.paymentMode = nil
        clear.queueDuration = nil
        clear.diningOccasions = []
        clear.diningOccasionText = ""
        clear.valueTags = []
        clear.environmentTags = []
        clear.serviceTags = []
        clear.noiseLevel = nil
        clear.diningDuration = nil
        clear.portionLevel = nil
        clear.transportConvenience = nil
        clear.specialNotes = ""
        try store.update(visit, draft: clear)
        try await SyncEngine(context: source.mainContext, api: client).synchronize()
        try await SyncEngine(context: receiving.mainContext, api: client).synchronize()
        #expect(pulled.serverVersion == 2)
        #expect(pulled.visibility == .private)
        #expect(pulled.totalPrice == nil && pulled.pricePerPerson == nil)
        #expect(pulled.paymentMode == nil && pulled.queueDuration == nil)
        #expect(pulled.diningOccasions.isEmpty && pulled.diningOccasionText == nil)
        #expect(pulled.valueTags.isEmpty && pulled.environmentTags.isEmpty && pulled.serviceTags.isEmpty)
        #expect(pulled.noiseLevel == nil && pulled.diningDuration == nil)
        #expect(pulled.portionLevel == nil && pulled.transportConvenience == nil)
        #expect(pulled.specialNotes == nil)
        #expect(pulled.rating == 4.5)
        #expect(pulled.valueRating == 5 && pulled.environmentRating == 4 && pulled.serviceRating == 3.5)

        let isolated = try await otherClient.pull(cursor: "0", limit: 200)
        #expect(!isolated.restaurants.contains { $0.record.id == restaurant.remoteID })
        #expect(!isolated.visits.contains { $0.record.id == visit.remoteID })

        try store.delete(visit)
        try await SyncEngine(context: source.mainContext, api: client).synchronize()
        try store.delete(restaurant)
        try await SyncEngine(context: source.mainContext, api: client).synchronize()
        let cleanup = try await client.pull(cursor: "0", limit: 200)
        #expect(cleanup.tombstones.contains { $0.entityType == .visit && $0.entityId == visit.remoteID })
        #expect(cleanup.tombstones.contains { $0.entityType == .restaurant && $0.entityId == restaurant.remoteID })
    }

    @Test("P2-B iOS local photo uploads to private Development R2 and downloads on a fresh client")
    func developmentPhotoBinaryRoundTrip() async throws {
#if !TASTEMAP_DEVELOPMENT_INTEGRATION
        guard ProcessInfo.processInfo.environment["TASTEMAP_RUN_DEV_SYNC_TESTS"] == "1" else { return }
#endif
        let runID = UUID().uuidString.lowercased()
        let userID = "ios-p2b:\(runID)"
        let authorization = DevelopmentSyncAuthorization(testUserID: userID)
        let configuration = APIConfiguration.current()
        let syncAPI = URLSessionSyncAPIClient(
            configuration: configuration,
            authorization: authorization
        )
        let binaryAPI = URLSessionPhotoBinaryAPIClient(
            configuration: configuration,
            authorization: authorization
        )
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let localStore = LocalTasteMapStore(context: context)
        let restaurant = try localStore.addToWantToGo(
            candidate: RestaurantCandidate(
                name: "P2-B Development Private Photo Restaurant",
                address: "Development D1/R2 only",
                latitude: 30.259,
                longitude: 120.168,
                appleMapItemIdentifier: "apple-p2b-\(runID)"
            ),
            among: []
        )
        let visit = try localStore.createVisit(
            restaurantId: restaurant.id,
            draft: VisitDraft(note: "P2-B native binary test")
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("taste-map-p2b-dev-\(runID)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = try LocalPhotoFileStore(rootURL: directory)
        let coordinator = PhotoTransferCoordinator(
            context: context,
            api: binaryAPI,
            files: files,
            hasAuthenticatedSession: { true },
            synchronizeMetadata: {
                try? await SyncEngine(context: context, api: syncAPI).synchronize()
            }
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: 1_600, height: 1_200),
            format: format
        ).image { render in
            UIColor.systemTeal.setFill()
            render.fill(CGRect(x: 0, y: 0, width: 1_600, height: 1_200))
        }
        let prepared = try await coordinator.preparePhoto(
            data: try #require(image.jpegData(compressionQuality: 0.9)),
            suggestedContentType: "image/jpeg",
            originalFileName: "ios-development-photo.jpg"
        )
        let photo = try coordinator.attachPreparedPhoto(
            prepared,
            restaurantID: restaurant.id,
            visitID: visit.id,
            sortOrder: 0,
            queueForUpload: true
        )

        await coordinator.processNowForTesting()
        #expect(photo.uploadState == .uploaded)
        #expect(photo.storageProvider == .r2)
        #expect(photo.serverVersion == 1)
        #expect(photo.storageKey?.contains(photo.id.uuidString.lowercased()) == true)
        #expect(photo.thumbnailStorageKey != nil)

        let receivingContainer = try TasteMapPersistence.makeContainer(inMemory: true)
        let receivingContext = receivingContainer.mainContext
        try await SyncEngine(context: receivingContext, api: syncAPI).synchronize()
        let pulledPhoto = try #require(receivingContext.fetch(FetchDescriptor<PhotoAsset>()).first)
        let receivingFiles = try LocalPhotoFileStore(
            rootURL: directory.appendingPathComponent("receiving", isDirectory: true)
        )
        let receivingCoordinator = PhotoTransferCoordinator(
            context: receivingContext,
            api: binaryAPI,
            files: receivingFiles,
            hasAuthenticatedSession: { true }
        )
        let downloaded = try await receivingCoordinator.imageData(for: pulledPhoto, variant: .display)
        #expect(!downloaded.isEmpty)
        #expect(pulledPhoto.displayFileRelativePath != nil)

        let otherAPI = URLSessionPhotoBinaryAPIClient(
            configuration: configuration,
            authorization: DevelopmentSyncAuthorization(testUserID: "ios-p2b-other:\(runID)")
        )
        await #expect(throws: PhotoBinaryAPIError.self) {
            _ = try await otherAPI.download(photoID: photo.id, variant: .display)
        }

        try await coordinator.delete(photo)
        #expect(photo.deletedAt != nil)
        #expect(photo.binaryDeletedAt != nil)
        await #expect(throws: PhotoBinaryAPIError.self) {
            _ = try await binaryAPI.download(photoID: photo.id, variant: .display)
        }
        try localStore.delete(visit)
        try await SyncEngine(context: context, api: syncAPI).synchronize()
        try localStore.delete(restaurant)
        try await SyncEngine(context: context, api: syncAPI).synchronize()
    }

    private func deletion(
        runID: String,
        suffix: String,
        type: SyncEntityType,
        id: String,
        version: Int64
    ) -> SyncMutationRequestV1 {
        SyncMutationRequestV1(
            mutationId: "\(runID):\(suffix)",
            entityType: type,
            entityId: id,
            operation: .delete,
            baseVersion: version,
            clientTimestamp: ISO8601DateFormatter().string(from: Date()),
            payload: nil
        )
    }
}
