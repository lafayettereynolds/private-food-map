import SwiftData
import SwiftUI
import PhotosUI

struct VisitEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.photoTransferCoordinator) private var photoCoordinator
    @Environment(PremiumEntitlementService.self) private var premiumEntitlementService
    @Environment(NativeAuthServices.self) private var authServices
    @Environment(\.localAccountScope) private var accountScope
    @Query private var allRestaurants: [Restaurant]
    @Query private var allPhotos: [PhotoAsset]
    @Query private var allDishes: [Dish]
    @Query private var allVisitDishes: [VisitDish]
    @Query private var allVisits: [Visit]
    @Query private var profiles: [UserProfile]
    @Query private var companions: [DiningCompanion]

    private let restaurant: Restaurant?
    private let candidate: RestaurantCandidate?
    private let visit: Visit?
    private let onSaved: ((UUID) -> Void)?
    private let onVisitSaved: ((Visit) -> Void)?
    private let onRestaurantDeleted: ((UUID) -> Void)?

    @State private var draft: VisitDraft
    @State private var partySizeText: String
    private let initialPaymentDraft: VisitDraft
    @State private var totalPriceText: String
    @State private var submissionGate = VisitSubmissionGate()
    @State private var didSaveCore = false
    @State private var savedPhotoWarning: String?
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
    @State private var isChoosingCompanions = false
    @State private var isChoosingRecommendationSource = false
    @State private var invitedUserIDs: Set<String> = []

    private var owned: ProfileOwnedContentScope.Snapshot {
        ProfileOwnedContentScope.capture(
            currentUserID: currentUserID,
            restaurants: allRestaurants,
            visits: allVisits,
            photos: allPhotos,
            dishes: allDishes,
            visitDishes: allVisitDishes,
            companions: companions
        )
    }

    @MainActor
    init(
        restaurant: Restaurant,
        visit: Visit? = nil,
        initialDraft: VisitDraft? = nil,
        onSaved: ((UUID) -> Void)? = nil,
        onVisitSaved: ((Visit) -> Void)? = nil,
        onRestaurantDeleted: ((UUID) -> Void)? = nil
    ) {
        self.restaurant = restaurant
        candidate = nil
        self.visit = visit
        self.onSaved = onSaved
        self.onVisitSaved = onVisitSaved
        self.onRestaurantDeleted = onRestaurantDeleted
        var initialDraft = visit.map(VisitDraft.init) ?? initialDraft ?? VisitDraft()
        if visit == nil && initialDraft.partySize == nil { initialDraft.partySize = 1 }
        _draft = State(initialValue: initialDraft)
        _partySizeText = State(initialValue: Self.integerString(initialDraft.partySize))
        self.initialPaymentDraft = initialDraft
        _totalPriceText = State(initialValue: Self.spendString(VisitSpendPolicy.inputAmount(actual: initialDraft.myActualSpend, total: initialDraft.totalPrice, mode: initialDraft.paymentModeRawValue, partySize: initialDraft.partySize)))
    }

    @MainActor
    init(
        candidate: RestaurantCandidate,
        initialDraft: VisitDraft? = nil,
        onSaved: ((UUID) -> Void)? = nil,
        onVisitSaved: ((Visit) -> Void)? = nil
    ) {
        restaurant = nil
        self.candidate = candidate
        visit = nil
        self.onSaved = onSaved
        self.onVisitSaved = onVisitSaved
        self.onRestaurantDeleted = nil
        var initialDraft = initialDraft ?? VisitDraft()
        if initialDraft.partySize == nil { initialDraft.partySize = 1 }
        _draft = State(initialValue: initialDraft)
        _partySizeText = State(initialValue: Self.integerString(initialDraft.partySize))
        self.initialPaymentDraft = initialDraft
        _totalPriceText = State(initialValue: Self.spendString(VisitSpendPolicy.inputAmount(actual: initialDraft.myActualSpend, total: initialDraft.totalPrice, mode: initialDraft.paymentModeRawValue, partySize: initialDraft.partySize)))
    }

    var body: some View {
        NavigationStack {
            Form {
                restaurantSection
                noteSection
                ratingSection
                basicsSection
                peopleAndSourceSection
                diningContextSection
                spendSection
                photosSection
                dishesSection
                detailedRatingSection
                experienceContextSection
                privacySection
                if visit != nil { deleteSection }
            }
            .scrollContentBackground(.hidden)
            .background(TasteMapCoreTheme.page)
            .tint(TasteMapCoreTheme.brand)
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
                        .disabled(isSaving || isImportingPhotos || didSaveCore)
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
                Text(RestaurantDeletionPresentation.visitMessage(isLast: isDeletingLastVisit))
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
            .alert("到访已保存", isPresented: Binding(
                get: { savedPhotoWarning != nil },
                set: { if !$0 { savedPhotoWarning = nil } }
            )) {
                Button("完成") { dismiss() }
            } message: {
                Text(savedPhotoWarning ?? "部分照片没有附加成功，其余到访资料已安全保存在本机。")
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
                    usageByDishID: dishUsageByID,
                    photos: visibleVisitPhotos,
                    preparedPhotos: preparedPhotos
                )
            }
            .sheet(isPresented: $isChoosingCompanions) {
                CompanionPickerSheet(
                    selectedIDs: $draft.companionIDs,
                    selectedNames: $draft.companionNames,
                    ownerUserID: currentUserID ?? "local",
                    socialAPI: authServices.socialAPI,
                    collaborationAPI: authServices.socialCollaborationAPI
                )
            }
            .sheet(isPresented: $isChoosingRecommendationSource) {
                RecommendationSourcePickerSheet(
                    selectedID: $draft.recommendationSourceID,
                    selectedTypeRawValue: $draft.recommendationSourceTypeRawValue,
                    selectedUserID: $draft.recommendationSourceUserID,
                    selectedText: $draft.recommendationSourceText,
                    ownerUserID: currentUserID ?? "local"
                )
            }
            .onAppear { loadDishDraftsIfNeeded() }
            .onDisappear {
                guard !didCommitPhotos else { return }
                Task { await discardUncommittedPhotos() }
            }
        }
    }

    private var isSaving: Bool { submissionGate.isSubmitting }

    private var restaurantSection: some View {
        Section("餐厅") {
            HStack(spacing: TasteMapDesignTokens.Spacing.regular) {
                TasteMapRestaurantImage(
                    resolution: restaurantImageResolution,
                    photosByID: restaurantImagePhotosByID,
                    semanticID: restaurant?.id.uuidString ?? candidate?.id.uuidString ?? "visit-editor",
                    fallbackKind: restaurantFallbackKind,
                    fallbackIconSize: TasteMapDesignTokens.Icon.sectionContainer,
                    accessibilityLabel: "到访餐厅图片"
                )
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: TasteMapDesignTokens.Radius.compact, style: .continuous))

                VStack(alignment: .leading, spacing: TasteMapDesignTokens.Spacing.xSmall) {
                    Text(restaurant?.name ?? candidate?.name ?? "")
                        .font(.headline)
                    let context = restaurantContextLine
                    if !context.isEmpty {
                        Text(context)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    if let count = restaurantVisitCount, count > 0 {
                        Text("第 \(count + (visit == nil ? 1 : 0)) 次到访")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(TasteMapCoreTheme.brandDeep)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var restaurantContextLine: String {
        let values = [restaurant?.city ?? candidate?.city, restaurant?.address ?? candidate?.address]
            .compactMap { value -> String? in
                guard let value else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        return values.joined(separator: " · ")
    }

    private var restaurantVisitCount: Int? {
        guard let restaurantID = restaurant?.id else { return nil }
        return owned.visits.filter { $0.restaurantId == restaurantID && $0.deletedAt == nil }.count
    }

    private var restaurantImageResolution: RestaurantImageResolution {
        if let restaurant {
            let metadata = RestaurantDetailMetadata(restaurant: restaurant)
            let photo = RestaurantImagePhotoSelectionPolicy.preferredPhoto(
                restaurantID: restaurant.id,
                photos: owned.photos,
                referencedPhotoID: metadata.markerPhotoID
            )
            return RestaurantImagePriorityPolicy.resolution(
                localUserPhotoID: photo?.id,
                publicOrCachedPhotoID: metadata.markerPhotoID,
                providerMerchantImageURL: metadata.merchantImageURL
            )
        }
        return RestaurantImagePriorityPolicy.resolution(
            localUserPhotoID: nil,
            providerMerchantImageURL: candidate?.photoURL
        )
    }

    private var restaurantImagePhotosByID: [UUID: PhotoAsset] {
        Dictionary(uniqueKeysWithValues: owned.photos.map { ($0.id, $0) })
    }

    private var restaurantFallbackKind: FoodDiningVisualKind {
        guard let restaurant else { return .genericDining }
        return FoodDiningVisualLibrary.kind(
            legacySymbol: RestaurantDetailMetadata(restaurant: restaurant).markerEmoji
        )
    }

    private var basicsSection: some View {
        Section {
            DatePicker(
                "到访日期",
                selection: $draft.visitedAt,
                displayedComponents: [.date, .hourAndMinute]
            )
            .accessibilityIdentifier("visit-editor-date")

            TasteMapSegmentedControl(
                selection: $draft.diningMode,
                items: DiningMode.allCases.map {
                    .init($0, title: $0.title, systemImage: $0.systemImage)
                },
                accessibilityIdentifier: "visit-editor-dining-mode"
            )

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
        } header: {
            Text("用餐情况")
                .accessibilityIdentifier("visit-editor-dining-context")
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

            ForEach(linkedSelectedCompanions) { companion in
                if let userID = companion.linkedTasteMapUserId {
                    Toggle(
                        "邀请 \(companion.displayName) 一起记录",
                        isOn: Binding(
                            get: { invitedUserIDs.contains(userID) },
                            set: { enabled in
                                if enabled { invitedUserIDs.insert(userID) }
                                else { invitedUserIDs.remove(userID) }
                            }
                        )
                    )
                    .accessibilityIdentifier("visit-shared-meal-invite-\(companion.id.uuidString)")
                }
            }

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
                VStack(alignment: .leading, spacing: 8) {
                    Text("本次到访已达当前 \(photoLimit) 张照片上限；已有照片会继续保留。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if premiumEntitlementService.access(for: .expandedVisitPhotos) == .denied {
                        Button {
                            premiumEntitlementService.openPaywall(from: .feature(.expandedVisitPhotos))
                        } label: {
                            Label("Premium 可添加到 20 张", systemImage: "photo.stack")
                        }
                        .accessibilityIdentifier("visit-photo-premium-entry")
                    }
                }
            }
        } header: {
            HStack {
                Text("照片")
                Spacer()
                Text("\(visibleVisitPhotos.count + preparedPhotos.count)/\(photoLimit)")
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
            ForEach(RatingDimension.allCases) { dimension in
                TasteMapRatingInput(
                    dimension: dimension,
                    rating: detailedRatingBinding(for: dimension)
                )
            }
        } header: {
            Text("详细评分")
                .accessibilityIdentifier("visit-detailed-ratings")
        } footer: {
            Text("性价比、环境和服务全部可选，可以只记录其中一项。")
        }
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
                accessibilityIdentifier: "visit-editor-payment-mode",
                emptyTitle: "单人消费"
            )
            if draft.paymentModeRawValue != nil {
                Button("清空消费方式") {
                    draft.paymentModeRawValue = nil
                }
                .accessibilityIdentifier("visit-editor-payment-clear")
            }
            LabeledContent("消费金额（元）") {
                TextField("未填写", text: $totalPriceText)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .accessibilityLabel("消费金额（元），可选")
                    .accessibilityIdentifier("visit-editor-spend")
            }
        } header: {
            Text("消费")
        }
    }

    private func paymentDraft() throws -> VisitDraft {
        var result = draft
        result.partySize = try VisitDraft.partySize(from: partySizeText)
        let amount = try VisitDraft.totalPrice(from: totalPriceText)
        let initial = initialPaymentDraft
        if amount == VisitSpendPolicy.inputAmount(actual: initial.myActualSpend, total: initial.totalPrice, mode: initial.paymentModeRawValue, partySize: initial.partySize)
            && result.partySize == initial.partySize && result.paymentModeRawValue == initial.paymentModeRawValue {
            result.totalPrice = initial.totalPrice
            result.myActualSpend = initial.myActualSpend ?? VisitSpendPolicy.resolve(actual: nil, amount: initial.totalPrice, mode: initial.paymentModeRawValue, partySize: initial.partySize)
        } else {
            let payment = VisitSpendPolicy.calculate(amount: amount, mode: result.paymentModeRawValue, partySize: result.partySize)
            result.totalPrice = payment.total
            result.myActualSpend = payment.actual
        }
        return result
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
            LabeledContent("可见范围", value: profiles.first(where: { $0.tasteMapUserID == currentUserID && $0.deletedAt == nil })?.visibility.title ?? "仅自己")
            Text("跟随设置中的主页可见范围，到访和附带照片同步。")
                .font(.caption).foregroundStyle(.secondary)

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
            Text(RestaurantDeletionPresentation.visitMessage(isLast: isDeletingLastVisit))
        }
    }

    private func save() {
        guard !didSaveCore, submissionGate.begin() else { return }
        Task { await saveAsync() }
    }

    private func saveAsync() async {
        defer { submissionGate.finish() }

        let draftPhotoCount = visibleVisitPhotos.filter { $0.draftSessionID == photoDraftSessionID }.count
        if premiumEntitlementService.access(for: .expandedVisitPhotos) != .allowed {
            let retainedDishPhotoIDs = Set(owned.photos.filter { $0.visitId == visit?.id && $0.dishId != nil && $0.deletedAt == nil }.map(\.id))
            if dishDrafts.contains(where: { $0.photoID.map { !retainedDishPhotoIDs.contains($0) } ?? false }) {
                photoError = "菜品照片仅限 Premium；已有照片会继续保留。"
                return
            }
        }
        guard PremiumFeatureAccessPolicy.permitsVisitPhotoAddition(
            existingCount: visibleVisitPhotos.count - draftPhotoCount,
            newCount: draftPhotoCount + preparedPhotos.count,
            membershipStatus: premiumEntitlementService.membershipStatus
        ) else {
            photoError = "每次到访最多可添加 \(photoLimit) 张照片；已有照片会继续保留。"
            return
        }

        do {
            var validatedDraft = draft
            validatedDraft = try paymentDraft()
            validatedDraft = try validatedDraft.validated()

            let result = try LocalVisitRecordingStore(context: modelContext).commit(
                restaurant: restaurant,
                candidate: candidate,
                existingVisit: visit,
                allRestaurants: owned.restaurants,
                draft: validatedDraft,
                dishDrafts: dishDrafts,
                actorUserID: currentUserID
            )
            didSaveCore = true
            let restaurantID = result.restaurant.id
            let savedVisit = result.visit

            if !invitedUserIDs.isEmpty, let ownerUserID = currentUserID,
               let sourceVisitID = savedVisit.remoteID {
                do {
                    try authServices.socialCollaborationOutbox.enqueue(
                        ownerUserID: ownerUserID,
                        sourceVisitID: sourceVisitID,
                        participantUserIDs: Array(invitedUserIDs)
                    )
                } catch {
                    savedPhotoWarning = "到访已保存，但聚餐邀请尚未进入重试队列。你可以稍后重新编辑这次到访。"
                }
            }

            if let photoCoordinator {
                do {
                    var savedPhotos = visibleVisitPhotos
                    for (offset, prepared) in preparedPhotos.enumerated() {
                        let photo = try photoCoordinator.attachPreparedPhoto(
                            prepared,
                            restaurantID: restaurantID,
                            visitID: savedVisit.id,
                            sortOrder: visibleVisitPhotos.count + offset,
                            visibility: PhotoVisibility(rawValue: profiles.first(where: { $0.tasteMapUserID == currentUserID && $0.deletedAt == nil })?.visibility.rawValue ?? "private") ?? .private,
                            queueForUpload: true
                        )
                        savedPhotos.append(photo)
                    }
                    for photo in savedPhotos where photo.visitId == savedVisit.id {
                        photo.visibility = PhotoVisibility(rawValue: profiles.first(where: { $0.tasteMapUserID == currentUserID && $0.deletedAt == nil })?.visibility.rawValue ?? "private") ?? .private
                        photo.updatedAt = .now
                        let selectedDraft = dishDrafts.first { $0.photoID == photo.id }
                        try photoCoordinator.setDishRelationship(
                            photo,
                            dish: selectedDraft.flatMap { result.dishesByDraftID[$0.id] }
                        )
                        if photo.draftSessionID == photoDraftSessionID {
                            try photoCoordinator.enqueue(photo)
                        }
                    }
                } catch {
                    onSaved?(restaurantID)
                    onVisitSaved?(savedVisit)
                    savedPhotoWarning = "部分照片没有附加成功，其余到访、菜品和用餐资料已安全保存在本机。"
                    return
                }
            }

            didCommitPhotos = true
            onSaved?(restaurantID)
            onVisitSaved?(savedVisit)
            dismiss()
        } catch let error as LocalizedError {
            saveError = error.errorDescription ?? "本地记录没有保存成功，请重试。"
        } catch {
            saveError = "本地记录没有保存成功，请重试。"
        }
    }

    private var visibleVisitPhotos: [PhotoAsset] {
        guard let visitID = visit?.id else { return [] }
        return owned.photos
            .filter { $0.visitId == visitID && $0.deletedAt == nil && ($0.kind == .visit || $0.kind == .dish) }
            .sorted { left, right in
                left.sortOrder == right.sortOrder
                    ? left.createdAt < right.createdAt
                    : left.sortOrder < right.sortOrder
            }
    }

    private var remainingPhotoCount: Int {
        max(0, photoLimit - visibleVisitPhotos.count - preparedPhotos.count)
    }

    private var photoLimit: Int {
        min(PhotoImportService.maximumSelectionCount, premiumEntitlementService.visitPhotoLimit)
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
                            visibility: PhotoVisibility(rawValue: profiles.first(where: { $0.tasteMapUserID == currentUserID && $0.deletedAt == nil })?.visibility.rawValue ?? "private") ?? .private,
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
                        visibility: PhotoVisibility(rawValue: profiles.first(where: { $0.tasteMapUserID == currentUserID && $0.deletedAt == nil })?.visibility.rawValue ?? "private") ?? .private,
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
        guard let visit, submissionGate.begin() else { return }
        defer { submissionGate.finish() }
        do {
            let deletedRestaurantID = try LocalTasteMapStore(context: modelContext).delete(
                visit,
                actorUserID: currentUserID
            )
            dismiss()
            if let deletedRestaurantID { onRestaurantDeleted?(deletedRestaurantID) }
        } catch {
            saveError = "这条到访记录没有删除成功，请重试。"
        }
    }

    private var isDeletingLastVisit: Bool {
        guard let visit else { return false }
        return !owned.visits.contains { $0.restaurantId == visit.restaurantId && $0.deletedAt == nil && $0.id != visit.id }
    }

    private var existingRestaurantDishes: [Dish] {
        guard let restaurantID = restaurant?.id else { return [] }
        return DishReuseResolver.orderedUniqueDishes(
            restaurantID: restaurantID,
            dishes: owned.dishes,
            usageByDishID: dishUsageByID
        )
    }

    private var dishUsageByID: [UUID: DishReuseUsage] {
        guard let restaurantID = restaurant?.id else { return [:] }
        return DishReuseResolver.usage(
            restaurantID: restaurantID,
            dishes: owned.dishes,
            associations: owned.visitDishes,
            visits: owned.visits
        )
    }

    private func loadDishDraftsIfNeeded() {
        guard !didLoadDishes else { return }
        didLoadDishes = true
        guard let visit else { return }
        try? LocalDishStore(context: modelContext).bootstrapLegacyAssociations()
        let associations = owned.visitDishes
            .filter { $0.visitId == visit.id && $0.deletedAt == nil }
            .sorted { $0.sortOrder < $1.sortOrder }
        dishDrafts = associations.compactMap { association in
            guard let dish = owned.dishes.first(where: { $0.id == association.dishId && $0.deletedAt == nil }) else { return nil }
            let photoID = owned.photos.first(where: {
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

    private var currentUserID: String? {
        accountScope.ownerUserID
    }

    private var linkedSelectedCompanions: [DiningCompanion] {
        owned.companions.filter { companion in
            companion.deletedAt == nil && companion.ownerUserId == currentUserID &&
                companion.remoteID.map(draft.companionIDs.contains) == true &&
                companion.linkedTasteMapUserId != nil
        }
    }
}
