import Foundation
import Testing
@testable import TasteMap

@Suite("Task 09 pending Share Extension imports")
struct Task09PendingImportTests {
    @Test("URL/text is normalized, atomically queued, and duplicate share is idempotent")
    func duplicateImport() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("task09-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PendingRestaurantImportStore(directoryURL: directory)
        let now = Date(timeIntervalSince1970: 1_788_100_000)
        let first = try store.enqueue(
            text: "  Apple Maps 餐厅  ",
            url: URL(string: "https://maps.apple.com/?q=Apple%20Maps")!,
            now: now
        )
        let duplicate = try store.enqueue(
            text: "Apple Maps 餐厅",
            url: URL(string: "https://maps.apple.com/?q=Apple%20Maps")!,
            now: now.addingTimeInterval(10)
        )
        #expect(first == duplicate)
        #expect(try store.pending(now: now).count == 1)
        #expect(first.acquisitionText.contains("maps.apple.com"))
    }

    @Test("expired and malformed records cannot replay")
    func expiryAndMalformed() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("task09-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PendingRestaurantImportStore(directoryURL: directory)
        let now = Date(timeIntervalSince1970: 1_788_100_000)
        let item = try store.enqueue(text: "餐厅", url: nil, now: now)
        try Data("not-json".utf8).write(to: directory.appendingPathComponent("malformed.json"))
        #expect(try store.pending(now: now.addingTimeInterval(PendingRestaurantImport.lifetime + 1)).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("malformed.json").path))
        try store.consume(id: item.id)
    }

    @Test("insecure URL, empty input, oversized input, and path injection fail closed")
    func malformedInput() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("task09-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PendingRestaurantImportStore(directoryURL: directory)
        #expect(throws: PendingRestaurantImportStoreError.insecureURL) {
            _ = try store.enqueue(text: nil, url: URL(string: "http://example.test")!)
        }
        #expect(throws: PendingRestaurantImportStoreError.emptyPayload) {
            _ = try store.enqueue(text: "  ", url: nil)
        }
        #expect(throws: PendingRestaurantImportStoreError.payloadTooLarge) {
            _ = try store.enqueue(text: String(repeating: "x", count: 40_000), url: nil)
        }
        #expect(throws: PendingRestaurantImportStoreError.invalidIdentifier) {
            try store.consume(id: "../../auth-token")
        }
    }
}
