import Foundation

/// The HTTP code is retained all the way to the optional bridge issue. This
/// decoder is also exercised by the platform-independent bridge test target.
struct TasteMapDiscoveryHTTPError: Error, LocalizedError, Sendable {
    let status: Int
    let code: String?
    let message: String

    static func decode(status: Int, data: Data) -> Self {
        struct Body: Decodable { let error: String?; let code: String? }
        do {
            let body = try JSONDecoder().decode(Body.self, from: data)
            return Self(status: status, code: body.code, message: body.error ?? "发现内容暂时无法加载。")
        } catch {
            return Self(status: status, code: nil, message: "发现内容暂时无法加载。")
        }
    }

    var errorDescription: String? { message }
}

enum TasteMapDiscoveryRefreshFailureStage { case request, cacheWrite }

func tasteMapDiscoveryRefreshIssue(_ error: Error, stage: TasteMapDiscoveryRefreshFailureStage = .request) -> TasteMapHybridBridgeErrorDTO {
    if stage == .cacheWrite {
        return .init(code: "discovery_cache_write_failed", message: "发现内容暂未保存，已保留上次缓存，请重试。", recoverable: true, details: nil)
    }
    if let error = error as? TasteMapDiscoveryHTTPError {
        let code = error.code ?? (error.status == 403 ? "discovery_access_required" : error.status == 401 ? "auth_required" : "discovery_refresh_failed")
        let message: String
        switch (error.status, code) {
        case (_, "DISCOVERY_AGGREGATE_CAPACITY"):
            message = "当前城市的发现数据超出完整统计容量，请稍后重试。未返回不完整榜单。"
        case (403, _): message = "这部分发现内容需要相应的访问权限。"
        case (401, _): message = "登录状态需要更新，请重新登录后重试。"
        default: message = "发现内容暂未更新，请稍后重试。"
        }
        return .init(code: code, message: message, recoverable: error.status != 401 && error.status != 403,
                     details: ["status": .number(Double(error.status))])
    }
    if error is DecodingError {
        return .init(code: "discovery_response_invalid", message: "发现数据格式异常，请稍后重试。", recoverable: true, details: nil)
    }
    if let error = error as? URLError {
        let offline = error.code == .notConnectedToInternet
        let timeout = error.code == .timedOut
        return .init(code: offline ? "discovery_offline" : timeout ? "discovery_timeout" : "discovery_transport_failed",
                     message: offline ? "当前未连接互联网，请连接后重试。" : timeout ? "发现请求超时，请重试。" : "暂时无法连接发现服务，请稍后重试。",
                     recoverable: true, details: ["transportCode": .number(Double(error.errorCode))])
    }
    return .init(code: "discovery_refresh_failed", message: "发现内容暂未更新，请稍后重试。", recoverable: true, details: nil)
}

/// Coordinates only Discovery refreshes. Requests never own navigation or the
/// editor's ModelContext. Owners, modes and implicit query scopes stay isolated.
@MainActor
final class TasteMapDiscoveryRefreshCoordinator {
    struct Scope: Hashable {
        let ownerUserID: String
        let mode: String
        let city: String
        let windowDays: Int
    }

    private var statuses: [Scope: TasteMapHybridDiscoveryRefreshStatusDTO] = [:]
    private var evidence: [Scope: TasteMapDiscoveryEvidenceAvailabilityDTO] = [:]
    private var successfulAt: [Scope: Date] = [:]
    private var failedAt: [Scope: Date] = [:]
    private var failureCount: [Scope: Int] = [:]
    private var revisions: [Scope: UInt64] = [:]
    private var pending: [Scope: Task<TasteMapHybridDiscoveryRefreshStatusDTO?, Never>] = [:]
    private var epoch: UInt64 = 0
    private let now: () -> Date

    init(now: @escaping () -> Date = { .now }) { self.now = now }

    func reset() {
        epoch &+= 1
        pending.values.forEach { $0.cancel() }
        pending.removeAll()
        statuses.removeAll()
        evidence.removeAll()
        successfulAt.removeAll()
        failedAt.removeAll(); failureCount.removeAll()
        revisions.removeAll()
    }

    func snapshot(ownerUserID: String, city: String, windowDays: Int) -> [String: TasteMapHybridDiscoveryRefreshStatusDTO] {
        Dictionary(uniqueKeysWithValues: statuses.compactMap { scope, status in
            guard scope.ownerUserID == ownerUserID, scope.city == city, scope.windowDays == windowDays else { return nil }
            return (scope.mode, status)
        })
    }

    func refresh<Page>(
        scope: Scope,
        force: Bool,
        isCurrent: @escaping () -> Bool,
        load: @escaping () async throws -> Page,
        save: @escaping (Page) throws -> Void,
        generatedAt: @escaping (Page) -> String,
        resolvedCity: ((Page) -> String)? = nil,
        evidenceAvailability: ((Page) -> TasteMapDiscoveryEvidenceAvailabilityDTO?)? = nil,
        cachedGeneratedAt: @escaping () throws -> String?
    ) async -> TasteMapHybridDiscoveryRefreshStatusDTO? {
        if !force, let running = pending[scope] { return await running.value }
        if !force, let lastSuccess = successfulAt[scope], now().timeIntervalSince(lastSuccess) < 30,
           let current = statuses[scope], current.issue == nil { return current }
        if !force, let failed = failedAt[scope], let current = statuses[scope],
           now().timeIntervalSince(failed) < min(900, 60 * pow(2, Double(min(4, (failureCount[scope] ?? 1) - 1)))) { return current }
        let revision = (revisions[scope] ?? 0) &+ 1
        revisions[scope] = revision
        let currentEpoch = epoch
        let attemptedAt = ISO8601DateFormatter().string(from: now())
        let task = Task { @MainActor [self] () -> TasteMapHybridDiscoveryRefreshStatusDTO? in
            let canPublish = { self.epoch == currentEpoch && self.revisions[scope] == revision && isCurrent() }
            var stage = TasteMapDiscoveryRefreshFailureStage.request
            do {
                let page = try await load()
                guard canPublish() else { return nil }
                stage = .cacheWrite
                try save(page)
                let result = TasteMapHybridDiscoveryRefreshStatusDTO(
                    state: .fresh, city: resolvedCity?(page) ?? scope.city, windowDays: scope.windowDays,
                    sourceGeneratedAt: generatedAt(page), attemptedAt: attemptedAt, issue: nil)
                statuses[scope] = result
                evidence[scope] = evidenceAvailability?(page)
                successfulAt[scope] = now()
                failedAt[scope] = nil; failureCount[scope] = nil
                return result
            } catch {
                guard canPublish() else { return nil }
                let issue = tasteMapDiscoveryRefreshIssue(error, stage: stage)
#if !TASTEMAP_HYBRID_BRIDGE_CORE
                DeviceAcceptanceLog.record("TasteMapDiagnostic category=discovery event=refresh_failed mode=\(scope.mode) code=\(issue.code)")
#endif
                let restricted = (error as? TasteMapDiscoveryHTTPError).map { $0.status == 403 || $0.status == 401 } ?? false
                var cachedDate: String?
                do { cachedDate = try cachedGeneratedAt() } catch { cachedDate = nil }
                let result = TasteMapHybridDiscoveryRefreshStatusDTO(
                    state: restricted ? .restricted : cachedDate == nil ? .unavailable : .cached,
                    city: statuses[scope]?.city ?? scope.city, windowDays: scope.windowDays,
                    sourceGeneratedAt: restricted ? nil : cachedDate, attemptedAt: attemptedAt, issue: issue)
                statuses[scope] = result
                if restricted || cachedDate == nil { evidence[scope] = nil }
                failedAt[scope] = now()
                failureCount[scope] = (failureCount[scope] ?? 0) + 1
                // Automatic retries back off; an explicit user retry remains available.
                successfulAt[scope] = nil
                return result
            }
        }
        pending[scope] = task
        let result = await task.value
        if epoch == currentEpoch && revisions[scope] == revision { pending[scope] = nil }
        return result
    }

    func evidenceSnapshot(ownerUserID: String, city: String, windowDays: Int) -> [String: TasteMapDiscoveryEvidenceAvailabilityDTO] {
        Dictionary(uniqueKeysWithValues: evidence.compactMap { scope, value in
            guard scope.ownerUserID == ownerUserID, scope.city == city, scope.windowDays == windowDays else { return nil }
            return (scope.mode, value)
        })
    }
}
