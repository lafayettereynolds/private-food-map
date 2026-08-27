import Foundation

@MainActor
protocol SyncAPI {
    func push(_ request: SyncPushRequestV1) async throws -> SyncPushResponseV1
    func pull(cursor: String, limit: Int) async throws -> SyncPullResponseV1
}

nonisolated protocol SyncAuthorizationProviding: Sendable {
    func headers() async throws -> [String: String]
    func recoverUnauthorized(failedAuthorization: String?) async throws -> Bool
}

extension SyncAuthorizationProviding {
    func recoverUnauthorized(failedAuthorization: String?) async throws -> Bool { false }
}

struct MissingSyncAuthorization: SyncAuthorizationProviding {
    func headers() async throws -> [String: String] { [:] }
}

struct DevelopmentSyncAuthorization: SyncAuthorizationProviding {
    let testUserID: String

    func headers() async throws -> [String: String] {
        ["X-Taste-Map-Test-User": testUserID]
    }
}

enum SyncAPIError: Error, Equatable {
    case invalidResponse
    case server(status: Int, message: String)
    case unsupportedVersion
}

final class URLSessionSyncAPIClient: SyncAPI {
    private let configuration: APIConfiguration
    private let authorization: any SyncAuthorizationProviding
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        configuration: APIConfiguration = .current(),
        authorization: any SyncAuthorizationProviding = MissingSyncAuthorization(),
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.authorization = authorization
        self.session = session
        encoder = JSONEncoder()
        decoder = JSONDecoder()
    }

    func push(_ requestBody: SyncPushRequestV1) async throws -> SyncPushResponseV1 {
        var request = try await makeRequest(path: "/api/v1/sync/push", method: "POST")
        request.httpBody = try encoder.encode(requestBody)
        let response = try await send(request, as: SyncPushResponseV1.self)
        guard response.apiVersion == SyncV1Contract.apiVersion else { throw SyncAPIError.unsupportedVersion }
        return response
    }

    func pull(cursor: String, limit: Int = 200) async throws -> SyncPullResponseV1 {
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "schemaVersion", value: String(SyncV1Contract.schemaVersion)),
            URLQueryItem(name: "cursor", value: cursor),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        guard let query = components.percentEncodedQuery else { throw SyncAPIError.invalidResponse }
        let request = try await makeRequest(path: "/api/v1/sync/pull?\(query)", method: "GET")
        let response = try await send(request, as: SyncPullResponseV1.self)
        guard response.apiVersion == SyncV1Contract.apiVersion,
              response.schemaVersion == SyncV1Contract.schemaVersion else {
            throw SyncAPIError.unsupportedVersion
        }
        return response
    }

    private func makeRequest(path: String, method: String) async throws -> URLRequest {
        var request = URLRequest(url: try configuration.url(for: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in try await authorization.headers() {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return request
    }

    private func send<Response: Decodable>(_ originalRequest: URLRequest, as type: Response.Type) async throws -> Response {
        var request = originalRequest
        var (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse,
           http.statusCode == 401,
           try await authorization.recoverUnauthorized(failedAuthorization: request.value(forHTTPHeaderField: "Authorization")) {
            for (name, value) in try await authorization.headers() {
                request.setValue(value, forHTTPHeaderField: name)
            }
            (data, response) = try await session.data(for: request)
        }
        guard let httpResponse = response as? HTTPURLResponse else { throw SyncAPIError.invalidResponse }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            throw SyncAPIError.server(
                status: httpResponse.statusCode,
                message: body?["error"] as? String ?? "Sync request failed."
            )
        }
        return try decoder.decode(type, from: data)
    }
}
