import SwiftData
import SwiftUI

struct RestaurantEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let restaurant: Restaurant

    @State private var name: String
    @State private var city: String
    @State private var isSaving = false
    @State private var saveError: String?

    init(restaurant: Restaurant) {
        self.restaurant = restaurant
        _name = State(initialValue: restaurant.name)
        _city = State(initialValue: restaurant.city)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基础信息") {
                    TextField("餐厅名称", text: $name)
                    TextField("城市（可选）", text: $city)
                }

                Section {
                    LabeledContent("地址", value: restaurant.address.isEmpty ? "暂无地址" : restaurant.address)
                    LabeledContent("地图位置") {
                        Text(String(format: "%.5f, %.5f", restaurant.latitude, restaurant.longitude))
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("受保护的位置资料")
                } footer: {
                    Text("地址和坐标来自当前地点记录。本阶段暂不开放文字修改，避免地址与地图位置不一致。")
                }

                if restaurant.appleMapItemIdentifier != nil {
                    Section {
                        Label("Apple Maps 地点关联会保持不变", systemImage: "checkmark.shield")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("编辑餐厅")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("无法保存", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("好", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "请稍后重试。")
            }
        }
    }

    private func save() {
        isSaving = true
        defer { isSaving = false }

        do {
            try LocalTasteMapStore(context: modelContext).updateBasics(
                restaurant,
                name: name,
                city: city
            )
            dismiss()
        } catch {
            saveError = "餐厅资料没有保存成功，请重试。"
        }
    }
}
