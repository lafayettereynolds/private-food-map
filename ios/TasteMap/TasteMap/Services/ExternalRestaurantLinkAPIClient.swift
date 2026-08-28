import Foundation

@MainActor
protocol ExternalRestaurantLinkResolving {
    func resolve(text: String, currentCity: String) async throws -> ExternalRestaurantLinkResponseV1
}

final class URLSessionExternalRestaurantLinkAPIClient: ExternalRestaurantLinkResolving {
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

    func resolve(text: String, currentCity: String) async throws -> ExternalRestaurantLinkResponseV1 {
        var request = URLRequest(url: try configuration.url(for: "/api/v1/external-place/resolve"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ExternalRestaurantLinkRequestV1(
            text: text,
            currentCity: currentCity
        ))
        for (name, value) in try await authorization.headers() {
            request.setValue(value, forHTTPHeaderField: name)
        }

        var result = try await session.data(for: request)
        if let response = result.1 as? HTTPURLResponse,
           response.statusCode == 401,
           try await authorization.recoverUnauthorized(
               failedAuthorization: request.value(forHTTPHeaderField: "Authorization")
           ) {
            for (name, value) in try await authorization.headers() {
                request.setValue(value, forHTTPHeaderField: name)
            }
            result = try await session.data(for: request)
        }
        guard let response = result.1 as? HTTPURLResponse else { throw SyncAPIError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else {
            let body = try? JSONSerialization.jsonObject(with: result.0) as? [String: Any]
            throw SyncAPIError.server(
                status: response.statusCode,
                message: body?["error"] as? String ?? "餐厅链接暂时无法解析。"
            )
        }
        let value = try JSONDecoder().decode(ExternalRestaurantLinkResponseV1.self, from: result.0)
        if let apiVersion = value.apiVersion, apiVersion != 1 { throw SyncAPIError.unsupportedVersion }
        return value
    }
}
