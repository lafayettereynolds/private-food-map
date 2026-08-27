import SwiftUI

struct DishManagerSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var drafts: [DishDraft]
    let existingDishes: [Dish]
    let photos: [PhotoAsset]
    let preparedPhotos: [PreparedLocalPhoto]

    @State private var searchText = ""
    @State private var editingDraft: DishDraft?

    var body: some View {
        NavigationStack {
            List {
                Section("本次吃了什么") {
                    if drafts.isEmpty {
                        ContentUnavailableView(
                            "还没有添加菜品",
                            systemImage: "fork.knife.circle",
                            description: Text("可以选择以前吃过的菜，也可以记录一道新菜。")
                        )
                    } else {
                        ForEach(drafts) { draft in
                            HStack(spacing: 10) {
                                DishDraftRow(
                                    draft: draft,
                                    photo: photos.first { $0.id == draft.photoID }
                                )
                                Button { editingDraft = draft } label: {
                                    Image(systemName: "pencil.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.tint)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("编辑 \(draft.name)")
                                .accessibilityIdentifier("visit-dish-edit-\(draft.id.uuidString)")
                                Button(role: .destructive) {
                                    drafts.removeAll { $0.id == draft.id }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.title2)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("从本次到访移除 \(draft.name)")
                                .accessibilityIdentifier("visit-dish-remove-\(draft.id.uuidString)")
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { editingDraft = draft }
                        }
                        .onDelete { drafts.remove(atOffsets: $0) }
                    }
                }

                Section {
                    ForEach(filteredExistingDishes) { dish in
                        Button {
                            guard !drafts.contains(where: { $0.dishID == dish.id }) else { return }
                            drafts.append(DishDraft(dish: dish))
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "fork.knife")
                                    .foregroundStyle(.tint)
                                    .frame(width: 34, height: 34)
                                    .background(Color.accentColor.opacity(0.1), in: Circle())
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(dish.name)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)
                                    Text(dish.rating.map { String(format: "%.1f ★", $0) } ?? "未评分")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: drafts.contains(where: { $0.dishID == dish.id })
                                      ? "checkmark.circle.fill" : "plus.circle")
                            }
                        }
                        .disabled(drafts.contains(where: { $0.dishID == dish.id }))
                        .accessibilityIdentifier("existing-dish-\(dish.id.uuidString)")
                    }
                    if filteredExistingDishes.isEmpty {
                        Text(existingDishes.isEmpty ? "这家餐厅还没有记录过菜品。" : "没有匹配的历史菜品。")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("以前吃过的菜")
                } footer: {
                    Text("再次选择会关联同一道 Restaurant Dish，不会复制菜品。")
                }

                Section {
                    Button("添加新菜品", systemImage: "plus.circle.fill") {
                        editingDraft = DishDraft()
                    }
                    .accessibilityIdentifier("visit-dish-add-new")
                }
            }
            .searchable(text: $searchText, prompt: "搜索以前吃过的菜")
            .navigationTitle("本次吃了什么")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .accessibilityIdentifier("dish-manager-done")
                }
            }
            .sheet(item: $editingDraft) { draft in
                DishFormSheet(
                    initialDraft: draft,
                    photos: photos,
                    preparedPhotos: preparedPhotos,
                    onSave: save
                )
            }
        }
    }

    private var filteredExistingDishes: [Dish] {
        let query = DishIdentity.normalizedName(searchText)
        return existingDishes
            .filter { query.isEmpty || DishIdentity.normalizedName($0.name).contains(query) }
            .sorted { $0.updatedAt == $1.updatedAt ? $0.name < $1.name : $0.updatedAt > $1.updatedAt }
    }

    private func save(_ draft: DishDraft) {
        if let index = drafts.firstIndex(where: { $0.id == draft.id }) {
            drafts[index] = draft
        } else {
            drafts.append(draft)
        }
        editingDraft = nil
    }
}

private struct DishDraftRow: View {
    let draft: DishDraft
    let photo: PhotoAsset?

    var body: some View {
        HStack(spacing: 12) {
            if let photo {
                PhotoAssetImageView(photo: photo)
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Image(systemName: "takeoutbag.and.cup.and.straw.fill")
                    .foregroundStyle(.orange)
                    .frame(width: 54, height: 54)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(draft.name.isEmpty ? "新菜品" : draft.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Text(draft.rating.map { String(format: "%.1f ★", $0) } ?? "未评分")
                    if let price = draft.price {
                        Text("¥\(NSDecimalNumber(decimal: price).stringValue)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

private struct DishFormSheet: View {
    @Environment(\.dismiss) private var dismiss

    let photos: [PhotoAsset]
    let preparedPhotos: [PreparedLocalPhoto]
    let onSave: (DishDraft) -> Void

    @State private var draft: DishDraft
    @State private var priceText: String
    @State private var error: String?

    init(
        initialDraft: DishDraft,
        photos: [PhotoAsset],
        preparedPhotos: [PreparedLocalPhoto],
        onSave: @escaping (DishDraft) -> Void
    ) {
        self.photos = photos
        self.preparedPhotos = preparedPhotos
        self.onSave = onSave
        _draft = State(initialValue: initialDraft)
        _priceText = State(initialValue: initialDraft.price.map { NSDecimalNumber(decimal: $0).stringValue } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("菜品") {
                    TextField("菜名，例如：招牌牛肉", text: $draft.name)
                        .accessibilityIdentifier("dish-name")
                    TextEditor(text: $draft.taste)
                        .frame(minHeight: 82)
                        .accessibilityLabel("口味与备注，可选")
                        .accessibilityIdentifier("dish-note")
                }
                Section("评分") {
                    HalfStarRatingPicker(rating: $draft.rating)
                }
                Section {
                    TextField("未记录", text: $priceText)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel("菜品价格，可选")
                        .accessibilityIdentifier("dish-price")
                } header: {
                    Text("菜品价格")
                } footer: {
                    Text("不会自动计入本次实际消费；留空与 0 元含义不同。")
                }
                if !photos.isEmpty || !preparedPhotos.isEmpty {
                    Section("代表照片（可选）") {
                        ScrollView(.horizontal) {
                            HStack(spacing: 10) {
                                Button {
                                    draft.photoID = nil
                                } label: {
                                    Image(systemName: draft.photoID == nil ? "checkmark.circle.fill" : "circle")
                                        .frame(width: 66, height: 66)
                                        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                                }
                                ForEach(photos) { photo in
                                    photoChoice(id: photo.id) {
                                        PhotoAssetImageView(photo: photo)
                                    }
                                }
                                ForEach(preparedPhotos) { photo in
                                    photoChoice(id: photo.id) {
                                        PreparedPhotoImageView(prepared: photo)
                                    }
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                    }
                }
            }
            .navigationTitle(draft.dishID == nil ? "新菜品" : "编辑菜品")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .accessibilityIdentifier("dish-save")
                }
            }
            .alert("无法保存菜品", isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )) {
                Button("好", role: .cancel) { error = nil }
            } message: {
                Text(error ?? "请检查菜品内容。")
            }
        }
    }

    private func photoChoice<Content: View>(
        id: UUID,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button { draft.photoID = draft.photoID == id ? nil : id } label: {
            content()
                .frame(width: 72, height: 66)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(draft.photoID == id ? Color.accentColor : .clear, lineWidth: 3)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(draft.photoID == id ? "已选择菜品照片" : "选择菜品照片")
        .accessibilityIdentifier("dish-photo-\(id.uuidString)")
    }

    private func save() {
        do {
            let trimmed = priceText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                draft.price = nil
            } else if let value = Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX")), value >= 0 {
                draft.price = value
            } else {
                throw DishDraftError.invalidPrice
            }
            onSave(try draft.validated())
            dismiss()
        } catch let localized as LocalizedError {
            error = localized.errorDescription ?? "请检查菜品内容。"
        } catch {
            self.error = "请检查菜品内容。"
        }
    }
}
