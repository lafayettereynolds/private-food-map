import Foundation

nonisolated struct PremiumCommerceConfigurationV1: Decodable, Equatable, Sendable {
    struct ProductReference: Decodable, Equatable, Sendable {
        let id: String
        let period: MembershipProductPeriod
    }

    let apiVersion: Int
    let configured: Bool
    var purchaseReady: Bool? = nil
    let appAccountToken: UUID
    let products: [ProductReference]
}

nonisolated struct PremiumCommerceReconciliationV1: Decodable, Equatable, Sendable {
    let apiVersion: Int
    let reconciled: Bool
    let transactionId: String
    let originalTransactionId: String
}

@MainActor
protocol PremiumCommerceAPI: Sendable {
    func configuration() async throws -> PremiumCommerceConfigurationV1
    func reconcile(transactionID: UInt64) async throws -> PremiumCommerceReconciliationV1
}

final class URLSessionPremiumCommerceAPIClient: PremiumCommerceAPI {
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

    func configuration() async throws -> PremiumCommerceConfigurationV1 {
        try await send(path: "/api/v1/storekit/config", method: "GET", body: nil)
    }

    func reconcile(transactionID: UInt64) async throws -> PremiumCommerceReconciliationV1 {
        try await send(
            path: "/api/v1/storekit/transactions/reconcile",
            method: "POST",
            body: try JSONSerialization.data(withJSONObject: ["transactionId": String(transactionID)])
        )
    }

    private func send<Response: Decodable>(path: String, method: String, body: Data?) async throws -> Response {
        var request = URLRequest(url: try configuration.url(for: path))
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
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
        guard let http = response as? HTTPURLResponse else {
            throw PremiumCommerceAPIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            throw PremiumCommerceAPIError.server(
                status: http.statusCode,
                code: payload?["code"] as? String,
                message: payload?["error"] as? String ?? "App Store 交易暂时无法验证。"
            )
        }
        return try decoder.decode(Response.self, from: data)
    }
}

nonisolated enum PremiumCommerceAPIError: LocalizedError, Equatable {
    case invalidResponse
    case server(status: Int, code: String?, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "会员交易服务返回了无法识别的内容。"
        case .server(_, _, let message): message
        }
    }
}
