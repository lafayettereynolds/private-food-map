import Foundation

@MainActor
protocol ProfileAPI {
    func publicProfile(userID: String) async throws -> PublicUserProfileV1
}

final class URLSessionProfileAPIClient: ProfileAPI {
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

    func publicProfile(userID: String) async throws -> PublicUserProfileV1 {
        let escaped = userID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? userID
        var request = URLRequest(url: try configuration.url(for: "/api/v1/public/profiles/\(escaped)"))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (name, value) in try await authorization.headers() {
            request.setValue(value, forHTTPHeaderField: name)
        }
        var (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse,
           http.statusCode == 401,
           try await authorization.recoverUnauthorized(
               failedAuthorization: request.value(forHTTPHeaderField: "Authorization")
           ) {
            for (name, value) in try await authorization.headers() {
                request.setValue(value, forHTTPHeaderField: name)
            }
            (data, response) = try await session.data(for: request)
        }
        guard let http = response as? HTTPURLResponse else { throw SyncAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            throw SyncAPIError.server(
                status: http.statusCode,
                message: body?["error"] as? String ?? "Profile request failed."
            )
        }
        let profile = try JSONDecoder().decode(PublicUserProfileV1.self, from: data)
        guard profile.apiVersion == 1 else { throw SyncAPIError.unsupportedVersion }
        return profile
    }
}
