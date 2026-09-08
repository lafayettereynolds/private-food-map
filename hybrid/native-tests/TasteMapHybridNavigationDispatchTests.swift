import Foundation
import XCTest
@testable import TasteMapHybridBridge

@MainActor
final class TasteMapHybridNavigationDispatchTests: XCTestCase {
    func testSynchronousNavigationUsesExistingEnvelopeAndCapabilityValidation() throws {
        var accepted: [String] = []
        let dispatcher = TasteMapHybridBridgeDispatcher(
            service: nil, appVersion: "1", build: "1", dataSource: "isolated-navigation-test",
            authState: { XCTFail("Presentation navigation must not read authentication"); return .init(state: "signedOut", userID: nil, displayName: nil) },
            capabilityOverrides: [.nativeNavigation: true],
            navigationAction: { request in
                accepted.append(request.requestId)
                return .object(["sourceRequestID": .string(request.requestId)])
            },
            asynchronousAction: { _, _ in XCTFail("Navigation must not enter an async session/task path"); return .null }
        )
        func request(_ id: String, version: Int = 1, method: TasteMapHybridBridgeMethod = .navigationOpenHybrid) throws -> TasteMapHybridBridgeRequest {
            let data = try JSONSerialization.data(withJSONObject: ["version": version, "requestId": id, "method": method.rawValue, "payload": ["surface": "map"]])
            return try JSONDecoder().decode(TasteMapHybridBridgeRequest.self, from: data)
        }
        XCTAssertEqual(dispatcher.dispatch(try request("invalid-version", version: 2)).error?.code, "bridge_version_mismatch")
        XCTAssertEqual(dispatcher.dispatch(try request("short")).error?.code, "invalid_request_id")
        XCTAssertTrue(accepted.isEmpty)
        for method in [TasteMapHybridBridgeMethod.navigationOpenHybrid, .navigationOpenNative, .navigationBack, .navigationCurrent] {
            XCTAssertNil(dispatcher.dispatch(try request("request-\(method.rawValue)", method: method)).error)
        }
        XCTAssertEqual(accepted, ["request-navigation.openHybrid", "request-navigation.openNative", "request-navigation.back", "request-navigation.current"])
        let unavailable = TasteMapHybridBridgeDispatcher(
            service: nil, appVersion: "1", build: "1", dataSource: "isolated-navigation-test",
            authState: { .init(state: "signedOut", userID: nil, displayName: nil) },
            navigationAction: { _ in XCTFail("Disabled capability must not invoke navigation"); return .null }
        )
        XCTAssertEqual(unavailable.dispatch(try request("request-disabled")).error?.code, "capability_unavailable")
    }

    func testNavigationCorrelationIsOptionalAndCredentialFree() throws {
        let route = try TasteMapHybridRouteDTO(surface: .map)
        let legacy = TasteMapHybridNavigationStateDTO(route: route, canGoBack: false)
        let oldData = try JSONEncoder().encode(legacy)
        XCTAssertFalse(String(decoding: oldData, as: UTF8.self).contains("sourceRequestID"))
        XCTAssertNil(try JSONDecoder().decode(TasteMapHybridNavigationStateDTO.self, from: oldData).sourceRequestID)
        let correlated = TasteMapHybridNavigationStateDTO(route: route, canGoBack: true, sourceRequestID: "request-map-1")
        XCTAssertEqual(try JSONDecoder().decode(TasteMapHybridNavigationStateDTO.self, from: JSONEncoder().encode(correlated)), correlated)
    }

    func testReplacementCommandMetadataIsOptionalValidatedAndNotRouteIdentity() throws {
        let legacyData = Data(#"{"surface":"restaurant","identifier":"r-1"}"#.utf8)
        let replacementData = Data(#"{"surface":"restaurant","identifier":"r-1","replaceCurrent":true}"#.utf8)
        let legacy = try JSONDecoder().decode(TasteMapHybridNavigationOpenOptions.self, from: legacyData)
        let replacement = try JSONDecoder().decode(TasteMapHybridNavigationOpenOptions.self, from: replacementData)
        XCTAssertNil(legacy.replaceCurrent)
        XCTAssertEqual(replacement.replaceCurrent, true)
        XCTAssertEqual(try JSONDecoder().decode(TasteMapHybridRouteDTO.self, from: legacyData),
            try JSONDecoder().decode(TasteMapHybridRouteDTO.self, from: replacementData))
        XCTAssertThrowsError(try JSONDecoder().decode(TasteMapHybridNavigationOpenOptions.self,
            from: Data(#"{"surface":"map","replaceCurrent":"true"}"#.utf8)))
    }
}
