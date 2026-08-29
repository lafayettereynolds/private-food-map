import CoreFoundation
import CryptoKit
import Foundation

nonisolated enum LegacyWebBackupV4DecodeError: Error, Equatable {
    case malformedJSON
    case rootMustBeObject
    case backupV1UsesDifferentLineage
    case missingApp
    case invalidApp
    case missingVersion
    case invalidVersion
    case missingMetadata(String)
    case invalidMetadata(String)
    case missingCollection(String)
    case invalidCollection(String)
}

/// Strictly recognizes the historical Dexie JSON envelope and converts it to
/// a non-authoritative, in-memory staging graph. It never opens SwiftData and
/// has no networking or sync side effects.
nonisolated struct LegacyWebBackupV4Decoder {
    func decode(_ data: Data) throws -> LegacyBackupStagingGraph {
        let rootValue: Any
        do {
            rootValue = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw LegacyWebBackupV4DecodeError.malformedJSON
        }

        guard let root = rootValue as? [String: Any] else {
            throw LegacyWebBackupV4DecodeError.rootMustBeObject
        }

        if root["format"] != nil || root["schemaVersion"] != nil {
            throw LegacyWebBackupV4DecodeError.backupV1UsesDifferentLineage
        }

        guard root["app"] != nil else { throw LegacyWebBackupV4DecodeError.missingApp }
        guard let app = root["app"] as? String, app == "Taste Map" else {
            throw LegacyWebBackupV4DecodeError.invalidApp
        }

        guard root["version"] != nil else { throw LegacyWebBackupV4DecodeError.missingVersion }
        guard let version = Self.exactInteger(root["version"]), version == 4 else {
            throw LegacyWebBackupV4DecodeError.invalidVersion
        }

        let environment = try requiredMetadataString("environment", root: root)
        let databaseName = try requiredMetadataString("databaseName", root: root)
        let exportedAtSource = try requiredMetadataString("exportedAt", root: root)
        guard let exportedAt = LegacyValueNormalization.timestamp(exportedAtSource) else {
            throw LegacyWebBackupV4DecodeError.invalidMetadata("exportedAt")
        }

        let collectionNames = [
            "restaurants", "visits", "photos", "users", "friendships",
            "sharedMeals", "sharedMealParticipants", "restaurantLists",
            "restaurantListItems",
        ]
        var collections: [String: [LegacyRawRecord]] = [:]
        for name in collectionNames {
            collections[name] = try rawRecords(name, root: root)
        }

        let knownTopLevelFields = Set(collectionNames + [
            "app", "version", "environment", "databaseName", "exportedAt",
        ])
        let unknownTopLevelFields = root.keys
            .filter { !knownTopLevelFields.contains($0) }
            .sorted()
            .map { field in
                LegacyUnknownTopLevelField(
                    name: field,
                    isCollection: root[field] is [Any],
                    collectionCount: (root[field] as? [Any])?.count
                )
            }

        let raw = LegacyWebV4RawEnvelope(
            sourceMetadata: LegacyWebV4SourceMetadata(
                sourceLineage: .legacyWebV4,
                app: app,
                version: version,
                environment: environment,
                databaseName: databaseName,
                exportedAt: exportedAt,
                sourceFingerprint: SHA256.hash(data: data).map {
                    String(format: "%02x", $0)
                }.joined()
            ),
            restaurants: collections["restaurants"] ?? [],
            visits: collections["visits"] ?? [],
            photos: collections["photos"] ?? [],
            users: collections["users"] ?? [],
            friendships: collections["friendships"] ?? [],
            sharedMeals: collections["sharedMeals"] ?? [],
            sharedMealParticipants: collections["sharedMealParticipants"] ?? [],
            restaurantLists: collections["restaurantLists"] ?? [],
            restaurantListItems: collections["restaurantListItems"] ?? [],
            unknownTopLevelFields: unknownTopLevelFields
        )
        return LegacyWebBackupV4Normalizer().normalize(raw)
    }

    private func requiredMetadataString(
        _ field: String,
        root: [String: Any]
    ) throws -> String {
        guard root[field] != nil else {
            throw LegacyWebBackupV4DecodeError.missingMetadata(field)
        }
        guard let value = root[field] as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.utf8.count <= 512 else {
            throw LegacyWebBackupV4DecodeError.invalidMetadata(field)
        }
        return value
    }

    private func rawRecords(
        _ field: String,
        root: [String: Any]
    ) throws -> [LegacyRawRecord] {
        guard root[field] != nil else {
            throw LegacyWebBackupV4DecodeError.missingCollection(field)
        }
        guard let array = root[field] as? [Any] else {
            throw LegacyWebBackupV4DecodeError.invalidCollection(field)
        }
        return array.enumerated().map { index, value in
            LegacyRawRecord(sourceIndex: index, object: value as? [String: Any])
        }
    }

    private static func exactInteger(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        guard double.isFinite, double.rounded() == double,
              double >= Double(Int.min), double <= Double(Int.max) else { return nil }
        return Int(double)
    }
}

nonisolated struct LegacyRawRecord {
    let sourceIndex: Int
    let object: [String: Any]?
}

nonisolated struct LegacyUnknownTopLevelField {
    let name: String
    let isCollection: Bool
    let collectionCount: Int?
}

nonisolated struct LegacyWebV4RawEnvelope {
    let sourceMetadata: LegacyWebV4SourceMetadata
    let restaurants: [LegacyRawRecord]
    let visits: [LegacyRawRecord]
    let photos: [LegacyRawRecord]
    let users: [LegacyRawRecord]
    let friendships: [LegacyRawRecord]
    let sharedMeals: [LegacyRawRecord]
    let sharedMealParticipants: [LegacyRawRecord]
    let restaurantLists: [LegacyRawRecord]
    let restaurantListItems: [LegacyRawRecord]
    let unknownTopLevelFields: [LegacyUnknownTopLevelField]
}

nonisolated enum LegacyValueNormalization {
    static func timestamp(_ source: String) -> BackupTimestampV1? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let wholeSeconds = ISO8601DateFormatter()
        wholeSeconds.formatOptions = [.withInternetDateTime]
        guard let date = fractional.date(from: source) ?? wholeSeconds.date(from: source) else {
            return nil
        }
        let output = ISO8601DateFormatter()
        output.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        output.timeZone = TimeZone(secondsFromGMT: 0)
        return BackupTimestampV1(rawValue: output.string(from: date))
    }

    static func normalizedName(_ source: String) -> String {
        source.precomposedStringWithCompatibilityMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func stableLookupKey(_ source: String) -> String {
        normalizedName(source).folding(
            options: [.caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }
}
