import Foundation
import UIKit

nonisolated struct PrivateDirectoryDashboard: Codable, Sendable {
    struct Entry: Codable, Identifiable, Sendable {
        let id: String
        let kind: String
        let displayName: String
        let linkedUserID: String?
        var avatarURL: String?
    }
    struct Person: Codable, Identifiable, Sendable { let id: String; let displayName: String }
    let apiVersion: Int
    let userID: String
    var entries: [Entry]
    let users: [Person]
    let links: [CompanionLinkRequestV1]
}

extension URLSessionPremiumEntitlementAPIClient {
    func directoryRequest(path: String = "/api/v1/directory", body: Data? = nil) async throws -> Data {
        guard path == "/api/v1/directory" || path.hasPrefix("/api/v1/directory/avatar/") || path.hasPrefix("/api/v1/social/companion-links/") else {
            throw PremiumEntitlementAPIError.invalidResponse
        }
        var request = URLRequest(url: try configuration.url(for: path))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        for (key,value) in try await authorization.headers() { request.setValue(value,forHTTPHeaderField:key) }
        var (data,response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 401,
           try await authorization.recoverUnauthorized(failedAuthorization: request.value(forHTTPHeaderField: "Authorization")) {
            for (key,value) in try await authorization.headers() { request.setValue(value,forHTTPHeaderField:key) }
            (data,response) = try await session.data(for: request)
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PremiumEntitlementAPIError.server(status: (response as? HTTPURLResponse)?.statusCode ?? 503, message: "私人资料操作未完成，请检查登录、同步和双方关系。")
        }
        return data
    }
    func directoryDashboard(userID: String) async throws -> PrivateDirectoryDashboard {
        let result = try JSONDecoder().decode(PrivateDirectoryDashboard.self, from: await directoryRequest())
        guard result.apiVersion == 1, result.userID == userID else { throw PremiumEntitlementAPIError.invalidResponse }
        return result
    }
}

@MainActor
enum PrivateDirectoryAvatar {
    static func encoded(_ data: Data) throws -> String {
        guard data.count <= 20_000_000, let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else {
            throw PremiumEntitlementAPIError.invalidResponse
        }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let side = CGFloat(256), factor = max(side/image.size.width, side/image.size.height)
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: side,height: side),format:format).image { _ in
            image.draw(in: CGRect(x:(side-image.size.width*factor)/2,y:(side-image.size.height*factor)/2,width:image.size.width*factor,height:image.size.height*factor))
        }
        guard let jpeg = rendered.jpegData(compressionQuality: 0.7), jpeg.count < 65_000 else { throw PremiumEntitlementAPIError.invalidResponse }
        return "data:image/jpeg;base64," + jpeg.base64EncodedString()
    }
}
