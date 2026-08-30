import SwiftUI

struct RestaurantQuickActionIdentifiers: Sendable, Equatable {
    let recordVisit: String
    let wantToGo: String
    let addToList: String
    let addToRoulette: String

    static let local = RestaurantQuickActionIdentifiers(
        recordVisit: "restaurant-action-record-visit",
        wantToGo: "restaurant-action-want-to-go",
        addToList: "restaurant-detail-add-to-list",
        addToRoulette: "restaurant-action-roulette"
    )

    static func discoveryDetail(restaurantKey: String) -> RestaurantQuickActionIdentifiers {
        RestaurantQuickActionIdentifiers(
            recordVisit: "discovery-detail-record-\(restaurantKey)",
            wantToGo: "discovery-detail-want-\(restaurantKey)",
            addToList: "discovery-detail-list-\(restaurantKey)",
            addToRoulette: "discovery-detail-roulette-\(restaurantKey)"
        )
    }
}

struct RestaurantQuickActionsSection: View {
    let restaurantAddress: String
    let status: RestaurantStatus?
    let publicShareEntityID: String
    let canPublicShare: Bool
    let showsShareAvailabilityHint: Bool
    let canRecordVisit: Bool
    let canMarkWantToGo: Bool
    let canEdit: Bool
    let canDelete: Bool
    let canAddToList: Bool
    let canAddToRoulette: Bool
    let identifiers: RestaurantQuickActionIdentifiers
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
                primaryAction("记录到访", systemImage: "plus", enabled: canRecordVisit, action: onRecordVisit)
                    .accessibilityIdentifier(identifiers.recordVisit)
                primaryAction(
                    wantToGoTitle,
                    systemImage: "bookmark.fill",
                    enabled: canMarkWantToGo,
                    action: onMarkWantToGo
                )
                .accessibilityIdentifier(identifiers.wantToGo)
                primaryAction(
                    "加入抽签", systemImage: "dice.fill",
                    enabled: canAddToRoulette, action: onAddToRoulette
                )
                    .accessibilityIdentifier(identifiers.addToRoulette)
            }

            HStack(spacing: 8) {
                compactAction("编辑", systemImage: "square.and.pencil", enabled: canEdit, action: onEdit)
                    .accessibilityIdentifier("restaurant-action-edit")
                compactAction("榜单", systemImage: "text.badge.plus", enabled: canAddToList, action: onAddToList)
                    .accessibilityIdentifier(identifiers.addToList)
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
                    if !restaurantAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button("复制地址", systemImage: "mappin.and.ellipse", action: onCopyAddress)
                            .accessibilityIdentifier("restaurant-action-copy-address")
                    }
                    if canDelete {
                        Button("删除餐厅", systemImage: "trash", role: .destructive, action: onDelete)
                            .accessibilityIdentifier("restaurant-action-delete")
                    }
                } label: {
                    compactActionLabel("更多", systemImage: "ellipsis")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("restaurant-action-more")
            }
            if showsShareAvailabilityHint, !canPublicShare {
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

    private var wantToGoTitle: String {
        switch status {
        case .wantToGo: "已在想吃"
        case .visited: "已去过"
        case nil: "标记想吃"
        }
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
