import Foundation

@MainActor
protocol SyncAPI {
    func push(_ request: SyncPushRequestV1) async throws -> SyncPushResponseV1
    func pull(cursor: String, limit: Int) async throws -> SyncPullResponseV1
    func conflictSnapshot(entityType: SyncEntityType, entityID: String) async throws -> SyncConflictSnapshotV1
}

struct SyncConflictSnapshotV1: Decodable {
    let apiVersion: Int
    let entityType: SyncEntityType
    let entityId: String
    let visit: VisitSyncRecordEnvelopeV1?
    let restaurantList: RestaurantListSyncRecordEnvelopeV1?
    let restaurantListItems: [RestaurantListItemSyncRecordEnvelopeV1]
    var visitDish: VisitDishSyncRecordEnvelopeV1? = nil
    var associationParents: AssociationParents? = nil

    struct AssociationParents: Codable {
        let restaurantVersion: Int64
        let visitVersion: Int64
        let dishVersion: Int64
    }

    var serverVersion: Int64? { visitDish?.serverVersion ?? visit?.serverVersion ?? restaurantList?.serverVersion }

    func approvalData() throws -> Data {
        func object<T: Encodable>(_ record: T) throws -> Any {
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(record))
        }
        var result: [String: Any] = ["entityType": entityType.rawValue, "entityId": entityId,
                                     "apiVersion": apiVersion]
        if let visit { result["visit"] = ["serverVersion": visit.serverVersion, "record": try object(visit.record)] }
        if let restaurantList { result["restaurantList"] = ["serverVersion": restaurantList.serverVersion, "record": try object(restaurantList.record)] }
        if let visitDish { result["visitDish"] = ["serverVersion": visitDish.serverVersion, "record": try object(visitDish.record)] }
        if let associationParents { result["associationParents"] = try object(associationParents) }
        result["restaurantListItems"] = try restaurantListItems.map {
            ["serverVersion": $0.serverVersion, "record": try object($0.record)] as [String: Any]
        }
        return try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    }
}

extension SyncAPI {
    func conflictSnapshot(entityType: SyncEntityType, entityID: String) async throws -> SyncConflictSnapshotV1 {
        throw SyncAPIError.unsupportedVersion
    }
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
    private let requestTimeout: TimeInterval

    init(
        configuration: APIConfiguration = .current(),
        authorization: any SyncAuthorizationProviding = MissingSyncAuthorization(),
        session: URLSession = .shared,
        requestTimeout: TimeInterval = SyncRetryPolicy.requestTimeout
    ) {
        self.configuration = configuration
        self.authorization = authorization
        self.session = session
        self.requestTimeout = max(1, min(requestTimeout, 30))
        encoder = JSONEncoder()
        decoder = JSONDecoder()
    }

    func push(_ requestBody: SyncPushRequestV1) async throws -> SyncPushResponseV1 {
        var request = try await makeRequest(path: "/api/v1/sync/push", method: "POST")
        request.httpBody = try encoder.encode(requestBody)
#if DEBUG || TASTEMAP_PRIVATE_PREVIEW
        SyncRecoveryDiagnostic.request(request)
#endif
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

    func conflictSnapshot(entityType: SyncEntityType, entityID: String) async throws -> SyncConflictSnapshotV1 {
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "entityType", value: entityType.rawValue),
                                 URLQueryItem(name: "entityId", value: entityID)]
        guard let query = components.percentEncodedQuery else { throw SyncAPIError.invalidResponse }
        let request = try await makeRequest(path: "/api/v1/sync/conflict-snapshot?\(query)", method: "GET")
        let response = try await send(request, as: SyncConflictSnapshotV1.self)
        guard response.apiVersion == SyncV1Contract.apiVersion,
              response.entityType == entityType, response.entityId == entityID else {
            throw SyncAPIError.invalidResponse
        }
        return response
    }

    private func makeRequest(path: String, method: String) async throws -> URLRequest {
        var request = URLRequest(url: try configuration.url(for: path))
        request.httpMethod = method
        request.timeoutInterval = requestTimeout
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
#if DEBUG || TASTEMAP_PRIVATE_PREVIEW
        SyncRecoveryDiagnostic.response(request, http: httpResponse, data: data)
#endif
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

#if DEBUG || TASTEMAP_PRIVATE_PREVIEW
/// Metadata only. Never log authorization headers, record content or raw bodies.
enum SyncRecoveryDiagnostic {
    static func requestMetadata(_ request: URLRequest) -> [String: Any]? {
        guard request.url?.path == "/api/v1/sync/push", let data = request.httpBody,
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let mutations = body["mutations"] as? [[String: Any]] else { return nil }
        return ["event": "push_request", "path": "/api/v1/sync/push", "method": "POST",
                "batchSize": mutations.count, "mutations": mutations.map { mutation in
            let payload = mutation["payload"] as? [String: Any] ?? [:]
            let restaurant = payload["restaurant"] as? [String: Any] ?? [:]
            return ["mutationID": mutation["mutationId"] as? String ?? "",
                    "type": mutation["entityType"] as? String ?? "",
                    "baseVersion": mutation["baseVersion"] as? NSNumber ?? -1,
                    "deletedAt": nullState(payload, "deletedAt"),
                    "customCoverPhotoId": nullState(payload, "customCoverPhotoId"),
                    "restaurant.markerPhotoId": nullState(restaurant, "markerPhotoId"),
                    "restaurant.merchantImageUrl": nullState(restaurant, "merchantImageUrl")] as [String: Any]
        }]
    }

    static func request(_ request: URLRequest) {
        if let value = requestMetadata(request) { record(value) }
    }

    static func response(_ request: URLRequest, http: HTTPURLResponse, data: Data) {
        guard request.url?.path == "/api/v1/sync/push" else { return }
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let acknowledgements = body["acknowledgements"] as? [[String: Any]] ?? []
        record(["event": "push_response", "status": http.statusCode,
                "requestID": http.value(forHTTPHeaderField: "CF-Ray") ?? "unavailable",
                "error": safeCode(body["error"]),
                "acknowledgements": acknowledgements.map { ack in
            ["mutationID": ack["mutationId"] as? String ?? "",
             "status": safeCode(ack["status"]),
             "duplicate": ack["duplicate"] as? Bool ?? false,
             "serverVersion": ack["serverVersion"] as? NSNumber ?? -1,
             "conflictReason": safeCode(ack["conflictReason"])] as [String: Any]
        }])
    }

    private static func nullState(_ value: [String: Any], _ key: String) -> String {
        guard let item = value[key] else { return "missing" }
        return item is NSNull ? "null" : "value"
    }

    private static func safeCode(_ value: Any?) -> String {
        guard let value = value as? String else { return "none" }
        return value.range(of: "^[a-zA-Z0-9_]{1,80}$", options: .regularExpression) != nil
            ? value : "non_code_error"
    }

    private static func record(_ metadata: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return }
        DeviceAcceptanceLog.record("TasteMapDiagnostic category=sync_wire \(text)")
    }
}
#endif
