import CoreFoundation
import Foundation

nonisolated struct BackupImportDetectedFormat: Equatable, Sendable {
    let format: BackupImportSourceFormat
    let version: Int
}

nonisolated enum BackupImportFormatDetector {
    static func detect(_ root: [String: Any]) throws -> BackupImportDetectedFormat {
        let hasBackupSignal = root["format"] != nil || root["schemaVersion"] != nil
        let hasLegacySignal = root["app"] != nil || root["version"] != nil
        guard !(hasBackupSignal && hasLegacySignal) else {
            throw BackupImportPreflightError.unsupportedFormat
        }
        if hasBackupSignal {
            guard root["format"] as? String == BackupV1Contract.format else {
                throw BackupImportPreflightError.invalidBackupV1Format
            }
            guard exactInteger(root["schemaVersion"]) == BackupV1Contract.schemaVersion else {
                throw BackupImportPreflightError.invalidBackupV1Version
            }
            return BackupImportDetectedFormat(format: .backupV1, version: 1)
        }
        if hasLegacySignal {
            guard root["app"] as? String == "Taste Map" else {
                throw BackupImportPreflightError.invalidLegacyApp
            }
            guard exactInteger(root["version"]) == 4 else {
                throw BackupImportPreflightError.invalidLegacyVersion
            }
            return BackupImportDetectedFormat(format: .legacyWebV4, version: 4)
        }
        throw BackupImportPreflightError.unsupportedFormat
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

nonisolated struct BackupImportJSONInspector {
    static let maximumDepth = 32
    static let maximumTotalEntityCount = 250_000

    private static let entityLimits: [String: Int] = [
        "restaurants": 25_000,
        "visits": 100_000,
        "dishes": 200_000,
        "visitDishes": 300_000,
        "photos": 100_000,
        "companions": 25_000,
        "recommendationSources": 25_000,
        "profiles": 1,
        "restaurantLists": 10_000,
        "restaurantListItems": 200_000,
        "tombstones": 250_000,
    ]

    func inspect(_ data: Data) throws -> [String: Any] {
        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw BackupImportPreflightError.malformedJSON
        }
        guard let root = value as? [String: Any] else {
            throw BackupImportPreflightError.rootMustBeObject
        }
        try inspectShape(root)
        try inspectEntityLimits(root)
        return root
    }

    private func inspectShape(_ root: [String: Any]) throws {
        var stack: [(value: Any, depth: Int, field: String)] = [(root, 1, "root")]
        while let item = stack.popLast() {
            guard item.depth <= Self.maximumDepth else {
                throw BackupImportPreflightError.excessiveNesting(
                    maximumDepth: Self.maximumDepth
                )
            }
            if let object = item.value as? [String: Any] {
                for (key, value) in object {
                    guard key.utf8.count <= 200 else {
                        throw BackupImportPreflightError.stringLimitExceeded(
                            field: "JSON key", maximumBytes: 200
                        )
                    }
                    stack.append((value, item.depth + 1, key))
                }
            } else if let array = item.value as? [Any] {
                for value in array {
                    stack.append((value, item.depth + 1, item.field))
                }
                if Self.isTagField(item.field), array.count > 100 {
                    throw BackupImportPreflightError.collectionLimitExceeded(
                        collection: item.field, maximum: 100
                    )
                }
            } else if let string = item.value as? String {
                let maximum = Self.maximumStringBytes(field: item.field)
                guard string.utf8.count <= maximum else {
                    throw BackupImportPreflightError.stringLimitExceeded(
                        field: item.field, maximumBytes: maximum
                    )
                }
            } else if let number = item.value as? NSNumber,
                      CFGetTypeID(number) != CFBooleanGetTypeID(),
                      !number.doubleValue.isFinite {
                throw BackupImportPreflightError.invalidNumber
            }
        }
    }

    private func inspectEntityLimits(_ root: [String: Any]) throws {
        if let entities = root["entities"] as? [String: Any] {
            var total = 0
            for (name, limit) in Self.entityLimits where name != "tombstones" {
                guard let array = entities[name] as? [Any] else { continue }
                try Self.validateCount(array.count, collection: name, maximum: limit)
                total += array.count
            }
            if let tombstones = root["tombstones"] as? [Any] {
                try Self.validateCount(
                    tombstones.count,
                    collection: "tombstones",
                    maximum: Self.entityLimits["tombstones"]!
                )
                total += tombstones.count
            }
            guard total <= Self.maximumTotalEntityCount else {
                throw BackupImportPreflightError.totalEntityLimitExceeded(
                    maximum: Self.maximumTotalEntityCount
                )
            }
            return
        }

        let legacyMapping: [(name: String, limit: Int)] = [
            ("restaurants", 25_000), ("visits", 100_000), ("photos", 100_000),
            ("users", 25_000), ("restaurantLists", 10_000),
            ("restaurantListItems", 200_000),
        ]
        var total = 0
        for item in legacyMapping {
            guard let array = root[item.name] as? [Any] else { continue }
            try Self.validateCount(array.count, collection: item.name, maximum: item.limit)
            total += array.count
        }
        if let visits = root["visits"] as? [[String: Any]] {
            let embeddedDishes = visits.reduce(0) { partial, visit in
                partial + ((visit["dishes"] as? [Any])?.count ?? 0)
            }
            try Self.validateCount(embeddedDishes, collection: "dishes", maximum: 200_000)
            try Self.validateCount(embeddedDishes, collection: "visitDishes", maximum: 300_000)
            total += embeddedDishes * 2
        }
        for ignoredCollection in ["friendships", "sharedMeals", "sharedMealParticipants"] {
            total += (root[ignoredCollection] as? [Any])?.count ?? 0
        }
        guard total <= Self.maximumTotalEntityCount else {
            throw BackupImportPreflightError.totalEntityLimitExceeded(
                maximum: Self.maximumTotalEntityCount
            )
        }
    }

    private static func validateCount(
        _ count: Int,
        collection: String,
        maximum: Int
    ) throws {
        guard count <= maximum else {
            throw BackupImportPreflightError.collectionLimitExceeded(
                collection: collection, maximum: maximum
            )
        }
    }

    private static func maximumStringBytes(field: String) -> Int {
        let normalized = field.lowercased()
        if normalized == "id" || normalized.hasSuffix("id") || normalized.hasSuffix("ids")
            || normalized.contains("globalkey") {
            return 128
        }
        if normalized.contains("url") { return 2_048 }
        if normalized.contains("note") || normalized.contains("bio")
            || normalized.contains("description") {
            return 20_000
        }
        if normalized.contains("name") || normalized == "title" { return 200 }
        if isTagField(field) { return 100 }
        return 20_000
    }

    private static func isTagField(_ field: String) -> Bool {
        field.lowercased().contains("tag")
    }
}
