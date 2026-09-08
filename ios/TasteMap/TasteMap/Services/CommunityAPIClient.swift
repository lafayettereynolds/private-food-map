import Foundation

@MainActor
protocol CommunityAPI {
    func feed(scope: CommunityFeedScopeV1, city: String, cursor: String?, limit: Int) async throws -> CommunityFeedPageV1
    func feed(scope: CommunityFeedScopeV1, city: String, cursor: String?, limit: Int,
              query: TasteMapDiscoveryAppliedQuery) async throws -> CommunityFeedPageV1
    func publicContent(
        userID: String, section: PublicContentSectionV1, cursor: String?, limit: Int
    ) async throws -> PublicProfileContentPageV1
    func publicOverview(userID: String) async throws -> PublicProfileOverviewV1
}

extension CommunityAPI {
    func feed(scope: CommunityFeedScopeV1, city: String, cursor: String?, limit: Int,
              query: TasteMapDiscoveryAppliedQuery) async throws -> CommunityFeedPageV1 {
        guard query.isDefault(mode: scope.rawValue) else { throw DiscoveryQueryValidation.unsupported() }
        return try await feed(scope: scope, city: city, cursor: cursor, limit: limit)
    }
    func feed(scope: CommunityFeedScopeV1, cursor: String?, limit: Int = 20) async throws -> CommunityFeedPageV1 {
        try await feed(scope: scope, city: "", cursor: cursor, limit: limit)
    }
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

    func feed(scope: CommunityFeedScopeV1, city: String = "", cursor: String?, limit: Int = 20) async throws -> CommunityFeedPageV1 {
        try await feed(scope: scope, city: city, cursor: cursor, limit: limit,
                       query: .normalized(mode: scope.rawValue, filters: nil, sort: nil, preferences: nil))
    }

    func feed(scope: CommunityFeedScopeV1, city: String, cursor: String?, limit: Int,
              query: TasteMapDiscoveryAppliedQuery) async throws -> CommunityFeedPageV1 {
        guard city.utf16.count <= 80, city.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw SyncAPIError.invalidResponse
        }
        let requestedCity = Self.cityQueryKey(city)
        let page: CommunityFeedPageV1 = try await get(path: "/api/v1/community/feed", query: [
            .init(name: "scope", value: scope.rawValue), .init(name: "cursor", value: cursor),
            .init(name: "city", value: requestedCity.isEmpty ? nil : requestedCity),
            .init(name: "limit", value: String(limit)),
        ] + (try query.queryItems(mode: scope.rawValue)))
        // An old server ignores city. Never show that unrestricted page as a
        // successful city query while the backend capability is undeployed.
        guard page.scope == scope,
              requestedCity.isEmpty || page.city.map(Self.cityQueryKey) == requestedCity else {
            throw SyncAPIError.invalidResponse
        }
        try query.verify(page.appliedQuery, mode: scope.rawValue)
        return page
    }

    static func cityQueryKey(_ value: String) -> String {
        let city = value.precomposedStringWithCompatibilityMapping.trimmingCharacters(in: .whitespacesAndNewlines)
        return (city.count > 2 && city.hasSuffix("市") ? String(city.dropLast()) : city).lowercased()
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
            throw TasteMapDiscoveryHTTPError.decode(status: http.statusCode, data: data)
        }
        let value = try JSONDecoder().decode(T.self, from: data)
        return value
    }
}
