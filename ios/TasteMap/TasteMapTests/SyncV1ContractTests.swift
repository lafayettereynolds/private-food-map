import Foundation
import Testing
@testable import TasteMap

@Suite("Sync V1 JSON contract")
struct SyncV1ContractTests {
    @Test("Visit encodes required nullable fields as explicit null")
    func visitEncodesRequiredNulls() throws {
        let visit = makeVisit()
        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(visit)) as? [String: Any]
        )

        #expect(object["rating"] is NSNull)
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

    private func makeVisit() -> VisitSyncContractV1 {
        VisitSyncContractV1(
            schemaVersion: 1,
            id: "visit-contract-test",
            userId: "user-contract-test",
            restaurantId: "restaurant-contract-test",
            visitedAt: "2026-08-27T00:00:00.000Z",
            rating: nil,
            note: nil,
            myActualSpend: nil,
            createdAt: "2026-08-27T00:00:00.000Z",
            updatedAt: "2026-08-27T00:00:00.000Z",
            deletedAt: nil
        )
    }
}
