import Foundation
import Testing
@testable import TasteMap

@Suite("Sync recovery metadata privacy")
struct SyncRecoveryDiagnosticTests {
    @Test func recordsWireNullsWithoutContentOrCredentials() throws {
        var request = URLRequest(url: URL(string: "https://example.invalid/api/v1/sync/push")!)
        request.setValue("secret-token", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["mutations": [
            ["mutationId": "mutation-1", "entityType": "restaurantListItem", "baseVersion": 0,
             "payload": ["note": "private-note", "deletedAt": NSNull(),
                         "restaurant": ["name": "private-name", "markerPhotoId": NSNull(), "merchantImageUrl": NSNull()]]]
        ]])
        let metadata = try #require(SyncRecoveryDiagnostic.requestMetadata(request))
        let rows = try #require(metadata["mutations"] as? [[String: Any]])
        #expect(metadata["batchSize"] as? Int == 1)
        #expect(rows[0]["mutationID"] as? String == "mutation-1")
        #expect(rows[0]["deletedAt"] as? String == "null")
        #expect(rows[0]["restaurant.markerPhotoId"] as? String == "null")
        #expect(rows[0]["restaurant.merchantImageUrl"] as? String == "null")
        #expect(rows[0]["customCoverPhotoId"] as? String == "missing")
        let encoded = String(decoding: try JSONSerialization.data(withJSONObject: metadata), as: UTF8.self)
        for forbidden in ["secret-token", "Authorization", "private-note", "private-name", "payload"] {
            #expect(!encoded.contains(forbidden))
        }
    }

    @Test func nonPushRequestsAreNotCaptured() {
        let request = URLRequest(url: URL(string: "https://example.invalid/api/v1/auth/apple")!)
        #expect(SyncRecoveryDiagnostic.requestMetadata(request) == nil)
    }
}
