import CryptoKit
import Foundation

public enum PendingImportStoreError: Error {
    case missingAppGroupConfiguration
    case appGroupUnavailable
    case emptyPayload
}

public final class PendingExternalRestaurantImportStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let storageKey = "taste-map.pending-external-restaurant-imports.v1"
    private let queue = DispatchQueue(label: "taste-map.pending-import-store")

    public convenience init(bundle: Bundle = .main) throws {
        guard let groupIdentifier = bundle.object(forInfoDictionaryKey: "TasteMapAppGroupIdentifier") as? String,
              !groupIdentifier.isEmpty else {
            throw PendingImportStoreError.missingAppGroupConfiguration
        }
        guard let defaults = UserDefaults(suiteName: groupIdentifier) else {
            throw PendingImportStoreError.appGroupUnavailable
        }
        self.init(defaults: defaults)
    }

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    @discardableResult
    public func enqueue(
        source: ExternalRestaurantImportSource,
        payload: String,
        ownerSubject: String?
    ) throws -> PendingExternalRestaurantImport {
        let sanitized = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty else { throw PendingImportStoreError.emptyPayload }
        let fingerprint = Self.fingerprint(for: sanitized, ownerSubject: ownerSubject)
        return try queue.sync {
            var items = loadUnsafe().filter { Date().timeIntervalSince($0.createdAt) < 60 * 60 * 24 * 7 }
            if let existing = items.first(where: { $0.normalizedFingerprint == fingerprint && $0.ownerSubject == ownerSubject }) {
                return existing
            }
            let pending = PendingExternalRestaurantImport(
                source: source,
                payload: sanitized,
                normalizedFingerprint: fingerprint,
                ownerSubject: ownerSubject
            )
            items.append(pending)
            try saveUnsafe(items)
            return pending
        }
    }

    public func item(id: UUID, ownerSubject: String?) -> PendingExternalRestaurantImport? {
        queue.sync { loadUnsafe().first { $0.id == id && $0.ownerSubject == ownerSubject } }
    }

    public func updateFailure(id: UUID, ownerSubject: String?, error: String) throws {
        try queue.sync {
            var items = loadUnsafe()
            guard let index = items.firstIndex(where: { $0.id == id && $0.ownerSubject == ownerSubject }) else { return }
            items[index].attemptCount += 1
            items[index].lastError = String(error.prefix(300))
            try saveUnsafe(items)
        }
    }

    public func remove(id: UUID, ownerSubject: String?) throws {
        try queue.sync {
            let items = loadUnsafe().filter { !($0.id == id && $0.ownerSubject == ownerSubject) }
            try saveUnsafe(items)
        }
    }

    private func loadUnsafe() -> [PendingExternalRestaurantImport] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        return (try? decoder.decode([PendingExternalRestaurantImport].self, from: data)) ?? []
    }

    private func saveUnsafe(_ items: [PendingExternalRestaurantImport]) throws {
        defaults.set(try encoder.encode(items), forKey: storageKey)
    }

    private static func fingerprint(for value: String, ownerSubject: String?) -> String {
        let normalized = value.precomposedStringWithCompatibilityMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let digest = SHA256.hash(data: Data("\(ownerSubject ?? "anonymous")|\(normalized)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
