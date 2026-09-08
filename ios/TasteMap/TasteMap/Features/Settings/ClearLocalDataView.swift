import SwiftData
import SwiftUI

struct ClearLocalDataView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var restaurants: [Restaurant]
    @Query private var visits: [Visit]
    @Query private var dishes: [Dish]
    @Query private var lists: [RestaurantList]
    @Query private var photos: [PhotoAsset]

    let currentUserID: String
    var completionAction = SettingsLocalDataClearedAction(perform: { _ in })

    @State private var isConfirming = false
    @State private var isWorking = false
    @State private var result: LocalAccountContentClearResult?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Label("只清除这台 iPhone", systemImage: "iphone.and.arrow.forward")
                    .font(.headline)
                Text("云端数据、其他设备上的记录、登录账号、个人资料、头像和 Premium 状态都不会被删除。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } header: {
                Text("清除范围")
            }

            Section("本机内容") {
                LabeledContent("餐厅", value: "\(activeRestaurants.count) 家")
                LabeledContent("到访", value: "\(activeVisits.count) 次")
                LabeledContent("菜品", value: "\(activeDishes.count) 道")
                LabeledContent("食单", value: "\(activeLists.count) 份")
                LabeledContent("相关照片", value: "\(contentPhotos.count) 张")
            }

            Section {
                Button("清除本机数据", role: .destructive) {
                    isConfirming = true
                }
                .disabled(isWorking || !hasClearableContent)
                .accessibilityIdentifier("settings-clear-local-data-confirm")
            } footer: {
                Text("清除后当前设备会回到没有餐厅记录的状态。以后重新登录、完整同步或导入备份时，云端或备份中的内容仍可能恢复。")
            }

            if isWorking {
                Section { ProgressView("正在安全清除本机数据…") }
            }
            if let result {
                Section {
                    Label("本机数据已清除", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("已移除 \(result.deletedRecordCount) 条本地记录和 \(result.deletedPhotoFileCount) 个本地照片文件。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("settings-clear-local-data-success")
            }
            if let errorMessage {
                Section { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(TasteMapCoreTheme.page)
        .navigationTitle("清除数据")
        .navigationBarTitleDisplayMode(.inline)
        .alert("清除这台 iPhone 上的数据？", isPresented: $isConfirming) {
            Button("确认清除", role: .destructive) { Task { await clear() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将移除本机的餐厅、到访、菜品、食单及相关照片，但不会删除账户和云端数据。")
        }
        .accessibilityIdentifier("settings-clear-local-data-page")
    }

    private var activeRestaurants: [Restaurant] {
        restaurants.filter { $0.ownerUserID == currentUserID && $0.deletedAt == nil }
    }

    private var activeVisits: [Visit] {
        visits.filter { $0.ownerUserID == currentUserID && $0.deletedAt == nil }
    }

    private var activeDishes: [Dish] {
        dishes.filter { $0.ownerUserID == currentUserID && $0.deletedAt == nil }
    }

    private var activeLists: [RestaurantList] {
        lists.filter { $0.ownerUserID == currentUserID && $0.deletedAt == nil }
    }

    private var contentPhotos: [PhotoAsset] {
        photos.filter { $0.ownerUserID == currentUserID && $0.deletedAt == nil && $0.kind != .avatar }
    }

    private var hasClearableContent: Bool {
        !activeRestaurants.isEmpty || !activeVisits.isEmpty || !activeDishes.isEmpty ||
            !activeLists.isEmpty || !contentPhotos.isEmpty
    }

    @MainActor
    private func clear() async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let value = try await LocalAccountDataPurger(context: modelContext)
                .clearCurrentAccountContent(userID: currentUserID)
            result = value
            await completionAction.perform(value)
        } catch {
            errorMessage = "本机数据没有清除完成，请稍后重试。"
        }
    }
}

struct SettingsLocalDataClearedAction: Sendable {
    let perform: @MainActor @Sendable (LocalAccountContentClearResult) async -> Void
}
