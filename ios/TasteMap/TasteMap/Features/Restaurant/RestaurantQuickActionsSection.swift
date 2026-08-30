import SwiftUI

struct RestaurantQuickActionsSection: View {
    let restaurant: Restaurant
    let publicShareEntityID: String
    let canPublicShare: Bool
    let canMutate: Bool
    let canAddToList: Bool
    let onRecordVisit: () -> Void
    let onMarkWantToGo: () -> Void
    let onEdit: () -> Void
    let onAddToList: () -> Void
    let onAddToRoulette: () -> Void
    let onCopyName: () -> Void
    let onCopyAddress: () -> Void
    let onDelete: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("快捷操作")
                .font(.headline)
            LazyVGrid(columns: columns, spacing: 10) {
                action("记录到访", systemImage: "plus.circle.fill", enabled: canMutate, action: onRecordVisit)
                    .accessibilityIdentifier("restaurant-action-record-visit")
                action(
                    restaurant.status == .wantToGo ? "已在想吃" : "标记想吃",
                    systemImage: "bookmark.fill",
                    enabled: canMutate && restaurant.status != .wantToGo,
                    action: onMarkWantToGo
                )
                .accessibilityIdentifier("restaurant-action-want-to-go")
                action("编辑", systemImage: "square.and.pencil", enabled: canMutate, action: onEdit)
                    .accessibilityIdentifier("restaurant-action-edit")
                action("加入榜单", systemImage: "text.badge.plus", enabled: canAddToList, action: onAddToList)
                    .accessibilityIdentifier("restaurant-detail-add-to-list")
                action("加入抽签", systemImage: "circle.hexagongrid.fill", action: onAddToRoulette)
                    .accessibilityIdentifier("restaurant-action-roulette")
                PublicShareButton(
                    entityType: .restaurant,
                    entityID: publicShareEntityID,
                    enabled: canPublicShare
                ) {
                    actionLabel("分享", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("restaurant-action-share")
                Menu {
                    Button("复制餐厅名", systemImage: "doc.on.doc", action: onCopyName)
                    if !restaurant.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button("复制地址", systemImage: "mappin.and.ellipse", action: onCopyAddress)
                    }
                } label: {
                    actionLabel("复制", systemImage: "doc.on.doc")
                }
                .accessibilityIdentifier("restaurant-action-copy")
            }
            if canMutate {
                Divider()
                Button("删除餐厅", systemImage: "trash", role: .destructive, action: onDelete)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .accessibilityIdentifier("restaurant-action-delete")
            }
            if !canPublicShare {
                Label("将本人主页设为公开，并至少公开一次到访后，才可生成餐厅公开链接。", systemImage: "hand.raised.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(15)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func action(
        _ title: String,
        systemImage: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            actionLabel(title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.48)
    }

    private func actionLabel(_ title: String, systemImage: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 62)
        .padding(.horizontal, 4)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13))
        .contentShape(Rectangle())
    }
}
