import SwiftData
import SwiftUI
import UIKit

enum RestaurantDetailEntrySource: String, CaseIterable, Sendable {
    case map
    case list
    case search
    case nearby
    case discovery
    case community
    case publicProfile
    case restaurantList
    case analysis
    case roulette
    case onThisDay
    case share
    case unknown
}

struct RestaurantDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.photoTransferCoordinator) private var photoCoordinator
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.localAccountScope) private var accountScope
    @Query private var allVisits: [Visit]
    @Query private var allPhotos: [PhotoAsset]
    @Query private var allDishes: [Dish]
    @Query private var allVisitDishes: [VisitDish]
    @Query private var allCompanions: [DiningCompanion]
    @Query private var allRecommendationSources: [RecommendationSource]
    @Query private var profiles: [UserProfile]
    @Query private var discoveryPlacements: [CachedDiscoveryPlacement]

    let restaurant: Restaurant
    let entrySource: RestaurantDetailEntrySource
    private let navigator: any RestaurantNavigating

    @State private var isAddingVisit = false
    @State private var isEditingRestaurant = false
    @State private var editingVisit: Visit?
    @State private var visitPendingDeletion: Visit?
    @State private var deleteError: String?
    @State private var navigationError: String?
    @State private var phoneError: String?
    @State private var selectedPhoto: PhotoAsset?
    @State private var isAddingToList = false
    @State private var isShowingRoulette = false
    @State private var isConfirmingRestaurantDeletion = false
    @State private var actionError: String?

    @MainActor
    init(
        restaurant: Restaurant,
        entrySource: RestaurantDetailEntrySource = .unknown
    ) {
        self.restaurant = restaurant
        self.entrySource = entrySource
        navigator = AppleMapsRestaurantNavigator()
    }

    @MainActor
    init(
        restaurant: Restaurant,
        entrySource: RestaurantDetailEntrySource = .unknown,
        navigator: any RestaurantNavigating
    ) {
        self.restaurant = restaurant
        self.entrySource = entrySource
        self.navigator = navigator
    }

    private var presentation: RestaurantDetailPresentation {
        RestaurantDetailPresentation(restaurantID: restaurant.id, visits: owned.visits)
    }

    private var owned: ProfileOwnedContentScope.Snapshot {
        ProfileOwnedContentScope.capture(
            currentUserID: currentUserID,
            restaurants: [restaurant],
            visits: allVisits,
            photos: allPhotos,
            dishes: allDishes,
            visitDishes: allVisitDishes,
            companions: allCompanions,
            recommendationSources: allRecommendationSources
        )
    }

    private var metadata: RestaurantDetailMetadata {
        RestaurantDetailMetadata(restaurant: restaurant)
    }

    private var categoryVisualID: FoodCategoryVisualID {
        let tags = restaurant.remoteRecordData.flatMap {
            try? JSONDecoder().decode(RestaurantJSONContractV1.self, from: $0)
        }?.tags ?? []
        return FoodCategoryVisualResolver.resolve(name: restaurant.name, tags: tags)
    }

    private var ratingReferences: [RestaurantRatingReference] {
        var values = RestaurantRatingReferenceResolver.resolve(
            metadata: metadata,
            currentUserID: currentUserID,
            placements: discoveryPlacements
        )
        if let average = presentation.averageRating, presentation.ratedVisitCount > 0 {
            values.insert(RestaurantRatingReference(
                title: "我的评分",
                value: average,
                sampleCount: presentation.ratedVisitCount,
                systemImage: "star.fill"
            ), at: 0)
        }
        return values
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                RestaurantDetailStandardBody {
                    RestaurantPhotoGallerySection(
                        restaurantID: restaurant.id,
                        photos: activePhotos,
                        publicPhotoID: metadata.markerPhotoID,
                        merchantImageURL: metadata.merchantImageURL,
                        markerEmoji: metadata.markerEmoji,
                        categoryVisualID: categoryVisualID,
                        onSelect: { selectedPhoto = $0 },
                        onRetry: retryPhoto,
                        showsThumbnails: false
                    )
                } header: {
                    RestaurantDetailHeader(restaurant: restaurant)
                } actions: {
                    RestaurantQuickActionsSection(
                        restaurantAddress: restaurant.address,
                        status: restaurant.status,
                        publicShareEntityID: restaurant.remoteID ?? "",
                        canPublicShare: canPublicShareRestaurant,
                        showsShareAvailabilityHint: true,
                        canRecordVisit: canMutateRestaurant,
                        canMarkWantToGo: false,
                        canEdit: canMutateRestaurant,
                        canDelete: canMutateRestaurant,
                        canAddToList: currentUserID != nil,
                        canAddToRoulette: currentUserID != nil,
                        identifiers: .local,
                        onRecordVisit: { isAddingVisit = true },
                        onMarkWantToGo: markWantToGo,
                        onEdit: { isEditingRestaurant = true },
                        onAddToList: { isAddingToList = true },
                        onAddToRoulette: { isShowingRoulette = true },
                        onCopyName: { UIPasteboard.general.string = restaurant.name },
                        onCopyAddress: { UIPasteboard.general.string = restaurant.address },
                        onDelete: { isConfirmingRestaurantDeletion = true }
                    )
                } business: {
                    if metadata.hasBusinessInformation {
                        RestaurantBusinessInformationSection(
                            metadata: metadata,
                            onCall: callRestaurant
                        )
                    }
                } location: {
                    RestaurantLocationSection(
                        restaurant: restaurant,
                        onOpenAppleMaps: openAppleMaps
                    )
                } ratings: {
                    if !ratingReferences.isEmpty {
                        RestaurantRatingReferencesSection(references: ratingReferences)
                    }
                } userPhotos: {
                    RestaurantUserPhotosSection(hasPhotos: !activePhotos.isEmpty) {
                        RestaurantLocalUserPhotosContent(
                            photos: activePhotos,
                            onSelect: { selectedPhoto = $0 },
                            onRetry: retryPhoto
                        )
                    }
                } personalOverview: {
                    RestaurantDetailStatsSection(presentation: presentation)
                } history: {
                    RestaurantVisitHistorySection(
                        visits: presentation.activeVisits,
                        companionNamesByID: companionNamesByID,
                        sourceNamesByID: sourceNamesByID,
                        onEdit: { editingVisit = $0 },
                        onDelete: { visitPendingDeletion = $0 }
                    )
                } context: {
                    if let latestDiscoveryContext {
                        RestaurantDiscoveryContextSection(context: latestDiscoveryContext)
                    }
                } extended: {
                    RestaurantDishSection(summaries: dishSummaries)
                    if presentation.queueSummary != nil || !presentation.tagGroups.isEmpty {
                        RestaurantExperienceSummarySection(presentation: presentation)
                    }
                    RestaurantDetailedRatingsSection(summaries: detailedRatingSummaries)
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(TasteMapCoreTheme.page)
            .navigationTitle("餐厅详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("编辑", systemImage: "square.and.pencil") {
                        isEditingRestaurant = true
                    }
                    .disabled(!canMutateRestaurant)
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("删除餐厅", systemImage: "trash", role: .destructive) {
                        isConfirmingRestaurantDeletion = true
                    }
                    .disabled(!canMutateRestaurant)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack {
                    Spacer()
                    Button {
                        isAddingVisit = true
                    } label: {
                        Label(
                            restaurant.status == .wantToGo ? "记录去过" : "再次记录",
                            systemImage: "plus"
                        )
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                        .padding(.horizontal, 16)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(!canMutateRestaurant)
                    .accessibilityIdentifier("restaurant-detail-add-visit")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .sheet(isPresented: $isAddingVisit) {
                VisitEditorView(restaurant: restaurant)
            }
            .sheet(item: $editingVisit) { visit in
                VisitEditorView(restaurant: restaurant, visit: visit)
            }
            .sheet(isPresented: $isEditingRestaurant) {
                RestaurantEditView(restaurant: restaurant)
            }
            .sheet(isPresented: $isAddingToList) {
                if let currentUserID {
                    AddRestaurantToListsSheet(
                        restaurant: restaurant,
                        currentUserID: currentUserID
                    )
                }
            }
            .sheet(isPresented: $isShowingRoulette) {
                NavigationStack {
                    RestaurantRouletteScreen(
                        preferredCity: restaurant.city,
                        initialRestaurantID: restaurant.id
                    )
                }
            }
            .fullScreenCover(item: $selectedPhoto) { photo in
                PhotoGalleryViewer(photos: activePhotos, selectedID: photo.id)
            }
            .confirmationDialog(
                "删除这次到访？",
                isPresented: Binding(
                    get: { visitPendingDeletion != nil },
                    set: { if !$0 { visitPendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("删除到访记录", role: .destructive) {
                    if let visit = visitPendingDeletion {
                        delete(visit)
                    }
                    visitPendingDeletion = nil
                }
                Button("取消", role: .cancel) { visitPendingDeletion = nil }
            } message: {
                Text("只会删除这一条到访，不会影响这家餐厅的其他历史记录。")
            }
            .confirmationDialog(
                "删除这家餐厅？",
                isPresented: $isConfirmingRestaurantDeletion,
                titleVisibility: .visible
            ) {
                Button("删除餐厅及其记录", role: .destructive, action: deleteRestaurant)
                    .accessibilityIdentifier("restaurant-delete-confirm")
                Button("取消", role: .cancel) {}
            } message: {
                Text("餐厅、到访、菜品和照片记录会先在本机标记删除，并按依赖顺序进入同步队列。其他设备同步后也不会把旧记录恢复。")
            }
            .alert("无法删除", isPresented: Binding(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            )) {
                Button("好", role: .cancel) { deleteError = nil }
            } message: {
                Text(deleteError ?? "请稍后重试。")
            }
            .alert("无法打开 Apple Maps", isPresented: Binding(
                get: { navigationError != nil },
                set: { if !$0 { navigationError = nil } }
            )) {
                Button("好", role: .cancel) { navigationError = nil }
            } message: {
                Text(navigationError ?? "请稍后重试。")
            }
            .alert("无法拨打电话", isPresented: Binding(
                get: { phoneError != nil },
                set: { if !$0 { phoneError = nil } }
            )) {
                Button("好", role: .cancel) { phoneError = nil }
            } message: {
                Text(phoneError ?? "这台设备暂时无法使用电话功能。")
            }
            .alert("操作没有完成", isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )) {
                Button("好", role: .cancel) { actionError = nil }
            } message: {
                Text(actionError ?? "请稍后重试。")
            }
        }
    }

    private func openAppleMaps() {
        if !navigator.openInAppleMaps(restaurant) {
            navigationError = "系统没有成功打开这家餐厅的位置。"
        }
    }

    private func callRestaurant() {
        guard let url = RestaurantPhoneDialing.url(for: metadata.callablePhone) else {
            phoneError = "餐厅电话格式无法安全拨打。"
            return
        }
        openURL(url) { accepted in
            if !accepted {
                Task { @MainActor in
                    phoneError = "这台设备暂时无法使用电话功能。"
                }
            }
        }
    }

    private func delete(_ visit: Visit) {
        do {
            try LocalTasteMapStore(context: modelContext).delete(
                visit,
                actorUserID: currentUserID
            )
        } catch {
            deleteError = "这条到访记录没有删除成功。"
        }
    }

    private func markWantToGo() {
        do {
            try LocalTasteMapStore(context: modelContext).markWantToGo(
                restaurant,
                actorUserID: currentUserID
            )
        } catch {
            actionError = "想吃状态没有保存成功。"
        }
    }

    private func deleteRestaurant() {
        do {
            try LocalTasteMapStore(context: modelContext).delete(
                restaurant,
                actorUserID: currentUserID
            )
            dismiss()
        } catch LocalTasteMapStoreError.restaurantOwnershipMismatch {
            actionError = "当前登录用户无权删除这条餐厅记录。"
        } catch {
            actionError = "餐厅没有删除成功，现有记录已保留。"
        }
    }

    private var activePhotos: [PhotoAsset] {
        let activeVisitIDs = Set(presentation.activeVisits.map(\.id))
        let photos = RestaurantDetailImageResolver.visibleRestaurantPhotos(
            owned.photos,
            restaurantID: restaurant.id,
            activeVisitIDs: activeVisitIDs
        )
        return RestaurantDetailImageResolver.orderedPhotos(photos, metadata: metadata)
    }

    private func retryPhoto(_ photo: PhotoAsset) {
        try? photoCoordinator?.retry(photo)
    }

    private var dishSummaries: [RestaurantDishSummary] {
        RestaurantDishPresentation.summaries(
            restaurantID: restaurant.id,
            dishes: owned.dishes,
            associations: owned.visitDishes,
            visits: owned.visits,
            photos: owned.photos
        )
    }

    private var detailedRatingSummaries: [RatingSummary] {
        RatingStatistics.summaries(for: presentation.activeVisits)
    }

    private var companionNamesByID: [String: String] {
        Dictionary(uniqueKeysWithValues: owned.companions.compactMap { companion in
            guard companion.deletedAt == nil, let remoteID = companion.remoteID else { return nil }
            return (remoteID, companion.displayName)
        })
    }

    private var sourceNamesByID: [String: String] {
        Dictionary(uniqueKeysWithValues: owned.recommendationSources.compactMap { source in
            guard source.deletedAt == nil, let remoteID = source.remoteID else { return nil }
            return (remoteID, source.displayName)
        })
    }

    private var currentUserID: String? {
        accountScope.authenticatedUserID
    }

    private var canMutateRestaurant: Bool {
        accountScope.contains(ownerUserID: restaurant.ownerUserID)
    }

    private var canPublicShareRestaurant: Bool {
        guard canMutateRestaurant,
              let currentUserID,
              profiles.contains(where: {
                  $0.tasteMapUserID == currentUserID && $0.deletedAt == nil && $0.visibility == .public
              }) else { return false }
        return presentation.activeVisits.contains { $0.visibility == .public }
    }

    private var latestDiscoveryContext: DiscoveryCachedCardContext? {
        guard let currentUserID, !metadata.globalIdentityKeys.isEmpty else { return nil }
        return discoveryPlacements
            .filter {
                $0.currentUserID == currentUserID &&
                    metadata.globalIdentityKeys.contains($0.globalKey)
            }
            .sorted { $0.generatedAt > $1.generatedAt }
            .compactMap(\.context)
            .first
    }
}
