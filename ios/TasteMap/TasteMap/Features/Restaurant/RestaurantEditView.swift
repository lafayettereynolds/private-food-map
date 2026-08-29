import SwiftData
import SwiftUI

struct RestaurantEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allPhotos: [PhotoAsset]

    let restaurant: Restaurant

    @State private var name: String
    @State private var address: String
    @State private var city: String
    @State private var status: RestaurantStatus
    @State private var phone: String
    @State private var openingHours: String
    @State private var referencePrice: String
    @State private var longTermNote: String
    @State private var markerType: RestaurantJSONContractV1.RestaurantMarkerTypeContract
    @State private var markerPhotoID: String?
    @State private var markerEmoji: String
    @State private var isSaving = false
    @State private var saveError: String?

    @MainActor
    init(restaurant: Restaurant) {
        self.restaurant = restaurant
        let metadata = RestaurantDetailMetadata(restaurant: restaurant)
        _name = State(initialValue: restaurant.name)
        _address = State(initialValue: restaurant.address)
        _city = State(initialValue: restaurant.city)
        _status = State(initialValue: restaurant.status)
        _phone = State(initialValue: metadata.storedPhone ?? "")
        _openingHours = State(initialValue: metadata.openingHours ?? "")
        _referencePrice = State(initialValue: metadata.referencePrice.map {
            NSDecimalNumber(decimal: $0).stringValue
        } ?? "")
        _longTermNote = State(initialValue: metadata.longTermNote ?? "")
        _markerType = State(initialValue: metadata.markerType)
        _markerPhotoID = State(initialValue: metadata.markerPhotoID)
        _markerEmoji = State(initialValue: metadata.markerEmoji)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基础信息") {
                    TextField("餐厅名称", text: $name)
                        .accessibilityIdentifier("restaurant-edit-name")
                    TextField("城市（可选）", text: $city)
                        .accessibilityIdentifier("restaurant-edit-city")
                    TextField("地址（可选）", text: $address, axis: .vertical)
                        .lineLimit(2...4)
                        .accessibilityIdentifier("restaurant-edit-address")
                    Picker("状态", selection: $status) {
                        ForEach(RestaurantStatus.allCases, id: \.self) { value in
                            Label(value.title, systemImage: value.systemImage).tag(value)
                        }
                    }
                    .accessibilityIdentifier("restaurant-edit-status")
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
                    Picker("地图标记", selection: $markerType) {
                        Text("表情").tag(RestaurantJSONContractV1.RestaurantMarkerTypeContract.emoji)
                        Text("图片").tag(RestaurantJSONContractV1.RestaurantMarkerTypeContract.image)
                    }
                    .accessibilityIdentifier("restaurant-edit-marker-type")
                    if markerType == .emoji {
                        TextField("地图表情", text: $markerEmoji)
                            .accessibilityIdentifier("restaurant-edit-marker-emoji")
                    } else if markerPhotos.isEmpty {
                        Text("暂无专用地图照片，将继续使用商户图片或默认标记。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("地图照片", selection: $markerPhotoID) {
                            Text("自动选择").tag(String?.none)
                            ForEach(markerPhotos) { photo in
                                Text(photo.fileName ?? "地图照片").tag(photoIdentity(photo) as String?)
                            }
                        }
                        .accessibilityIdentifier("restaurant-edit-marker-photo")
                    }
                } header: {
                    Text("地图呈现")
                } footer: {
                    Text("地图照片只可选择属于这家餐厅的专用标记照片；不会改变地点身份。")
                }

                Section {
                    LabeledContent("地图位置") {
                        Text(String(format: "%.5f, %.5f", restaurant.latitude, restaurant.longitude))
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("受保护的地点身份")
                } footer: {
                    Text("编辑地址不会重建餐厅；坐标、Taste Map Restaurant ID 与 Apple Maps / 高德等 Provider identity 保持不变。需要重新校准地点时应走地点身份校验流程。")
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
                update: RestaurantDetailsUpdate(
                    name: name,
                    address: address,
                    city: city,
                    status: status,
                    phone: normalizedPhone,
                    openingHours: openingHours,
                    referencePrice: price,
                    longTermNote: longTermNote,
                    markerType: markerType,
                    markerPhotoID: markerType == .image ? markerPhotoID : nil,
                    markerEmoji: markerEmoji
                )
            )
            dismiss()
        } catch {
            saveError = "餐厅资料没有保存成功，请重试。"
        }
    }

    private var markerPhotos: [PhotoAsset] {
        allPhotos
            .filter {
                $0.restaurantId == restaurant.id &&
                    $0.kind == .restaurantMarker &&
                    $0.deletedAt == nil &&
                    $0.binaryDeletedAt == nil
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func photoIdentity(_ photo: PhotoAsset) -> String {
        photo.remoteID ?? photo.id.uuidString.lowercased()
    }
}
