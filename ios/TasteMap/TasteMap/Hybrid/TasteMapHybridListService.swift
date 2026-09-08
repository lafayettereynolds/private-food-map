import Foundation
import SwiftData

/// Owner-scoped List read/share boundary. Continuations never accept an owner
/// or a raw server cursor supplied by JavaScript, and cannot outlive refresh.
@MainActor
final class TasteMapHybridListService {
    let ownerUserID: String
    private let container: ModelContainer
    private let api: any RestaurantListAPI
    private let sharing: any PublicSharingAPI
    private let currentOwner: () -> String?
    private struct Continuation {
        let listID: String
        let cursor: String
        let updatedAt: String
        let generation: Int
        let expiresAt: Date
    }
    private var pages: [String: Continuation] = [:]
    private var generations: [String: Int] = [:]
    private var invalidated = false

    init(container: ModelContainer, ownerUserID: String, api: any RestaurantListAPI,
         sharing: any PublicSharingAPI, currentOwner: @escaping () -> String?) {
        self.container = container
        self.ownerUserID = ownerUserID
        self.api = api
        self.sharing = sharing
        self.currentOwner = currentOwner
    }

    func invalidate() {
        invalidated = true
        pages.removeAll()
        // Keep monotonic generations, so an in-flight first page is rejected.
        for key in generations.keys { generations[key, default: 0] += 1 }
    }

    func get(_ request: TasteMapHybridListGetRequest) async throws -> TasteMapHybridListPageDTO {
        try validate(request.id)
        try assertOwner()
        let continuation: Continuation?
        if let cursor = request.cursor {
            guard let value = pages.removeValue(forKey: cursor), value.listID == request.id,
                  value.expiresAt > .now, generations[request.id] == value.generation else {
                throw error("list_cursor_expired", "食单分页已失效，请重新读取。")
            }
            continuation = value
        } else {
            generations[request.id, default: 0] += 1
            pages = pages.filter { $0.value.listID != request.id && $0.value.expiresAt > .now }
            continuation = nil
        }
        let generation = generations[request.id, default: 0]
        if try ModelContext(container).fetch(FetchDescriptor<RestaurantList>()).contains(where: {
            $0.ownerUserID == ownerUserID && $0.deletedAt != nil
                && ($0.remoteID?.caseInsensitiveCompare(request.id) == .orderedSame
                    || $0.id.uuidString.caseInsensitiveCompare(request.id) == .orderedSame)
        }) { throw error("list_unavailable", "这份食单已删除。") }
        let projection = try TasteMapHybridBridgeService(container: container, ownerUserID: ownerUserID)
        if continuation == nil, let own = try projection.ownedList(identifier: request.id) {
            return .init(list: own, nextCursor: nil, generatedAt: ISO8601DateFormatter().string(from: .now))
        }
#if DEBUG
        if continuation == nil,
           ownerUserID == TasteMapHybridDebugFixture.ownerUserID || TasteMapUITestFixtures.usesVisualQA,
           let fixture = try projection.contentSnapshot().lists.first(where: { $0.id == request.id }) {
            return .init(list: fixture, nextCursor: nil, generatedAt: ISO8601DateFormatter().string(from: .now))
        }
#endif
        do {
            let page = try await api.detail(listID: request.id, cursor: continuation?.cursor, limit: 50)
            try assertOwner()
            guard generations[request.id] == generation else { throw error("list_request_superseded", "食单已重新读取。") }
            guard page.apiVersion == 1, page.list.id == request.id,
                  page.list.restaurantCount >= 0 else { throw error("invalid_list_response", "食单服务返回的数据无效。") }
            if let continuation, continuation.updatedAt != page.list.updatedAt {
                throw error("list_changed", "食单已更新，请重新读取后继续。")
            }
            if let continuation, page.nextCursor == continuation.cursor {
                throw error("invalid_list_response", "食单服务返回了重复分页，请重新读取。")
            }
            let context = ModelContext(container)
            context.autosaveEnabled = false
            try LocalRestaurantListStore(context: context).cache(detail: page, viewerUserID: ownerUserID, replace: continuation == nil)
            let list = try projection.publicListProjection(page)
            let nextCursor = page.nextCursor.map { cursor in
                let token = UUID().uuidString
                pages[token] = Continuation(listID: request.id, cursor: cursor, updatedAt: page.list.updatedAt,
                    generation: generation, expiresAt: .now.addingTimeInterval(300))
                return token
            }
            return .init(list: list, nextCursor: nextCursor, generatedAt: page.generatedAt)
        } catch let failure as SyncAPIError {
            try assertOwner()
            guard generations[request.id] == generation else { throw error("list_request_superseded", "食单已重新读取。") }
            if case .server(let status, _) = failure, [401, 403, 404].contains(status) {
                LocalRestaurantListStore(context: ModelContext(container)).invalidate(listID: request.id, viewerUserID: ownerUserID)
                pages = pages.filter { $0.value.listID != request.id }
                throw error("list_unavailable", "这份食单已不可访问，可能已删除或改变可见范围。")
            }
            throw error("list_read_failed", "食单暂时无法读取，请重试。")
        }
    }

    func createShareLink(id: String) async throws -> TasteMapHybridListShareLinkDTO {
        try validate(id)
        try assertOwner()
        let context = ModelContext(container)
        guard let list = try context.fetch(FetchDescriptor<RestaurantList>()).first(where: {
            $0.ownerUserID == ownerUserID && $0.deletedAt == nil
                && ($0.remoteID == id || $0.id.uuidString.caseInsensitiveCompare(id) == .orderedSame)
        }) else { throw error("list_share_not_owned", "只能为自己的公开食单生成分享链接。") }
        guard list.visibility == .public else { throw error("list_share_not_public", "这份食单尚未公开；不会自动修改可见范围。") }
        guard let remoteID = list.remoteID, !remoteID.isEmpty else {
            throw error("list_share_sync_pending", "请先等待食单完成同步，再生成公开链接。")
        }
        do {
            let value = try await sharing.create(entityType: .list, entityID: remoteID)
            try assertOwner()
            let latest = try ModelContext(container).fetch(FetchDescriptor<RestaurantList>()).first {
                $0.ownerUserID == ownerUserID && $0.remoteID == remoteID && $0.deletedAt == nil
            }
            guard latest?.visibility == .public,
                  value.apiVersion == 1, value.entityType == .list,
                  PublicShareRoute.shareID(from: value.url) == value.shareId,
                  value.url.query == nil, value.url.fragment == nil else {
                throw error("invalid_list_share", "分享链接已不可用，请重新检查食单。")
            }
            return .init(url: value.url.absoluteString)
        } catch let failure as PublicSharingAPIError {
            throw error("list_share_failed", failure.errorDescription ?? "暂时无法生成公开链接。")
        }
    }

    private func assertOwner() throws {
        guard !invalidated, currentOwner() == ownerUserID else { throw error("auth_required", "账户已变化，请重新打开食单。") }
    }

    private func validate(_ id: String) throws {
        guard id.range(of: "^[A-Za-z0-9_-]{1,128}$", options: .regularExpression) != nil else {
            throw error("invalid_list_id", "食单标识无效。")
        }
    }

    private func error(_ code: String, _ message: String) -> TasteMapHybridBridgeErrorDTO {
        .init(code: code, message: message, recoverable: true, details: nil)
    }
}
