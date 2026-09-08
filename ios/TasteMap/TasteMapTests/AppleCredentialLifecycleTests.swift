import AuthenticationServices
import Foundation
import SwiftData
import Testing
@testable import TasteMap

@Suite("Apple credential lifecycle", .serialized)
struct AppleCredentialLifecycleTests {
    @Test(arguments: [AppleCredentialStatus.authorized, .transferred, .unknown])
    func validAndMigrationStatesPreserveSession(_ state: AppleCredentialStatus) async throws {
        let store = LifecycleStore(credential("A"))
        let manager = AuthSessionManager(api: LifecycleAPI(), credentialStore: store, appleState: { _ in state })
        #expect(await manager.validateAppleCredential() == false)
        #expect(await manager.restoredUser()?.id == "A")
        #expect(try store.load()?.appleUserIdentifier == "apple-A")
    }

    @Test(arguments: [AppleCredentialStatus.revoked, .notFound])
    func invalidStateClearsOnlyAuth(_ state: AppleCredentialStatus) async throws {
        let store = LifecycleStore(credential("A"))
        let api = LifecycleAPI()
        let manager = AuthSessionManager(api: api, credentialStore: store, appleState: { _ in state })
        #expect(await manager.validateAppleCredential())
        #expect(await manager.restoredUser() == nil)
        #expect(try store.load() == nil)
        await #expect(throws: (any Error).self) { _ = try await manager.headers() }
        #expect(await manager.validateAppleCredential() == false)
        #expect(store.deletions == 1)
        // Production operation can call AuthAPI.logout only. It is never given
        // a business store, data purger, or Account Delete API.
        for _ in 0..<100 { if await api.logoutCount == 1 { break }; await Task.yield() }
        #expect(await api.logoutCount == 1)
        #expect(await api.otherCalls == 0)
    }

    @Test("A callback cannot invalidate B, nor a new A generation")
    func lateCallbackIsolation() async throws {
        for next in ["B", "A"] {
            let provider = LifecycleProvider()
            let store = LifecycleStore(credential("A"))
            let manager = AuthSessionManager(api: LifecycleAPI(), credentialStore: store, appleState: { try await provider.state($0) })
            let check = Task { await manager.validateAppleCredential() }
            await provider.waitUntilRequested()
            _ = try await manager.accept(response(next), appleUserIdentifier: "apple-" + next)
            await provider.finish(.revoked)
            #expect(await check.value == false)
            #expect(await manager.restoredUser()?.id == next)
            #expect(try store.load()?.user.id == next)
            #expect(store.deletions == 0)
        }
    }

    @Test("B revoke after A switch affects B auth only")
    func currentBRevocation() async throws {
        let store = LifecycleStore(credential("A"))
        let manager = AuthSessionManager(api: LifecycleAPI(), credentialStore: store, appleState: { id in
            #expect(id == "apple-B")
            return .revoked
        })
        _ = try await manager.accept(response("B"), appleUserIdentifier: "apple-B")
        #expect(await manager.validateAppleCredential())
        #expect(store.deletions == 1)
    }

    @Test("Logout ignores late credential state")
    func lateAfterLogout() async throws {
        let provider = LifecycleProvider()
        let store = LifecycleStore(credential("A"))
        let manager = AuthSessionManager(api: LifecycleAPI(), credentialStore: store, appleState: { try await provider.state($0) })
        let task = Task { await manager.validateAppleCredential() }
        await provider.waitUntilRequested()
        try await manager.logout()
        await provider.finish(.revoked)
        #expect(await task.value == false)
        #expect(store.deletions == 1)
    }

    @Test("Duplicate concurrent checks share one Apple request")
    func duplicateChecks() async throws {
        let provider = LifecycleProvider()
        let store = LifecycleStore(credential("A"))
        let manager = AuthSessionManager(api: LifecycleAPI(), credentialStore: store, appleState: { try await provider.state($0) })
        let one = Task { await manager.validateAppleCredential() }
        await provider.waitUntilRequested()
        let two = Task { await manager.validateAppleCredential() }
        await Task.yield()
        await provider.finish(.revoked)
        let results = await [one.value, two.value]
        #expect(results.filter { $0 }.count == 1)
        #expect(store.deletions == 1)
        #expect(await provider.calls == 1)
    }

    @Test("Restored Keychain Apple ID is checked; legacy decoder remains compatible")
    func restoredAndLegacy() async throws {
        let store = LifecycleStore(credential("A"))
        let relaunched = AuthSessionManager(api: LifecycleAPI(), credentialStore: store, appleState: { id in
            #expect(id == "apple-A"); return .revoked
        })
        #expect(await relaunched.validateAppleCredential())
        var legacy = credential("A")
        legacy.appleUserIdentifier = nil
        let bytes = try JSONEncoder().encode(legacy)
        let decoded = try JSONDecoder().decode(AuthCredential.self, from: bytes)
        #expect(decoded.appleUserIdentifier == nil)
        let legacyManager = AuthSessionManager(api: LifecycleAPI(), credentialStore: LifecycleStore(decoded))
        #expect(await legacyManager.validateAppleCredential())
    }

    @Test("Transient provider failure is not revoked")
    func systemError() async {
        let manager = AuthSessionManager(api: LifecycleAPI(), credentialStore: LifecycleStore(credential("A")), appleState: { _ in throw URLError(.notConnectedToInternet) })
        #expect(await manager.validateAppleCredential() == false)
        #expect(await manager.restoredUser()?.id == "A")
    }

    @Test("Native launch restore invalidates private context without a backend")
    @MainActor
    func nativeRestoreScope() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let a = Restaurant(ownerUserID: "A", name: "A", address: "A", latitude: 30, longitude: 120)
        let b = Restaurant(ownerUserID: "B", name: "B", address: "B", latitude: 31, longitude: 121)
        context.insert(a)
        context.insert(b)
        try context.save()
        let store = LifecycleStore(credential("A"))
        let services = NativeAuthServices(configuration: APIConfiguration(environment: .production, baseURL: nil),
                                          credentialStore: store, appleState: { _ in .revoked })
        var cleanups = 0
        services.credentialInvalidationHandler = { cleanups += 1 }
        #expect(await services.restoreLocalAccountScope() == nil)
        #expect(services.localAccountScope == .guest)
        #expect(cleanups == 1)
        await services.refreshAppleCredential()
        #expect(cleanups == 1)
        #expect(try context.fetchCount(FetchDescriptor<Restaurant>()) == 2)
        #expect(a.ownerUserID == "A" && b.ownerUserID == "B")
    }

    @Test("Observer owns one registration per event and tears down")
    func observerLifecycle() {
        let center = NotificationCenter()
        let counter = LifecycleCounter()
        var observer: AppleCredentialObservers? = AppleCredentialObservers(center: center) { counter.increment() }
        #expect(observer != nil)
        center.post(name: ASAuthorizationAppleIDProvider.credentialRevokedNotification, object: nil)
        center.post(name: ASAuthorizationAppleIDProvider.credentialRevokedNotification, object: nil)
        #expect(counter.value == 2)
        observer = nil
        center.post(name: ASAuthorizationAppleIDProvider.credentialRevokedNotification, object: nil)
        #expect(counter.value == 2)
    }

    @Test("In-flight token refresh cannot resurrect a revoked credential")
    func lateTokenRefresh() async throws {
        let api = LifecycleRefreshAPI()
        let store = LifecycleStore(credential("A"))
        let manager = AuthSessionManager(api: api, credentialStore: store, appleState: { _ in .revoked })
        let refresh = Task { try await manager.forceRefresh() }
        await api.waitUntilRequested()
        #expect(await manager.validateAppleCredential())
        await api.finish(response("A"))
        await #expect(throws: (any Error).self) { _ = try await refresh.value }
        #expect(await manager.restoredUser() == nil)
        #expect(try store.load() == nil)
    }

    private func credential(_ id: String) -> AuthCredential {
        var result = try! AuthCredential(response: response(id))
        result.appleUserIdentifier = "apple-" + id
        return result
    }
    private func response(_ id: String) -> AuthSessionResponseV1 {
        let date = ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600))
        return .init(apiVersion: 1, user: .init(id: id, email: nil), session: .init(accessToken: "test-access-" + id, accessTokenExpiresAt: date, refreshToken: "test-refresh-" + id, refreshTokenExpiresAt: date))
    }
}

nonisolated private final class LifecycleStore: AuthCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value: AuthCredential?
    private var count = 0
    var deletions: Int { lock.withLock { count } }
    init(_ value: AuthCredential?) { self.value = value }
    func load() throws -> AuthCredential? { lock.withLock { value } }
    func save(_ credential: AuthCredential) throws { lock.withLock { value = credential } }
    func delete() throws { lock.withLock { value = nil; count += 1 } }
}
nonisolated private final class LifecycleCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}
private actor LifecycleProvider {
    private var continuation: CheckedContinuation<AppleCredentialStatus, any Error>?
    private(set) var calls = 0
    func state(_ id: String) async throws -> AppleCredentialStatus {
        calls += 1
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func waitUntilRequested() async { while continuation == nil { await Task.yield() } }
    func finish(_ state: AppleCredentialStatus) { continuation?.resume(returning: state); continuation = nil }
}
private actor LifecycleAPI: AuthAPI {
    private(set) var logoutCount = 0
    private(set) var otherCalls = 0
    func challenge() async throws -> AuthChallengeV1 { otherCalls += 1; throw AuthClientError.invalidResponse }
    func exchangeAppleToken(identityToken: String, state: String, nonce: String, givenName: String?, familyName: String?, referralCode: String?) async throws -> AuthSessionResponseV1 { otherCalls += 1; throw AuthClientError.invalidResponse }
    func refresh(refreshToken: String) async throws -> AuthSessionResponseV1 { otherCalls += 1; throw AuthClientError.invalidResponse }
    func logout(accessToken: String?, refreshToken: String) async throws { logoutCount += 1 }
}

private actor LifecycleRefreshAPI: AuthAPI {
    private var pending: CheckedContinuation<AuthSessionResponseV1, any Error>?
    func waitUntilRequested() async { while pending == nil { await Task.yield() } }
    func finish(_ value: AuthSessionResponseV1) { pending?.resume(returning: value); pending = nil }
    func challenge() async throws -> AuthChallengeV1 { throw AuthClientError.invalidResponse }
    func exchangeAppleToken(identityToken: String, state: String, nonce: String, givenName: String?, familyName: String?, referralCode: String?) async throws -> AuthSessionResponseV1 { throw AuthClientError.invalidResponse }
    func refresh(refreshToken: String) async throws -> AuthSessionResponseV1 {
        try await withCheckedThrowingContinuation { pending = $0 }
    }
    func logout(accessToken: String?, refreshToken: String) async throws {}
}
