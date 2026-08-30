import Foundation
import Testing
@testable import TasteMap

@Suite("Native Auth Session", .serialized)
struct AuthSessionManagerTests {
    @Test("An isolated credential session survives a new manager instance")
    func isolatedCredentialRestoresAfterRelaunch() async throws {
        let store = IsolatedAuthCredentialStore()
        let credential = sampleCredential(accessToken: "tm_access_restart")

        try store.save(credential)
        let relaunchedManager = AuthSessionManager(
            api: MockAuthAPI(),
            credentialStore: store
        )

        #expect(await relaunchedManager.restoredUser() == credential.user)
        #expect(try await relaunchedManager.headers()["Authorization"] == "Bearer tm_access_restart")
    }

    @Test("Concurrent 401 recovery performs one refresh")
    func concurrentUnauthorizedUsesSingleFlightRefresh() async throws {
        let store = MemoryCredentialStore(sampleCredential(accessToken: "tm_access_old"))
        let api = MockAuthAPI()
        let manager = AuthSessionManager(api: api, credentialStore: store)

        try await withThrowingTaskGroup(of: Bool.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    try await manager.recoverUnauthorized(failedAuthorization: "Bearer tm_access_old")
                }
            }
            for try await recovered in group { #expect(recovered) }
        }

        #expect(await api.refreshCount == 1)
        #expect(try await manager.headers()["Authorization"] == "Bearer tm_access_refreshed")
    }

    @Test("Logout clears local credentials even if server revoke fails")
    func logoutAlwaysClearsKeychainState() async {
        let store = MemoryCredentialStore(sampleCredential(accessToken: "tm_access_logout"))
        let api = MockAuthAPI(logoutError: AuthClientError.invalidResponse)
        let manager = AuthSessionManager(api: api, credentialStore: store)

        await #expect(throws: AuthClientError.invalidResponse) {
            try await manager.logout()
        }
        #expect((try? store.load()) == nil)
        #expect(await manager.restoredUser() == nil)
    }

    @Test("Completed account deletion clears Keychain without issuing a second logout")
    func accountDeletionClearsOnlyLocalSession() async throws {
        let store = MemoryCredentialStore(sampleCredential(accessToken: "tm_access_deleted"))
        let api = MockAuthAPI()
        let manager = AuthSessionManager(api: api, credentialStore: store)

        try await manager.clearLocalSessionAfterAccountDeletion()

        #expect((try? store.load()) == nil)
        #expect(await manager.restoredUser() == nil)
        #expect(await api.logoutCount == 0)
    }

    private func sampleCredential(accessToken: String) -> AuthCredential {
        AuthCredential(
            user: AuthenticatedUserV1(id: "tm_test_user", email: nil),
            accessToken: accessToken,
            accessTokenExpiresAt: Date().addingTimeInterval(600),
            refreshToken: "tm_refresh_test_value",
            refreshTokenExpiresAt: Date().addingTimeInterval(3_600)
        )
    }
}

nonisolated private final class MemoryCredentialStore: AuthCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var credential: AuthCredential?

    init(_ credential: AuthCredential?) { self.credential = credential }

    func load() throws -> AuthCredential? {
        lock.withLock { credential }
    }

    func save(_ credential: AuthCredential) throws {
        lock.withLock { self.credential = credential }
    }

    func delete() throws {
        lock.withLock { credential = nil }
    }
}

private actor MockAuthAPI: AuthAPI {
    private(set) var refreshCount = 0
    private(set) var logoutCount = 0
    private let logoutError: Error?

    init(logoutError: Error? = nil) {
        self.logoutError = logoutError
    }

    func challenge() async throws -> AuthChallengeV1 {
        throw AuthClientError.invalidResponse
    }

    func exchangeAppleToken(
        identityToken: String,
        state: String,
        nonce: String,
        givenName: String?,
        familyName: String?
    ) async throws -> AuthSessionResponseV1 {
        throw AuthClientError.invalidResponse
    }

    func refresh(refreshToken: String) async throws -> AuthSessionResponseV1 {
        refreshCount += 1
        try await Task.sleep(for: .milliseconds(50))
        let formatter = ISO8601DateFormatter()
        return AuthSessionResponseV1(
            apiVersion: AuthV1Contract.apiVersion,
            user: AuthenticatedUserV1(id: "tm_test_user", email: nil),
            session: AuthSessionTokensV1(
                accessToken: "tm_access_refreshed",
                accessTokenExpiresAt: formatter.string(from: Date().addingTimeInterval(600)),
                refreshToken: "tm_refresh_rotated_value",
                refreshTokenExpiresAt: formatter.string(from: Date().addingTimeInterval(3_600))
            )
        )
    }

    func logout(accessToken: String?, refreshToken: String) async throws {
        logoutCount += 1
        if let logoutError { throw logoutError }
    }
}
