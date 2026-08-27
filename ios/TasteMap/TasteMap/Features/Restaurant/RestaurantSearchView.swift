import SwiftUI

struct RestaurantSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: RestaurantSearchViewModel
    @State private var query = ""

    let onSelect: (RestaurantCandidate) -> Void

    init(
        searchService: any RestaurantSearching = MapKitRestaurantSearchService(),
        onSelect: @escaping (RestaurantCandidate) -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: RestaurantSearchViewModel(searchService: searchService)
        )
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("正在搜索餐厅…")
                } else if let errorMessage = viewModel.errorMessage {
                    ContentUnavailableView {
                        Label("无法完成搜索", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("重试") {
                            Task { await viewModel.retry() }
                        }
                    }
                } else if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView(
                        "搜索餐厅",
                        systemImage: "magnifyingglass",
                        description: Text("输入真实餐厅名称或地址，结果由 Apple 地图提供。")
                    )
                } else if viewModel.results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(viewModel.results) { candidate in
                        Button {
                            onSelect(candidate)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(candidate.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                if !candidate.address.isEmpty {
                                    Text(candidate.address)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}
