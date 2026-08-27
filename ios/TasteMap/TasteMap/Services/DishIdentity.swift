import CryptoKit
import Foundation

nonisolated enum DishIdentity {
    static func normalizedName(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
    }

    static func dishRemoteID(restaurantRemoteID: String, normalizedName: String) -> String {
        "dish:\(digest("\(restaurantRemoteID)|\(normalizedName)"))"
    }

    static func fallbackDishRemoteID() -> String {
        "dish:\(UUID().uuidString.lowercased())"
    }

    static func associationRemoteID(visitRemoteID: String, dishRemoteID: String) -> String {
        "visit-dish:\(digest("\(visitRemoteID)|\(dishRemoteID)"))"
    }

    static func legacyAssociationRemoteID(visitRemoteID: String, dishRemoteID: String) -> String {
        "legacy:\(dishRemoteID):\(visitRemoteID)"
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
