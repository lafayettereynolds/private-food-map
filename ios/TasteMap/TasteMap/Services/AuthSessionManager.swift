import Foundation

actor AuthSessionManager: SyncAuthorizationProviding {
    private let api: any AuthAPI
    private let credentialStore: any AuthCredentialStoring
    private let now: @Sendable () -> Date
    private var credential: AuthCredential?
    private var refreshTask: Task<AuthCredential, Error>?

    init(
        api: any AuthAPI,
        credentialStore: any AuthCredentialStoring = KeychainCredentialStore(),
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.api = api
        self.credentialStore = credentialStore
        self.now = now
        credential = try? credentialStore.load()
    }

    func headers() async throws -> [String: String] {
        let credential = try await validCredential()
        return ["Authorization": "Bearer \(credential.accessToken)"]
    }

    func recoverUnauthorized(failedAuthorization: String?) async throws -> Bool {
        guard credential != nil else { return false }
        if let failedAuthorization,
           failedAuthorization != "Bearer \(credential?.accessToken ?? "")" {
            return true
        }
        _ = try await refreshCredential()
        return true
    }

    func accept(_ response: AuthSessionResponseV1) throws -> AuthenticatedUserV1 {
        let newCredential = try AuthCredential(response: response)
        try credentialStore.save(newCredential)
        credential = newCredential
        return newCredential.user
    }

    func restoredUser() -> AuthenticatedUserV1? {
        guard let credential, credential.refreshTokenExpiresAt > now() else { return nil }
        return credential.user
    }

    func forceRefresh() async throws -> AuthenticatedUserV1 {
        try await refreshCredential().user
    }

    func logout() async throws {
        let previous = credential
        credential = nil
        refreshTask?.cancel()
        refreshTask = nil
        try credentialStore.delete()
        guard let previous else { return }
        do {
            try await api.logout(accessToken: previous.accessToken, refreshToken: previous.refreshToken)
        } catch {
            // Local logout is authoritative for the device. The server session
            // still expires and can be revoked after the user signs in again.
            throw error
        }
    }

    private func validCredential() async throws -> AuthCredential {
        guard let credential else { throw AuthSessionError.notAuthenticated }
        guard credential.refreshTokenExpiresAt > now() else {
            try credentialStore.delete()
            self.credential = nil
            throw AuthSessionError.sessionExpired
        }
        if credential.accessTokenExpiresAt.timeIntervalSince(now()) > 30 { return credential }
        return try await refreshCredential()
    }

    private func refreshCredential() async throws -> AuthCredential {
        if let refreshTask { return try await refreshTask.value }
        guard let current = credential, current.refreshTokenExpiresAt > now() else {
            try credentialStore.delete()
            credential = nil
            throw AuthSessionError.sessionExpired
        }
        let api = self.api
        let task = Task<AuthCredential, Error> {
            try AuthCredential(response: try await api.refresh(refreshToken: current.refreshToken))
        }
        refreshTask = task
        do {
            let refreshed = try await task.value
            try credentialStore.save(refreshed)
            credential = refreshed
            refreshTask = nil
            return refreshed
        } catch {
            refreshTask = nil
            if case AuthClientError.server(let status, _, _) = error, status == 401 {
                try credentialStore.delete()
                credential = nil
            }
            throw error
        }
    }
}

enum AuthSessionError: Error, Equatable {
    case notAuthenticated
    case sessionExpired
}
