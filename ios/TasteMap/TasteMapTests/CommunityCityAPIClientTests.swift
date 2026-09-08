import Foundation
import Testing
@testable import TasteMap

@Suite(.serialized)
@MainActor
struct CommunityCityAPIClientTests {
    @Test func cityAliasesAreQueryOnlyAndPreserveMeaningfulNameCharacters() {
        #expect(URLSessionCommunityAPIClient.cityQueryKey(" 杭州市 ") == "杭州")
        #expect(URLSessionCommunityAPIClient.cityQueryKey("温州") == "温州")
        #expect(URLSessionCommunityAPIClient.cityQueryKey("New York") == "new york")
        #expect(URLSessionCommunityAPIClient.cityQueryKey("") == "")
    }

    @Test func bothFeedScopesSendExplicitCityAndOpaqueCursorWithAuthenticatedRequest() async throws {
        let session = session()
        defer { session.invalidateAndCancel(); CommunityCityURLProtocol.handler = nil }
        let api = URLSessionCommunityAPIClient(configuration: .init(environment: .development, baseURL: URL(string: "https://community.example.test")!), authorization: CommunityCityAuthorization(), session: session)
        for scope in [CommunityFeedScopeV1.following, .latest] {
            CommunityCityURLProtocol.handler = { request in
                let url = try #require(request.url)
                #expect(url.path == "/api/v1/community/feed")
                let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                #expect(query.first { $0.name == "city" }?.value == "成都")
                #expect(query.first { $0.name == "scope" }?.value == scope.rawValue)
                #expect(query.first { $0.name == "cursor" }?.value == "opaque/next+page")
                #expect(query.first { $0.name == "limit" }?.value == "20")
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer city-test-only")
                let json = "{\"apiVersion\":1,\"scope\":\"\(scope.rawValue)\",\"city\":\"成都\",\"generatedAt\":\"2026-09-06T00:00:00Z\",\"items\":[],\"nextCursor\":null}"
                return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
            }
            let page = try await api.feed(scope: scope, city: "成都市", cursor: "opaque/next+page")
            #expect(page.city == "成都")
        }
    }

    @Test func cityQueriesRejectUnpublishedOrWrongCityResponsesInsteadOfDisplayingAllCities() async throws {
        let session = session()
        defer { session.invalidateAndCancel(); CommunityCityURLProtocol.handler = nil }
        let api = URLSessionCommunityAPIClient(configuration: .init(environment: .development, baseURL: URL(string: "https://community.example.test")!), session: session)
        for cityField in ["", ",\"city\":\"杭州\""] {
            CommunityCityURLProtocol.handler = { request in
                let json = "{\"apiVersion\":1,\"scope\":\"latest\"\(cityField),\"generatedAt\":\"2026-09-06T00:00:00Z\",\"items\":[],\"nextCursor\":null}"
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
            }
            do { _ = try await api.feed(scope: .latest, city: "成都", cursor: nil); Issue.record("An unconfirmed city response must fail") }
            catch let error as SyncAPIError { #expect(error == .invalidResponse) }
        }
    }

    @Test func legacyNoCityCallRemainsCompatibleWithOlderServers() async throws {
        let session = session()
        defer { session.invalidateAndCancel(); CommunityCityURLProtocol.handler = nil }
        let api: any CommunityAPI = URLSessionCommunityAPIClient(configuration: .init(environment: .development, baseURL: URL(string: "https://community.example.test")!), session: session)
        CommunityCityURLProtocol.handler = { request in
            #expect(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "city" } == false)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(#"{"apiVersion":1,"scope":"latest","generatedAt":"2026-09-06T00:00:00Z","items":[],"nextCursor":null}"#.utf8))
        }
        #expect(try await api.feed(scope: .latest, cursor: nil).city == nil)
    }

    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CommunityCityURLProtocol.self]
        return URLSession(configuration: config)
    }
}

private struct CommunityCityAuthorization: SyncAuthorizationProviding {
    func headers() async throws -> [String: String] { ["Authorization": "Bearer city-test-only"] }
}

private final class CommunityCityURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let callback = try Self.handler ?? { _ in throw URLError(.badServerResponse) }
            let (response, data) = try callback(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
