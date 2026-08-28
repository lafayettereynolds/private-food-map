import SwiftData
import SwiftUI

struct RestaurantDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.photoTransferCoordinator) private var photoCoordinator
    @Query private var allVisits: [Visit]
    @Query private var allPhotos: [PhotoAsset]
    @Query private var allDishes: [Dish]
    @Query private var allVisitDishes: [VisitDish]
    @Query private var allCompanions: [DiningCompanion]
    @Query private var allRecommendationSources: [RecommendationSource]
    @Query private var profiles: [UserProfile]

    let restaurant: Restaurant
    private let navigator: any RestaurantNavigating

    @State private var isAddingVisit = false
    @State private var isEditingRestaurant = false
    @State private var editingVisit: Visit?
    @State private var visitPendingDeletion: Visit?
    @State private var deleteError: String?
    @State private var navigationError: String?
    @State private var selectedPhoto: PhotoAsset?
    @State private var isAddingToList = false

    @MainActor
    init(restaurant: Restaurant) {
        self.restaurant = restaurant
        navigator = AppleMapsRestaurantNavigator()
    }

    @MainActor
    init(restaurant: Restaurant, navigator: any RestaurantNavigating) {
        self.restaurant = restaurant
        self.navigator = navigator
    }

    private var presentation: RestaurantDetailPresentation {
        RestaurantDetailPresentation(restaurantID: restaurant.id, visits: allVisits)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 18) {
                    RestaurantDetailHeader(restaurant: restaurant)
                    if currentUserID != nil {
                        Button { isAddingToList = true } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "text.badge.plus")
                                    .foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("加入榜单").font(.headline).foregroundStyle(.primary)
                                    Text("可同时整理到不同主题，不会改变想吃状态")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                            .padding(15)
                            .background(.background, in: RoundedRectangle(cornerRadius: 18))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("restaurant-detail-add-to-list")
                    }
                    RestaurantLocationSection(
                        restaurant: restaurant,
                        onOpenAppleMaps: openAppleMaps
                    )
                    RestaurantPhotoGallerySection(
                        photos: activePhotos,
                        onSelect: { selectedPhoto = $0 },
                        onRetry: retryPhoto
                    )
                    RestaurantDishSection(summaries: dishSummaries)
                    RestaurantDetailStatsSection(presentation: presentation)
                    RestaurantDetailedRatingsSection(summaries: detailedRatingSummaries)
                    RestaurantVisitHistorySection(
                        visits: presentation.activeVisits,
                        companionNamesByID: companionNamesByID,
                        sourceNamesByID: sourceNamesByID,
                        onEdit: { editingVisit = $0 },
                        onDelete: { visitPendingDeletion = $0 }
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("餐厅详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("编辑", systemImage: "square.and.pencil") {
                        isEditingRestaurant = true
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button {
                    isAddingVisit = true
                } label: {
                    Label(
                        restaurant.status == .wantToGo ? "记录去过" : "再次记录",
                        systemImage: "plus.circle.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.bar)
                .accessibilityIdentifier("restaurant-detail-add-visit")
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
        }
    }

    private func openAppleMaps() {
        if !navigator.openInAppleMaps(restaurant) {
            navigationError = "系统没有成功打开这家餐厅的位置。"
        }
    }

    private func delete(_ visit: Visit) {
        do {
            try LocalTasteMapStore(context: modelContext).delete(visit)
        } catch {
            deleteError = "这条到访记录没有删除成功。"
        }
    }

    private var activePhotos: [PhotoAsset] {
        allPhotos
            .filter { $0.restaurantId == restaurant.id && $0.deletedAt == nil }
            .sorted { left, right in
                left.createdAt == right.createdAt
                    ? left.sortOrder < right.sortOrder
                    : left.createdAt > right.createdAt
            }
    }

    private func retryPhoto(_ photo: PhotoAsset) {
        try? photoCoordinator?.retry(photo)
    }

    private var dishSummaries: [RestaurantDishSummary] {
        RestaurantDishPresentation.summaries(
            restaurantID: restaurant.id,
            dishes: allDishes,
            associations: allVisitDishes,
            visits: allVisits,
            photos: allPhotos
        )
    }

    private var detailedRatingSummaries: [RatingSummary] {
        RatingStatistics.summaries(for: presentation.activeVisits)
    }

    private var companionNamesByID: [String: String] {
        Dictionary(uniqueKeysWithValues: allCompanions.compactMap { companion in
            guard companion.deletedAt == nil, let remoteID = companion.remoteID else { return nil }
            return (remoteID, companion.displayName)
        })
    }

    private var sourceNamesByID: [String: String] {
        Dictionary(uniqueKeysWithValues: allRecommendationSources.compactMap { source in
            guard source.deletedAt == nil, let remoteID = source.remoteID else { return nil }
            return (remoteID, source.displayName)
        })
    }

    private var currentUserID: String? {
        profiles.first { $0.deletedAt == nil }?.tasteMapUserID
    }
}
