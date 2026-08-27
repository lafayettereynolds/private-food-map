import Foundation
import SwiftData
import Testing
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
            rating: nil,
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
