import Foundation
import Testing
@testable import TasteMap

@Suite("Sync V1 JSON contract")
@MainActor
struct SyncV1ContractTests {
    @Test("Legacy list payloads re-encode required nullable wire fields without changing identity")
    func listRetryEncodesRequiredNulls() throws {
        let timestamp = "2026-09-04T00:00:00Z"
        let legacyList: [String: Any] = [
            "schemaVersion": 1, "id": "list-retry", "userId": "owner-retry",
            "title": "Test list", "description": "", "visibility": "private",
            "isRanked": false, "coverMode": "automatic",
            "createdAt": timestamp, "updatedAt": timestamp,
        ]
        let list = try JSONDecoder().decode(RestaurantListSyncContractV1.self,
            from: JSONSerialization.data(withJSONObject: legacyList))
        let listJSON = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(list)) as? [String: Any])
        #expect(listJSON["deletedAt"] is NSNull)
        #expect(listJSON["customCoverPhotoId"] is NSNull)
        #expect(listJSON["id"] as? String == "list-retry")
        #expect(listJSON["userId"] as? String == "owner-retry")
        let place: [String: Any] = [
            "globalKey": "manual:place-retry", "restaurantId": "place-retry",
            "placeIdentities": [["provider": "manual", "externalId": "place-retry", "isPrimary": true]],
            "name": "Test restaurant", "address": "", "city": "", "latitude": 0, "longitude": 0,
            "markerEmoji": "",
        ]
        let legacyItem: [String: Any] = [
            "schemaVersion": 1, "id": "item-retry", "userId": "owner-retry", "listId": "list-retry",
            "restaurantId": "place-retry", "restaurantGlobalKey": "manual:place-retry",
            "position": 0, "note": "", "restaurant": place, "createdAt": timestamp, "updatedAt": timestamp,
        ]
        let item = try JSONDecoder().decode(RestaurantListItemSyncContractV1.self,
            from: JSONSerialization.data(withJSONObject: legacyItem))
        let itemJSON = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any])
        #expect(itemJSON["deletedAt"] is NSNull)
        let placeJSON = try #require(itemJSON["restaurant"] as? [String: Any])
        #expect(placeJSON["markerPhotoId"] is NSNull)
        #expect(placeJSON["merchantImageUrl"] is NSNull)
        #expect(try JSONDecoder().decode(RestaurantListItemSyncContractV1.self, from: JSONEncoder().encode(item)) == item)
    }

    @Test("Visit encodes required nullable fields as explicit null")
    func visitEncodesRequiredNulls() throws {
        let visit = makeVisit()
        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(visit)) as? [String: Any]
        )

        #expect(object["rating"] is NSNull)
        #expect(object["valueRating"] is NSNull)
        #expect(object["environmentRating"] is NSNull)
        #expect(object["serviceRating"] is NSNull)
        #expect(object["partySize"] is NSNull)
        #expect(object["note"] is NSNull)
        #expect(object["myActualSpend"] is NSNull)
        #expect(object["deletedAt"] is NSNull)
    }

    @Test("Visit rejects an omitted required nullable field")
    func visitRejectsMissingNullableField() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "id": "visit-contract-test",
            "userId": "user-contract-test",
            "restaurantId": "restaurant-contract-test",
            "visitedAt": "2026-08-27T00:00:00.000Z",
            "note": NSNull(),
            "myActualSpend": NSNull(),
            "createdAt": "2026-08-27T00:00:00.000Z",
            "updatedAt": "2026-08-27T00:00:00.000Z",
            "deletedAt": NSNull()
        ])

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(VisitSyncContractV1.self, from: data)
        }
    }

    @Test("Swift decodes dining mode and nullable party size from the shared fixture")
    func visitCoreFieldsDecodeSharedFixture() throws {
        let visit = try JSONDecoder().decode(
            VisitSyncContractV1.self,
            from: try fixture(named: "visit.v1.valid")
        )

        #expect(visit.diningMode == .takeout)
        #expect(visit.partySize == nil)
        #expect(visit.rating == nil)
        #expect(visit.valueRating == nil)
        #expect(visit.environmentRating == nil)
        #expect(visit.serviceRating == nil)
        #expect(visit.myActualSpend == nil)
    }

    @Test("P0 Visit payload decodes with explicit compatibility defaults")
    func legacyVisitCompatibility() throws {
        let visit = try JSONDecoder().decode(
            VisitSyncContractV1.self,
            from: try fixture(named: "visit.v0.legacy")
        )

        #expect(visit.diningMode == .dineIn)
        #expect(visit.partySize == nil)
        #expect(visit.valueRating == nil)
        #expect(visit.environmentRating == nil)
        #expect(visit.serviceRating == nil)
    }

    @Test("Visit instant survives JSON and Date round-trip")
    func visitDateRoundTrip() throws {
        let visit = try JSONDecoder().decode(
            VisitSyncContractV1.self,
            from: try fixture(named: "visit.v1.valid")
        )
        let date = try #require(SyncRecordMapper.date(visit.visitedAt))

        #expect(SyncRecordMapper.dateString(date) == visit.visitedAt)
        #expect(try JSONDecoder().decode(
            VisitSyncContractV1.self,
            from: JSONEncoder().encode(visit)
        ).visitedAt == visit.visitedAt)
    }

    private func makeVisit() -> VisitSyncContractV1 {
        VisitSyncContractV1(
            schemaVersion: 1,
            id: "visit-contract-test",
            userId: "user-contract-test",
            restaurantId: "restaurant-contract-test",
            visitedAt: "2026-08-27T00:00:00.000Z",
            diningMode: .takeout,
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
            note: nil,
            myActualSpend: nil,
            createdAt: "2026-08-27T00:00:00.000Z",
            updatedAt: "2026-08-27T00:00:00.000Z",
            deletedAt: nil
        )
    }

    private func fixture(named name: String) throws -> Data {
        let bundle = Bundle(for: VisitContractBundleMarker.self)
        let candidates = [
            bundle.url(forResource: name, withExtension: "json"),
            bundle.url(forResource: name, withExtension: "json", subdirectory: "fixtures"),
            bundle.url(forResource: name, withExtension: "json", subdirectory: "contracts/fixtures")
        ]
        return try Data(contentsOf: try #require(candidates.compactMap { $0 }.first))
    }
}

private final class VisitContractBundleMarker {}
