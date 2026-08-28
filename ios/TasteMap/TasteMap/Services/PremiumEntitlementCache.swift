import Foundation
import Security

nonisolated protocol PremiumEntitlementCaching: Sendable {
    func load(userID: String) throws -> PremiumEntitlementSnapshot?
    func save(_ snapshot: PremiumEntitlementSnapshot) throws
    func delete(userID: String) throws
}

nonisolated struct KeychainPremiumEntitlementCache: PremiumEntitlementCaching, Sendable {
    static let defaultService = "com.lafayette.tastemap.premium-cache"
    let service: String

    init(service: String = Self.defaultService) {
        self.service = service
    }

    func load(userID: String) throws -> PremiumEntitlementSnapshot? {
        var query = baseQuery(userID: userID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw PremiumEntitlementCacheError.unexpectedStatus(status) }
        guard let data = result as? Data,
              let snapshot = try? JSONDecoder().decode(PremiumEntitlementSnapshot.self, from: data),
              snapshot.userID == userID else {
            throw PremiumEntitlementCacheError.invalidData
        }
        return snapshot
    }

    func save(_ snapshot: PremiumEntitlementSnapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        let query = baseQuery(userID: snapshot.userID)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = query
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(attributes as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw PremiumEntitlementCacheError.unexpectedStatus(addStatus)
            }
            return
        }
        guard status == errSecSuccess else { throw PremiumEntitlementCacheError.unexpectedStatus(status) }
    }

    func delete(userID: String) throws {
        let status = SecItemDelete(baseQuery(userID: userID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PremiumEntitlementCacheError.unexpectedStatus(status)
        }
    }

    private func baseQuery(userID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "premium-v1:\(userID)",
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
    }
}

nonisolated enum PremiumEntitlementCacheError: Error, Equatable {
    case unexpectedStatus(OSStatus)
    case invalidData
}

nonisolated final class InMemoryPremiumEntitlementCache: PremiumEntitlementCaching, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: PremiumEntitlementSnapshot]

    init(values: [String: PremiumEntitlementSnapshot] = [:]) {
        self.values = values
    }

    func load(userID: String) throws -> PremiumEntitlementSnapshot? {
        lock.withLock { values[userID] }
    }

    func save(_ snapshot: PremiumEntitlementSnapshot) throws {
        lock.withLock { values[snapshot.userID] = snapshot }
    }

    func delete(userID: String) throws {
        _ = lock.withLock { values.removeValue(forKey: userID) }
    }
}
