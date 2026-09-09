import Foundation
import OSLog

actor AuthSessionManager: SyncAuthorizationProviding {
    private let api: any AuthAPI
    private let credentialStore: any AuthCredentialStoring
    private let now: @Sendable () -> Date
    private var credential: AuthCredential?
    private var refreshTask: Task<AuthCredential, Error>?
    private var generation = UUID()
    private let appleState: @Sendable (String) async throws -> AppleCredentialStatus
    private var appleCheck: (generation: UUID, task: Task<AppleCredentialStatus, Error>)?

    init(
        api: any AuthAPI,
        credentialStore: any AuthCredentialStoring = KeychainCredentialStore(),
        now: @escaping @Sendable () -> Date = { .now },
        appleState: @escaping @Sendable (String) async throws -> AppleCredentialStatus = AppleCredentialStateProvider.state
    ) {
        self.api = api
        self.credentialStore = credentialStore
        self.now = now
        self.appleState = appleState
        credential = try? credentialStore.load()
    }

    func headers() async throws -> [String: String] {
        do {
            let credential = try await validCredential()
            return ["Authorization": "Bearer \(credential.accessToken)"]
        } catch {
            // Classifications only: never persist tokens, response bodies or messages.
            let kind: String
            switch error {
            case AuthSessionError.notAuthenticated: kind = "not_authenticated"
            case AuthSessionError.sessionExpired: kind = "session_expired"
            case AuthClientError.server(let status, _, _): kind = "server_\(status)"
            case is DecodingError: kind = "response_decode"
            case let error as URLError: kind = "transport_\(error.errorCode)"
            default: kind = "credential_unavailable"
            }
            DeviceAcceptanceLog.record("TasteMapDiagnostic category=auth event=headers_failed kind=\(kind)")
            throw error
        }
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

    func accept(_ response: AuthSessionResponseV1, appleUserIdentifier: String? = nil) throws -> AuthenticatedUserV1 {
        var newCredential = try AuthCredential(response: response)
        newCredential.appleUserIdentifier = appleUserIdentifier
        try credentialStore.save(newCredential)
        advanceGeneration()
        credential = newCredential
        DeviceAcceptanceLog.record("TasteMapDiagnostic category=auth event=session_accepted")
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
        advanceGeneration()
        credential = nil
        refreshTask?.cancel()
        refreshTask = nil
        try credentialStore.delete()
        guard let previous else { return }
        DeviceAcceptanceLog.record("TasteMapDiagnostic category=auth event=local_logout_complete")
        do {
            try await api.logout(accessToken: previous.accessToken, refreshToken: previous.refreshToken)
        } catch {
            // Local logout is authoritative for the device. The server session
            // still expires and can be revoked after the user signs in again.
            throw error
        }
    }

    /// Used only after the server has completed authenticated account deletion.
    /// No second logout request is sent because every server session has already
    /// been revoked by the deletion job.
    func clearLocalSessionAfterAccountDeletion() throws {
        advanceGeneration()
        credential = nil
        refreshTask?.cancel()
        refreshTask = nil
        try credentialStore.delete()
    }

    private func advanceGeneration() {
        generation = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        appleCheck?.task.cancel()
        appleCheck = nil
    }

    /// Invalidates only the originating session; no business-data/delete API.
    func validateAppleCredential() async -> Bool {
        guard let current = credential else { return false }
        let origin = generation
        let status: AppleCredentialStatus
        if let appleUser = current.appleUserIdentifier, !appleUser.isEmpty {
            let task: Task<AppleCredentialStatus, Error>
            if let pending = appleCheck, pending.generation == origin {
                task = pending.task
            } else {
                let provider = appleState
                task = Task { try await provider(appleUser) }
                appleCheck = (origin, task)
            }
            do { status = try await task.value }
            catch {
                if generation == origin { appleCheck = nil }
                return false // System/transport errors are not proof of revocation.
            }
        } else {
            // Legacy session: require one fresh sign-in to establish Apple ID.
            status = .notFound
        }
        guard generation == origin, credential?.user.id == current.user.id,
              credential?.appleUserIdentifier == current.appleUserIdentifier else { return false }
        appleCheck = nil
        switch status {
        case .authorized, .transferred, .unknown:
            return false // Transfer requires a separate migration, never deletion.
        case .revoked, .notFound:
            advanceGeneration()
            credential = nil
            do { try credentialStore.delete() }
            catch { authDebug("Apple credential cleanup failed") }
            let api = self.api
            Task { try? await api.logout(accessToken: current.accessToken, refreshToken: current.refreshToken) }
            return true
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
        if let refreshTask {
            let origin = generation
            let value = try await refreshTask.value
            guard origin == generation else { throw AuthSessionError.notAuthenticated }
            return value
        }
        guard let current = credential, current.refreshTokenExpiresAt > now() else {
            try credentialStore.delete()
            credential = nil
            throw AuthSessionError.sessionExpired
        }
        let api = self.api
        let originatingGeneration = generation
        authDebug("Access token refresh started")
        let task = Task<AuthCredential, Error> {
            var result = try AuthCredential(response: try await api.refresh(refreshToken: current.refreshToken))
            guard result.user.id == current.user.id else { throw AuthSessionError.sessionExpired }
            result.appleUserIdentifier = current.appleUserIdentifier
            return result
        }
        refreshTask = task
        do {
            let refreshed = try await task.value
            guard generation == originatingGeneration else { throw AuthSessionError.notAuthenticated }
            try credentialStore.save(refreshed)
            credential = refreshed
            refreshTask = nil
            authDebug("Access token refresh completed")
            return refreshed
        } catch {
            guard generation == originatingGeneration else { throw AuthSessionError.notAuthenticated }
            refreshTask = nil
            authDebug("Access token refresh failed: \(String(describing: type(of: error)))")
            if case AuthClientError.server(let status, _, _) = error, status == 401 {
                try credentialStore.delete()
                credential = nil
            }
            throw error
        }
    }
}

nonisolated private func authDebug(_ message: String) {
#if DEBUG
    Logger(subsystem: "com.lafayette.tastemap", category: "AuthSession")
        .debug("\(message, privacy: .public)")
#endif
}

enum AuthSessionError: Error, Equatable {
    case notAuthenticated
    case sessionExpired
}
