import Foundation

@MainActor
protocol CommunityAPI {
    func feed(scope: CommunityFeedScopeV1, cursor: String?, limit: Int) async throws -> CommunityFeedPageV1
    func publicContent(
        userID: String, section: PublicContentSectionV1, cursor: String?, limit: Int
    ) async throws -> PublicProfileContentPageV1
    func publicOverview(userID: String) async throws -> PublicProfileOverviewV1
}

final class URLSessionCommunityAPIClient: CommunityAPI {
    private let configuration: APIConfiguration
    private let authorization: any SyncAuthorizationProviding
    private let session: URLSession

    init(
        configuration: APIConfiguration,
        authorization: any SyncAuthorizationProviding = MissingSyncAuthorization(),
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.authorization = authorization
        self.session = session
    }

    func feed(scope: CommunityFeedScopeV1, cursor: String?, limit: Int = 20) async throws -> CommunityFeedPageV1 {
        try await get(path: "/api/v1/community/feed", query: [
            .init(name: "scope", value: scope.rawValue), .init(name: "cursor", value: cursor),
            .init(name: "limit", value: String(limit)),
        ])
    }

    func publicContent(
        userID: String, section: PublicContentSectionV1, cursor: String?, limit: Int = 20
    ) async throws -> PublicProfileContentPageV1 {
        let escaped = userID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? userID
        return try await get(path: "/api/v1/community/users/\(escaped)/content", query: [
            .init(name: "section", value: section.rawValue), .init(name: "cursor", value: cursor),
            .init(name: "limit", value: String(limit)),
        ])
    }

    func publicOverview(userID: String) async throws -> PublicProfileOverviewV1 {
        let escaped = userID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? userID
        return try await get(path: "/api/v1/community/users/\(escaped)/overview", query: [])
    }

    private func get<T: Decodable>(path: String, query: [URLQueryItem]) async throws -> T {
        var components = URLComponents(url: try configuration.url(for: path), resolvingAgainstBaseURL: false)
        components?.queryItems = query.filter { $0.value != nil }
        guard let url = components?.url else { throw APIConfigurationError.invalidPath }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (name, value) in try await authorization.headers() { request.setValue(value, forHTTPHeaderField: name) }
        var (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 401,
           try await authorization.recoverUnauthorized(
               failedAuthorization: request.value(forHTTPHeaderField: "Authorization")
           ) {
            for (name, value) in try await authorization.headers() { request.setValue(value, forHTTPHeaderField: name) }
            (data, response) = try await session.data(for: request)
        }
        guard let http = response as? HTTPURLResponse else { throw SyncAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            throw SyncAPIError.server(
                status: http.statusCode,
                message: body?["error"] as? String ?? "Community request failed."
            )
        }
        let value = try JSONDecoder().decode(T.self, from: data)
        return value
    }
}
