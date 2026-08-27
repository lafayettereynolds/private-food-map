import AuthenticationServices
import SwiftData
import SwiftUI
import UIKit

struct ProfileView: View {
    @Environment(NativeAuthServices.self) private var authServices
    @Environment(\.modelContext) private var modelContext
    @Query private var restaurants: [Restaurant]
    @Query private var visits: [Visit]
    @State private var authenticatedUser: AuthenticatedUserV1?
    @State private var isRunningAuthOperation = false
    @State private var authMessage: String?

    private var activeRestaurants: [Restaurant] { restaurants.filter { $0.deletedAt == nil } }
    private var activeVisits: [Visit] { visits.filter { $0.deletedAt == nil } }

    private var visitedRestaurantCount: Int {
        Set(activeVisits.map(\.restaurantId)).count
    }

    private var averageRating: Double? {
        let ratings = activeVisits.compactMap(\.rating)
        guard !ratings.isEmpty else { return nil }
        return ratings.reduce(0, +) / Double(ratings.count)
    }

    private var totalSpend: Decimal? {
        let values = activeVisits.compactMap(\.myActualSpend)
        guard !values.isEmpty else { return nil }
        return values.reduce(Decimal.zero, +)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("账号与同步") {
                    if let authenticatedUser {
                        LabeledContent("Taste Map 用户") {
                            Text(authenticatedUser.id)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                        if let email = authenticatedUser.email {
                            LabeledContent("Apple 邮箱", value: email)
                        }
                        Button("立即同步") {
                            Task { await synchronize() }
                        }
#if DEBUG
                        Button("验证 Token 刷新") {
                            Task { await forceRefresh() }
                        }
#endif
                        Button("退出登录", role: .destructive) {
                            Task { await logout() }
                        }
                    } else {
                        Button {
                            Task { await signIn() }
                        } label: {
                            Label("使用 Apple 登录", systemImage: "apple.logo")
                        }
                    }

                    if isRunningAuthOperation {
                        ProgressView()
                    }
                    if let authMessage {
                        Text(authMessage)
                            .font(.footnote)
                            .foregroundStyle(authMessage.hasPrefix("失败") ? .red : .secondary)
                    }
                }

                Section("我的记录") {
                    LabeledContent("去过的餐厅", value: "\(visitedRestaurantCount)")
                    LabeledContent("到访记录", value: "\(activeVisits.count)")
                    LabeledContent(
                        "我的平均评分",
                        value: averageRating.map { String(format: "%.1f", $0) } ?? "未评分"
                    )
                    if let totalSpend {
                        LabeledContent("累计实际消费", value: Self.currencyString(totalSpend))
                    }
                }

                if activeRestaurants.isEmpty {
                    Section {
                        Text("保存第一次到访后，你的真实记录会显示在这里。")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("我的")
            .task {
                authenticatedUser = await authServices.sessionManager.restoredUser()
                if authenticatedUser != nil {
                    await synchronize(showProgress: false)
                }
            }
        }
    }

    @MainActor
    private func signIn() async {
        guard let anchor = presentationAnchor else {
            authMessage = "失败：无法取得登录窗口。"
            return
        }
        await performAuthOperation {
            authenticatedUser = try await authServices.appleSignIn.signIn(presentationAnchor: anchor)
            try await SyncEngine(context: modelContext, api: authServices.syncAPI).synchronize()
            return "Apple 登录和同步成功。"
        }
    }

    @MainActor
    private func synchronize(showProgress: Bool = true) async {
        await performAuthOperation(showProgress: showProgress) {
            try await SyncEngine(context: modelContext, api: authServices.syncAPI).synchronize()
            return "同步成功。"
        }
    }

    @MainActor
    private func forceRefresh() async {
        await performAuthOperation {
            authenticatedUser = try await authServices.sessionManager.forceRefresh()
            return "Access/refresh token 已安全轮换。"
        }
    }

    @MainActor
    private func logout() async {
        await performAuthOperation {
            try await authServices.sessionManager.logout()
            authenticatedUser = nil
            return "已退出并清理 Keychain session。"
        }
    }

    @MainActor
    private func performAuthOperation(
        showProgress: Bool = true,
        _ operation: () async throws -> String
    ) async {
        if showProgress { isRunningAuthOperation = true }
        defer { if showProgress { isRunningAuthOperation = false } }
        do {
            authMessage = try await operation()
        } catch {
            authMessage = "失败：\(error.localizedDescription)"
        }
    }

    private var presentationAnchor: ASPresentationAnchor? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }

    private static func currencyString(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = .current
        return formatter.string(from: NSDecimalNumber(decimal: value))
            ?? NSDecimalNumber(decimal: value).stringValue
    }
}
