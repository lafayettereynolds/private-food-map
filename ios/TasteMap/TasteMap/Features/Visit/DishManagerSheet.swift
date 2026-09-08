import SwiftUI

struct DishManagerSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var drafts: [DishDraft]
    let existingDishes: [Dish]
    var usageByDishID: [UUID: DishReuseUsage] = [:]
    let photos: [PhotoAsset]
    let preparedPhotos: [PreparedLocalPhoto]

    @State private var searchText = ""
    @State private var editingDraft: DishDraft?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    mealStoryHeader

                    VStack(alignment: .leading, spacing: 12) {
                        DishStorySectionHeader(
                            eyebrow: "THIS MEAL",
                            title: "本次吃了什么",
                            detail: drafts.isEmpty ? "从一道菜开始，留下这次用餐的味道。" : "\(drafts.count) 道菜组成了这次用餐故事。"
                        )
                        if drafts.isEmpty {
                            TasteMapEmptyState(
                                title: "还没有添加菜品",
                                message: "可以选择以前吃过的菜，也可以记录一道新菜。",
                                systemImage: "fork.knife.circle",
                                foodDiningVisualKind: .food,
                                presentation: .embedded,
                                accessibilityIdentifier: "dish-manager-empty-state"
                            )
                            .frame(minHeight: 170)
                        } else {
                            ForEach(drafts) { draft in
                                DishStoryDraftCard(
                                    draft: draft,
                                    photo: photos.first { $0.id == draft.photoID },
                                    onEdit: { editingDraft = draft },
                                    onRemove: { drafts.removeAll { $0.id == draft.id } }
                                )
                            }
                        }

                        Button {
                            editingDraft = DishDraft()
                        } label: {
                            Label("记录一道新菜", systemImage: "plus.circle.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("visit-dish-add-new")
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        DishStorySectionHeader(
                            eyebrow: "REVISIT A FLAVOR",
                            title: "以前吃过的菜",
                            detail: "再次选择会关联同一道 Restaurant Dish，不会复制菜品。"
                        )
                        if filteredExistingDishes.isEmpty {
                            Text(existingDishes.isEmpty ? "这家餐厅还没有记录过菜品。" : "没有匹配的历史菜品。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(18)
                                .tasteMapCoreCard(radius: 18)
                        } else {
                            LazyVStack(spacing: 1) {
                                ForEach(filteredExistingDishes) { dish in
                                    let selected = drafts.contains(where: { $0.dishID == dish.id })
                                    Button {
                                        guard !selected else { return }
                                        drafts.append(DishDraft(dish: dish))
                                    } label: {
                                        HStack(spacing: 12) {
                                            FoodDiningVisualIcon(
                                                kind: .food,
                                                usage: .dataLinked,
                                                size: 42,
                                                foregroundColor: TasteMapCoreTheme.brandDeep,
                                                backgroundColor: TasteMapCoreTheme.brandSoft
                                            )
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(dish.name)
                                                    .font(.body.weight(.semibold))
                                                    .foregroundStyle(.primary)
                                                    .multilineTextAlignment(.leading)
                                                Text(reuseDetail(for: dish))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Image(systemName: selected ? "checkmark.circle.fill" : "plus.circle")
                                                .foregroundStyle(selected ? TasteMapCoreTheme.brand : .secondary)
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 11)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(selected)
                                    .accessibilityIdentifier("existing-dish-\(dish.id.uuidString)")
                                    if dish.id != filteredExistingDishes.last?.id {
                                        Divider().padding(.leading, 68)
                                    }
                                }
                            }
                            .tasteMapCoreCard(radius: 18)
                        }
                    }
                }
                .padding(.horizontal, TasteMapDesignTokens.Layout.pageInset)
                .padding(.top, 14)
                .padding(.bottom, 34)
            }
            .background(TasteMapCoreTheme.page)
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

    private var mealStoryHeader: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("MEAL NOTES")
                        .font(.caption2.weight(.bold))
                        .tracking(1.6)
                        .foregroundStyle(TasteMapCoreTheme.brand)
                    Text("把菜和照片留在同一个故事里")
                        .font(.title2.weight(.bold))
                    Text("菜品、评分与代表照片都属于这一次真实到访；离线时也可以继续整理。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                FoodDiningVisualIcon(
                    kind: .tableware,
                    usage: .decorative,
                    size: 58,
                    foregroundColor: TasteMapCoreTheme.brandDeep,
                    backgroundColor: TasteMapCoreTheme.brandSoft
                )
            }
            if !photos.isEmpty || !preparedPhotos.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(photos.prefix(3))) { photo in
                        PhotoAssetImageView(photo: photo)
                            .frame(maxWidth: .infinity)
                            .frame(height: 82)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    ForEach(Array(preparedPhotos.prefix(max(0, 3 - photos.count)))) { photo in
                        PreparedPhotoImageView(prepared: photo)
                            .frame(maxWidth: .infinity)
                            .frame(height: 82)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                .accessibilityElement(children: .contain)
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [TasteMapCoreTheme.surface, TasteMapCoreTheme.brandSoft.opacity(0.72)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay { RoundedRectangle(cornerRadius: 24).stroke(TasteMapCoreTheme.border, lineWidth: 1) }
        .accessibilityIdentifier("dish-manager-meal-story-header")
    }

    private var filteredExistingDishes: [Dish] {
        let query = DishIdentity.normalizedName(searchText)
        return existingDishes
            .filter { query.isEmpty || DishIdentity.normalizedName($0.name).contains(query) }
    }

    private func reuseDetail(for dish: Dish) -> String {
        let rating = dish.rating.map { String(format: "%.1f ★", $0) } ?? "未评分"
        guard let usage = usageByDishID[dish.id], usage.count > 0 else { return rating }
        if let latest = usage.lastUsedAt {
            return "吃过 \(usage.count) 次 · 最近 \(TasteMapDisplayDate.monthDay(latest)) · \(rating)"
        }
        return "吃过 \(usage.count) 次 · \(rating)"
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

private struct DishStorySectionHeader: View {
    let eyebrow: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow)
                .font(.caption2.weight(.bold))
                .tracking(1.4)
                .foregroundStyle(TasteMapCoreTheme.brand)
            Text(title).font(.title3.weight(.bold))
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DishStoryDraftCard: View {
    let draft: DishDraft
    let photo: PhotoAsset?
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 13) {
            DishDraftRow(draft: draft, photo: photo)
            VStack(spacing: 8) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .frame(width: 34, height: 34)
                        .background(TasteMapCoreTheme.surfaceSubtle, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("编辑 \(draft.name)")
                .accessibilityIdentifier("visit-dish-edit-\(draft.id.uuidString)")
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "minus")
                        .frame(width: 34, height: 34)
                        .background(Color.red.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("从本次到访移除 \(draft.name)")
                .accessibilityIdentifier("visit-dish-remove-\(draft.id.uuidString)")
            }
        }
        .padding(14)
        .tasteMapCoreCard(radius: 18)
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
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
    @Environment(PremiumEntitlementService.self) private var premiumEntitlementService

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
                    HalfStarRatingPicker(
                        rating: $draft.rating,
                        accessibilityName: "菜品",
                        accessibilityIdentifier: "dish-rating"
                    )
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
        Button {
            if draft.photoID == id { draft.photoID = nil }
            else if premiumEntitlementService.access(for: .dishPhotos) == .allowed { draft.photoID = id }
            else { premiumEntitlementService.openPaywall(from: .feature(.dishPhotos)) }
        } label: {
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
