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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                primaryAction("记录到访", systemImage: "plus", enabled: canMutate, action: onRecordVisit)
                    .accessibilityIdentifier("restaurant-action-record-visit")
                primaryAction(
                    restaurant.status == .wantToGo ? "已在想吃" : "标记想吃",
                    systemImage: "bookmark.fill",
                    enabled: canMutate && restaurant.status != .wantToGo,
                    action: onMarkWantToGo
                )
                .accessibilityIdentifier("restaurant-action-want-to-go")
                primaryAction("加入抽签", systemImage: "dice.fill", action: onAddToRoulette)
                    .accessibilityIdentifier("restaurant-action-roulette")
            }

            HStack(spacing: 8) {
                compactAction("编辑", systemImage: "square.and.pencil", enabled: canMutate, action: onEdit)
                    .accessibilityIdentifier("restaurant-action-edit")
                compactAction("榜单", systemImage: "text.badge.plus", enabled: canAddToList, action: onAddToList)
                    .accessibilityIdentifier("restaurant-detail-add-to-list")
                PublicShareButton(
                    entityType: .restaurant,
                    entityID: publicShareEntityID,
                    enabled: canPublicShare
                ) {
                    compactActionLabel("分享", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("restaurant-action-share")
                Menu {
                    Button("复制餐厅名", systemImage: "doc.on.doc", action: onCopyName)
                        .accessibilityIdentifier("restaurant-action-copy-name")
                    if !restaurant.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button("复制地址", systemImage: "mappin.and.ellipse", action: onCopyAddress)
                            .accessibilityIdentifier("restaurant-action-copy-address")
                    }
                    if canMutate {
                        Button("删除餐厅", systemImage: "trash", role: .destructive, action: onDelete)
                            .accessibilityIdentifier("restaurant-action-delete")
                    }
                } label: {
                    compactActionLabel("更多", systemImage: "ellipsis")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("restaurant-action-more")
            }
            if !canPublicShare {
                Label("将本人主页设为公开，并至少公开一次到访后，才可生成餐厅公开链接。", systemImage: "hand.raised.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .tasteMapCoreCard(radius: 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("restaurant-detail-quick-actions")
    }

    private func primaryAction(
        _ title: String,
        systemImage: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(TasteMapCoreTheme.brandDeep)
                    .frame(width: 44, height: 44)
                    .background(TasteMapCoreTheme.brandSoft, in: Circle())
                    .overlay { Circle().stroke(TasteMapCoreTheme.border) }
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.48)
    }

    private func compactAction(
        _ title: String,
        systemImage: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            compactActionLabel(title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.48)
    }

    private func compactActionLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(TasteMapCoreTheme.brandDeep)
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .background(TasteMapCoreTheme.surfaceSubtle, in: Capsule())
        .overlay { Capsule().stroke(TasteMapCoreTheme.border) }
        .contentShape(Rectangle())
    }
}
