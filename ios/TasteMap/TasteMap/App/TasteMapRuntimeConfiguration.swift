import Foundation

enum TasteMapRuntimeTier: String, Equatable, Sendable {
    case application
    case unit
    case localIntegration = "local-integration"
    case ui
    case developmentE2E = "development-e2e"
}

struct TasteMapRuntimeConfiguration: Equatable, Sendable {
    #if DEBUG
    static let explicitTierEnvironmentKey = "TASTEMAP_TEST_TIER"
    static let uiRuntimeEnvironmentKey = "TASTEMAP_UI_TEST_RUNTIME"
    #endif

    let tier: TasteMapRuntimeTier

    var isolatesPersistentState: Bool { tier != .application }
    var allowsNetwork: Bool { tier == .application || tier == .developmentE2E }
    var allowsAutomaticServices: Bool { tier == .application }

    static var current: TasteMapRuntimeConfiguration {
        #if DEBUG
        resolve(
            environment: ProcessInfo.processInfo.environment,
            arguments: ProcessInfo.processInfo.arguments
        )
        #else
        // Release artifacts cannot be switched into a fixture or isolated-test
        // tier through process environment or launch arguments.
        TasteMapRuntimeConfiguration(tier: .application)
        #endif
    }

    #if DEBUG
    static func resolve(
        environment: [String: String],
        arguments: [String]
    ) -> TasteMapRuntimeConfiguration {
        if let explicit = environment[explicitTierEnvironmentKey],
           let tier = TasteMapRuntimeTier(rawValue: explicit) {
            return TasteMapRuntimeConfiguration(tier: tier)
        }
        if environment["XCTestConfigurationFilePath"] != nil {
            return TasteMapRuntimeConfiguration(tier: .unit)
        }
        let isUIFixture = environment[uiRuntimeEnvironmentKey] == "1"
            || environment.keys.contains { key in
                key.hasPrefix("TASTEMAP_") && key.contains("_UI_TEST")
            }
            || arguments.contains { $0.hasPrefix("-p1") && $0.contains("fixture") }
        if isUIFixture {
            return TasteMapRuntimeConfiguration(tier: .ui)
        }
        return TasteMapRuntimeConfiguration(tier: .application)
    }
    #endif
}

nonisolated final class IsolatedAuthCredentialStore: AuthCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var credential: AuthCredential?

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

final class TestNetworkBlockerURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        client?.urlProtocol(
            self,
            didFailWithError: URLError(.notConnectedToInternet)
        )
    }

    override func stopLoading() {}
}

enum TasteMapTestRuntimeResources {
    static func networkSession(for runtime: TasteMapRuntimeConfiguration) -> URLSession {
        guard !runtime.allowsNetwork else { return .shared }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestNetworkBlockerURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func temporaryRoot(component: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TasteMapTests", isDirectory: true)
            .appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString, isDirectory: true)
            .appendingPathComponent(component, isDirectory: true)
    }
}
