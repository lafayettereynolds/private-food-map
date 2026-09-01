import SwiftData
import SwiftUI

struct SocialCollaborationInboxView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncCoordinator.self) private var syncCoordinator
    @Query private var visits: [Visit]

    let currentUserID: String
    let api: any SocialCollaborationAPI

    @State private var incoming: [SharedMealInvitationV1] = []
    @State private var sent: [SharedMealInvitationV1] = []
    @State private var accepted: [SharedMealInvitationV1] = []
    @State private var companionIncoming: [CompanionLinkRequestV1] = []
    @State private var isLoading = false
    @State private var processingIDs: Set<String> = []
    @State private var message: String?
    @State private var visitPlan: SharedMealVisitPlan?

    var body: some View {
        NavigationStack {
            List {
                if companionIncoming.isEmpty && incoming.isEmpty && sent.isEmpty && accepted.isEmpty && !isLoading {
                    TasteMapEmptyState(
                        title: "暂无协作消息",
                        message: "饭搭子关联和一起记录邀请会出现在这里。",
                        systemImage: "person.2.wave.2",
                        foodDiningVisualKind: .sharedMeal,
                        presentation: .embedded,
                        accessibilityIdentifier: "social-collaboration-empty-state"
                    )
                }

                if !companionIncoming.isEmpty {
                    Section("饭搭子关联请求") {
                        ForEach(companionIncoming) { request in
                            companionRequestRow(request)
                        }
                    }
                }

                if !incoming.isEmpty {
                    Section("待处理的一起记录") {
                        ForEach(incoming) { invitation in
                            sharedMealRow(invitation, scope: .incoming)
                        }
                    }
                }

                if !accepted.isEmpty {
                    Section("已接受") {
                        ForEach(accepted) { invitation in
                            sharedMealRow(invitation, scope: .accepted)
                        }
                    }
                }

                if !sent.isEmpty {
                    Section("我发出的邀请") {
                        ForEach(sent) { invitation in
                            sharedMealRow(invitation, scope: .sent)
                        }
                    }
                }

                if let message {
                    Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .overlay { if isLoading && allItemsAreEmpty { ProgressView("正在加载…") } }
            .refreshable { await load() }
            .navigationTitle("协作收件箱")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .task { await load() }
            .sheet(item: $visitPlan) { plan in
                VisitEditorView(
                    candidate: plan.candidate,
                    initialDraft: plan.draft,
                    onVisitSaved: { visit in
                        Task { await attach(visit, to: plan.invitation) }
                    }
                )
            }
        }
    }

    @ViewBuilder
    private func companionRequestRow(_ request: CompanionLinkRequestV1) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("\(request.otherUser.displayName) 想与你确认饭搭子关联")
            } icon: {
                PresetProfileAvatarView(preset: request.otherUser.avatarPresetId)
                    .frame(width: 36, height: 36).clipShape(Circle())
            }
            Text("对方通讯录中的名称：\(request.companionDisplayName)")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("接受") { Task { await mutateLink(request, action: .accept) } }
                    .buttonStyle(.borderedProminent)
                Button("拒绝", role: .destructive) { Task { await mutateLink(request, action: .reject) } }
                    .buttonStyle(.bordered)
            }
            .disabled(processingIDs.contains(request.id))
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("companion-link-incoming-\(request.id)")
    }

    @ViewBuilder
    private func sharedMealRow(_ invitation: SharedMealInvitationV1, scope: SharedMealScopeV1) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                FoodDiningVisualIcon(
                    kind: FoodDiningVisualLibrary.kind(
                        legacySymbol: invitation.restaurant.markerEmoji
                    ),
                    usage: .decorative,
                    size: 38
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(invitation.restaurant.name).font(.headline)
                    Text(invitation.restaurant.address).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Text(mealRelationshipText(invitation, scope: scope))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(TasteMapDisplayDate.abbreviatedDateTime(Self.date(invitation.occurredAt)))
                .font(.caption).foregroundStyle(.secondary)

            switch scope {
            case .incoming:
                HStack {
                    Button("接受并记录我的到访") { Task { await accept(invitation) } }
                        .buttonStyle(.borderedProminent)
                    Button("忽略", role: .destructive) { Task { await decline(invitation) } }
                        .buttonStyle(.bordered)
                }
            case .accepted:
                if invitation.visitId != nil {
                    Label("已记录自己的到访", systemImage: "checkmark.circle.fill")
                        .font(.subheadline).foregroundStyle(.green)
                } else if let visit = localVisit(for: invitation) {
                    Button("同步并完成关联", systemImage: "arrow.triangle.2.circlepath") {
                        Task { await attach(visit, to: invitation) }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("记录我的到访", systemImage: "square.and.pencil") {
                        visitPlan = SharedMealVisitPlan(invitation: invitation)
                    }
                    .buttonStyle(.borderedProminent)
                }
            case .sent:
                if invitation.revokedAt != nil || invitation.status == "revoked" {
                    Label("已撤回", systemImage: "xmark.circle")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Label(statusTitle(invitation.status), systemImage: statusIcon(invitation.status))
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("撤回邀请", role: .destructive) { Task { await revoke(invitation) } }
                }
            }
        }
        .padding(.vertical, 5)
        .disabled(processingIDs.contains(invitation.participantId))
        .accessibilityIdentifier("shared-meal-\(scope.rawValue)-\(invitation.participantId)")
    }

    private var allItemsAreEmpty: Bool {
        companionIncoming.isEmpty && incoming.isEmpty && sent.isEmpty && accepted.isEmpty
    }

    private func localVisit(for invitation: SharedMealInvitationV1) -> Visit? {
        for visit in visits {
            guard visit.ownerUserID == currentUserID, visit.deletedAt == nil else { continue }
            if visit.sharedMealID == invitation.mealId { return visit }
        }
        return nil
    }

    private func mealRelationshipText(_ invitation: SharedMealInvitationV1, scope: SharedMealScopeV1) -> String {
        switch scope {
        case .sent: "邀请了 \(invitation.participant.displayName)"
        case .incoming, .accepted: "由 \(invitation.inviter.displayName) 邀请"
        }
    }

    private func statusTitle(_ status: String) -> String {
        switch status {
        case "accepted": "对方已接受"
        case "declined": "对方已忽略"
        case "revoked": "已撤回"
        default: "等待对方处理"
        }
    }

    private func statusIcon(_ status: String) -> String {
        switch status {
        case "accepted": "checkmark.circle"
        case "declined", "revoked": "xmark.circle"
        default: "clock"
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let incomingMeals = api.sharedMeals(scope: .incoming, cursor: nil, limit: 50)
            async let sentMeals = api.sharedMeals(scope: .sent, cursor: nil, limit: 50)
            async let acceptedMeals = api.sharedMeals(scope: .accepted, cursor: nil, limit: 50)
            async let links = api.companionLinks(scope: .incoming, cursor: nil, limit: 50)
            let results = try await (incomingMeals, sentMeals, acceptedMeals, links)
            incoming = results.0.items
            sent = results.1.items
            accepted = results.2.items
            companionIncoming = results.3.items
            message = nil
        } catch {
            message = "协作消息暂时无法加载，请检查网络后重试。"
        }
    }

    @MainActor
    private func mutateLink(_ request: CompanionLinkRequestV1, action: CompanionLinkActionV1) async {
        processingIDs.insert(request.id)
        defer { processingIDs.remove(request.id) }
        do {
            _ = try await api.mutateCompanionLink(id: request.id, action: action)
            await syncCoordinator.synchronizeNow()
            await load()
        } catch { message = "饭搭子关联没有处理成功，请稍后重试。" }
    }

    @MainActor
    private func accept(_ invitation: SharedMealInvitationV1) async {
        processingIDs.insert(invitation.participantId)
        defer { processingIDs.remove(invitation.participantId) }
        do {
            let accepted = try await api.mutateSharedMealParticipant(
                id: invitation.participantId, action: .accept, visitID: nil
            )
            await load()
            visitPlan = SharedMealVisitPlan(invitation: accepted)
        } catch { message = "一起记录邀请没有接受成功，请稍后重试。" }
    }

    @MainActor
    private func decline(_ invitation: SharedMealInvitationV1) async {
        processingIDs.insert(invitation.participantId)
        defer { processingIDs.remove(invitation.participantId) }
        do {
            _ = try await api.mutateSharedMealParticipant(
                id: invitation.participantId, action: .decline, visitID: nil
            )
            await load()
        } catch { message = "邀请没有处理成功，请稍后重试。" }
    }

    @MainActor
    private func attach(_ visit: Visit, to invitation: SharedMealInvitationV1) async {
        processingIDs.insert(invitation.participantId)
        defer { processingIDs.remove(invitation.participantId) }
        guard let visitID = visit.remoteID else {
            message = "到访已保存在本机，但缺少可同步标识；请稍后重试同步。"
            return
        }
        await syncCoordinator.synchronizeNow()
        do {
            _ = try await api.mutateSharedMealParticipant(
                id: invitation.participantId, action: .attach, visitID: visitID
            )
            message = "你的到访已经与这次聚餐安全关联。"
            await load()
        } catch {
            message = "到访已安全保存在本机；云端关联会在你稍后点击“同步并完成关联”时重试。"
            await load()
        }
    }

    @MainActor
    private func revoke(_ invitation: SharedMealInvitationV1) async {
        processingIDs.insert(invitation.participantId)
        defer { processingIDs.remove(invitation.participantId) }
        do {
            _ = try await api.revokeSharedMeal(id: invitation.mealId)
            await load()
        } catch { message = "邀请没有撤回成功，请稍后重试。" }
    }

    fileprivate static func date(_ value: String) -> Date {
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return precise.date(from: value) ?? ISO8601DateFormatter().date(from: value) ?? .now
    }
}

private struct SharedMealVisitPlan: Identifiable {
    let invitation: SharedMealInvitationV1
    let candidate: RestaurantCandidate
    let draft: VisitDraft
    var id: String { invitation.participantId }

    init(invitation: SharedMealInvitationV1) {
        self.invitation = invitation
        let restaurant = invitation.restaurant
        let identities = restaurant.placeIdentities.map {
            RestaurantCandidatePlaceIdentity(
                provider: $0.provider,
                externalID: $0.externalId,
                isPrimary: $0.isPrimary
            )
        }
        candidate = RestaurantCandidate(
            name: restaurant.name,
            address: restaurant.address,
            city: restaurant.city,
            latitude: restaurant.latitude,
            longitude: restaurant.longitude,
            appleMapItemIdentifier: restaurant.placeIdentities.first {
                $0.provider == .appleMaps
            }?.externalId,
            placeIdentities: identities.isEmpty ? [
                RestaurantCandidatePlaceIdentity(
                    provider: .manual,
                    externalID: "shared-meal:\(restaurant.globalKey)",
                    isPrimary: true
                ),
            ] : identities,
            photoURL: restaurant.merchantImageUrl.flatMap(URL.init(string:))
        )
        draft = VisitDraft(
            visitedAt: SocialCollaborationInboxView.date(invitation.occurredAt),
            visibility: .private,
            sharedMealID: invitation.mealId
        )
    }
}

struct CompanionLinkManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncCoordinator.self) private var syncCoordinator
    @Query private var companions: [DiningCompanion]

    let currentUserID: String
    let socialAPI: any SocialAPI
    let collaborationAPI: any SocialCollaborationAPI

    @State private var friends: [SocialUserResultV1] = []
    @State private var incoming: [CompanionLinkRequestV1] = []
    @State private var outgoing: [CompanionLinkRequestV1] = []
    @State private var active: [CompanionLinkRequestV1] = []
    @State private var selectedCompanion: DiningCompanion?
    @State private var processingIDs: Set<String> = []
    @State private var isLoading = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("关联必须由双方明确确认；同名不会自动合并，也不会读取 Apple 登录信息。")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("我的饭搭子通讯录") {
                    ForEach(localCompanions) { companion in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(companion.displayName)
                                Text(companionStatus(companion))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if link(for: companion, in: active) != nil {
                                Image(systemName: "person.crop.circle.badge.checkmark")
                                    .foregroundStyle(.green)
                            } else if link(for: companion, in: outgoing) != nil {
                                Image(systemName: "clock").foregroundStyle(.secondary)
                            } else {
                                Button("选择好友") { selectedCompanion = companion }
                                    .buttonStyle(.bordered)
                            }
                        }
                        .accessibilityIdentifier("companion-link-row-\(companion.id.uuidString)")
                    }
                    if localCompanions.isEmpty {
                        Text("先在饭搭子选择器中新建一个真实姓名或称呼。")
                            .foregroundStyle(.secondary)
                    }
                }

                if !incoming.isEmpty {
                    Section("收到的关联请求") {
                        ForEach(incoming) { request in
                            linkRequestRow(request, incoming: true)
                        }
                    }
                }
                if !outgoing.isEmpty {
                    Section("等待对方确认") {
                        ForEach(outgoing) { request in
                            linkRequestRow(request, incoming: false)
                        }
                    }
                }
                if !active.isEmpty {
                    Section("已关联") {
                        ForEach(active) { request in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(request.companionDisplayName) ↔ \(request.otherUser.displayName)")
                                Button("解除关联", role: .destructive) {
                                    Task { await mutate(request, action: .unlink) }
                                }
                                .disabled(processingIDs.contains(request.id))
                            }
                        }
                    }
                }

                if let message { Section { Text(message).font(.footnote).foregroundStyle(.secondary) } }
            }
            .overlay { if isLoading { ProgressView("正在加载…") } }
            .navigationTitle("关联 Taste Map 好友")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .task { await load() }
            .refreshable { await load() }
            .sheet(item: $selectedCompanion) { companion in
                NavigationStack {
                    List {
                        Section("把“\(companion.displayName)”关联到") {
                            ForEach(friends) { friend in
                                Button {
                                    selectedCompanion = nil
                                    Task { await requestLink(companion: companion, friend: friend) }
                                } label: {
                                    Label(friend.profile.displayName, systemImage: "person.crop.circle")
                                }
                            }
                            if friends.isEmpty {
                                Text("当前没有已接受的 Taste Map 好友。")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .navigationTitle("选择好友")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { selectedCompanion = nil } } }
                }
            }
        }
    }

    private var localCompanions: [DiningCompanion] {
        companions.filter { $0.ownerUserId == currentUserID && $0.deletedAt == nil }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    @ViewBuilder
    private func linkRequestRow(_ request: CompanionLinkRequestV1, incoming isIncoming: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("\(request.companionDisplayName) ↔ \(request.otherUser.displayName)")
            HStack {
                if isIncoming {
                    Button("接受") { Task { await mutate(request, action: .accept) } }
                        .buttonStyle(.borderedProminent)
                    Button("拒绝", role: .destructive) { Task { await mutate(request, action: .reject) } }
                        .buttonStyle(.bordered)
                } else {
                    Button("取消请求", role: .destructive) { Task { await mutate(request, action: .cancel) } }
                }
            }
            .disabled(processingIDs.contains(request.id))
        }
    }

    private func link(for companion: DiningCompanion, in requests: [CompanionLinkRequestV1]) -> CompanionLinkRequestV1? {
        guard let remoteID = companion.remoteID else { return nil }
        return requests.first { $0.companionId == remoteID && $0.requesterUserId == currentUserID }
    }

    private func companionStatus(_ companion: DiningCompanion) -> String {
        if let link = link(for: companion, in: active) { return "已关联 \(link.otherUser.displayName)" }
        if let link = link(for: companion, in: outgoing) { return "等待 \(link.otherUser.displayName) 确认" }
        if companion.linkedTasteMapUserId != nil { return "关联状态将在同步后刷新" }
        return "未关联"
    }

    @MainActor
    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            friends = try await socialAPI.friendships(scope: .friends, cursor: nil, limit: 50).items
            incoming = try await collaborationAPI.companionLinks(scope: .incoming, cursor: nil, limit: 50).items
            outgoing = try await collaborationAPI.companionLinks(scope: .outgoing, cursor: nil, limit: 50).items
            active = try await collaborationAPI.companionLinks(scope: .active, cursor: nil, limit: 50).items
            message = nil
        } catch { message = "关联状态暂时无法加载，请检查网络后重试。" }
    }

    @MainActor
    private func requestLink(companion: DiningCompanion, friend: SocialUserResultV1) async {
        guard let companionID = companion.remoteID else { return }
        processingIDs.insert(companionID)
        defer { processingIDs.remove(companionID) }
        await syncCoordinator.synchronizeNow()
        do {
            _ = try await collaborationAPI.requestCompanionLink(
                companionID: companionID,
                targetUserID: friend.profile.userId
            )
            await load()
        } catch {
            message = "关联请求没有发出。请确认饭搭子已同步，并且对方仍是你的好友。"
        }
    }

    @MainActor
    private func mutate(_ request: CompanionLinkRequestV1, action: CompanionLinkActionV1) async {
        processingIDs.insert(request.id)
        defer { processingIDs.remove(request.id) }
        do {
            _ = try await collaborationAPI.mutateCompanionLink(id: request.id, action: action)
            await syncCoordinator.synchronizeNow()
            await load()
        } catch { message = "关联状态没有更新成功，请稍后重试。" }
    }
}
