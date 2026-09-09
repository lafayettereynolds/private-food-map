import Foundation

@MainActor
protocol DiscoveryAPI {
    func page(mode: DiscoveryModeV1, city: String, trendWindowDays: Int,
              cursor: String?, limit: Int) async throws -> DiscoveryPageV1
    func page(mode: DiscoveryModeV1, city: String, trendWindowDays: Int,
              cursor: String?, limit: Int, query: TasteMapDiscoveryAppliedQuery) async throws -> DiscoveryPageV1
}

extension DiscoveryAPI {
    func page(mode: DiscoveryModeV1, city: String, trendWindowDays: Int, cursor: String?, limit: Int,
              query: TasteMapDiscoveryAppliedQuery) async throws -> DiscoveryPageV1 {
        guard query.isDefault(mode: mode.rawValue) else { throw DiscoveryQueryValidation.unsupported() }
        return try await page(mode: mode, city: city, trendWindowDays: trendWindowDays, cursor: cursor, limit: limit)
    }
}

final class URLSessionDiscoveryAPIClient: DiscoveryAPI {
    private let configuration: APIConfiguration
    private let authorization: any SyncAuthorizationProviding
    private let session: URLSession

    init(configuration: APIConfiguration,
         authorization: any SyncAuthorizationProviding = MissingSyncAuthorization(),
         session: URLSession = .shared) {
        self.configuration = configuration
        self.authorization = authorization
        self.session = session
    }

    func page(mode: DiscoveryModeV1, city: String, trendWindowDays: Int = 7,
              cursor: String? = nil, limit: Int = 20) async throws -> DiscoveryPageV1 {
        try await page(mode: mode, city: city, trendWindowDays: trendWindowDays, cursor: cursor, limit: limit,
                       query: .normalized(mode: mode.rawValue, filters: nil, sort: nil, preferences: nil))
    }

    func page(mode: DiscoveryModeV1, city: String, trendWindowDays: Int,
              cursor: String?, limit: Int, query: TasteMapDiscoveryAppliedQuery) async throws -> DiscoveryPageV1 {
        let path: String
        switch mode {
        case .forYou: path = "/api/v1/discovery/for-you"
        case .similarTaste: path = "/api/v1/discovery/similar-taste"
        case .trending: path = "/api/v1/discovery/trending"
        }
        var components = URLComponents(url: try configuration.url(for: path), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "city", value: city.isEmpty ? nil : city),
            URLQueryItem(name: "window", value: mode == .trending ? String(trendWindowDays) : nil),
            URLQueryItem(name: "cursor", value: cursor),
            URLQueryItem(name: "limit", value: String(min(50, max(1, limit)))),
        ].filter { $0.value != nil } + (try query.queryItems(mode: mode.rawValue))
        guard let url = components?.url else { throw APIConfigurationError.invalidPath }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (name, value) in try await authorization.headers() { request.setValue(value, forHTTPHeaderField: name) }
        var result = try await fetch(request)
        if let response = result.1 as? HTTPURLResponse, response.statusCode == 401,
           try await authorization.recoverUnauthorized(failedAuthorization: request.value(forHTTPHeaderField: "Authorization")) {
            for (name, value) in try await authorization.headers() { request.setValue(value, forHTTPHeaderField: name) }
            result = try await fetch(request)
        }
        guard let response = result.1 as? HTTPURLResponse else { throw SyncAPIError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else {
            DeviceAcceptanceLog.record("TasteMapDiagnostic category=discovery event=http_failed status=\(response.statusCode) mode=\(mode.rawValue)")
            throw TasteMapDiscoveryHTTPError.decode(status: response.statusCode, data: result.0)
        }
        let value: DiscoveryPageV1
        do {
            value = try JSONDecoder().decode(DiscoveryPageV1.self, from: result.0)
        } catch {
            DeviceAcceptanceLog.record("TasteMapDiagnostic category=discovery event=response_decode_failed status=\(response.statusCode) mode=\(mode.rawValue)")
            throw error
        }
        guard value.apiVersion == 1 else { throw SyncAPIError.invalidResponse }
        do { try query.verify(value.appliedQuery, mode: mode.rawValue) }
        catch {
            DeviceAcceptanceLog.record("TasteMapDiagnostic category=discovery event=query_contract_failed mode=\(mode.rawValue)")
            throw error
        }
        return value
    }
    private func fetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let attempt = UUID().uuidString
        let started = ProcessInfo.processInfo.systemUptime
        let observer = DiscoveryTransportObserver(attempt: attempt)
        DeviceAcceptanceLog.record("TasteMapDiagnostic category=discovery event=request_start attempt=\(attempt)")
        do {
            let result = try await session.data(for: request, delegate: observer)
            let response = result.1 as? HTTPURLResponse
            let elapsed = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
            DeviceAcceptanceLog.record("TasteMapDiagnostic category=discovery event=request_end attempt=\(attempt) status=\(response?.statusCode ?? 0) elapsedMs=\(elapsed) ray=\(DiscoveryTransportObserver.safeRay(response?.value(forHTTPHeaderField: "cf-ray")))")
            return result
        }
        catch {
            let code = (error as? URLError)?.errorCode ?? 0
            let elapsed = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
            DeviceAcceptanceLog.record("TasteMapDiagnostic category=discovery event=transport_failed code=\(code) attempt=\(attempt) elapsedMs=\(elapsed)")
            throw error
        }
    }

}

/// Per-task observer: retains the injected session, its authentication and transport
/// defaults. Never logs URLs, query parameters, headers other than validated Ray ID,
/// bodies, addresses, credentials or user identifiers. It does not retry requests.
nonisolated final class DiscoveryTransportObserver: NSObject, URLSessionTaskDelegate, Sendable {
    let attempt: String
    init(attempt: String) { self.attempt = attempt }

    static func safeRay(_ value: String?) -> String {
        guard let value, value.count == 20,
              value.range(of: "^[0-9a-fA-F]{16}-[A-Z]{3}$", options: .regularExpression) != nil else { return "unavailable" }
        return value
    }

    static func safeProtocol(_ value: String?) -> String {
        guard let value, ["h3", "h2", "http/1.1", "http/1.0"].contains(value) else { return "unknown" }
        return value
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        for (index, transaction) in metrics.transactionMetrics.enumerated() {
            let response = transaction.response as? HTTPURLResponse
            DeviceAcceptanceLog.record("TasteMapDiagnostic category=discovery event=transport_metrics attempt=\(attempt) transaction=\(index) protocol=\(Self.safeProtocol(transaction.networkProtocolName)) reused=\(transaction.isReusedConnection) proxy=\(transaction.isProxyConnection) status=\(response?.statusCode ?? 0) ray=\(Self.safeRay(response?.value(forHTTPHeaderField: "cf-ray"))) durationMs=\(Int(metrics.taskInterval.duration * 1000))")
        }
    }
}
