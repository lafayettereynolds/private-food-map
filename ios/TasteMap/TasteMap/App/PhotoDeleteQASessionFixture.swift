#if DEBUG
import Foundation
import SwiftData
import SwiftUI

/// Establish the fixture through the normal resolver before mounting a WebView.
/// This tests deletion in an authenticated session, not sign-in UI lifecycle.
struct PhotoDeleteQASessionBootstrap<Content: View>: View {
    let auth: NativeAuthServices
    @ViewBuilder let content: () -> Content
    @State private var ready = false
    var body: some View {
        Group {
            if ready { content() }
            else { ProgressView("Preparing isolated photo test") }
        }.task {
            guard !ready else { return }
            ready = await auth.restoreLocalAccountScope() != nil
        }
    }
}

/// Opt-in, process-local test service. Never participates in the application tier.
enum PhotoDeleteQASessionFixture {
    static let environmentKey = "TASTEMAP_PHOTO_DELETE_QA_SESSION"
    static let ownerID = TasteMapVisualQAFixtures.userID
    static let otherID = "tm_qa_photo_other_user"
    static var enabled: Bool {
        let runtime = TasteMapRuntimeConfiguration.current
        return runtime.isolatesPersistentState && !runtime.allowsNetwork
            && TasteMapUITestFixtures.usesVisualQA
            && ProcessInfo.processInfo.environment[environmentKey] == "1"
    }
    static func credentialStore() throws -> IsolatedAuthCredentialStore {
        let store = IsolatedAuthCredentialStore()
        var credential = try AuthCredential(response: PhotoDeleteQATestService.shared.issue(owner: ownerID))
        credential.appleUserIdentifier = PhotoDeleteQATestService.appleIdentifier
        try store.save(credential)
        return store
    }
    static func configuration() throws -> APIConfiguration {
        try APIConfiguration.resolve(environment: .development,
            values: [APIConfiguration.developmentKey: "https://photo-delete.qa.invalid"])
    }
    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        // Intercept ALL requests: unexpected origins are denied, never forwarded.
        config.protocolClasses = [PhotoDeleteQAURLProtocol.self]
        return URLSession(configuration: config)
    }
    static func storageURL() throws -> URL {
        // UUID supplied by this UI test, reused only for its restart assertion.
        guard let value = ProcessInfo.processInfo.environment["TASTEMAP_PHOTO_DELETE_QA_RUN"],
              let run = UUID(uuidString: value) else { throw CocoaError(.fileReadInvalidFileName) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoDeleteQA", isDirectory: true)
            .appendingPathComponent(run.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent("photo-test.store")
    }
    static func registerPhotos(in container: ModelContainer) throws {
        // This authenticated, offline fixture starts with footprint visibility
        // already reconciled. The rich visual seed otherwise mixes friends/public
        // values and has display-only uploaded photos, not server upload records.
        // Do not enqueue synthetic sync work or reset deletion state on restart.
        let context = container.mainContext
        if let profile = try context.fetch(FetchDescriptor<UserProfile>()).first(where: { $0.tasteMapUserID == ownerID }) {
            for visit in try context.fetch(FetchDescriptor<Visit>()) where visit.ownerUserID == ownerID && visit.deletedAt == nil {
                visit.visibility = VisitVisibility(rawValue: profile.visibility.rawValue) ?? .private
            }
            for photo in try context.fetch(FetchDescriptor<PhotoAsset>()) where photo.ownerUserID == ownerID && photo.deletedAt == nil {
                photo.visibility = PhotoVisibility(rawValue: profile.visibility.rawValue) ?? .private
            }
            try context.save()
        }
        for photo in try container.mainContext.fetch(FetchDescriptor<PhotoAsset>()) {
            PhotoDeleteQATestService.shared.register(photoID: photo.id.uuidString.lowercased(), owner: photo.ownerUserID)
        }
    }
}

nonisolated final class PhotoDeleteQATestService: @unchecked Sendable {
    static let shared = PhotoDeleteQATestService()
    static let appleIdentifier = "photo-delete-qa-local-identity"
    private let lock = NSLock()
    private var access: [String: String] = [:]
    private var refresh: [String: String] = [:]
    private var photos: [String: String] = [:]
    private var deleted: Set<String> = []

    func issue(owner: String) -> AuthSessionResponseV1 {
        lock.withLock {
            let a = "photo-qa-access-" + UUID().uuidString
            let r = "photo-qa-refresh-" + UUID().uuidString
            access[a] = owner; refresh[r] = owner
            let expiry = ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600))
            return AuthSessionResponseV1(apiVersion: 1, user: .init(id: owner, email: nil),
                session: .init(accessToken: a, accessTokenExpiresAt: expiry,
                    refreshToken: r, refreshTokenExpiresAt: expiry))
        }
    }
    func register(photoID: String, owner: String) {
        lock.withLock { photos[photoID] = owner }
    }
    func isDeleted(_ photoID: String) -> Bool { lock.withLock { deleted.contains(photoID) } }
    func respond(_ request: URLRequest, body: Data?) -> (Int, Data) {
        func json(_ status: Int, _ value: [String: Any]) -> (Int, Data) {
            (status, (try? JSONSerialization.data(withJSONObject: value)) ?? Data())
        }
        guard request.url?.host == "photo-delete.qa.invalid" else { return json(403, ["error": "QA origin denied"]) }
        let path = request.url!.path
        if path == "/api/v1/auth/refresh", request.httpMethod == "POST" {
            let payload = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            guard let token = payload?["refreshToken"] as? String,
                  let owner = lock.withLock({ refresh[token] }) else { return json(401, ["error": "Invalid test session"]) }
            return (200, (try? JSONEncoder().encode(issue(owner: owner))) ?? Data())
        }
        let bearer = request.value(forHTTPHeaderField: "Authorization") ?? ""
        guard bearer.hasPrefix("Bearer "), let owner = lock.withLock({ access[String(bearer.dropFirst(7))] }) else {
            return json(401, ["error": "Session required"])
        }
        let parts = path.split(separator: "/")
        if parts.count == 5, parts[0...2].joined(separator: "/") == "api/v1/photos",
           parts[4] == "content", request.httpMethod == "GET" {
            let id = String(parts[3]).lowercased()
            return lock.withLock {
                guard photos[id] == owner, !deleted.contains(id) else { return json(404, ["error": "Photo unavailable"]) }
                return (200, Data([1, 2, 3, 4]))
            }
        }
        if parts.count == 5, parts[0...2].joined(separator: "/") == "api/v1/photos",
           parts[4] == "content", request.httpMethod == "DELETE" {
            let id = String(parts[3]).lowercased()
            return lock.withLock {
                guard photos[id] == owner else { return json(404, ["error": "Photo unavailable"]) }
                deleted.insert(id)
                return json(200, ["apiVersion": 1, "deleted": true])
            }
        }
        // No Sync/Apple/entitlement implementation or broad success fallback.
        return json(503, ["error": "Outside isolated photo test service"])
    }
}

final class PhotoDeleteQAURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var data = Data(); var bytes = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&bytes, maxLength: bytes.count)
                if count <= 0 { break }
                data.append(contentsOf: bytes.prefix(count))
                if data.count > 65536 { break }
            }
            body = data
        }
        let (status, data) = PhotoDeleteQATestService.shared.respond(request, body: body)
        guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: status,
            httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
