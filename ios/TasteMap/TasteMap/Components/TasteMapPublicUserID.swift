import Foundation

enum TasteMapPublicUserID {
    private static let base: UInt64 = 100_000_000_000
    private static let range: UInt64 = 900_000_000_000

    /// Mirrors the Web FNV-1a projection so every surface shows the same
    /// numeric public ID without exposing the internal account key.
    static func numeric(from internalID: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for scalar in internalID.unicodeScalars {
            hash ^= UInt64(scalar.value)
            hash = hash &* 1_099_511_628_211
        }
        return String(base + hash % range)
    }
}
