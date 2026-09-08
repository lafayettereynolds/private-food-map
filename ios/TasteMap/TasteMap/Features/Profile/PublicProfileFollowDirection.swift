import Foundation

enum PublicProfileFollowDirection {
    enum ReadError: Error { case repeatedCursor, capacityExceeded }

    static func label(isFollowing: Bool, followedByOwner: Bool?) -> String {
        guard isFollowing else { return "关注" }
        return followedByOwner == true ? "互相关注" : "已关注"
    }

    /// A match proves the reverse edge. Absence is known only after the real
    /// followers endpoint is exhausted; partial pages/errors are never false.
    @MainActor
    static func load(ownerUserID: String, api: any SocialAPI, maximumPages: Int = 200) async throws -> Bool {
        var cursor: String?
        var seenCursors = Set<String>()
        for _ in 0..<maximumPages {
            try Task.checkCancellation()
            let page = try await api.follows(scope: .followers, cursor: cursor, limit: 50)
            if page.items.contains(where: { $0.id == ownerUserID }) { return true }
            guard let next = page.nextCursor else { return false }
            guard seenCursors.insert(next).inserted else { throw ReadError.repeatedCursor }
            cursor = next
        }
        throw ReadError.capacityExceeded
    }
}
