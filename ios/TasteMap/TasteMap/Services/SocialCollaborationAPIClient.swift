import Foundation

@MainActor
protocol SocialCollaborationAPI {
    func suggestions(cursor: String?, limit: Int) async throws -> SocialSuggestionPageV1
    func companionLinks(scope: CompanionLinkScopeV1, cursor: String?, limit: Int) async throws -> CompanionLinkPageV1
    func requestCompanionLink(companionID: String, targetUserID: String) async throws -> CompanionLinkRequestV1
    func mutateCompanionLink(id: String, action: CompanionLinkActionV1) async throws -> CompanionLinkRequestV1
    func sharedMeals(scope: SharedMealScopeV1, cursor: String?, limit: Int) async throws -> SharedMealPageV1
    func inviteSharedMeal(sourceVisitID: String, participantUserIDs: [String], mutationID: String) async throws -> SharedMealInviteResponseV1
    func mutateSharedMealParticipant(id: String, action: SharedMealParticipantActionV1, visitID: String?) async throws -> SharedMealInvitationV1
    func revokeSharedMeal(id: String) async throws -> SharedMealInvitationV1
}

@MainActor
protocol CommunityInteractionAPI {
    func setLike(_ liked: Bool, visitID: String) async throws -> CommunityLikeMutationV1
    func comments(visitID: String, cursor: String?, limit: Int) async throws -> CommunityCommentPageV1
    func addComment(visitID: String, body: String) async throws -> CommunityCommentMutationV1
    func deleteComment(id: String) async throws -> CommunityCommentMutationV1
}

@MainActor
final class URLSessionSocialCollaborationAPIClient: SocialCollaborationAPI, CommunityInteractionAPI {
    func scoped(to authorization: UGCRequestAuthorization) -> URLSessionSocialCollaborationAPIClient {
        .init(configuration: configuration, authorization: authorization, session: session)
    }
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

    func suggestions(cursor: String?, limit: Int = 20) async throws -> SocialSuggestionPageV1 {
        try await get(path: "/api/v1/social/suggestions", query: pageQuery(cursor: cursor, limit: limit))
    }

    func companionLinks(scope: CompanionLinkScopeV1, cursor: String?, limit: Int = 20) async throws -> CompanionLinkPageV1 {
        try await get(path: "/api/v1/social/companion-links", query: [
            .init(name: "scope", value: scope.rawValue),
            .init(name: "cursor", value: cursor), .init(name: "limit", value: String(limit)),
        ])
    }

    func requestCompanionLink(companionID: String, targetUserID: String) async throws -> CompanionLinkRequestV1 {
        try await send(path: "/api/v1/social/companion-links", method: "POST", body: [
            "companionId": companionID, "targetUserId": targetUserID,
        ])
    }

    func mutateCompanionLink(id: String, action: CompanionLinkActionV1) async throws -> CompanionLinkRequestV1 {
        try await send(path: "/api/v1/social/companion-links/\(escaped(id))", method: "POST", body: ["action": action.rawValue])
    }

    func sharedMeals(scope: SharedMealScopeV1, cursor: String?, limit: Int = 20) async throws -> SharedMealPageV1 {
        try await get(path: "/api/v1/social/shared-meals", query: [
            .init(name: "scope", value: scope.rawValue),
            .init(name: "cursor", value: cursor), .init(name: "limit", value: String(limit)),
        ])
    }

    func inviteSharedMeal(
        sourceVisitID: String,
        participantUserIDs: [String],
        mutationID: String
    ) async throws -> SharedMealInviteResponseV1 {
        struct Body: Encodable { let sourceVisitId: String; let participantUserIds: [String]; let mutationId: String }
        return try await send(
            path: "/api/v1/social/shared-meals", method: "POST",
            body: Body(sourceVisitId: sourceVisitID, participantUserIds: participantUserIDs, mutationId: mutationID)
        )
    }

    func mutateSharedMealParticipant(
        id: String,
        action: SharedMealParticipantActionV1,
        visitID: String? = nil
    ) async throws -> SharedMealInvitationV1 {
        struct Body: Encodable { let action: String; let visitId: String? }
        return try await send(
            path: "/api/v1/social/shared-meals/participants/\(escaped(id))", method: "POST",
            body: Body(action: action.rawValue, visitId: visitID)
        )
    }

    func revokeSharedMeal(id: String) async throws -> SharedMealInvitationV1 {
        try await send(path: "/api/v1/social/shared-meals/\(escaped(id))", method: "DELETE", body: Optional<[String: String]>.none)
    }

    func setLike(_ liked: Bool, visitID: String) async throws -> CommunityLikeMutationV1 {
        try await send(
            path: "/api/v1/community/content/visit/\(escaped(visitID))/like",
            method: liked ? "PUT" : "DELETE", body: Optional<[String: String]>.none
        )
    }

    func comments(visitID: String, cursor: String?, limit: Int = 20) async throws -> CommunityCommentPageV1 {
        try await get(
            path: "/api/v1/community/content/visit/\(escaped(visitID))/comments",
            query: pageQuery(cursor: cursor, limit: limit)
        )
    }

    func addComment(visitID: String, body: String) async throws -> CommunityCommentMutationV1 {
        try await send(
            path: "/api/v1/community/content/visit/\(escaped(visitID))/comments",
            method: "POST", body: ["body": body]
        )
    }

    func deleteComment(id: String) async throws -> CommunityCommentMutationV1 {
        try await send(path: "/api/v1/community/comments/\(escaped(id))", method: "DELETE", body: Optional<[String: String]>.none)
    }

    private func pageQuery(cursor: String?, limit: Int) -> [URLQueryItem] {
        [.init(name: "cursor", value: cursor), .init(name: "limit", value: String(limit))]
    }

    private func get<T: Decodable>(path: String, query: [URLQueryItem]) async throws -> T {
        var components = URLComponents(url: try configuration.url(for: path), resolvingAgainstBaseURL: false)
        components?.queryItems = query.filter { $0.value != nil }
        guard let url = components?.url else { throw APIConfigurationError.invalidPath }
        return try await execute(URLRequest(url: url))
    }

    private func send<T: Decodable, Body: Encodable>(path: String, method: String, body: Body?) async throws -> T {
        var request = URLRequest(url: try configuration.url(for: path))
        request.httpMethod = method
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return try await execute(request)
    }

    private func execute<T: Decodable>(_ original: URLRequest) async throws -> T {
        var request = original
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (name, value) in try await authorization.headers() { request.setValue(value, forHTTPHeaderField: name) }
        var (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 401,
           try await authorization.recoverUnauthorized(failedAuthorization: request.value(forHTTPHeaderField: "Authorization")) {
            for (name, value) in try await authorization.headers() { request.setValue(value, forHTTPHeaderField: name) }
            (data, response) = try await session.data(for: request)
        }
        guard let http = response as? HTTPURLResponse else { throw SyncAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            throw SyncAPIError.server(status: http.statusCode, message: body?["error"] as? String ?? "Social collaboration request failed.")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func escaped(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }
}
