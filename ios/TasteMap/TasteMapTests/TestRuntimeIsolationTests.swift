import Foundation
import Testing
@testable import TasteMap

struct TestRuntimeIsolationTests {
    @Test("XCTest host defaults to isolated unit runtime")
    func unitRuntimeDetection() {
        let runtime = TasteMapRuntimeConfiguration.resolve(
            environment: ["XCTestConfigurationFilePath": "/tmp/test.xctestconfiguration"],
            arguments: ["TasteMap"]
        )

        #expect(runtime.tier == .unit)
        #expect(runtime.isolatesPersistentState)
        #expect(!runtime.allowsNetwork)
        #expect(!runtime.allowsAutomaticServices)
    }

    @Test("UI fixtures are isolated without depending on an empty simulator Keychain")
    func uiRuntimeDetection() {
        let explicit = TasteMapRuntimeConfiguration.resolve(
            environment: [TasteMapRuntimeConfiguration.uiRuntimeEnvironmentKey: "1"],
            arguments: ["TasteMap"]
        )
        let existingFixture = TasteMapRuntimeConfiguration.resolve(
            environment: ["TASTEMAP_P3C_DISCOVERY_UI_TEST": "1"],
            arguments: ["TasteMap"]
        )

        #expect(explicit.tier == .ui)
        #expect(existingFixture.tier == .ui)
        #expect(!existingFixture.allowsNetwork)
    }

    @Test("Development E2E network access requires an explicit tier")
    func developmentE2ETier() {
        let runtime = TasteMapRuntimeConfiguration.resolve(
            environment: [TasteMapRuntimeConfiguration.explicitTierEnvironmentKey: "development-e2e"],
            arguments: ["TasteMap"]
        )

        #expect(runtime.tier == .developmentE2E)
        #expect(runtime.isolatesPersistentState)
        #expect(runtime.allowsNetwork)
        #expect(!runtime.allowsAutomaticServices)
    }

    @Test("Normal application launch keeps production runtime behavior")
    func applicationTier() {
        let runtime = TasteMapRuntimeConfiguration.resolve(
            environment: [:],
            arguments: ["TasteMap"]
        )

        #expect(runtime.tier == .application)
        #expect(!runtime.isolatesPersistentState)
        #expect(runtime.allowsNetwork)
        #expect(runtime.allowsAutomaticServices)
    }

    @Test("Isolated credentials never leak between test runtime instances")
    func isolatedCredentialStore() throws {
        let first = IsolatedAuthCredentialStore()
        let second = IsolatedAuthCredentialStore()
        let credential = AuthCredential(
            user: AuthenticatedUserV1(id: "tm_runtime_test", email: nil),
            accessToken: "isolated-access",
            accessTokenExpiresAt: .distantFuture,
            refreshToken: "isolated-refresh",
            refreshTokenExpiresAt: .distantFuture
        )

        try first.save(credential)
        #expect(try first.load() == credential)
        #expect(try second.load() == nil)
        try first.delete()
        #expect(try first.load() == nil)
    }

    @Test("Unit and UI sessions fail closed instead of reaching a real endpoint")
    func blockedNetworkSession() async {
        let session = TasteMapTestRuntimeResources.networkSession(
            for: TasteMapRuntimeConfiguration(tier: .unit)
        )

        do {
            _ = try await session.data(from: URL(string: "https://api-dev.tastemap.cn/health")!)
            Issue.record("The isolated test session unexpectedly reached the network")
        } catch let error as URLError {
            #expect(error.code == .notConnectedToInternet)
        } catch {
            Issue.record("Unexpected isolated network error: \(type(of: error))")
        }
    }
}
