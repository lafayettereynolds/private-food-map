import Foundation

@MainActor
protocol SocialAPI {
    func search(query: String, cursor: String?, limit: Int) async throws -> SocialPageV1<SocialUserResultV1>
    func friendships(scope: FriendshipListScope, cursor: String?, limit: Int) async throws -> SocialPageV1<SocialUserResultV1>
    func follows(scope: FollowListScope, cursor: String?, limit: Int) async throws -> SocialPageV1<SocialUserResultV1>
    func profileContext(userID: String) async throws -> SocialProfileContextV1
    func requestFriend(userID: String) async throws -> FriendshipMutationResponseV1
    func mutateFriendship(id: String, action: FriendshipMutationAction) async throws -> FriendshipMutationResponseV1
    func setFollowing(_ following: Bool, userID: String) async throws -> FollowMutationResponseV1
}

final class URLSessionSocialAPIClient: SocialAPI {
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

    func search(query: String, cursor: String?, limit: Int = 20) async throws -> SocialPageV1<SocialUserResultV1> {
        try await get(path: "/api/v1/social/users/search", query: [
            .init(name: "q", value: query), .init(name: "cursor", value: cursor),
            .init(name: "limit", value: String(limit)),
        ])
    }

    func friendships(scope: FriendshipListScope, cursor: String?, limit: Int = 20) async throws -> SocialPageV1<SocialUserResultV1> {
        try await get(path: "/api/v1/social/friendships", query: [
            .init(name: "scope", value: scope.rawValue), .init(name: "cursor", value: cursor),
            .init(name: "limit", value: String(limit)),
        ])
    }

    func follows(scope: FollowListScope, cursor: String?, limit: Int = 20) async throws -> SocialPageV1<SocialUserResultV1> {
        try await get(path: "/api/v1/social/follows", query: [
            .init(name: "scope", value: scope.rawValue), .init(name: "cursor", value: cursor),
            .init(name: "limit", value: String(limit)),
        ])
    }

    func profileContext(userID: String) async throws -> SocialProfileContextV1 {
        let escaped = userID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? userID
        return try await get(path: "/api/v1/social/users/\(escaped)/context", query: [])
    }

    func requestFriend(userID: String) async throws -> FriendshipMutationResponseV1 {
        try await send(path: "/api/v1/social/friendships", method: "POST", body: ["targetUserId": userID])
    }

    func mutateFriendship(id: String, action: FriendshipMutationAction) async throws -> FriendshipMutationResponseV1 {
        let escaped = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return try await send(path: "/api/v1/social/friendships/\(escaped)", method: "POST", body: ["action": action.rawValue])
    }

    func setFollowing(_ following: Bool, userID: String) async throws -> FollowMutationResponseV1 {
        let escaped = userID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? userID
        return try await send(
            path: "/api/v1/social/follows/\(escaped)",
            method: following ? "PUT" : "DELETE",
            body: Optional<[String: String]>.none
        )
    }

    private func get<T: Decodable>(path: String, query: [URLQueryItem]) async throws -> T {
        var components = URLComponents(url: try configuration.url(for: path), resolvingAgainstBaseURL: false)
        components?.queryItems = query.filter { $0.value != nil }
        guard let url = components?.url else { throw APIConfigurationError.invalidPath }
        return try await execute(URLRequest(url: url))
    }

    private func send<T: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body?
    ) async throws -> T {
        var request = URLRequest(url: try configuration.url(for: path))
        request.httpMethod = method
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return try await execute(request)
    }

    private func execute<T: Decodable>(_ original: URLRequest) async throws -> T {
        var request = original
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (name, value) in try await authorization.headers() { request.setValue(value, forHTTPHeaderField: name) }
        var (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse,
           http.statusCode == 401,
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
                message: body?["error"] as? String ?? "Social request failed."
            )
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
