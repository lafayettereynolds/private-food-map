import Foundation

@MainActor
protocol RestaurantListAPI {
    func profileLists(userID: String, cursor: String?, limit: Int) async throws -> PublicListSummaryPageDTO
    func detail(listID: String, cursor: String?, limit: Int) async throws -> PublicListDetailDTO
}

final class URLSessionRestaurantListAPIClient: RestaurantListAPI {
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

    func profileLists(
        userID: String,
        cursor: String? = nil,
        limit: Int = 20
    ) async throws -> PublicListSummaryPageDTO {
        let escaped = userID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? userID
        return try await get(path: "/api/v1/lists/users/\(escaped)", cursor: cursor, limit: limit)
    }

    func detail(
        listID: String,
        cursor: String? = nil,
        limit: Int = 50
    ) async throws -> PublicListDetailDTO {
        let escaped = listID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? listID
        return try await get(path: "/api/v1/lists/\(escaped)", cursor: cursor, limit: limit)
    }

    private func get<Value: Decodable>(path: String, cursor: String?, limit: Int) async throws -> Value {
        var components = URLComponents(url: try configuration.url(for: path), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "cursor", value: cursor),
            URLQueryItem(name: "limit", value: String(min(50, max(1, limit))))
        ].filter { $0.value != nil }
        guard let url = components?.url else { throw APIConfigurationError.invalidPath }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (name, value) in try await authorization.headers() {
            request.setValue(value, forHTTPHeaderField: name)
        }
        var result = try await session.data(for: request)
        if let response = result.1 as? HTTPURLResponse, response.statusCode == 401,
           try await authorization.recoverUnauthorized(
               failedAuthorization: request.value(forHTTPHeaderField: "Authorization")
           ) {
            for (name, value) in try await authorization.headers() {
                request.setValue(value, forHTTPHeaderField: name)
            }
            result = try await session.data(for: request)
        }
        guard let response = result.1 as? HTTPURLResponse else { throw SyncAPIError.invalidResponse }
        guard (200 ..< 300).contains(response.statusCode) else {
            let body = try? JSONSerialization.jsonObject(with: result.0) as? [String: Any]
            throw SyncAPIError.server(
                status: response.statusCode,
                message: body?["error"] as? String ?? "榜单暂时无法加载。"
            )
        }
        return try JSONDecoder().decode(Value.self, from: result.0)
    }
}
