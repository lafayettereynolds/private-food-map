import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import TasteMap

@Suite("F1-C2 backup import preflight")
@MainActor
struct BackupImportPreflightTests {
    private let reader = BackupImportFileReader()
    private let service = BackupImportPreflightService()

    @Test("Backup v1 optional website metadata follows the existing HTTP/HTTPS contract")
    func websiteMetadataContract() async throws {
        for website: Any in [NSNull(), "https://restaurant.example/menu", "http://restaurant.example/menu"] {
            var root = try fixtureObject("backup.v1.full.valid")
            var entities = try requiredDictionary(root["entities"])
            var restaurants = try #require(entities["restaurants"] as? [[String: Any]])
            restaurants[0]["websiteUrl"] = website
            entities["restaurants"] = restaurants
            root["entities"] = entities
            let result = try await preflight(data: recanonicalized(root)).result
            #expect(result.blockingCount == 0)
        }
        for website in ["javascript:alert(1)", "file:///private/data", "https://name:password@restaurant.example", "https://"] {
            var root = try fixtureObject("backup.v1.full.valid")
            var entities = try requiredDictionary(root["entities"])
            var restaurants = try #require(entities["restaurants"] as? [[String: Any]])
            restaurants[0]["websiteUrl"] = website
            entities["restaurants"] = restaurants
            root["entities"] = entities
            let result = try await preflight(data: recanonicalized(root)).result
            #expect(result.issues.contains { $0.code == "schema_website_url_invalid" && $0.field == "websiteUrl" })
        }
    }

    @Test("Valid full and minimal Backup v1 files pass deterministic preflight")
    func validBackupV1Fixtures() async throws {
        let full = try await preflightFixture("backup.v1.full.valid")
        let minimal = try await preflightFixture("backup.v1.minimal.valid")

        #expect(full.result.sourceFormat == .backupV1)
        #expect(full.result.blockingCount == 0)
        #expect(full.result.counts.restaurants == 3)
        #expect(full.result.photoBinaryStatus == .metadataOnlyBackupV1)
        #expect(minimal.result.sourceFormat == .backupV1)
        #expect(minimal.result.blockingCount == 0)
        #expect(minimal.result.counts.total == 0)

        var repeated = [ImportPreflightResult]()
        for _ in 0 ..< 100 {
            repeated.append(try await preflightFixture("backup.v1.minimal.valid").result)
        }
        #expect(repeated.allSatisfy { $0 == minimal.result })
    }

    @Test("Format detector keeps Backup v1 and Legacy Web v4 lineages independent")
    func strictLineageDetection() async throws {
        var v1 = try fixtureObject("backup.v1.minimal.valid")
        v1["schemaVersion"] = 2
        #expect(await preflightError(data: jsonData(v1)) == .invalidBackupV1Version)

        v1 = try fixtureObject("backup.v1.minimal.valid")
        v1["format"] = "other.backup"
        #expect(await preflightError(data: jsonData(v1)) == .invalidBackupV1Format)

        var legacy = legacyEnvelope()
        legacy["app"] = "Other App"
        #expect(await preflightError(data: jsonData(legacy)) == .invalidLegacyApp)
        legacy = legacyEnvelope()
        legacy["version"] = 3
        #expect(await preflightError(data: jsonData(legacy)) == .invalidLegacyVersion)

        #expect(await preflightError(data: Data("{\"hello\":true}".utf8)) == .unsupportedFormat)
    }

    @Test("Backup v1 integrity and metadata counts are independently verified")
    func integrityAndCounts() async throws {
        var modified = try fixtureObject("backup.v1.full.valid")
        var entities = try #require(modified["entities"] as? [String: Any])
        var restaurants = try #require(entities["restaurants"] as? [[String: Any]])
        restaurants[0]["name"] = "内容已变化"
        entities["restaurants"] = restaurants
        modified["entities"] = entities
        let integrityResult = try await preflight(data: jsonData(modified)).result
        #expect(integrityResult.issues.contains { $0.code == "backup_integrity_mismatch" })

        modified = try fixtureObject("backup.v1.full.valid")
        var metadata = try #require(modified["metadata"] as? [String: Any])
        var counts = try #require(metadata["entityCounts"] as? [String: Any])
        counts["restaurants"] = 99
        metadata["entityCounts"] = counts
        modified["metadata"] = metadata
        let countResult = try await preflight(data: try recanonicalized(modified)).result
        #expect(countResult.issues.contains { $0.code == "metadata_count_mismatch" })
        #expect(countResult.counts.restaurants == 3)
    }

    @Test("Backup v1 rejects active/tombstone collision and conflicting tombstones")
    func tombstoneConsistency() async throws {
        var root = try fixtureObject("backup.v1.full.valid")
        var tombstones = try #require(root["tombstones"] as? [[String: Any]])
        tombstones[0]["entityType"] = "restaurant"
        tombstones[0]["id"] = "restaurant-amap"
        root["tombstones"] = tombstones
        var result = try await preflight(data: try recanonicalized(root)).result
        #expect(result.issues.contains { $0.code == "active_tombstone_collision" })

        root = try fixtureObject("backup.v1.full.valid")
        tombstones = try #require(root["tombstones"] as? [[String: Any]])
        var conflicting = tombstones[0]
        conflicting["deletedAt"] = "2026-08-28T12:00:00.000Z"
        tombstones.append(conflicting)
        root["tombstones"] = tombstones
        var metadata = try #require(root["metadata"] as? [String: Any])
        metadata["tombstoneCount"] = 2
        root["metadata"] = metadata
        result = try await preflight(data: try recanonicalized(root)).result
        #expect(result.issues.contains { $0.code == "conflicting_tombstone" })
        #expect(result.counts.tombstones == 1)
    }

    @Test("Backup v1 verifies Restaurant, Visit, Dish, and VisitDish relationships")
    func businessRelationships() async throws {
        var root = try fixtureObject("backup.v1.full.valid")
        var entities = try #require(root["entities"] as? [String: Any])
        var visits = try #require(entities["visits"] as? [[String: Any]])
        visits[0]["restaurantId"] = "missing-restaurant"
        entities["visits"] = visits
        root["entities"] = entities
        var result = try await preflight(data: try recanonicalized(root)).result
        #expect(hasBrokenReference(result, type: "visit"))

        root = try fixtureObject("backup.v1.full.valid")
        entities = try #require(root["entities"] as? [String: Any])
        var dishes = try #require(entities["dishes"] as? [[String: Any]])
        dishes[0]["restaurantId"] = "missing-restaurant"
        entities["dishes"] = dishes
        root["entities"] = entities
        result = try await preflight(data: try recanonicalized(root)).result
        #expect(hasBrokenReference(result, type: "dish"))

        root = try fixtureObject("backup.v1.full.valid")
        entities = try #require(root["entities"] as? [String: Any])
        var links = try #require(entities["visitDishes"] as? [[String: Any]])
        links[0]["dishId"] = "missing-dish"
        entities["visitDishes"] = links
        root["entities"] = entities
        result = try await preflight(data: try recanonicalized(root)).result
        #expect(hasBrokenReference(result, type: "visitDish"))
    }

    @Test("Backup v1 verifies Photo parents, Profile avatar, and list relationships")
    func presentationRelationships() async throws {
        var root = try fixtureObject("backup.v1.full.valid")
        var entities = try #require(root["entities"] as? [String: Any])
        var photos = try #require(entities["photos"] as? [[String: Any]])
        var parent = try #require(photos[0]["parent"] as? [String: Any])
        parent["entityId"] = "missing-dish"
        photos[0]["parent"] = parent
        entities["photos"] = photos
        root["entities"] = entities
        var result = try await preflight(data: try recanonicalized(root)).result
        #expect(hasBrokenReference(result, type: "photo"))

        root = try fixtureObject("backup.v1.full.valid")
        entities = try #require(root["entities"] as? [String: Any])
        var profiles = try #require(entities["profiles"] as? [[String: Any]])
        profiles[0]["avatarPhotoId"] = "missing-avatar"
        entities["profiles"] = profiles
        root["entities"] = entities
        result = try await preflight(data: try recanonicalized(root)).result
        #expect(hasBrokenReference(result, type: "profile"))

        root = try fixtureObject("backup.v1.full.valid")
        entities = try #require(root["entities"] as? [String: Any])
        var items = try #require(entities["restaurantListItems"] as? [[String: Any]])
        items[0]["listId"] = "missing-list"
        entities["restaurantListItems"] = items
        root["entities"] = entities
        result = try await preflight(data: try recanonicalized(root)).result
        #expect(hasBrokenReference(result, type: "restaurantListItem"))
    }

    @Test("Backup v1 unknown fields are blocking even when Codable would ignore them")
    func unknownBackupField() async throws {
        var root = try fixtureObject("backup.v1.minimal.valid")
        root["unexpectedAuthority"] = "must-not-be-trusted"
        let result = try await preflight(data: jsonData(root)).result
        #expect(result.issues.contains { $0.code == "schema_unknown_field" })
        #expect(result.blockingCount > 0)
    }

    @Test("JSON gate rejects malformed, array-root, deep, and excessive entity inputs")
    func jsonSafetyGate() async throws {
        #expect(await preflightError(data: Data("{".utf8)) == .malformedJSON)
        #expect(await preflightError(data: Data("[]".utf8)) == .rootMustBeObject)

        var nested: Any = "leaf"
        for index in 0 ..< 33 { nested = ["level\(index)": nested] }
        let deep = try JSONSerialization.data(withJSONObject: nested)
        #expect(await preflightError(data: deep) == .excessiveNesting(maximumDepth: 32))

        let excessive: [String: Any] = [
            "format": BackupV1Contract.format,
            "schemaVersion": 1,
            "entities": ["restaurants": Array(repeating: NSNull(), count: 25_001)],
        ]
        let excessiveData = try JSONSerialization.data(withJSONObject: excessive)
        #expect(await preflightError(data: excessiveData) == .collectionLimitExceeded(
            collection: "restaurants", maximum: 25_000
        ))
    }

    @Test("Bounded reader enforces strict UTF-8 and exact 25 MiB boundary")
    func boundedReaderAndEncoding() async throws {
        let boundary = Data(repeating: 0x20, count: BackupImportFileReader.maximumByteCount)
        let accepted = try await reader.read(data: boundary, fileName: "boundary.json")
        #expect(accepted.fileSize == BackupImportFileReader.maximumByteCount)

        let oversized = Data(repeating: 0x20, count: BackupImportFileReader.maximumByteCount + 1)
        do {
            _ = try await reader.read(data: oversized, fileName: "oversized.json")
            Issue.record("Oversized input should fail")
        } catch let error as BackupImportPreflightError {
            #expect(error == .fileTooLarge(maximumBytes: BackupImportFileReader.maximumByteCount))
        }

        do {
            _ = try await reader.read(data: Data([0xC3, 0x28]), fileName: "invalid.json")
            Issue.record("Invalid UTF-8 should fail")
        } catch let error as BackupImportPreflightError {
            #expect(error == .invalidUTF8)
        }
    }

    @Test("File hash is raw-byte deterministic and distinct from envelope integrity")
    func fileHash() async throws {
        let data = try fixtureData("backup.v1.full.valid")
        let first = try await reader.read(data: data, fileName: "full.json")
        let second = try await reader.read(data: data, fileName: "full.json")
        let expected = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let result = try await service.preflight(first).result

        #expect(first.sourceFileSHA256 == second.sourceFileSHA256)
        #expect(first.sourceFileSHA256 == expected)
        #expect(result.sourceFileSHA256 == expected)
        #expect(result.backupIntegritySHA256 != nil)
    }

    @Test("Security-scoped access is balanced on success and failure")
    func securityScopedCleanup() async throws {
        let counter = LockedAccessCounter()
        let scopedReader = BackupImportFileReader(
            maximumByteCount: 128,
            securityScopedAccess: BackupImportSecurityScopedAccess(
                start: { _ in counter.start() },
                stop: { _ in counter.stop() }
            )
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("f1c2-reader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let validURL = directory.appendingPathComponent("valid.json")
        try Data("{}".utf8).write(to: validURL)
        _ = try await scopedReader.read(from: validURL)
        #expect(counter.snapshot == (1, 1))

        let largeURL = directory.appendingPathComponent("large.json")
        try Data(repeating: 0x20, count: 129).write(to: largeURL)
        _ = try? await scopedReader.read(from: largeURL)
        #expect(counter.snapshot == (2, 2))
    }

    @Test("Cancellation leaves no security scope or retained artifact")
    func cancellation() async throws {
        let counter = LockedAccessCounter()
        let scopedReader = BackupImportFileReader(
            chunkSize: 1,
            securityScopedAccess: BackupImportSecurityScopedAccess(
                start: { _ in counter.start() },
                stop: { _ in counter.stop() }
            )
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("f1c2-cancel-\(UUID().uuidString).json")
        try Data(repeating: 0x20, count: 1_000_000).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let task = Task { try await scopedReader.read(from: url) }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Cancelled read should fail")
        } catch let error as BackupImportPreflightError {
            #expect(error == .cancelled)
        } catch is CancellationError {
            // Cancellation may be observed before the reader maps it.
        }
        #expect(counter.snapshot.0 == counter.snapshot.1)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("Legacy v4 uses strict decoder and exposes a sanitized conversion report")
    func legacyIntegration() async throws {
        var root = legacyEnvelope()
        root["restaurants"] = [legacyRestaurant(id: "r-1")]
        root["visits"] = [legacyVisit(id: "v-1", restaurantID: "r-1")]
        root["friendships"] = [["id": "server-owned"]]
        root["unknownCollection"] = [["private": "value"]]
        let run = try await preflight(data: jsonData(root))

        #expect(run.result.sourceFormat == .legacyWebV4)
        #expect(run.result.counts.restaurants == 1)
        #expect(run.result.counts.visits == 1)
        #expect(run.result.securityDiscardCount > 0)
        #expect(run.result.unsupportedCount > 0)
        #expect(run.result.photoBinaryStatus == .partialLegacyMetadataOnly)
        #expect(!String(describing: run.result).contains("server-owned"))
        #expect(!String(describing: run.result).contains("private\": \"value"))
    }

    @Test("Legacy broken references become blocking Dry Run issues")
    func legacyBrokenReference() async throws {
        var root = legacyEnvelope()
        root["visits"] = [legacyVisit(id: "v-broken", restaurantID: "missing")]
        let result = try await preflight(data: jsonData(root)).result
        #expect(result.blockingCount > 0)
        #expect(result.issues.contains { $0.code == LegacyBackupIssueCode.brokenReference.rawValue })
    }

    @Test("Preflight cannot alter SwiftData business records, profile, or mutations")
    func noWriteBoundary() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let before = try businessCounts(context)
        _ = try await preflightFixture("backup.v1.full.valid")
        _ = try await preflight(data: jsonData(legacyEnvelope()))
        let after = try businessCounts(context)

        #expect(before == after)
        #expect(after == .zero)
    }

    @Test("Large Legacy fixture records stage timings without parser redesign")
    func largeLegacyPerformance() async throws {
        let data = largeLegacyFixture(
            restaurantCount: 1_000,
            visitCount: 10_000,
            embeddedDishCount: 5_000
        )
        let run = try await preflight(data: data, fileName: "legacy-large.json")

        #expect(run.result.counts.restaurants == 1_000)
        #expect(run.result.counts.visits == 10_000)
        #expect(run.result.counts.dishes == 5_000)
        #expect(run.timing.totalSeconds >= run.timing.decodeAndNormalizeSeconds)
        #expect(run.timing.inspectionSeconds >= 0)
        #expect(run.timing.validationSeconds >= 0)
    }

    private func preflightFixture(_ name: String) async throws -> BackupImportPreflightRun {
        try await preflight(data: fixtureData(name), fileName: "\(name).json")
    }

    private func preflight(
        data: Data,
        fileName: String = "fixture.json"
    ) async throws -> BackupImportPreflightRun {
        let source = try await reader.read(data: data, fileName: fileName)
        return try await service.preflight(source, inspectedAt: Date(timeIntervalSince1970: 0))
    }

    private func preflightError(data: Data) async -> BackupImportPreflightError? {
        do {
            _ = try await preflight(data: data)
            return nil
        } catch let error as BackupImportPreflightError {
            return error
        } catch {
            return nil
        }
    }

    private func hasBrokenReference(_ result: ImportPreflightResult, type: String) -> Bool {
        result.issues.contains { $0.code == "broken_reference" && $0.entityType == type }
    }

    private func fixtureData(_ name: String) throws -> Data {
        let bundle = Bundle(for: BackupImportContractBundleMarker.self)
        let candidates = [
            bundle.url(forResource: name, withExtension: "json"),
            bundle.url(forResource: name, withExtension: "json", subdirectory: "backup/fixtures"),
            bundle.url(forResource: name, withExtension: "json", subdirectory: "contracts/backup/fixtures"),
        ]
        guard let url = candidates.compactMap({ $0 }).first else {
            throw FixtureError.missing(name)
        }
        return try Data(contentsOf: url)
    }

    private func fixtureObject(_ name: String) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: fixtureData(name)) as? [String: Any]
        else { throw FixtureError.invalid(name) }
        return object
    }

    private func recanonicalized(_ root: [String: Any]) throws -> Data {
        var root = root
        var integrity = try requiredDictionary(root["integrity"])
        integrity["digest"] = String(repeating: "0", count: 64)
        root["integrity"] = integrity
        var payload = root
        payload.removeValue(forKey: "integrity")
        let canonical = try BackupCanonicalJSONV1.canonicalString(forJSONObject: payload)
        integrity["digest"] = BackupCanonicalJSONV1.sha256Hex(of: canonical)
        root["integrity"] = integrity
        return jsonData(root)
    }

    private func requiredDictionary(_ value: Any?) throws -> [String: Any] {
        guard let value = value as? [String: Any] else { throw FixtureError.invalid("dictionary") }
        return value
    }

    private func jsonData(_ object: Any) -> Data {
        // Test dictionaries contain only explicitly constructed JSON primitives.
        try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func legacyEnvelope() -> [String: Any] {
        [
            "app": "Taste Map", "version": 4, "environment": "development",
            "databaseName": "FoodMapDB", "exportedAt": timestamp,
            "restaurants": [], "visits": [], "photos": [], "users": [],
            "friendships": [], "sharedMeals": [], "sharedMealParticipants": [],
            "restaurantLists": [], "restaurantListItems": [],
        ]
    }

    private func legacyRestaurant(id: String) -> [String: Any] {
        [
            "id": id, "name": "Restaurant \(id)", "latitude": 31.2, "longitude": 121.4,
            "status": "visited", "preferenceLevel": "normal", "amapPoiId": "amap-\(id)",
            "createdAt": timestamp, "updatedAt": timestamp, "deletedAt": NSNull(),
        ]
    }

    private func legacyVisit(
        id: String,
        restaurantID: String,
        dish: [String: Any]? = nil
    ) -> [String: Any] {
        [
            "id": id, "restaurantId": restaurantID, "visitedAt": timestamp,
            "diningMode": "dine_in", "visibility": "private",
            "dishes": dish.map { [$0] } ?? [],
            "createdAt": timestamp, "updatedAt": timestamp, "deletedAt": NSNull(),
        ]
    }

    private func largeLegacyFixture(
        restaurantCount: Int,
        visitCount: Int,
        embeddedDishCount: Int
    ) -> Data {
        var root = legacyEnvelope()
        root["restaurants"] = (0 ..< restaurantCount).map { legacyRestaurant(id: "r-\($0)") }
        root["visits"] = (0 ..< visitCount).map { index in
            let dish: [String: Any]? = index < embeddedDishCount
                ? ["id": "d-\(index)", "name": "Dish \(index)"]
                : nil
            return legacyVisit(
                id: "v-\(index)",
                restaurantID: "r-\(index % restaurantCount)",
                dish: dish
            )
        }
        return jsonData(root)
    }

    private func businessCounts(_ context: ModelContext) throws -> BusinessCounts {
        BusinessCounts(
            restaurants: try context.fetchCount(FetchDescriptor<Restaurant>()),
            visits: try context.fetchCount(FetchDescriptor<Visit>()),
            dishes: try context.fetchCount(FetchDescriptor<Dish>()),
            photos: try context.fetchCount(FetchDescriptor<PhotoAsset>()),
            profiles: try context.fetchCount(FetchDescriptor<UserProfile>()),
            mutations: try context.fetchCount(FetchDescriptor<SyncMutation>())
        )
    }

    private var timestamp: String { "2026-08-29T12:00:00.000Z" }
}

private struct BusinessCounts: Equatable {
    let restaurants: Int
    let visits: Int
    let dishes: Int
    let photos: Int
    let profiles: Int
    let mutations: Int

    static let zero = BusinessCounts(
        restaurants: 0, visits: 0, dishes: 0, photos: 0, profiles: 0, mutations: 0
    )
}

private enum FixtureError: Error {
    case missing(String)
    case invalid(String)
}

private final class BackupImportContractBundleMarker {}

private final class LockedAccessCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var starts = 0
    private var stops = 0

    func start() -> Bool {
        lock.withLock { starts += 1 }
        return true
    }

    func stop() {
        lock.withLock { stops += 1 }
    }

    var snapshot: (Int, Int) {
        lock.withLock { (starts, stops) }
    }
}
