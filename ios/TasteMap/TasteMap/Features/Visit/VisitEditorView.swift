import SwiftData
import SwiftUI
import PhotosUI

struct VisitEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.photoTransferCoordinator) private var photoCoordinator
    @Query private var allRestaurants: [Restaurant]
    @Query private var allPhotos: [PhotoAsset]
    @Query private var allDishes: [Dish]
    @Query private var allVisitDishes: [VisitDish]

    private let restaurant: Restaurant?
    private let candidate: RestaurantCandidate?
    private let visit: Visit?
    private let onSaved: ((UUID) -> Void)?

    @State private var draft: VisitDraft
    @State private var partySizeText: String
    @State private var spendText: String
    @State private var totalPriceText: String
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var isConfirmingDeletion = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var preparedPhotos: [PreparedLocalPhoto] = []
    @State private var isImportingPhotos = false
    @State private var photoError: String?
    @State private var didCommitPhotos = false
    @State private var photoDraftSessionID = UUID()
    @State private var dishDrafts: [DishDraft] = []
    @State private var isManagingDishes = false
    @State private var didLoadDishes = false
    @State private var showsDetailedRatings: Bool
    @State private var showsDiningContext: Bool
    @State private var showsExperienceContext: Bool
    @State private var isChoosingCompanions = false
    @State private var isChoosingRecommendationSource = false

    @MainActor
    init(
        restaurant: Restaurant,
        visit: Visit? = nil,
        onSaved: ((UUID) -> Void)? = nil
    ) {
        self.restaurant = restaurant
        candidate = nil
        self.visit = visit
        self.onSaved = onSaved
        let initialDraft = visit.map(VisitDraft.init) ?? VisitDraft()
        _draft = State(initialValue: initialDraft)
        _partySizeText = State(initialValue: Self.integerString(initialDraft.partySize))
        _spendText = State(initialValue: Self.spendString(initialDraft.myActualSpend))
        _totalPriceText = State(initialValue: Self.spendString(initialDraft.totalPrice))
        _showsDetailedRatings = State(initialValue: RatingDimension.allCases.contains {
            $0.value(in: initialDraft) != nil
        })
        _showsDiningContext = State(initialValue:
            !initialDraft.diningOccasionRawValues.isEmpty || initialDraft.queueDurationRawValue != nil
        )
        _showsExperienceContext = State(initialValue: initialDraft.hasExperienceContext)
    }

    @MainActor
    init(candidate: RestaurantCandidate, onSaved: ((UUID) -> Void)? = nil) {
        restaurant = nil
        self.candidate = candidate
        visit = nil
        self.onSaved = onSaved
        _draft = State(initialValue: VisitDraft())
        _partySizeText = State(initialValue: "")
        _spendText = State(initialValue: "")
        _totalPriceText = State(initialValue: "")
        _showsDetailedRatings = State(initialValue: false)
        _showsDiningContext = State(initialValue: false)
        _showsExperienceContext = State(initialValue: false)
    }

    var body: some View {
        NavigationStack {
            Form {
                restaurantSection
                basicsSection
                peopleAndSourceSection
                diningContextSection
                ratingSection
                detailedRatingSection
                dishesSection
                photosSection
                spendSection
                experienceContextSection
                noteSection
                privacySection
                if visit != nil { deleteSection }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(visit == nil ? "新增到访" : "编辑到访")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isSaving || isImportingPhotos)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(isSaving || isImportingPhotos)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(isSaving || isImportingPhotos)
                        .accessibilityIdentifier("visit-editor-save")
                }
            }
            .confirmationDialog(
                "删除这次到访？",
                isPresented: $isConfirmingDeletion,
                titleVisibility: .visible
            ) {
                Button("删除到访记录", role: .destructive, action: deleteVisit)
                Button("取消", role: .cancel) {}
            } message: {
                Text("这只会删除当前 Visit，不会影响这家餐厅的其他记录。")
            }
            .alert("无法完成", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("好", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "请稍后重试。")
            }
            .alert("无法添加照片", isPresented: Binding(
                get: { photoError != nil },
                set: { if !$0 { photoError = nil } }
            )) {
                Button("好", role: .cancel) { photoError = nil }
            } message: {
                Text(photoError ?? "请换一张图片重试。")
            }
            .onChange(of: pickerItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                pickerItems = []
                Task { await importPhotos(newItems) }
            }
            .sheet(isPresented: $isManagingDishes) {
                DishManagerSheet(
                    drafts: $dishDrafts,
                    existingDishes: existingRestaurantDishes,
                    photos: visibleVisitPhotos,
                    preparedPhotos: preparedPhotos
                )
            }
            .sheet(isPresented: $isChoosingCompanions) {
                CompanionPickerSheet(
                    selectedIDs: $draft.companionIDs,
                    selectedNames: $draft.companionNames
                )
            }
            .sheet(isPresented: $isChoosingRecommendationSource) {
                RecommendationSourcePickerSheet(
                    selectedID: $draft.recommendationSourceID,
                    selectedTypeRawValue: $draft.recommendationSourceTypeRawValue,
                    selectedUserID: $draft.recommendationSourceUserID,
                    selectedText: $draft.recommendationSourceText
                )
            }
            .onAppear { loadDishDraftsIfNeeded() }
            .onDisappear {
                guard !didCommitPhotos else { return }
                Task { await discardUncommittedPhotos() }
            }
        }
    }

    private var restaurantSection: some View {
        Section("餐厅") {
            Text(restaurant?.name ?? candidate?.name ?? "")
                .font(.headline)
            let address = restaurant?.address ?? candidate?.address ?? ""
            if !address.isEmpty {
                Text(address)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var basicsSection: some View {
        Section {
            DatePicker(
                "到访日期",
                selection: $draft.visitedAt,
                displayedComponents: [.date, .hourAndMinute]
            )
            .accessibilityIdentifier("visit-editor-date")

            Picker("用餐方式", selection: $draft.diningMode) {
                ForEach(DiningMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("visit-editor-dining-mode")

            LabeledContent("用餐人数") {
                TextField("未填写", text: $partySizeText)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numberPad)
                    .accessibilityLabel("用餐人数，可选")
                    .accessibilityIdentifier("visit-editor-party-size")
            }
        } header: {
            Text("基础")
        } footer: {
            Text("人数可留空；填写时必须是大于 0 的整数。日期与时间会按设备当前时区显示。")
        }
    }

    private var diningContextSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showsDiningContext) {
                VisitOptionalChoicePicker(
                    title: "排队 / 等位",
                    selection: $draft.queueDurationRawValue,
                    options: VisitQueueDuration.allCases.map {
                        VisitContextChoiceOption(value: $0.rawValue, title: $0.title)
                    },
                    accessibilityIdentifier: "visit-editor-queue-duration"
                )
                VisitMultiChoicePicker(
                    title: "适合场景",
                    selection: $draft.diningOccasionRawValues,
                    options: VisitDiningOccasion.allCases.map {
                        VisitContextChoiceOption(value: $0.rawValue, title: $0.title)
                    },
                    accessibilityIdentifier: "visit-editor-dining-occasions"
                )
                if draft.diningOccasionRawValues.contains(VisitDiningOccasion.other.rawValue) {
                    TextField("例如：工作简餐", text: $draft.diningOccasionText)
                        .accessibilityLabel("自定义用餐场景")
                        .accessibilityIdentifier("visit-editor-dining-occasion-text")
                }
            } label: {
                HStack {
                    Label("用餐场景与等位", systemImage: "clock.badge.questionmark")
                    Spacer()
                    Text(diningContextSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("visit-editor-dining-context")
        } header: {
            Text("用餐情况")
        } footer: {
            Text("全部可选。未记录排队与明确无需排队会作为两个不同状态保存。")
        }
    }

    private var peopleAndSourceSection: some View {
        Section {
            Button {
                isChoosingCompanions = true
            } label: {
                LabeledContent("和谁一起吃") {
                    Text(draft.companionNames.isEmpty
                         ? "未记录"
                         : draft.companionNames.joined(separator: "、"))
                        .foregroundStyle(draft.companionNames.isEmpty ? .secondary : .primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
            }
            .foregroundStyle(.primary)
            .accessibilityIdentifier("visit-editor-companions")

            Button {
                isChoosingRecommendationSource = true
            } label: {
                LabeledContent("推荐来源") {
                    Text(draft.recommendationSourceText.isEmpty ? "未记录" : draft.recommendationSourceText)
                        .foregroundStyle(draft.recommendationSourceText.isEmpty ? .secondary : .primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
            }
            .foregroundStyle(.primary)
            .accessibilityIdentifier("visit-editor-recommendation-source")
        } header: {
            Text("这顿饭")
        } footer: {
            Text("全部可选。名字只来自你的输入，不会读取通讯录；保存后下次可以直接复用。")
        }
    }

    private var diningContextSummary: String {
        let count = draft.diningOccasions.count
        if count > 0 { return "\(count) 个场景" }
        if let queue = draft.queueDuration { return queue.title }
        return "可选"
    }

    private var photosSection: some View {
        Section {
            if visibleVisitPhotos.isEmpty && preparedPhotos.isEmpty {
                Label("还没有照片", systemImage: "photo.on.rectangle.angled")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(visibleVisitPhotos) { photo in
                            visitPhotoTile(photo)
                        }
                        ForEach(preparedPhotos) { prepared in
                            preparedPhotoTile(prepared)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
                .frame(height: 116)
            }

            if remainingPhotoCount > 0 {
                PhotosPicker(
                    selection: $pickerItems,
                    maxSelectionCount: remainingPhotoCount,
                    selectionBehavior: .ordered,
                    matching: .images
                ) {
                    Label(
                        isImportingPhotos ? "正在处理照片…" : "从照片图库选择",
                        systemImage: "photo.badge.plus"
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(isImportingPhotos || isSaving)
                .accessibilityIdentifier("visit-photo-picker")
#if DEBUG
                if TasteMapUITestFixtures.usesPhotoFixture {
                    Button("添加测试照片", systemImage: "camera.fill") {
                        Task { await importUITestPhoto() }
                    }
                    .accessibilityIdentifier("visit-photo-ui-test-import")
                }
#endif
            } else {
                Text("每次到访最多保存 \(PhotoImportService.maximumSelectionCount) 张照片。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text("照片")
                Spacer()
                Text("\(visibleVisitPhotos.count + preparedPhotos.count)/\(PhotoImportService.maximumSelectionCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("照片会先保存在本机。保存到访不需要等待上传，离线时也可以继续。")
        }
    }

    private func visitPhotoTile(_ photo: PhotoAsset) -> some View {
        ZStack(alignment: .topTrailing) {
            PhotoAssetImageView(photo: photo)
                .frame(width: 104, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            Button {
                Task { await remove(photo) }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.65))
            }
            .padding(5)
            .accessibilityLabel("删除照片")
            VStack {
                Spacer()
                HStack {
                    PhotoUploadStatusBadge(photo: photo)
                    Spacer(minLength: 0)
                }
                .padding(5)
            }
        }
        .frame(width: 104, height: 104)
        .overlay(alignment: .bottomTrailing) {
            if photo.uploadState == .failed {
                Button("重试") {
                    do { try photoCoordinator?.retry(photo) }
                    catch { photoError = "照片重试没有启动成功。" }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .padding(4)
                .accessibilityIdentifier("visit-photo-retry-\(photo.id.uuidString)")
            }
        }
    }

    private func preparedPhotoTile(_ prepared: PreparedLocalPhoto) -> some View {
        PreparedPhotoImageView(prepared: prepared)
            .frame(width: 104, height: 104)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(alignment: .topTrailing) {
                Button {
                    preparedPhotos.removeAll { $0.id == prepared.id }
                    Task { await photoCoordinator?.discardPrepared(prepared) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.65))
                }
                .padding(5)
                .accessibilityLabel("删除待保存照片")
            }
            .overlay(alignment: .bottomLeading) {
                Text("本机")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.orange.opacity(0.9), in: Capsule())
                    .padding(5)
            }
    }

    private var ratingSection: some View {
        Section {
            HalfStarRatingPicker(
                rating: $draft.rating,
                accessibilityName: nil,
                accessibilityIdentifier: "visit-overall-rating"
            )
        } header: {
            Text("总体评分")
        } footer: {
            Text("总体感受独立保存，不会由详细评分自动计算。")
        }
    }

    private var detailedRatingSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showsDetailedRatings) {
                ForEach(RatingDimension.allCases) { dimension in
                    TasteMapRatingInput(
                        dimension: dimension,
                        rating: detailedRatingBinding(for: dimension)
                    )
                }
            } label: {
                HStack {
                    Label("详细评分", systemImage: "slider.horizontal.3")
                    Spacer()
                    Text("\(detailedRatingCount)/\(RatingDimension.allCases.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("visit-editor-experience-context")
            .accessibilityIdentifier("visit-detailed-ratings")
        } footer: {
            Text("性价比、环境和服务全部可选，可以只记录其中一项。")
        }
    }

    private var detailedRatingCount: Int {
        RatingDimension.allCases.filter { $0.value(in: draft) != nil }.count
    }

    private func detailedRatingBinding(for dimension: RatingDimension) -> Binding<Double?> {
        Binding(
            get: { dimension.value(in: draft) },
            set: { dimension.setValue($0, in: &draft) }
        )
    }

    private var dishesSection: some View {
        Section {
            if dishDrafts.isEmpty {
                Label("还没有记录菜品", systemImage: "fork.knife.circle")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(dishDrafts) { dish in
                    HStack(alignment: .firstTextBaseline) {
                        Text(dish.name)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Text(dish.rating.map { String(format: "%.1f ★", $0) } ?? "未评分")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Button(dishDrafts.isEmpty ? "添加菜品" : "管理本次菜品", systemImage: "plus.circle.fill") {
                isManagingDishes = true
            }
            .accessibilityIdentifier("visit-dish-manager")
        } header: {
            HStack {
                Text("本次吃了什么")
                Spacer()
                if !dishDrafts.isEmpty {
                    Text("\(dishDrafts.count) 道")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text("可以选择这家店以前吃过的菜；菜品价格不会改变本次实际消费。")
        }
    }

    private var spendSection: some View {
        Section {
            VisitOptionalChoicePicker(
                title: "消费方式",
                selection: $draft.paymentModeRawValue,
                options: VisitPaymentMode.allCases.map {
                    VisitContextChoiceOption(value: $0.rawValue, title: $0.title)
                },
                accessibilityIdentifier: "visit-editor-payment-mode"
            )
            if draft.paymentModeRawValue != nil {
                Button("清空消费方式") {
                    draft.paymentModeRawValue = nil
                }
                .accessibilityIdentifier("visit-editor-payment-clear")
            }
            LabeledContent("整桌账单") {
                TextField("未填写", text: $totalPriceText)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .accessibilityLabel("整桌账单，可选")
                    .accessibilityIdentifier("visit-editor-total-price")
            }
            TextField("例如 128.50", text: $spendText)
                .keyboardType(.decimalPad)
                .accessibilityLabel("我的实际消费，可选")
                .accessibilityIdentifier("visit-editor-spend")
            if let pricePerPerson = displayedPricePerPerson {
                LabeledContent("人均参考") {
                    Text("¥\(NSDecimalNumber(decimal: pricePerPerson).stringValue)")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("消费")
        } footer: {
            Text("整桌账单、本人实际消费与菜品价格彼此独立；留空表示未记录，不会按 0 元保存。")
        }
    }

    private var displayedPricePerPerson: Decimal? {
        var preview = draft
        do {
            preview.partySize = try VisitDraft.partySize(from: partySizeText)
            preview.totalPrice = try VisitDraft.totalPrice(from: totalPriceText)
            return preview.calculatedPricePerPerson
        } catch {
            return nil
        }
    }

    private var experienceContextSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showsExperienceContext) {
                VisitOptionalChoicePicker(
                    title: "嘈杂程度",
                    selection: $draft.noiseLevelRawValue,
                    options: VisitNoiseLevel.allCases.map {
                        VisitContextChoiceOption(value: $0.rawValue, title: $0.title)
                    },
                    accessibilityIdentifier: "visit-editor-noise-level"
                )
                VisitOptionalChoicePicker(
                    title: "上餐时长",
                    selection: $draft.diningDurationRawValue,
                    options: VisitDiningDuration.allCases.map {
                        VisitContextChoiceOption(value: $0.rawValue, title: $0.title)
                    },
                    accessibilityIdentifier: "visit-editor-serving-duration"
                )
                VisitOptionalChoicePicker(
                    title: "菜量",
                    selection: $draft.portionLevelRawValue,
                    options: VisitPortionLevel.allCases.map {
                        VisitContextChoiceOption(value: $0.rawValue, title: $0.title)
                    },
                    accessibilityIdentifier: "visit-editor-portion-level"
                )
                VisitOptionalChoicePicker(
                    title: "交通便利度",
                    selection: $draft.transportConvenienceRawValue,
                    options: VisitTransportConvenience.allCases.map {
                        VisitContextChoiceOption(value: $0.rawValue, title: $0.title)
                    },
                    accessibilityIdentifier: "visit-editor-transport-convenience"
                )
                VisitTagPicker(
                    title: "性价比标签",
                    selection: $draft.valueTags,
                    presets: VisitContextOptions.valueTags,
                    accessibilityIdentifier: "visit-editor-value-tags"
                )
                VisitTagPicker(
                    title: "环境标签",
                    selection: $draft.environmentTags,
                    presets: VisitContextOptions.environmentTags,
                    accessibilityIdentifier: "visit-editor-environment-tags"
                )
                VisitTagPicker(
                    title: "服务标签",
                    selection: $draft.serviceTags,
                    presets: VisitContextOptions.serviceTags,
                    accessibilityIdentifier: "visit-editor-service-tags"
                )
                TextField(
                    "最低消费、现场取号、用餐限时或特殊营业规则……",
                    text: $draft.specialNotes,
                    axis: .vertical
                )
                .lineLimit(2...5)
                .accessibilityLabel("特殊注意事项")
                .accessibilityIdentifier("visit-editor-special-notes")
            } label: {
                HStack {
                    Label("更多体验记录", systemImage: "tag.fill")
                    Spacer()
                    Text(draft.hasExperienceContext ? "已记录" : "可选")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("体验补充")
        } footer: {
            Text("这些信息只在你主动记录时保存，后续可用于口味分析。")
        }
    }

    private var noteSection: some View {
        Section("记录") {
            TextEditor(text: $draft.note)
                .frame(minHeight: 120)
                .accessibilityLabel("到访备注，可选")
                .accessibilityIdentifier("visit-editor-note")
        }
    }

    private var privacySection: some View {
        Section {
            Picker("可见性", selection: $draft.visibility) {
                ForEach(VisitVisibility.allCases) { visibility in
                    Label(visibility.title, systemImage: visibility.systemImage).tag(visibility)
                }
            }
            .accessibilityIdentifier("visit-editor-visibility")
            LabeledContent("当前范围") {
                Text(draft.visibility.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        } header: {
            Text("隐私")
        } footer: {
            Text("同步 API 始终按登录用户隔离；仅自己记录不会通过公开或好友接口展示。")
        }
    }

    private var deleteSection: some View {
        Section {
            Button("删除这次到访", systemImage: "trash", role: .destructive) {
                isConfirmingDeletion = true
            }
            .disabled(isSaving)
            .accessibilityIdentifier("visit-editor-delete")
        } footer: {
            Text("不会删除餐厅，也不会影响其他到访记录。")
        }
    }

    private func save() {
        Task { await saveAsync() }
    }

    private func saveAsync() async {
        isSaving = true
        defer { isSaving = false }

        do {
            var validatedDraft = draft
            validatedDraft.partySize = try VisitDraft.partySize(from: partySizeText)
            validatedDraft.myActualSpend = try VisitDraft.spend(from: spendText)
            validatedDraft.totalPrice = try VisitDraft.totalPrice(from: totalPriceText)
            validatedDraft = try validatedDraft.validated()

            let store = LocalTasteMapStore(context: modelContext)
            let restaurantID: UUID
            let savedVisit: Visit
            if let visit, let restaurant {
                try store.update(visit, draft: validatedDraft)
                restaurantID = restaurant.id
                savedVisit = visit
            } else {
                let resolvedRestaurant: Restaurant
                if let restaurant {
                    resolvedRestaurant = restaurant
                } else if let candidate {
                    resolvedRestaurant = try store.restaurant(for: candidate, among: allRestaurants)
                } else {
                    throw VisitEditorError.missingRestaurant
                }
                savedVisit = try store.createVisit(
                    restaurantId: resolvedRestaurant.id,
                    draft: validatedDraft
                )
                restaurantID = resolvedRestaurant.id
            }

            if let photoCoordinator {
                let dishMap = try LocalDishStore(context: modelContext).reconcile(
                    restaurantID: restaurantID,
                    visitID: savedVisit.id,
                    drafts: dishDrafts
                )
                var savedPhotos = visibleVisitPhotos
                for (offset, prepared) in preparedPhotos.enumerated() {
                    let photo = try photoCoordinator.attachPreparedPhoto(
                        prepared,
                        restaurantID: restaurantID,
                        visitID: savedVisit.id,
                        sortOrder: visibleVisitPhotos.count + offset,
                        queueForUpload: true
                    )
                    savedPhotos.append(photo)
                }
                for photo in savedPhotos where photo.visitId == savedVisit.id {
                    let selectedDraft = dishDrafts.first { $0.photoID == photo.id }
                    try photoCoordinator.setDishRelationship(
                        photo,
                        dish: selectedDraft.flatMap { dishMap[$0.id] }
                    )
                    if photo.draftSessionID == photoDraftSessionID {
                        try photoCoordinator.enqueue(photo)
                    }
                }
            } else {
                _ = try LocalDishStore(context: modelContext).reconcile(
                    restaurantID: restaurantID,
                    visitID: savedVisit.id,
                    drafts: dishDrafts
                )
            }

            didCommitPhotos = true
            onSaved?(restaurantID)
            dismiss()
        } catch let error as LocalizedError {
            saveError = error.errorDescription ?? "本地记录没有保存成功，请重试。"
        } catch {
            saveError = "本地记录没有保存成功，请重试。"
        }
    }

    private var visibleVisitPhotos: [PhotoAsset] {
        guard let visitID = visit?.id else { return [] }
        return allPhotos
            .filter { $0.visitId == visitID && $0.deletedAt == nil && ($0.kind == .visit || $0.kind == .dish) }
            .sorted { left, right in
                left.sortOrder == right.sortOrder
                    ? left.createdAt < right.createdAt
                    : left.sortOrder < right.sortOrder
            }
    }

    private var remainingPhotoCount: Int {
        max(0, PhotoImportService.maximumSelectionCount - visibleVisitPhotos.count - preparedPhotos.count)
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        guard let photoCoordinator else {
            photoError = "照片服务尚未准备好，请重新打开页面再试。"
            return
        }
        isImportingPhotos = true
        defer { isImportingPhotos = false }
        for item in items.prefix(remainingPhotoCount) {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw PhotoImportError.invalidImage
                }
                let contentType = item.supportedContentTypes.first?.preferredMIMEType
                let prepared = try await photoCoordinator.preparePhoto(
                    data: data,
                    suggestedContentType: contentType
                )
                do {
                    if let visit, let restaurant {
                        _ = try photoCoordinator.attachPreparedPhoto(
                            prepared,
                            restaurantID: restaurant.id,
                            visitID: visit.id,
                            sortOrder: visibleVisitPhotos.count,
                            queueForUpload: false,
                            draftSessionID: photoDraftSessionID
                        )
                    } else {
                        preparedPhotos.append(prepared)
                    }
                } catch {
                    await photoCoordinator.discardPrepared(prepared)
                    throw error
                }
            } catch let error as LocalizedError {
                photoError = error.errorDescription ?? "这张图片没有添加成功。"
            } catch {
                photoError = "这张图片没有添加成功。"
            }
        }
    }

#if DEBUG
    private func importUITestPhoto() async {
        guard remainingPhotoCount > 0, let photoCoordinator else { return }
        do {
            let prepared = try await photoCoordinator.preparePhoto(
                data: TasteMapUITestFixtures.samplePhotoData(),
                suggestedContentType: "image/jpeg",
                originalFileName: "ui-test.jpg"
            )
            do {
                if let visit, let restaurant {
                    _ = try photoCoordinator.attachPreparedPhoto(
                        prepared,
                        restaurantID: restaurant.id,
                        visitID: visit.id,
                        sortOrder: visibleVisitPhotos.count,
                        queueForUpload: false,
                        draftSessionID: photoDraftSessionID
                    )
                } else {
                    preparedPhotos.append(prepared)
                }
            } catch {
                await photoCoordinator.discardPrepared(prepared)
                throw error
            }
        } catch {
            photoError = "测试照片没有添加成功。"
        }
    }
#endif

    private func remove(_ photo: PhotoAsset) async {
        guard let photoCoordinator else { return }
        do {
            if photo.draftSessionID == photoDraftSessionID && photo.serverVersion == 0 {
                try await photoCoordinator.discardLocalPhoto(photo)
            } else {
                try await photoCoordinator.delete(photo)
            }
        } catch {
            photoError = "照片没有删除成功，请重试。"
        }
    }

    private func discardUncommittedPhotos() async {
        guard let photoCoordinator else { return }
        for prepared in preparedPhotos { await photoCoordinator.discardPrepared(prepared) }
        for photo in visibleVisitPhotos where photo.draftSessionID == photoDraftSessionID {
            try? await photoCoordinator.discardLocalPhoto(photo)
        }
    }

    private func deleteVisit() {
        guard let visit else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try LocalTasteMapStore(context: modelContext).delete(visit)
            dismiss()
        } catch {
            saveError = "这条到访记录没有删除成功，请重试。"
        }
    }

    private var existingRestaurantDishes: [Dish] {
        let restaurantID = restaurant?.id
        var seen = Set<String>()
        return allDishes
            .filter { $0.restaurantId == restaurantID && $0.deletedAt == nil }
            .sorted { $0.createdAt == $1.createdAt ? ($0.remoteID ?? "") < ($1.remoteID ?? "") : $0.createdAt < $1.createdAt }
            .filter { seen.insert(DishIdentity.normalizedName($0.name)).inserted }
    }

    private func loadDishDraftsIfNeeded() {
        guard !didLoadDishes else { return }
        didLoadDishes = true
        guard let visit else { return }
        try? LocalDishStore(context: modelContext).bootstrapLegacyAssociations()
        let associations = ((try? modelContext.fetch(FetchDescriptor<VisitDish>())) ?? [])
            .filter { $0.visitId == visit.id && $0.deletedAt == nil }
            .sorted { $0.sortOrder < $1.sortOrder }
        dishDrafts = associations.compactMap { association in
            guard let dish = allDishes.first(where: { $0.id == association.dishId && $0.deletedAt == nil }) else { return nil }
            let photoID = allPhotos.first(where: {
                $0.visitId == visit.id && $0.dishId == dish.id && $0.deletedAt == nil
            })?.id
            return DishDraft(dish: dish, photoID: photoID)
        }
    }

    private static func integerString(_ value: Int?) -> String {
        value.map(String.init) ?? ""
    }

    private static func spendString(_ spend: Decimal?) -> String {
        spend.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
    }
}

private enum VisitEditorError: Error {
    case missingRestaurant
}
