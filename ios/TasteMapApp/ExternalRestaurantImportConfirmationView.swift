import SwiftUI

/// 主 App 接收 Share Extension 的待处理导入后使用的轻量确认页。
/// 这里只选择或搜索餐厅，不在解析阶段自动创建 Restaurant 或自动加入想吃。
public struct ExternalRestaurantImportConfirmationView: View {
    public let response: ExternalRestaurantResolveResponse
    public let onOpenRestaurant: (ExternalRestaurantCandidate) -> Void
    public let onAddWantToGo: (ExternalRestaurantCandidate) -> Void
    public let onRecordVisit: (ExternalRestaurantCandidate) -> Void
    public let onSearchFallback: (ExternalRestaurantSearchFallback) -> Void

    public init(
        response: ExternalRestaurantResolveResponse,
        onOpenRestaurant: @escaping (ExternalRestaurantCandidate) -> Void,
        onAddWantToGo: @escaping (ExternalRestaurantCandidate) -> Void,
        onRecordVisit: @escaping (ExternalRestaurantCandidate) -> Void,
        onSearchFallback: @escaping (ExternalRestaurantSearchFallback) -> Void
    ) {
        self.response = response
        self.onOpenRestaurant = onOpenRestaurant
        self.onAddWantToGo = onAddWantToGo
        self.onRecordVisit = onRecordVisit
        self.onSearchFallback = onSearchFallback
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(response.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if response.candidates.isEmpty {
                        fallbackView
                    } else {
                        ForEach(response.candidates) { candidate in
                            candidateCard(candidate)
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("确认餐厅")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private var fallbackView: some View {
        if let fallback = response.searchFallback {
            VStack(alignment: .leading, spacing: 12) {
                Label("还不能确定具体门店", systemImage: "magnifyingglass")
                    .font(.headline)
                Text("将使用“\(fallback.keyword)”打开餐厅搜索，请你确认门店后再保存。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("搜索并选择门店") { onSearchFallback(fallback) }
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        } else {
            ContentUnavailableView(
                "没有识别到餐厅",
                systemImage: "mappin.slash",
                description: Text("请复制餐厅名称或更完整的地图链接后重试。")
            )
        }
    }

    private func candidateCard(_ candidate: ExternalRestaurantCandidate) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                AsyncImage(url: candidate.merchantImageUrl.flatMap(URL.init(string:))) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "fork.knife")
                        .foregroundStyle(.secondary)
                }
                .frame(width: 56, height: 56)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text(candidate.name).font(.headline)
                    Text([candidate.city, candidate.address].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            HStack {
                Button("查看餐厅") { onOpenRestaurant(candidate) }
                Spacer()
                Button("想吃") { onAddWantToGo(candidate) }
                Button("记录到访") { onRecordVisit(candidate) }
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
