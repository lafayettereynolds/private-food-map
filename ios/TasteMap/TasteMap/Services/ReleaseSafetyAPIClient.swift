import Foundation

protocol ReleaseSafetyAPI: Sendable {
    func accountDeletionPreview() async throws -> AccountDeletionPreviewV1
    func confirmAccountDeletion(requestID: UUID, statusToken: String) async throws -> AccountDeletionJobV1
    func accountDeletionStatus(statusToken: String) async throws -> AccountDeletionJobV1
    func retryAccountDeletion(statusToken: String) async throws -> AccountDeletionJobV1
    func report(
        type: ModerationContentTypeV1, id: String, reason: ModerationReasonV1,
        details: String, requestID: UUID
    ) async throws -> ContentReportResponseV1
    func setBlocked(_ blocked: Bool, userID: String) async throws -> UserBlockMutationV1
}

final class URLSessionReleaseSafetyAPIClient: ReleaseSafetyAPI, @unchecked Sendable {
    private let configuration: APIConfiguration
    private let authorization: any SyncAuthorizationProviding
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        configuration: APIConfiguration,
        authorization: any SyncAuthorizationProviding,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.authorization = authorization
        self.session = session
    }

    func accountDeletionPreview() async throws -> AccountDeletionPreviewV1 {
        try await authenticated(path: "/api/v1/account-deletion/preview", method: "GET", body: Optional<Empty>.none)
    }

    func confirmAccountDeletion(requestID: UUID, statusToken: String) async throws -> AccountDeletionJobV1 {
        try await authenticated(
            path: "/api/v1/account-deletion/confirm", method: "POST",
            body: AccountDeletionConfirmBody(
                apiVersion: ReleaseSafetyV1Contract.apiVersion,
                requestId: requestID.uuidString.lowercased(),
                statusToken: statusToken,
                confirmation: "DELETE"
            )
        )
    }

    func accountDeletionStatus(statusToken: String) async throws -> AccountDeletionJobV1 {
        try await statusRequest(path: "/api/v1/account-deletion/status", method: "GET", statusToken: statusToken)
    }

    func retryAccountDeletion(statusToken: String) async throws -> AccountDeletionJobV1 {
        try await statusRequest(path: "/api/v1/account-deletion/retry", method: "POST", statusToken: statusToken)
    }

    func report(
        type: ModerationContentTypeV1,
        id: String,
        reason: ModerationReasonV1,
        details: String,
        requestID: UUID
    ) async throws -> ContentReportResponseV1 {
        try await authenticated(
            path: "/api/v1/community/reports", method: "POST",
            body: ReportBody(
                apiVersion: ReleaseSafetyV1Contract.apiVersion,
                requestId: requestID.uuidString.lowercased(),
                contentType: type,
                contentId: id,
                reason: reason,
                details: details
            )
        )
    }

    func setBlocked(_ blocked: Bool, userID: String) async throws -> UserBlockMutationV1 {
        let escaped = userID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? userID
        return try await authenticated(
            path: "/api/v1/community/blocks/\(escaped)",
            method: blocked ? "PUT" : "DELETE",
            body: Optional<Empty>.none
        )
    }

    private func authenticated<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body?
    ) async throws -> Response {
        var request = try request(path: path, method: method, body: body)
        for (name, value) in try await authorization.headers() {
            request.setValue(value, forHTTPHeaderField: name)
        }
        var (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 401,
           try await authorization.recoverUnauthorized(
               failedAuthorization: request.value(forHTTPHeaderField: "Authorization")
           ) {
            for (name, value) in try await authorization.headers() {
                request.setValue(value, forHTTPHeaderField: name)
            }
            (data, response) = try await session.data(for: request)
        }
        return try decoded(data: data, response: response)
    }

    private func statusRequest<Response: Decodable>(
        path: String,
        method: String,
        statusToken: String
    ) async throws -> Response {
        var request = try request(path: path, method: method, body: Optional<Empty>.none)
        request.setValue(statusToken, forHTTPHeaderField: "X-Taste-Map-Deletion-Token")
        let (data, response) = try await session.data(for: request)
        return try decoded(data: data, response: response)
    }

    private func request<Body: Encodable>(path: String, method: String, body: Body?) throws -> URLRequest {
        var request = URLRequest(url: try configuration.url(for: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }
        return request
    }

    private func decoded<Response: Decodable>(data: Data, response: URLResponse) throws -> Response {
        guard let http = response as? HTTPURLResponse else { throw SyncAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let error = try? decoder.decode(ServerError.self, from: data)
            throw SyncAPIError.server(status: http.statusCode, message: error?.error ?? "Request failed.")
        }
        return try decoder.decode(Response.self, from: data)
    }
}

private struct Empty: Codable {}
private struct AccountDeletionConfirmBody: Encodable {
    let apiVersion: Int
    let requestId: String
    let statusToken: String
    let confirmation: String
}
private struct ReportBody: Encodable {
    let apiVersion: Int
    let requestId: String
    let contentType: ModerationContentTypeV1
    let contentId: String
    let reason: ModerationReasonV1
    let details: String
}
private struct ServerError: Decodable { let error: String; let code: String? }
