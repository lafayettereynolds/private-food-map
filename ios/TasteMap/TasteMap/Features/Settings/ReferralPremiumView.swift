import SwiftUI

struct ReferralPremiumView: View {
    @Environment(NativeAuthServices.self) private var authServices
    @State private var dashboard: ReferralDashboardV1?
    @State private var message: String?
    @State private var code = ""
    @State private var loading = false

    var body: some View {
        if ReferralInvitationStore.isAvailable { availableBody } else { Text("邀请功能暂未开放。") }
    }

    private var availableBody: some View {
        List {
            if let dashboard {
                Section("我的邀请") {
                    LabeledContent("已成功邀请", value: "\(dashboard.qualifiedCount)/5")
                    LabeledContent("已获得 Premium 天数", value: "\(dashboard.earnedDays) 天")
                    LabeledContent("待生效奖励天数", value: "\(dashboard.pendingDays) 天")
                    LabeledContent("邀请码") { Text(dashboard.code).textSelection(.enabled) }
                    if let url = URL(string: dashboard.inviteLink) {
                        Text(dashboard.inviteLink).textSelection(.enabled)
                        ShareLink(item: url, subject: Text("一起用 Taste Map 记录美食"), message: Text("新用户通过邀请注册并完成首次有效到访，可获得 14 天 Premium。")) {
                            Label("分享邀请链接", systemImage: "square.and.arrow.up")
                        }.accessibilityIdentifier("referral-share-link")
                    }
                }
                Section("邀请记录") {
                    if dashboard.records.isEmpty { Text("还没有邀请记录") }
                    ForEach(Array(dashboard.records.enumerated()), id: \.element.id) { index, record in
                        SettingsDestinationLabel(title: "好友 \(dashboard.records.count-index) · \(record.statusText)",
                            subtitle: "注册 \(String(record.boundAt.prefix(10)))", systemImage: "person")
                    }
                }
            } else if loading {
                Section { ProgressView("正在读取邀请记录") }
            }
            if authServices.localAccountScope == .guest {
                Section("通过邀请码注册") {
                    TextField("24 位邀请码", text: $code)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("使用此邀请码") {
                        do { try ReferralInvitationStore.prepare(code); message = "邀请码已保存。请返回‘我的’，使用 Apple 登录创建新账号；完成首次有效到访后可领取奖励。已有账号不参与新用户奖励。" }
                        catch { message = error.localizedDescription }
                    }
                }
            }
            Section("奖励规则") {
                Text("每成功邀请 1 位新用户，你获得 30 天 Premium，好友获得一次性 14 天 Premium。终身最多成功邀请 5 人，累计最多 150 天。")
                Text("好友需通过邀请码或链接注册，并保存首次有效到访。每个新用户只能绑定一位邀请人。撤销记录不会恢复终身名额。")
                Text("App Store 订阅有效期间，奖励存入待生效余额，订阅权益结束后生效；不会修改 Apple 订阅或续费日期。普通赠送或奖励会员顺延，永久赠送会员不增加期限。")
            }
            if let message { Section { Text(message).accessibilityIdentifier("referral-message") } }
            Section { Button("刷新邀请记录") { Task { await load() } }.disabled(loading) }
        }
        .listStyle(.insetGrouped).scrollContentBackground(.hidden)
        .background(TasteMapCoreTheme.page).tint(TasteMapCoreTheme.brand)
        .navigationTitle("邀请好友").navigationBarTitleDisplayMode(.inline)
        .task(id: authServices.localAccountScope) { dashboard = nil; await load() }
        .onReceive(NotificationCenter.default.publisher(for: .tasteMapSyncDidComplete)) { _ in Task { await load() } }
    }

    @MainActor private func load() async {
        guard case .authenticated(let owner) = authServices.localAccountScope else { dashboard = nil; return }
        loading = true; message = nil
        defer { loading = false }
        do {
            let result = try await authServices.premiumAPI.referralDashboard(userID: owner)
            guard authServices.localAccountScope == .authenticated(owner), result.userID == owner else { return }
            dashboard = result
        } catch {
            guard authServices.localAccountScope == .authenticated(owner) else { return }
            dashboard = nil; message = error.localizedDescription
        }
    }
}
