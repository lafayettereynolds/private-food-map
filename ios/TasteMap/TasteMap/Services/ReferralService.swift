import Foundation

nonisolated struct ReferralDashboardV1: Codable, Sendable {
    struct Record: Codable, Identifiable, Sendable {
        let id: String
        let status: String
        let boundAt: String
        let qualifiedAt: String?
        let revokedAt: String?
        var statusText: String {
            switch status {
            case "qualified": "邀请成功"
            case "capped": "已达 5 人上限"
            case "revoked": "已撤销"
            default: "等待首次有效到访"
            }
        }
    }
    let apiVersion: Int
    let userID: String
    let code: String
    let inviteLink: String
    let qualifiedCount: Int
    let maxQualified: Int
    let earnedDays: Int
    let pendingDays: Int
    let records: [Record]
}

/// A temporary registration hint, never an entitlement or device-bound attribution.
@MainActor
enum ReferralInvitationStore {
    static var isAvailable: Bool {
        guard let url = Bundle.main.url(forResource: "ProductionEnvironment", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let values = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return values["referralAvailable"] as? Bool == true
    }
    private static var value: (code: String, received: Date)?
    static var code: String? {
        guard isAvailable, let value, Date.now.timeIntervalSince(value.received) < 86_400 else { return nil }
        return value.code
    }
    static func prepare(_ input: String) throws {
        guard isAvailable else { throw PremiumEntitlementAPIError.server(status: 403, message: "邀请功能暂未开放。") }
        let code = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard code.range(of: "^[a-f0-9]{24}$", options: .regularExpression) != nil else {
            throw PremiumEntitlementAPIError.server(status: 400, message: "请输入完整的 24 位邀请码。")
        }
        value = (code, .now)
    }
    static func clear() { value = nil }
    static func receive(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil,
              url.host == APIConfiguration.current().baseURL?.host else { return false }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 2, parts[0] == "invite" else { return false }
        do { try prepare(parts[1]); return true } catch { return false }
    }
}

extension URLSessionPremiumEntitlementAPIClient {
    func referralDashboard(userID: String) async throws -> ReferralDashboardV1 {
        guard ReferralInvitationStore.isAvailable else { throw PremiumEntitlementAPIError.server(status: 403, message: "邀请功能暂未开放。") }
#if DEBUG
        if TasteMapUITestFixtures.usesVisualQA && ProcessInfo.processInfo.environment["TASTEMAP_REFERRAL_UI_TEST"] == "1" {
            return .visualQA(userID: userID)
        }
#endif
        var request = URLRequest(url: try configuration.url(for: "/api/v1/referrals"))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        for (key,value) in try await authorization.headers() { request.setValue(value,forHTTPHeaderField:key) }
        var (data,response) = try await session.data(for:request)
        if let http=response as? HTTPURLResponse, http.statusCode==401,
           try await authorization.recoverUnauthorized(failedAuthorization: request.value(forHTTPHeaderField: "Authorization")) {
            for (key,value) in try await authorization.headers() { request.setValue(value,forHTTPHeaderField:key) }
            (data,response) = try await session.data(for:request)
        }
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw PremiumEntitlementAPIError.server(status: 401, message: "请先登录并联网，再查看邀请奖励。")
        }
        let dashboard = try JSONDecoder().decode(ReferralDashboardV1.self,from:data)
        guard dashboard.apiVersion == 1, dashboard.userID == userID, dashboard.maxQualified == 5,
              (0...5).contains(dashboard.qualifiedCount), URL(string: dashboard.inviteLink)?.host == configuration.baseURL?.host else {
            throw PremiumEntitlementAPIError.invalidResponse
        }
        return dashboard
    }
}

#if DEBUG
extension ReferralDashboardV1 {
    static func visualQA(userID: String) -> Self {
        .init(apiVersion: 1,userID: userID,code: "1234567890abcdef12345678",
              inviteLink: "https://api.tastemap.cn/invite/1234567890abcdef12345678",
              qualifiedCount: 2,maxQualified: 5,earnedDays: 60,pendingDays: 30,
              records: [
                .init(id: "referral-qa-pending",status: "pending",boundAt: "2026-09-07T00:00:00Z",qualifiedAt: nil,revokedAt: nil),
                .init(id: "referral-qa-qualified",status: "qualified",boundAt: "2026-09-06T00:00:00Z",qualifiedAt: "2026-09-06T00:00:00Z",revokedAt: nil),
                .init(id: "referral-qa-qualified-2",status: "qualified",boundAt: "2026-09-05T00:00:00Z",qualifiedAt: "2026-09-05T00:00:00Z",revokedAt: nil)
              ])
    }
}
#endif
