import SwiftUI

struct RestaurantSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: RestaurantSearchViewModel
    @State private var query: String
    @State private var actionError: String?

    let onAction: (RestaurantCandidate, RestaurantSearchAction) throws -> Void
    private let selectionTitle: String?

    init(
        searchService: any RestaurantSearching = MapKitRestaurantSearchService(),
        initialQuery: String = "",
        onAction: @escaping (RestaurantCandidate, RestaurantSearchAction) throws -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: RestaurantSearchViewModel(searchService: searchService)
        )
        _query = State(initialValue: initialQuery)
        self.onAction = onAction
        selectionTitle = nil
    }

    init(
        searchService: any RestaurantSearching = MapKitRestaurantSearchService(),
        initialQuery: String = "",
        selectionTitle: String,
        onSelect: @escaping (RestaurantCandidate) throws -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: RestaurantSearchViewModel(searchService: searchService)
        )
        _query = State(initialValue: initialQuery)
        self.selectionTitle = selectionTitle
        onAction = { candidate, _ in try onSelect(candidate) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("正在搜索餐厅…")
                } else if let errorMessage = viewModel.errorMessage {
                    TasteMapEmptyState(
                        title: "无法完成搜索",
                        message: errorMessage,
                        systemImage: "wifi.exclamationmark",
                        actionTitle: "重试",
                        action: { Task { await viewModel.retry() } },
                        presentation: .embedded,
                        accessibilityIdentifier: "restaurant-search-error-state"
                    )
                } else if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    TasteMapEmptyState(
                        title: "搜索餐厅",
                        message: "输入真实餐厅名称或地址，结果由 Apple 地图提供。",
                        systemImage: "magnifyingglass",
                        foodDiningVisualKind: .genericDining,
                        presentation: .embedded,
                        accessibilityIdentifier: "restaurant-search-guidance-state"
                    )
                } else if viewModel.results.isEmpty {
                    TasteMapEmptyState(
                        title: "没有找到餐厅",
                        message: "Apple 地图没有找到与“\(query)”匹配的真实餐厅。",
                        systemImage: "magnifyingglass",
                        presentation: .embedded,
                        accessibilityIdentifier: "restaurant-search-empty-state"
                    )
                } else {
                    List(viewModel.results) { candidate in
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(candidate.name)
                                    .font(.headline)
                                if !candidate.address.isEmpty {
                                    Text(candidate.address)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if let selectionTitle {
                                Button {
                                    perform(.wantToGo, candidate: candidate)
                                } label: {
                                    Label(selectionTitle, systemImage: "text.badge.plus")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                            } else { HStack(spacing: 10) {
                                Button {
                                    perform(.wantToGo, candidate: candidate)
                                } label: {
                                    Label("加入想吃", systemImage: "bookmark")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)

                                Button {
                                    perform(.recordVisit, candidate: candidate)
                                } label: {
                                    Label(
                                        "记录去过",
                                        systemImage: RestaurantStatus.visited.systemImage
                                    )
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                            } }
                        }
                        .padding(.vertical, 5)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("搜索餐厅")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "餐厅名称或地址")
            .onSubmit(of: .search) {
                Task { await viewModel.search(query: query) }
            }
            .task {
                if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   viewModel.results.isEmpty {
                    await viewModel.search(query: query)
                }
            }
            .alert("无法保存餐厅", isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )) {
                Button("好", role: .cancel) { actionError = nil }
            } message: {
                Text(actionError ?? "请稍后重试。")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func perform(_ action: RestaurantSearchAction, candidate: RestaurantCandidate) {
        do {
            try onAction(candidate, action)
            dismiss()
        } catch {
            actionError = "餐厅先保存在本地时出现问题，请重试。"
        }
    }
}

enum RestaurantSearchAction: Sendable {
    case wantToGo
    case recordVisit
}

#Preview("Search results") {
    RestaurantSearchView(
        searchService: PreviewRestaurantSearchService(),
        initialQuery: "寿喜烧"
    ) { _, _ in }
}

private struct PreviewRestaurantSearchService: RestaurantSearching {
    func search(query: String) async throws -> [RestaurantCandidate] {
        [
            RestaurantCandidate(
                name: "牛 New 寿喜烧（一个用于验证长名称展示的门店）",
                address: "杭州市上城区东宁路与和兴路交叉口",
                latitude: 30.29,
                longitude: 120.21,
                appleMapItemIdentifier: "preview-apple-place-1"
            ),
            RestaurantCandidate(
                name: "山葵家精致料理",
                address: "杭州市拱墅区湖墅南路",
                latitude: 30.28,
                longitude: 120.16,
                appleMapItemIdentifier: "preview-apple-place-2"
            ),
        ]
    }
}
