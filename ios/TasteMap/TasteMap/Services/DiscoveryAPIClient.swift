import Foundation

@MainActor
protocol DiscoveryAPI {
    func page(mode: DiscoveryModeV1, city: String, trendWindowDays: Int,
              cursor: String?, limit: Int) async throws -> DiscoveryPageV1
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
        ].filter { $0.value != nil }
        guard let url = components?.url else { throw APIConfigurationError.invalidPath }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (name, value) in try await authorization.headers() { request.setValue(value, forHTTPHeaderField: name) }
        var result = try await session.data(for: request)
        if let response = result.1 as? HTTPURLResponse, response.statusCode == 401,
           try await authorization.recoverUnauthorized(failedAuthorization: request.value(forHTTPHeaderField: "Authorization")) {
            for (name, value) in try await authorization.headers() { request.setValue(value, forHTTPHeaderField: name) }
            result = try await session.data(for: request)
        }
        guard let response = result.1 as? HTTPURLResponse else { throw SyncAPIError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else {
            let body = try? JSONSerialization.jsonObject(with: result.0) as? [String: Any]
            throw SyncAPIError.server(status: response.statusCode,
                                      message: body?["error"] as? String ?? "发现内容暂时无法加载。")
        }
        let value = try JSONDecoder().decode(DiscoveryPageV1.self, from: result.0)
        guard value.apiVersion == 1 else { throw SyncAPIError.invalidResponse }
        return value
    }
}
