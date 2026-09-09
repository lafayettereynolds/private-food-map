import Foundation
import Security

nonisolated protocol AuthCredentialStoring: Sendable {
    func load() throws -> AuthCredential?
    func save(_ credential: AuthCredential) throws
    func delete() throws
}

nonisolated enum KeychainCredentialStoreError: Error, Equatable {
    case unexpectedStatus(OSStatus)
    case invalidData
}

nonisolated struct KeychainCredentialStore: AuthCredentialStoring, Sendable {
    static let defaultService = APIConfiguration.current().environment == .development
        ? "com.lafayette.tastemap.auth.development" : "com.lafayette.tastemap.auth"
    static let defaultAccount = "native-session-v1"

    let service: String
    let account: String

    init(service: String = Self.defaultService, account: String = Self.defaultAccount) {
        self.service = service
        self.account = account
    }

    func load() throws -> AuthCredential? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainCredentialStoreError.unexpectedStatus(status) }
        guard let data = result as? Data,
              let credential = try? JSONDecoder().decode(AuthCredential.self, from: data) else {
            throw KeychainCredentialStoreError.invalidData
        }
        return credential
    }

    func save(_ credential: AuthCredential) throws {
        let data = try JSONEncoder().encode(credential)
        let status = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = baseQuery
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(attributes as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainCredentialStoreError.unexpectedStatus(addStatus) }
            return
        }
        guard status == errSecSuccess else { throw KeychainCredentialStoreError.unexpectedStatus(status) }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainCredentialStoreError.unexpectedStatus(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
    }
}
