import SwiftUI

struct CommunityInteractionControls: View {
    let visitID: String
    let initial: CommunityEngagementSummaryV1
    let currentUserID: String
    let api: any CommunityInteractionAPI
    let onChange: (CommunityEngagementSummaryV1) -> Void

    @State private var engagement: CommunityEngagementSummaryV1
    @State private var processingLike = false
    @State private var showingComments = false
    @State private var message: String?

    init(
        visitID: String,
        initial: CommunityEngagementSummaryV1,
        currentUserID: String,
        api: any CommunityInteractionAPI,
        onChange: @escaping (CommunityEngagementSummaryV1) -> Void
    ) {
        self.visitID = visitID
        self.initial = initial
        self.currentUserID = currentUserID
        self.api = api
        self.onChange = onChange
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
            }
            .font(.subheadline.weight(.semibold))
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
        }
        .sheet(isPresented: $showingComments) {
            CommunityCommentsView(
                visitID: visitID, currentUserID: currentUserID, api: api,
                initialCount: engagement.commentCount
            ) { count in
                engagement.commentCount = count
                onChange(engagement)
            }
        }
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
}

private struct CommunityCommentsView: View {
    @Environment(\.dismiss) private var dismiss
    let visitID: String
    let currentUserID: String
    let api: any CommunityInteractionAPI
    let initialCount: Int
    let onCountChange: (Int) -> Void

    @State private var comments: [CommunityCommentV1] = []
    @State private var nextCursor: String?
    @State private var text = ""
    @State private var loading = true
    @State private var submitting = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Group {
                    if loading && comments.isEmpty {
                        ProgressView("正在加载评论…").frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if comments.isEmpty {
                        ContentUnavailableView(
                            "还没有评论", systemImage: "bubble.left",
                            description: Text(message ?? "写下与这次公开到访有关的友善评论。")
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

    private func displayDate(_ value: String) -> String {
        CachedCommunityContent.date(value)?.formatted(date: .abbreviated, time: .shortened) ?? value
    }
}
