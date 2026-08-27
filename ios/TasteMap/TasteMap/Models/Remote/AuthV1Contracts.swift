import Foundation

nonisolated enum AuthV1Contract {
    static let apiVersion = 1
}

nonisolated struct AuthChallengeV1: Decodable, Sendable {
    let apiVersion: Int
    let state: String
    let nonce: String
    let expiresAt: String
}

nonisolated struct AuthenticatedUserV1: Codable, Equatable, Sendable {
    let id: String
    let email: String?
}

nonisolated struct AuthSessionTokensV1: Codable, Equatable, Sendable {
    let accessToken: String
    let accessTokenExpiresAt: String
    let refreshToken: String
    let refreshTokenExpiresAt: String
}

nonisolated struct AuthSessionResponseV1: Codable, Equatable, Sendable {
    let apiVersion: Int
    let user: AuthenticatedUserV1
    let session: AuthSessionTokensV1
}

nonisolated struct AuthCredential: Codable, Equatable, Sendable {
    let user: AuthenticatedUserV1
    let accessToken: String
    let accessTokenExpiresAt: Date
    let refreshToken: String
    let refreshTokenExpiresAt: Date

    init(response: AuthSessionResponseV1) throws {
        guard response.apiVersion == AuthV1Contract.apiVersion,
              let accessExpiry = Self.date(response.session.accessTokenExpiresAt),
              let refreshExpiry = Self.date(response.session.refreshTokenExpiresAt) else {
            throw AuthClientError.invalidResponse
        }
        user = response.user
        accessToken = response.session.accessToken
        accessTokenExpiresAt = accessExpiry
        refreshToken = response.session.refreshToken
        refreshTokenExpiresAt = refreshExpiry
    }

    init(
        user: AuthenticatedUserV1,
        accessToken: String,
        accessTokenExpiresAt: Date,
        refreshToken: String,
        refreshTokenExpiresAt: Date
    ) {
        self.user = user
        self.accessToken = accessToken
        self.accessTokenExpiresAt = accessTokenExpiresAt
        self.refreshToken = refreshToken
        self.refreshTokenExpiresAt = refreshTokenExpiresAt
    }

    private static func date(_ value: String) -> Date? {
        ISO8601DateFormatter.fractional.date(from: value)
            ?? ISO8601DateFormatter().date(from: value)
    }
}

nonisolated private extension ISO8601DateFormatter {
    static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
