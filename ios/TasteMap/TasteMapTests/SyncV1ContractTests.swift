import Foundation
import Testing
@testable import TasteMap

@Suite("Sync V1 JSON contract")
@MainActor
struct SyncV1ContractTests {
    @Test("Visit encodes required nullable fields as explicit null")
    func visitEncodesRequiredNulls() throws {
        let visit = makeVisit()
        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(visit)) as? [String: Any]
        )

        #expect(object["rating"] is NSNull)
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
            partySize: nil,
            rating: nil,
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
