import Foundation
import XCTest
@testable import TasteMapNativePOC

@MainActor
final class TasteMapHybridPOCServiceTests: XCTestCase {
    private func makeService() throws -> TasteMapHybridPOCService {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("public/hybrid-poc/dataset.json")
        let service = try TasteMapHybridPOCService()
        try service.bootstrap(fixtureData: Data(contentsOf: fixtureURL))
        return service
    }

    func testRuntimeDeclaresLocalOfflineSwiftDataBoundary() throws {
        let payload = try json(try makeService().runtimeJSON())
        XCTAssertEqual(payload["bridgeVersion"] as? Int, 1)
        XCTAssertEqual(payload["platform"] as? String, "ios")
        XCTAssertEqual(payload["dataSource"] as? String, "native-swiftdata-in-memory")
        XCTAssertEqual(payload["localBundle"] as? Bool, true)
        XCTAssertEqual(payload["offlineCapable"] as? Bool, true)
    }

    func testProfileIsReconstructedFromTheIsolatedSwiftDataStore() throws {
        let payload = try json(try makeService().profileJSON())
        XCTAssertEqual(payload["followingCount"] as? Int, 76)
        XCTAssertEqual(payload["followerCount"] as? Int, 128)
        XCTAssertEqual((payload["restaurants"] as? [[String: Any]])?.count, 5)
        XCTAssertEqual((payload["visits"] as? [[String: Any]])?.count, 2)

        let user = try XCTUnwrap(payload["user"] as? [String: Any])
        XCTAssertEqual(user["id"] as? String, "tm_capacitor_poc")
        XCTAssertNil(payload["appleToken"])
        XCTAssertNil(payload["accessToken"])
    }

    func testRestaurantUsesTheCurrentImagePriorityPolicyAndCurrentDetailPayload() throws {
        let payload = try json(try makeService().restaurantJSON(
            id: "11111111-1111-4111-8111-111111111111"
        ))
        XCTAssertEqual(payload["name"] as? String, "湖滨二十八号 · 江南味道")
        XCTAssertEqual(payload["_nativeImageSource"] as? String, "providerMerchantImage")
        XCTAssertEqual((payload["visits"] as? [[String: Any]])?.count, 2)
        XCTAssertNotNil(payload["merchantImageUrl"] as? String)
    }

    private func json(_ value: String) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any]
        )
    }
}
