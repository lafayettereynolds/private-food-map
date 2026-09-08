import Foundation
import XCTest
@testable import TasteMapHybridBridge

final class RecommendationSignalContractTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-09-06T00:00:00Z")!
    private var payload: [String: Any] { [
        "value": 0.82, "modelVersion": "test-only-model", "calibrationVersion": "test-only-calibration",
        "calibrationStatus": "validated", "evidenceStatus": "sufficient", "definitionStatus": "approved",
        "positiveFeedbackDefinition": "用户在到访后明确选择喜欢", "definitionVersion": "test-only-definition",
        "validationSampleCount": 800, "validUntil": "2026-09-07T00:00:00Z"
    ] }
    private func decode(_ value: [String: Any]) throws -> TasteMapCalibratedLikeProbabilityDTO {
        try JSONDecoder().decode(TasteMapCalibratedLikeProbabilityDTO.self, from: JSONSerialization.data(withJSONObject: value))
    }
    func testExplicitEvaluatedModelAttestationCanBeDisplayed() throws {
        XCTAssertTrue(try decode(payload).isDisplayable(now: now))
    }
    func testInvalidUnapprovedInsufficientAndExpiredValuesFailClosed() throws {
        let patches: [(String, Any)] = [("value", -0.1), ("value", 1.1), ("modelVersion", ""), ("calibrationVersion", " "),
            ("calibrationStatus", "unvalidated"), ("evidenceStatus", "insufficient"), ("definitionStatus", "draft"),
            ("positiveFeedbackDefinition", ""), ("definitionVersion", ""), ("validationSampleCount", 0),
            ("validUntil", "invalid"), ("validUntil", "2026-09-06T00:00:00Z")]
        for (key, value) in patches {
            var candidate = payload; candidate[key] = value
            XCTAssertFalse(try decode(candidate).isDisplayable(now: now), key)
        }
    }
    func testLegacyPercentageIsNotAProbabilityPayload() throws {
        XCTAssertThrowsError(try decode(["personalTastePercent": 100]))
    }
}
