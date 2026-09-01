import SwiftUI

struct CommunityInteractionControls: View {
    let visitID: String
    let initial: CommunityEngagementSummaryV1
    let currentUserID: String
    let authorUserID: String
    let api: any CommunityInteractionAPI
    let safetyAPI: any ReleaseSafetyAPI
    let onChange: (CommunityEngagementSummaryV1) -> Void
    let onBlocked: () -> Void

    @State private var engagement: CommunityEngagementSummaryV1
    @State private var processingLike = false
    @State private var showingComments = false
    @State private var message: String?
    @State private var reportTarget: CommunityReportTarget?
    @State private var confirmingBlock = false

    init(
        visitID: String,
        initial: CommunityEngagementSummaryV1,
        currentUserID: String,
        authorUserID: String,
        api: any CommunityInteractionAPI,
        safetyAPI: any ReleaseSafetyAPI,
        onChange: @escaping (CommunityEngagementSummaryV1) -> Void,
        onBlocked: @escaping () -> Void
    ) {
        self.visitID = visitID
        self.initial = initial
        self.currentUserID = currentUserID
        self.authorUserID = authorUserID
        self.api = api
        self.safetyAPI = safetyAPI
        self.onChange = onChange
        self.onBlocked = onBlocked
        _engagement = State(initialValue: initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 18) {
                Button { Task { await toggleLike() } } label: {
                    Label("\(engagement.likeCount)", systemImage: engagement.likedByViewer ? "heart.fill" : "heart")
                        .foregroundStyle(engagement.likedByViewer ? .red : .primary)
                }
                .buttonStyle(.plain)
                .disabled(processingLike)
                .accessibilityLabel(engagement.likedByViewer ? "取消点赞，当前 \(engagement.likeCount) 个赞" : "点赞，当前 \(engagement.likeCount) 个赞")
                .accessibilityIdentifier("community-like-\(visitID)")

                Button { showingComments = true } label: {
                    Label("\(engagement.commentCount)", systemImage: "bubble.left")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("查看评论，当前 \(engagement.commentCount) 条")
                .accessibilityIdentifier("community-comments-\(visitID)")
                Spacer()
                if authorUserID != currentUserID {
                    Menu {
                        Button("举报内容", systemImage: "exclamationmark.bubble") {
                            reportTarget = CommunityReportTarget(
                                type: .visit, contentID: visitID, authorUserID: authorUserID,
                                title: "公开到访记录"
                            )
                        }
                        Button("屏蔽用户", systemImage: "person.crop.circle.badge.xmark", role: .destructive) {
                            confirmingBlock = true
                        }
                    } label: { Image(systemName: "ellipsis") }
                    .accessibilityLabel("内容安全操作")
                    .accessibilityIdentifier("community-safety-\(visitID)")
                }
            }
            .font(.subheadline.weight(.semibold))
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
        }
        .sheet(isPresented: $showingComments) {
            CommunityCommentsView(
                visitID: visitID, currentUserID: currentUserID, api: api,
                safetyAPI: safetyAPI,
                initialCount: engagement.commentCount
            ) { count in
                engagement.commentCount = count
                onChange(engagement)
            }
        }
        .sheet(item: $reportTarget) { CommunityReportSheet(target: $0, api: safetyAPI) }
        .alert("屏蔽这个用户？", isPresented: $confirmingBlock) {
            Button("屏蔽", role: .destructive) { Task { await blockAuthor() } }
            Button("取消", role: .cancel) {}
        } message: { Text("你们将无法在搜索、主页和社区内容中看到对方。已有好友和关注关系会解除。") }
    }

    @MainActor
    private func toggleLike() async {
        guard !processingLike else { return }
        processingLike = true; defer { processingLike = false }
        do {
            let result = try await api.setLike(!engagement.likedByViewer, visitID: visitID)
            engagement = .init(
                likedByViewer: result.likedByViewer,
                likeCount: result.likeCount,
                commentCount: result.commentCount
            )
            message = nil
            onChange(engagement)
        } catch {
            message = "点赞状态没有更新，请稍后重试。"
        }
    }

    @MainActor
    private func blockAuthor() async {
        do {
            _ = try await safetyAPI.setBlocked(true, userID: authorUserID)
            onBlocked()
        } catch { message = "屏蔽没有完成，请稍后重试。" }
    }
}

private struct CommunityCommentsView: View {
    @Environment(\.dismiss) private var dismiss
    let visitID: String
    let currentUserID: String
    let api: any CommunityInteractionAPI
    let safetyAPI: any ReleaseSafetyAPI
    let initialCount: Int
    let onCountChange: (Int) -> Void

    @State private var comments: [CommunityCommentV1] = []
    @State private var nextCursor: String?
    @State private var text = ""
    @State private var loading = true
    @State private var submitting = false
    @State private var message: String?
    @State private var reportTarget: CommunityReportTarget?
    @State private var confirmingBlockUserID: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Group {
                    if loading && comments.isEmpty {
                        ProgressView("正在加载评论…").frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if comments.isEmpty {
                        TasteMapEmptyState(
                            title: "还没有评论",
                            message: message ?? "写下与这次公开到访有关的友善评论。",
                            systemImage: "bubble.left",
                            presentation: .embedded,
                            accessibilityIdentifier: "community-comments-empty-state"
                        )
                    } else {
                        List {
                            ForEach(comments) { comment in
                                commentRow(comment)
                            }
                            if nextCursor != nil {
                                Button("加载更多") { Task { await loadMore() } }
                                    .frame(maxWidth: .infinity)
                            }
                            if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                        }
                        .listStyle(.plain)
                    }
                }
                Divider()
                HStack(alignment: .bottom, spacing: 10) {
                    TextField("写评论（最多 280 字）", text: $text, axis: .vertical)
                        .lineLimit(1...4)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("community-comment-field")
                    Button("发送") { Task { await submit() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(submitting || normalizedText.isEmpty || normalizedText.count > 280)
                        .accessibilityIdentifier("community-comment-submit")
                }
                .padding()
                .background(.bar)
            }
            .navigationTitle("评论")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .task { await load(reset: true) }
        }
        .sheet(item: $reportTarget) { CommunityReportSheet(target: $0, api: safetyAPI) }
        .alert("屏蔽这个用户？", isPresented: Binding(
            get: { confirmingBlockUserID != nil },
            set: { if !$0 { confirmingBlockUserID = nil } }
        )) {
            Button("屏蔽", role: .destructive) {
                if let userID = confirmingBlockUserID { Task { await block(userID) } }
            }
            Button("取消", role: .cancel) {}
        } message: { Text("屏蔽后，你们将无法在社区中看到对方。") }
    }

    private func commentRow(_ comment: CommunityCommentV1) -> some View {
        HStack(alignment: .top, spacing: 10) {
            PresetProfileAvatarView(preset: comment.author.avatarPresetId)
                .frame(width: 36, height: 36).clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(comment.author.displayName).font(.subheadline.bold())
                Text(comment.body).font(.body).fixedSize(horizontal: false, vertical: true)
                Text(displayDate(comment.createdAt)).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if comment.author.userId == currentUserID {
                Button(role: .destructive) { Task { await delete(comment) } } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删除自己的评论")
            } else {
                Menu {
                    Button("举报评论", systemImage: "exclamationmark.bubble") {
                        reportTarget = CommunityReportTarget(
                            type: .comment, contentID: comment.id,
                            authorUserID: comment.author.userId,
                            title: "\(comment.author.displayName) 的评论"
                        )
                    }
                    Button("屏蔽用户", systemImage: "person.crop.circle.badge.xmark", role: .destructive) {
                        confirmingBlockUserID = comment.author.userId
                    }
                } label: { Image(systemName: "ellipsis") }
                .accessibilityLabel("评论安全操作")
                .accessibilityIdentifier("community-comment-safety-\(comment.id)")
            }
        }
    }

    private var normalizedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    @MainActor
    private func load(reset: Bool) async {
        loading = true; defer { loading = false }
        do {
            let page = try await api.comments(visitID: visitID, cursor: reset ? nil : nextCursor, limit: 20)
            if reset { comments = page.items } else {
                var seen = Set(comments.map(\.id))
                comments.append(contentsOf: page.items.filter { seen.insert($0.id).inserted })
            }
            nextCursor = page.nextCursor
            onCountChange(comments.count + (page.nextCursor == nil ? 0 : max(0, initialCount - comments.count)))
            message = nil
        } catch { message = "评论暂时无法加载。" }
    }

    @MainActor private func loadMore() async { guard nextCursor != nil else { return }; await load(reset: false) }

    @MainActor
    private func submit() async {
        guard !submitting, !normalizedText.isEmpty, normalizedText.count <= 280 else { return }
        submitting = true; defer { submitting = false }
        do {
            let result = try await api.addComment(visitID: visitID, body: normalizedText)
            comments.insert(result.comment, at: 0)
            text = ""
            message = nil
            onCountChange(result.commentCount)
        } catch { message = "评论没有发送成功，请稍后重试。" }
    }

    @MainActor
    private func delete(_ comment: CommunityCommentV1) async {
        do {
            let result = try await api.deleteComment(id: comment.id)
            comments.removeAll { $0.id == comment.id }
            onCountChange(result.commentCount)
        } catch { message = "只能删除自己的评论，请刷新后重试。" }
    }

    @MainActor
    private func block(_ userID: String) async {
        do {
            _ = try await safetyAPI.setBlocked(true, userID: userID)
            comments.removeAll { $0.author.userId == userID }
            confirmingBlockUserID = nil
            onCountChange(comments.count)
        } catch { message = "屏蔽没有完成，请稍后重试。" }
    }

    private func displayDate(_ value: String) -> String {
        CachedCommunityContent.date(value).map(TasteMapDisplayDate.abbreviatedDateTime) ?? value
    }
}
