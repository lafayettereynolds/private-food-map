import Foundation

@MainActor
protocol PublicSharingAPI: Sendable {
    func create(entityType: PublicShareEntityTypeV1, entityID: String) async throws -> CreatePublicShareResponseV1
    func read(shareID: String) async throws -> PublicShareResponseV1
}

final class URLSessionPublicSharingAPIClient: PublicSharingAPI {
    private let configuration: APIConfiguration
    private let authorization: any SyncAuthorizationProviding
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        configuration: APIConfiguration,
        authorization: any SyncAuthorizationProviding = MissingSyncAuthorization(),
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.authorization = authorization
        self.session = session
    }

    func create(entityType: PublicShareEntityTypeV1, entityID: String) async throws -> CreatePublicShareResponseV1 {
        var request = URLRequest(url: try configuration.url(for: "/api/v1/public-shares"))
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(CreatePublicShareRequestV1(entityType: entityType, entityId: entityID))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
        return try decode(CreatePublicShareResponseV1.self, data: data, response: response)
    }

    func read(shareID: String) async throws -> PublicShareResponseV1 {
        guard shareID.range(of: "^[A-Za-z0-9_-]{32}$", options: .regularExpression) != nil else {
            throw PublicSharingAPIError.invalidShareID
        }
        let escaped = shareID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? shareID
        var request = URLRequest(url: try configuration.url(for: "/api/public/shares/\(escaped)"))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        return try decode(PublicShareResponseV1.self, data: data, response: response)
    }

    private func decode<T: Decodable>(_ type: T.Type, data: Data, response: URLResponse) throws -> T {
        guard let http = response as? HTTPURLResponse else { throw PublicSharingAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            throw PublicSharingAPIError.server(
                status: http.statusCode,
                message: body?["error"] as? String ?? "这个分享暂时不可用。"
            )
        }
        let value = try decoder.decode(T.self, from: data)
        if let created = value as? CreatePublicShareResponseV1, created.apiVersion != 1 {
            throw PublicSharingAPIError.unsupportedVersion
        }
        if let shared = value as? PublicShareResponseV1, shared.apiVersion != 1 {
            throw PublicSharingAPIError.unsupportedVersion
        }
        return value
    }
}

nonisolated enum PublicSharingAPIError: LocalizedError, Equatable {
    case invalidShareID
    case invalidResponse
    case unsupportedVersion
    case server(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidShareID: "分享链接格式无效。"
        case .invalidResponse: "分享服务返回了无法识别的内容。"
        case .unsupportedVersion: "分享服务版本与当前 App 不兼容。"
        case .server(_, let message): message
        }
    }
}
