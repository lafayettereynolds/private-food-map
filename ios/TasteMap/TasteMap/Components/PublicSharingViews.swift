import SwiftUI
import UIKit

struct PublicShareRouteSelection: Identifiable, Equatable {
    let shareID: String
    var id: String { shareID }
}

struct PublicShareButton<Label: View>: View {
    @Environment(NativeAuthServices.self) private var authServices
    let entityType: PublicShareEntityTypeV1
    let entityID: String
    let enabled: Bool
    @ViewBuilder let label: () -> Label

    @State private var isLoading = false
    @State private var result: PublicShareActionResult?
    @State private var errorMessage: String?

    init(
        entityType: PublicShareEntityTypeV1,
        entityID: String,
        enabled: Bool = true,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.entityType = entityType
        self.entityID = entityID
        self.enabled = enabled
        self.label = label
    }

    var body: some View {
        Button {
            Task { await createShare() }
        } label: {
            ZStack {
                label().opacity(isLoading ? 0.35 : 1)
                if isLoading { ProgressView().controlSize(.small) }
            }
        }
        .disabled(!enabled || isLoading)
        .sheet(item: $result) { value in
            PublicShareActionsView(result: value)
        }
        .alert("无法公开分享", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "请稍后重试。")
        }
    }

    @MainActor
    private func createShare() async {
        guard !entityID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "请先等待这条内容完成同步，再生成公开链接。"
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let value = try await authServices.publicSharingAPI.create(
                entityType: entityType,
                entityID: entityID
            )
            result = PublicShareActionResult(url: value.url, entityType: value.entityType)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct PublicShareActionResult: Identifiable, Equatable {
    let url: URL
    let entityType: PublicShareEntityTypeV1
    var id: String { url.absoluteString }

    var title: String {
        switch entityType {
        case .restaurant: "分享餐厅"
        case .profile: "分享我的公开主页"
        case .list: "分享公开榜单"
        }
    }
}

private struct PublicShareActionsView: View {
    @Environment(\.dismiss) private var dismiss
    let result: PublicShareActionResult
    @State private var isShowingSystemShare = false
    @State private var copied = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Label("公开链接会始终重新检查内容可见性", systemImage: "lock.shield")
                    .font(.headline)
                Text("如果内容被删除或改为非公开，原链接会立即停止展示。链接不包含你的内部用户 ID 或记录 ID。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(result.url.absoluteString)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(TasteMapCoreTheme.surfaceSubtle, in: RoundedRectangle(cornerRadius: 14))
                Button {
                    isShowingSystemShare = true
                } label: {
                    Label("系统分享", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Button {
                    UIPasteboard.general.url = result.url
                    copied = true
                } label: {
                    Label(copied ? "链接已复制" : "复制链接", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                Spacer()
            }
            .padding(20)
            .navigationTitle(result.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
            .sheet(isPresented: $isShowingSystemShare) {
                PublicURLActivityView(items: [result.url])
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct PublicURLActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct PublicShareLandingView: View {
    let shareID: String
    let api: any PublicSharingAPI
    @State private var response: PublicShareResponseV1?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    if let response { content(response.entity) }
                    else if let errorMessage {
                        TasteMapEmptyState(
                            title: "这个分享已经不可用",
                            message: errorMessage,
                            systemImage: "link.badge.plus",
                            presentation: .embedded,
                            accessibilityIdentifier: "public-share-unavailable-state"
                        )
                    } else {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("正在打开分享").foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 320)
                    }
                }
                .padding(18)
            }
            .background(TasteMapCoreTheme.page)
            .navigationTitle("Taste Map 分享")
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
        }
    }

    @ViewBuilder
    private func content(_ entity: PublicShareEntityV1) -> some View {
        switch entity {
        case .restaurant(let value):
            PublicSharedRestaurantDetailBody(value: value)
        case .profile(let value):
            shareCard(title: value.displayName, subtitle: value.city ?? "Taste Map 用户", imageURL: nil) {
                if let bio = value.bio { Text(bio).foregroundStyle(.secondary) }
                HStack {
                    Label("\(value.statistics.restaurantCount) 家公开餐厅", systemImage: "fork.knife")
                    Spacer()
                    Label("\(value.statistics.visitCount) 次公开到访", systemImage: "mappin.and.ellipse")
                }.font(.caption.weight(.semibold))
            }
        case .list(let value):
            shareCard(title: value.title, subtitle: "\(value.ownerDisplayName) · \(value.restaurantCount) 家餐厅", imageURL: nil) {
                if !value.description.isEmpty { Text(value.description).foregroundStyle(.secondary) }
                ForEach(Array(value.restaurants.prefix(20).enumerated()), id: \.element.id) { index, restaurant in
                    HStack(alignment: .top, spacing: 10) {
                        if value.isRanked { Text("\(index + 1)").font(.headline).foregroundStyle(Color.accentColor) }
                        TasteMapRestaurantImage(
                            resolution: RestaurantImagePriorityPolicy.resolution(
                                localUserPhotoID: nil,
                                providerMerchantImageURL: restaurant.merchantImageUrl
                            ),
                            semanticID: restaurant.id,
                            fallbackIconSize: 30,
                            accessibilityLabel: "\(restaurant.name)餐厅图片"
                        )
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(restaurant.name).font(.subheadline.weight(.semibold))
                            Text([restaurant.city, restaurant.address].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                            if let note = restaurant.note { Text(note).font(.caption) }
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(TasteMapCoreTheme.surfaceSubtle, in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    private func shareCard<Content: View>(
        title: String,
        subtitle: String,
        imageURL: URL?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let imageURL {
                AsyncImage(url: imageURL) { image in image.resizable().scaledToFill() } placeholder: { Color.accentColor.opacity(0.1) }
                    .frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 20))
            } else {
                Image(systemName: "fork.knife.circle.fill")
                    .font(.system(size: 58)).foregroundStyle(Color.accentColor)
            }
            Text(title).font(.largeTitle.bold())
            if !subtitle.isEmpty { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
            content()
            Label("公开状态发生变化后，这个链接会立即停止展示内容。", systemImage: "hand.raised.fill")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 24))
    }

    @MainActor
    private func load() async {
        do { response = try await api.read(shareID: shareID) }
        catch { errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }
}

/// A public share is another Restaurant entry source, not a separate card-only
/// product. The public contract intentionally omits private fields, so this
/// wrapper supplies honest empty states to the same ordered detail body.
private struct PublicSharedRestaurantDetailBody: View {
    let value: PublicRestaurantShareV1

    private var identity: RestaurantDetailIdentityPresentation {
        value.restaurantDetailIdentity
    }

    var body: some View {
        RestaurantDetailStandardBody {
            hero
        } header: {
            RestaurantDetailHeader(identity: identity)
        } actions: {
            publicActions
        } business: {
            if let price = value.pricePerPerson, price.isFinite, price > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("餐厅信息").font(.headline)
                    Label(
                        RestaurantDetailFormatting.referencePrice(Decimal(price)),
                        systemImage: FoodDiningVisualKind.receipt.systemImageName
                    )
                    .font(.subheadline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .tasteMapCoreCard(radius: 16)
                .accessibilityIdentifier("restaurant-business-information")
            }
        } location: {
            EmptyView()
        } ratings: {
            EmptyView()
        } userPhotos: {
            RestaurantUserPhotosSection(hasPhotos: false) { EmptyView() }
        } personalOverview: {
            RestaurantDetailStatsSection(
                remoteMessage: "公开分享不会暴露任何人的私人到访；登录后明确记录，才会显示你的记录。"
            )
        } history: {
            RestaurantVisitHistorySection(
                visits: [],
                companionNamesByID: [:],
                sourceNamesByID: [:],
                onEdit: { _ in },
                onDelete: { _ in }
            )
        } context: {
            if !value.cuisines.isEmpty {
                Label(value.cuisines.joined(separator: " · "), systemImage: FoodDiningVisualKind.menu.systemImageName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .tasteMapCoreCard(radius: 22)
            }
        } extended: {
            Label("公开状态发生变化后，这个链接会立即停止展示内容。", systemImage: "hand.raised.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("restaurant-detail-standard-body-share")
    }

    private var hero: some View {
        TasteMapRestaurantImage(
            resolution: RestaurantImagePriorityPolicy.resolution(
                localUserPhotoID: nil,
                providerMerchantImageURL: value.merchantImageUrl
            ),
            semanticID: value.shareId,
            variant: .display,
            fallbackKind: .restaurant,
            fallbackIconSize: 72,
            accessibilityLabel: "\(value.name)餐厅图片"
        )
        .frame(maxWidth: .infinity)
        .frame(height: 216)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .clipped()
        .accessibilityIdentifier("restaurant-photo-gallery")
    }

    private var publicActions: some View {
        HStack(spacing: 10) {
            Button {
                UIPasteboard.general.string = value.name
            } label: {
                Label("复制餐厅名", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            if !value.address.isEmpty {
                Button {
                    UIPasteboard.general.string = value.address
                } label: {
                    Label("复制地址", systemImage: "mappin.and.ellipse")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .tasteMapCoreCard(radius: 16)
        .accessibilityIdentifier("restaurant-detail-quick-actions")
    }
}

extension PublicRestaurantShareV1 {
    var restaurantDetailIdentity: RestaurantDetailIdentityPresentation {
        RestaurantDetailIdentityPresentation(
            name: name,
            address: address,
            city: city
        )
    }
}
