import Foundation

protocol AuthAPI: Sendable {
    func challenge() async throws -> AuthChallengeV1
    func exchangeAppleToken(
        identityToken: String,
        state: String,
        nonce: String,
        givenName: String?,
        familyName: String?,
        referralCode: String?
    ) async throws -> AuthSessionResponseV1
    func refresh(refreshToken: String) async throws -> AuthSessionResponseV1
    func logout(accessToken: String?, refreshToken: String) async throws
}

enum AuthClientError: Error, Equatable {
    case invalidResponse
    case server(status: Int, code: String?, message: String)
}

final class URLSessionAuthAPIClient: AuthAPI, @unchecked Sendable {
    private let configuration: APIConfiguration
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(configuration: APIConfiguration = .current(), session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func challenge() async throws -> AuthChallengeV1 {
        try await send(path: "/api/v1/auth/challenge", body: EmptyRequest())
    }

    func exchangeAppleToken(
        identityToken: String,
        state: String,
        nonce: String,
        givenName: String?,
        familyName: String?,
        referralCode: String? = nil
    ) async throws -> AuthSessionResponseV1 {
        try await send(path: "/api/v1/auth/apple/exchange", body: AppleExchangeRequest(
            apiVersion: AuthV1Contract.apiVersion,
            identityToken: identityToken,
            state: state,
            nonce: nonce,
            givenName: givenName,
            familyName: familyName,
            referralCode: referralCode
        ))
    }

    func refresh(refreshToken: String) async throws -> AuthSessionResponseV1 {
        try await send(path: "/api/v1/auth/refresh", body: RefreshRequest(
            apiVersion: AuthV1Contract.apiVersion,
            refreshToken: refreshToken
        ))
    }

    func logout(accessToken: String?, refreshToken: String) async throws {
        var headers: [String: String] = [:]
        if let accessToken { headers["Authorization"] = "Bearer \(accessToken)" }
        let _: LogoutResponse = try await send(
            path: "/api/v1/auth/logout",
            body: LogoutRequest(apiVersion: AuthV1Contract.apiVersion, refreshToken: refreshToken),
            headers: headers
        )
    }

    private func send<Body: Encodable, Response: Decodable>(
        path: String,
        body: Body,
        headers: [String: String] = [:]
    ) async throws -> Response {
        var request = URLRequest(url: try configuration.url(for: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.httpBody = try encoder.encode(body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let error = try? decoder.decode(ErrorResponse.self, from: data)
            throw AuthClientError.server(
                status: http.statusCode,
                code: error?.code,
                message: error?.error ?? "Authentication request failed."
            )
        }
        return try decoder.decode(Response.self, from: data)
    }
}

private struct EmptyRequest: Encodable {}

private struct AppleExchangeRequest: Encodable {
    let apiVersion: Int
    let identityToken: String
    let state: String
    let nonce: String
    let givenName: String?
    let familyName: String?
    let referralCode: String?
}

private struct RefreshRequest: Encodable {
    let apiVersion: Int
    let refreshToken: String
}

private struct LogoutRequest: Encodable {
    let apiVersion: Int
    let refreshToken: String
}

private struct LogoutResponse: Decodable {
    let apiVersion: Int
    let revoked: Bool
}

private struct ErrorResponse: Decodable {
    let error: String
    let code: String?
}
