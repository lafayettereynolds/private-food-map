import XCTest
@testable import TasteMapHybridBridge

final class RestaurantOwnerAvatarEmojiTests: XCTestCase {
    func testOwnerGlyphValidationMatchesSaveWithoutCuisineAllowlist() {
        for value in ["🐸", "🍽️", "🇨🇳", "👩🏽‍🍳", "1️⃣"] {
            XCTAssertEqual(RestaurantOwnerAvatarEmojiPolicy.normalized(" \(value) "), value)
        }
        for value in ["", "frog", "🐸🐸", "1", "<img>"] {
            XCTAssertNil(RestaurantOwnerAvatarEmojiPolicy.normalized(value))
        }
        XCTAssertNil(RestaurantOwnerAvatarEmojiPolicy.normalized(nil))
    }
}
