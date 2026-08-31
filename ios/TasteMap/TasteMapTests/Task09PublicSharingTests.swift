import Foundation
import Testing
@testable import TasteMap

@MainActor
@Suite("Task 09 public sharing client and routes", .serialized)
struct Task09PublicSharingTests {
    @Test("authenticated create and anonymous read use the versioned allowlisted contract")
    func createAndRead() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Task09URLProtocol.self]
        let session = URLSession(configuration: configuration)
        var requests: [URLRequest] = []
        Task09URLProtocol.handler = { request in
            requests.append(request)
            let path = request.url?.path ?? ""
            let body: String
            if path == "/api/v1/public-shares" {
                #expect(request.httpMethod == "POST")
                #expect(request.value(forHTTPHeaderField: "X-Taste-Map-Test-User") == "tm_task09")
                let payload = try #require(Self.requestBody(request))
                let decoded = try JSONDecoder().decode(CreatePublicShareRequestV1.self, from: payload)
                #expect(decoded == .init(entityType: .restaurant, entityId: "restaurant-remote"))
                body = #"{"apiVersion":1,"shareId":"12345678901234567890123456789012","entityType":"restaurant","url":"https://share.example.test/share/12345678901234567890123456789012"}"#
            } else {
                #expect(path == "/api/public/shares/12345678901234567890123456789012")
                #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
                #expect(request.value(forHTTPHeaderField: "X-Taste-Map-Test-User") == nil)
                body = #"{"apiVersion":1,"shareId":"12345678901234567890123456789012","entityType":"profile","entity":{"shareId":"12345678901234567890123456789012","displayName":"公开用户","bio":null,"city":"杭州","statistics":{"restaurantCount":3,"visitCount":5}}}"#
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        defer { Task09URLProtocol.handler = nil }
        let client = URLSessionPublicSharingAPIClient(
            configuration: APIConfiguration(environment: .development, baseURL: URL(string: "https://api.example.test")!),
            authorization: DevelopmentSyncAuthorization(testUserID: "tm_task09"),
            session: session
        )

        let created = try await client.create(entityType: .restaurant, entityID: "restaurant-remote")
        #expect(created.shareId == "12345678901234567890123456789012")
        let shared = try await client.read(shareID: created.shareId)
        guard case .profile(let profile) = shared.entity else {
            Issue.record("Expected allowlisted public profile projection")
            return
        }
        #expect(profile.displayName == "公开用户")
        #expect(profile.statistics.visitCount == 5)
        #expect(requests.count == 2)
    }

    @Test("Universal Link routing accepts only opaque HTTPS share paths")
    func routeValidation() {
        #expect(PublicShareRoute.shareID(from: URL(string: "https://api-dev.tastemap.cn/share/12345678901234567890123456789012")!) == "12345678901234567890123456789012")
        #expect(PublicShareRoute.shareID(from: URL(string: "http://api-dev.tastemap.cn/share/12345678901234567890123456789012")!) == nil)
        #expect(PublicShareRoute.shareID(from: URL(string: "https://api-dev.tastemap.cn/share/internal-restaurant-id")!) == nil)
        #expect(PublicShareRoute.shareID(from: URL(string: "https://api-dev.tastemap.cn/api/public/shares/12345678901234567890123456789012")!) == nil)
    }

    @Test("A public Restaurant share projects into the standard detail identity")
    func restaurantShareDetailProjection() {
        let shared = PublicRestaurantShareV1(
            shareId: "12345678901234567890123456789012",
            name: "公开餐厅",
            address: "湖滨路 8 号",
            city: "杭州",
            cuisines: ["杭帮菜"],
            pricePerPerson: 168,
            merchantImageUrl: nil
        )
        let identity = shared.restaurantDetailIdentity
        #expect(identity.name == "公开餐厅")
        #expect(identity.address == "湖滨路 8 号")
        #expect(identity.city == "杭州")
        #expect(identity.status == nil)
        #expect(RestaurantDetailEntrySource.share.rawValue == "share")
    }

    @Test("unsupported versions and malformed IDs fail closed")
    func failures() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Task09URLProtocol.self]
        Task09URLProtocol.handler = { request in
            let body = #"{"apiVersion":2,"shareId":"12345678901234567890123456789012","entityType":"profile","entity":{"shareId":"12345678901234567890123456789012","displayName":"x","bio":null,"city":null,"statistics":{"restaurantCount":0,"visitCount":0}}}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        defer { Task09URLProtocol.handler = nil }
        let client = URLSessionPublicSharingAPIClient(
            configuration: APIConfiguration(environment: .development, baseURL: URL(string: "https://api.example.test")!),
            session: URLSession(configuration: configuration)
        )
        await #expect(throws: PublicSharingAPIError.invalidShareID) {
            _ = try await client.read(shareID: "internal-id")
        }
        await #expect(throws: PublicSharingAPIError.unsupportedVersion) {
            _ = try await client.read(shareID: "12345678901234567890123456789012")
        }
    }

    private static func requestBody(_ request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { return nil }
            if count == 0 { break }
            result.append(buffer, count: count)
        }
        return result
    }
}

private final class Task09URLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let handler = try Self.handler ?? { _ in throw URLError(.badServerResponse) }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}
