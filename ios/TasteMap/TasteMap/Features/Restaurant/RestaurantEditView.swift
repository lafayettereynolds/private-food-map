import SwiftData
import SwiftUI

struct RestaurantEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let restaurant: Restaurant

    @State private var name: String
    @State private var city: String
    @State private var phone: String
    @State private var openingHours: String
    @State private var referencePrice: String
    @State private var longTermNote: String
    @State private var isSaving = false
    @State private var saveError: String?

    @MainActor
    init(restaurant: Restaurant) {
        self.restaurant = restaurant
        let metadata = RestaurantDetailMetadata(restaurant: restaurant)
        _name = State(initialValue: restaurant.name)
        _city = State(initialValue: restaurant.city)
        _phone = State(initialValue: metadata.storedPhone ?? "")
        _openingHours = State(initialValue: metadata.openingHours ?? "")
        _referencePrice = State(initialValue: metadata.referencePrice.map {
            NSDecimalNumber(decimal: $0).stringValue
        } ?? "")
        _longTermNote = State(initialValue: metadata.longTermNote ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基础信息") {
                    TextField("餐厅名称", text: $name)
                        .accessibilityIdentifier("restaurant-edit-name")
                    TextField("城市（可选）", text: $city)
                        .accessibilityIdentifier("restaurant-edit-city")
                }

                Section {
                    TextField("电话号码（可选）", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .accessibilityIdentifier("restaurant-edit-phone")
                    TextField("例如：周一至周日 11:00–22:00", text: $openingHours, axis: .vertical)
                        .lineLimit(2...5)
                        .accessibilityIdentifier("restaurant-edit-opening-hours")
                    TextField("参考人均（可选）", text: $referencePrice)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("restaurant-edit-reference-price")
                } header: {
                    Text("营业资料")
                } footer: {
                    Text("参考人均是餐厅层面的消费参考，不会替代任何一次到访中的“我的实际消费”。")
                }

                Section("我的长期备注") {
                    TextEditor(text: $longTermNote)
                        .frame(minHeight: 110)
                        .accessibilityIdentifier("restaurant-edit-long-term-note")
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
                    Text("地址和坐标来自当前地点记录。本阶段不开放修改，避免地址、地图位置和外部地点身份不一致。")
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
                        .accessibilityIdentifier("restaurant-edit-save")
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
        let priceText = referencePrice.trimmingCharacters(in: .whitespacesAndNewlines)
        let price: Decimal?
        if priceText.isEmpty {
            price = nil
        } else if let value = Decimal(string: priceText, locale: .current), value > .zero {
            price = value
        } else {
            saveError = "参考人均需要填写大于 0 的数字。"
            return
        }
        let normalizedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedPhone.isEmpty, RestaurantPhoneDialing.url(for: normalizedPhone) == nil {
            saveError = "电话号码格式无法安全拨打，请只使用数字、空格、括号、短横线和开头的 +。"
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            try LocalTasteMapStore(context: modelContext).updateDetails(
                restaurant,
                name: name,
                city: city,
                phone: normalizedPhone,
                openingHours: openingHours,
                referencePrice: price,
                longTermNote: longTermNote
            )
            dismiss()
        } catch {
            saveError = "餐厅资料没有保存成功，请重试。"
        }
    }
}
