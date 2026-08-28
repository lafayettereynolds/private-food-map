import Foundation

@MainActor
protocol PremiumEntitlementAPI: Sendable {
    func entitlement() async throws -> PremiumEntitlementResponseV1
}

final class URLSessionPremiumEntitlementAPIClient: PremiumEntitlementAPI {
    private let configuration: APIConfiguration
    private let authorization: any SyncAuthorizationProviding
    private let session: URLSession
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

    func entitlement() async throws -> PremiumEntitlementResponseV1 {
        var request = URLRequest(url: try configuration.url(for: "/api/v1/me/entitlements"))
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
        guard let http = response as? HTTPURLResponse else { throw PremiumEntitlementAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            throw PremiumEntitlementAPIError.server(
                status: http.statusCode,
                message: body?["error"] as? String ?? "会员状态暂时无法确认。"
            )
        }
        let value = try decoder.decode(PremiumEntitlementResponseV1.self, from: data)
        guard value.apiVersion == PremiumEntitlementContract.apiVersion else {
            throw PremiumEntitlementAPIError.unsupportedVersion
        }
        return value
    }
}

nonisolated enum PremiumEntitlementAPIError: LocalizedError, Equatable {
    case invalidResponse
    case unsupportedVersion
    case server(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "会员服务返回了无法识别的内容。"
        case .unsupportedVersion: "会员服务版本与当前 App 不兼容。"
        case .server(_, let message): message
        }
    }
}
