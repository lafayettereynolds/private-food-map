import Foundation
import SwiftData
import SwiftUI

/// A private per-account preference, not a Restaurant deletion or a Visit mutation.
@MainActor
enum RestaurantRecommendationPreferences {
    static let didChange = Notification.Name("TasteMapRecommendationPreferencesDidChange")
    struct Snapshot: Sendable {
        let excludedIDs: [String]
        let intentFeedback: RestaurantRecommendationIntentFeedback
    }

    static func excludedIDs(ownerID: String, context: ModelContext, adding identifier: String? = nil,
                            authorizedSessionIdentityGroups: [Set<String>] = []) throws -> [String] {
        try snapshot(ownerID: ownerID, context: context, adding: identifier,
                     authorizedSessionIdentityGroups: authorizedSessionIdentityGroups).excludedIDs
    }

    static func snapshot(ownerID: String, context: ModelContext, adding identifier: String? = nil,
                         authorizedSessionIdentityGroups: [Set<String>] = [],
                         authorizedSessionMetadata: [RestaurantRecommendationIntentMetadata] = [],
                         defaults: UserDefaults = .standard) throws -> Snapshot {
        guard !ownerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TasteMapHybridServiceError.invalidRequest
        }
        let key = "tastemap.recommendation-exclusions.v1.\(ownerID)"
        let intentKey = "tastemap.recommendation-intent.v1.\(ownerID)"
        if defaults.object(forKey: key) != nil && defaults.stringArray(forKey: key) == nil {
            throw TasteMapHybridServiceError.invalidRequest
        }
        var excluded = Set(defaults.stringArray(forKey: key) ?? [])
        var votes: [RestaurantRecommendationIntentVote] = []
        if defaults.object(forKey: intentKey) != nil {
            guard let data = defaults.data(forKey: intentKey) else { throw TasteMapHybridServiceError.invalidRequest }
            votes = try JSONDecoder().decode([RestaurantRecommendationIntentVote].self, from: data)
        }
        let synchronized = try RecommendationPreferenceLedger.values(owner: ownerID, defaults: defaults)
        excluded.formUnion(synchronized.excluded)
        votes = synchronized.votes + votes
        // Supplied only by Native's accepted current-owner city-page authority,
        // never by a JavaScript payload or a persistent Discovery cache write.
        var groups = authorizedSessionIdentityGroups
        var metadata = authorizedSessionMetadata
        for restaurant in try context.fetch(FetchDescriptor<Restaurant>()) where restaurant.ownerUserID == ownerID {
            let record = try SyncRecordMapper.restaurantRecord(restaurant)
            let aliases = Set(([restaurant.id.uuidString, record.id] + record.placeIdentities.map {
                "\($0.provider.rawValue):\($0.externalId)"
            }).map { $0.lowercased() })
            groups.append(aliases)
            if restaurant.deletedAt == nil {
                metadata.append(.init(aliases: aliases, name: restaurant.name, tags: record.tags))
            }
        }
        for cached in try context.fetch(FetchDescriptor<CachedDiscoveryRestaurant>()) where cached.currentUserID == ownerID {
            guard let projection = cached.projection else { continue }
            let aliases = Set(([projection.globalKey] + projection.placeIdentities.map {
                "\($0.provider.rawValue):\($0.externalId)"
            }).map { $0.lowercased() })
            groups.append(aliases)
            metadata.append(.init(aliases: aliases, name: projection.name, tags: projection.tags))
        }
        groups += metadata.map(\.aliases)
        excluded = RestaurantRecommendationIntentPolicy.expand(excluded, through: groups)
        votes = RestaurantRecommendationIntentPolicy.reconcile(votes, groups: groups)
        if let identifier {
            let normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty, normalized.count <= 512,
                  groups.contains(where: { $0.contains(normalized) }) else {
                throw TasteMapHybridServiceError.invalidRequest
            }
            let aliases = RestaurantRecommendationIntentPolicy.expand([normalized], through: groups)
            // Existing v1 exclusions are not retroactive willingness feedback.
            // Alias expansion prevents another ID of the same shop voting twice.
            if excluded.isDisjoint(with: aliases) && !votes.contains(where: { !$0.aliases.isDisjoint(with: aliases) }) {
                let classifications = metadata.filter { !$0.aliases.isDisjoint(with: aliases) }.map {
                    RestaurantRecommendationIntentPolicy.classify(name: $0.name, tags: $0.tags)
                }
                let brands = Set(classifications.compactMap(\.brandID))
                let contexts = Set(classifications.compactMap(\.context))
                votes.append(.init(aliases: aliases, brandID: brands.count == 1 ? brands.first : nil,
                                   context: contexts.count == 1 ? contexts.first : nil))
            }
            excluded.formUnion(aliases)
        }
        // Resolve transitive local/provider/global aliases, including identities learned
        // after the original dismissal. Never merge by name or approximate location.
        var previousCount: Int
        repeat {
            previousCount = excluded.count
            for group in groups where !group.isDisjoint(with: excluded) { excluded.formUnion(group) }
        } while previousCount != excluded.count
        let result = excluded.sorted()
        let encodedVotes = try JSONEncoder().encode(votes)
        // Write durable events before acknowledging local success. Remote push
        // runs separately; no network wait or rollback of the user's choice.
        try RecommendationPreferenceLedger.capture(owner: ownerID, excluded: excluded, votes: votes,
            explicitAliases: identifier.map { RestaurantRecommendationIntentPolicy.expand([$0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()], through: groups) }, defaults: defaults)
        if defaults.data(forKey: intentKey) != encodedVotes && !votes.isEmpty {
            defaults.set(encodedVotes, forKey: intentKey)
        }
        if defaults.stringArray(forKey: key) != result {
            defaults.set(result, forKey: key)
        }
        if identifier != nil {
            NotificationCenter.default.post(name: didChange, object: ownerID)
            NotificationCenter.default.post(name: .tasteMapLocalDataDidChange, object: nil,
                                            userInfo: ["reason": "recommendationPreferenceChanged"])
        }
        return Snapshot(excludedIDs: result, intentFeedback: RestaurantRecommendationIntentPolicy.feedback(votes))
    }
}

/// One action owner for Native rollback cards and the canonical detail cover.
struct RestaurantNotInterestedButton: View {
    @Environment(\.modelContext) private var context
    @Environment(\.localAccountScope) private var accountScope
    let restaurantID: String
    var overlay = false
    @State private var saved = false
    @State private var error: String?
    @State private var confirmationOwnerID: String?
    @State private var showingConfirmation = false

    var body: some View {
        Button {
            guard let owner = accountScope.authenticatedUserID else { error = "请先登录后再保存推荐偏好。"; return }
            confirmationOwnerID = owner
            showingConfirmation = true
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: TasteMapDesignTokens.Icon.standard))
                .foregroundStyle(TasteMapCoreTheme.textSecondary)
                .frame(minWidth: TasteMapDesignTokens.Control.minimumHitTarget,
                       minHeight: TasteMapDesignTokens.Control.minimumHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(saved)
        .accessibilityLabel(saved ? "已标记不感兴趣" : "不感兴趣")
        .task(id: "\(accountScope.authenticatedUserID ?? ""):\(restaurantID)") {
            confirmationOwnerID = nil
            showingConfirmation = false
            guard let owner = accountScope.authenticatedUserID else { saved = false; return }
            saved = (try? RestaurantRecommendationPreferences.excludedIDs(ownerID: owner, context: context))?.contains(restaurantID.lowercased()) == true
        }
        .confirmationDialog("不再推荐这家餐厅？", isPresented: $showingConfirmation, titleVisibility: .visible) {
            Button("确认不感兴趣") {
                guard let owner = confirmationOwnerID, owner == accountScope.authenticatedUserID else { confirmationOwnerID = nil; return }
                do {
                    _ = try RestaurantRecommendationPreferences.excludedIDs(ownerID: owner, context: context, adding: restaurantID)
                    saved = true
                } catch { self.error = "未能保存不感兴趣，请重试。" }
                confirmationOwnerID = nil
            }
            Button("取消", role: .cancel) { confirmationOwnerID = nil }
        } message: {
            Text("确认后，这家餐厅将从为你推荐和地图推荐中移除；不会删除收藏、到访记录或评分。这次选择用于调整推荐，不代表不喜欢它的味道。")
        }
        .alert("推荐偏好", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }
}
