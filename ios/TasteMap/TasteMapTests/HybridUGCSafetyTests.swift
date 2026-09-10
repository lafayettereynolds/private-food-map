import Foundation
import Testing
@testable import TasteMap

@Suite(.serialized)
@MainActor
struct HybridUGCSafetyTests {
    @Test func scopedUGCRequestCannotRefreshAsAnotherAccount() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [UGCSafetyURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); UGCSafetyURLProtocol.handler = nil }
        let api = URLSessionReleaseSafetyAPIClient(configuration: .init(environment: .development,
            baseURL: URL(string: "https://ugc.example.test")!), authorization: UGCSafetyAuthorization(), session: session)
            .scoped(to: UGCRequestAuthorization(capturedHeaders: ["Authorization": "Bearer captured-account-a-test-only"]))
        var calls = 0
        UGCSafetyURLProtocol.handler = { request in
            calls += 1
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer captured-account-a-test-only")
            return (401, #"{"error":"expired"}"#)
        }
        do { _ = try await api.setBlocked(true, userID: "other"); Issue.record("Expired identity must fail") }
        catch SyncAPIError.server(let status, _) { #expect(status == 401) }
        #expect(calls == 1)
    }
    @Test func authenticatedCapabilityReadUsesEncodedTargetAndNeverClientOwner() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [UGCSafetyURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); UGCSafetyURLProtocol.handler = nil }
        let api = URLSessionReleaseSafetyAPIClient(configuration: .init(environment: .development,
            baseURL: URL(string: "https://ugc.example.test")!), authorization: UGCSafetyAuthorization(), session: session)
        UGCSafetyURLProtocol.handler = { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/api/v1/community/safety")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer ugc-test-only")
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            #expect(query.first { $0.name == "id" }?.value == "comment&userId=other")
            #expect(!query.contains { $0.name == "userId" })
            return (200, #"{"ownerID":"viewer","canReport":false,"canBlock":false,"canDelete":true}"#)
        }
        let result = try await api.safetyCapabilities(type: "comment", id: "comment&userId=other")
        #expect(result.canDelete && !result.canReport && !result.canBlock)
    }

    @Test func reportAndBlockReuseExistingAuthenticatedContractsAndRejectFailure() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [UGCSafetyURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); UGCSafetyURLProtocol.handler = nil }
        let api = URLSessionReleaseSafetyAPIClient(configuration: .init(environment: .development,
            baseURL: URL(string: "https://ugc.example.test")!), authorization: UGCSafetyAuthorization(), session: session)
        let id = UUID()
        UGCSafetyURLProtocol.handler = { request in
            #expect(request.url?.path == "/api/v1/community/reports")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer ugc-test-only")
            return (200, #"{"apiVersion":1,"reportId":"report","status":"pending","duplicate":false}"#)
        }
        #expect(try await api.report(type: .visit, id: "visit", reason: .harassment, details: "", requestID: id).status == "pending")
        UGCSafetyURLProtocol.handler = { request in
            #expect(request.url?.path == "/api/v1/community/blocks/other")
            #expect(request.httpMethod == "PUT")
            return (403, #"{"error":"forbidden"}"#)
        }
        do {
            _ = try await api.setBlocked(true, userID: "other")
            Issue.record("A rejected block must not appear successful")
        } catch SyncAPIError.server(let status, _) { #expect(status == 403) }
    }
}

private struct UGCSafetyAuthorization: SyncAuthorizationProviding {
    func headers() async throws -> [String: String] { ["Authorization": "Bearer ugc-test-only"] }
}
private final class UGCSafetyURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, String))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, body) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
