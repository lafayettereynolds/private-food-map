import AuthenticationServices
import SwiftData
import SwiftUI
import UIKit

struct AccountDeletionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(NativeAuthServices.self) private var authServices
    @Query private var localSyncMutations: [SyncMutation]

    let currentUserID: String
    let completionAction: SettingsAccountDeletedAction

    private let deletionCredentialStore: any AccountDeletionCredentialStoring

    @State private var preview: AccountDeletionPreviewV1?
    @State private var job: AccountDeletionJobV1?
    @State private var confirmation = ""
    @State private var freshlyAuthenticated = false
    @State private var isWorking = false
    @State private var statusToken: String?
    @State private var message: String?
    @State private var showingFinalConfirmation = false

    init(
        currentUserID: String,
        completionAction: SettingsAccountDeletedAction,
        deletionCredentialStore: any AccountDeletionCredentialStoring = AccountDeletionCredentialStore()
    ) {
        self.currentUserID = currentUserID
        self.completionAction = completionAction
        self.deletionCredentialStore = deletionCredentialStore
    }

    var body: some View {
        List {
            Section {
                Label("永久删除 Taste Map 账户", systemImage: "person.crop.circle.badge.minus")
                    .font(.headline)
                    .foregroundStyle(.red)
                Text("这不会删除你的 Apple Account。服务器会删除当前 Taste Map 用户拥有的餐厅、到访、菜品、照片、榜单与社交关系，并撤销全部登录会话。")
                    .font(.subheadline)
            } header: { Text("删除范围") }

            Section("删除前") {
                NavigationLink {
                    DataBackupSettingsView(
                        isAuthenticated: true,
                        currentTasteMapUserID: currentUserID,
                        allowsImport: true
                    )
                } label: {
                    Label("建议先导出 Backup v1", systemImage: "externaldrive.badge.plus")
                }
                if let preview {
                    LabeledContent(
                        "此设备待同步变更",
                        value: "\(localSyncMutations.filter { $0.ownerUserID == currentUserID }.count)"
                    )
                    LabeledContent("服务器同步冲突", value: "\(preview.pendingMutationCount)")
                    LabeledContent("服务器照片对象", value: "\(preview.photoObjectCount)")
                    LabeledContent("餐厅", value: "\(preview.entityCounts["restaurants"] ?? 0)")
                    LabeledContent("到访", value: "\(preview.entityCounts["visits"] ?? 0)")
                } else if isWorking {
                    ProgressView("正在读取删除范围…")
                }
            }

            Section("安全验证") {
                Button {
                    Task { await freshAuthenticate() }
                } label: {
                    Label(
                        freshlyAuthenticated ? "Apple 登录已重新验证" : "使用 Apple 登录重新验证",
                        systemImage: freshlyAuthenticated ? "checkmark.shield.fill" : "apple.logo"
                    )
                }
                .disabled(isWorking || freshlyAuthenticated)
                Text("重新验证会创建一个短期会话，只用于确认删除的是当前账户。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                TextField("输入 DELETE", text: $confirmation)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("account-delete-confirmation")
                Button("永久删除账户", role: .destructive) {
                    showingFinalConfirmation = true
                }
                .disabled(!canDelete || isWorking)
                .accessibilityIdentifier("account-delete-submit")
            } footer: {
                Text("删除完成后，此设备的 Keychain、本地业务记录、待同步队列和本地照片会清理。使用同一个 Apple 登录再次注册时会获得新的 Taste Map ID，旧数据不会自动恢复。")
            }

            if let job {
                Section("删除任务") {
                    LabeledContent("状态", value: statusTitle(job.status))
                    if job.retryable, statusToken != nil {
                        Button("安全重试") { Task { await retry() } }
                            .disabled(isWorking)
                    }
                }
            }

            if let message {
                Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(TasteMapCoreTheme.page)
        .navigationTitle("删除账户")
        .navigationBarTitleDisplayMode(.inline)
        .task { await resumePendingDeletionOrLoadPreview() }
        .alert("确认永久删除？", isPresented: $showingFinalConfirmation) {
            Button("永久删除", role: .destructive) { Task { await deleteAccount() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作不能撤销。不要关闭 App，直到删除任务完成或显示可重试状态。")
        }
    }

    private var canDelete: Bool {
        preview != nil && freshlyAuthenticated && confirmation == "DELETE"
    }

    @MainActor
    private func resumePendingDeletionOrLoadPreview() async {
        do {
            if let pending = try deletionCredentialStore.load(), pending.userID == currentUserID {
                statusToken = pending.statusToken
                isWorking = true
                defer { isWorking = false }
                let result = try await authServices.releaseSafetyAPI.accountDeletionStatus(
                    statusToken: pending.statusToken
                )
                job = result
                try await finishIfCompleted(result)
                if result.status != .completed {
                    message = result.retryable
                        ? "已恢复上次中断的删除任务，可以安全重试。"
                        : "已恢复上次中断的删除任务。"
                }
                return
            }
        } catch {
            message = "无法恢复上次的删除任务；凭据仍安全保留在 Keychain。"
            return
        }
        await loadPreview()
    }

    @MainActor
    private func loadPreview() async {
        isWorking = true
        defer { isWorking = false }
        do { preview = try await authServices.releaseSafetyAPI.accountDeletionPreview() }
        catch { message = "暂时无法读取删除范围。请联网后重试。" }
    }

    @MainActor
    private func freshAuthenticate() async {
        guard let anchor = presentationAnchor else {
            message = "无法取得 Apple 登录窗口。"
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await authServices.appleSignIn.reauthenticate(
                expectedUserID: currentUserID,
                presentationAnchor: anchor
            )
            freshlyAuthenticated = true
            message = "身份已重新验证。"
        } catch AppleSignInServiceError.accountMismatch {
            message = "重新验证的账户与当前 Taste Map 账户不一致，当前登录状态未切换。"
        } catch { message = "Apple 登录重新验证没有完成。" }
    }

    @MainActor
    private func deleteAccount() async {
        guard canDelete else { return }
        isWorking = true
        defer { isWorking = false }
        let token = Self.makeStatusToken()
        let requestID = UUID()
        statusToken = token
        do {
            try deletionCredentialStore.save(
                PendingAccountDeletionCredential(
                    userID: currentUserID,
                    requestID: requestID,
                    statusToken: token,
                    createdAt: .now
                )
            )
            let result = try await authServices.releaseSafetyAPI.confirmAccountDeletion(
                requestID: requestID, statusToken: token
            )
            job = result
            try await finishIfCompleted(result)
        } catch {
            message = "无法确认服务器是否已接受请求；删除凭据已保存在 Keychain，可在下次打开时恢复。"
        }
    }

    @MainActor
    private func retry() async {
        guard let statusToken else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await authServices.releaseSafetyAPI.retryAccountDeletion(statusToken: statusToken)
            job = result
            try await finishIfCompleted(result)
        } catch { message = "删除任务重试失败；任务凭据仍保留在 Keychain。" }
    }

    @MainActor
    private func finishIfCompleted(_ result: AccountDeletionJobV1) async throws {
        guard result.status == .completed else {
            message = result.retryable ? "服务器数据已进入安全重试状态。" : "删除任务仍在处理中。"
            return
        }
        _ = try await LocalAccountDataPurger(context: modelContext).purgeCurrentAccount(userID: currentUserID)
        try await authServices.sessionManager.clearLocalSessionAfterAccountDeletion()
        try deletionCredentialStore.delete()
        await completionAction.perform()
        message = "Taste Map 账户和此设备上的本地账户数据已删除。"
        dismiss()
    }

    private func statusTitle(_ status: AccountDeletionStatusV1) -> String {
        switch status {
        case .previewed: "已预览"
        case .confirmed: "已确认"
        case .deletingData: "正在删除数据"
        case .deletingObjects: "正在删除照片"
        case .completed: "已完成"
        case .failed: "等待重试"
        }
    }

    private var presentationAnchor: ASPresentationAnchor? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }

    private static func makeStatusToken() -> String {
        let random = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        return "tm_delete_\(random.lowercased())"
    }
}

struct SettingsAccountDeletedAction: Sendable {
    let perform: @MainActor @Sendable () async -> Void
}
