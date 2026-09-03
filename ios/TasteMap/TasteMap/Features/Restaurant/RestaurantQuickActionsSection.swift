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
    var isInRoulette = false
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
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    circularAction(
                        "记录",
                        systemImage: "plus",
                        enabled: canRecordVisit,
                        action: onRecordVisit
                    )
                    .accessibilityIdentifier(identifiers.recordVisit)
                    circularAction(
                        wantToGoTitle,
                        systemImage: status == .visited
                            ? RestaurantStatus.visited.systemImage
                            : "bookmark.fill",
                        enabled: canMarkWantToGo,
                        action: onMarkWantToGo
                    )
                    .accessibilityIdentifier(identifiers.wantToGo)
                    circularAction(
                        isInRoulette ? "移出转盘" : "加入转盘",
                        systemImage: "dice.fill",
                        enabled: canAddToRoulette,
                        isSelected: isInRoulette,
                        action: onAddToRoulette
                    )
                    .accessibilityIdentifier(identifiers.addToRoulette)
                    circularAction("编辑", systemImage: "square.and.pencil", enabled: canEdit, action: onEdit)
                    .accessibilityIdentifier("restaurant-action-edit")
                    circularAction("榜单", systemImage: "text.badge.plus", enabled: canAddToList, action: onAddToList)
                    .accessibilityIdentifier(identifiers.addToList)
                    PublicShareButton(
                        entityType: .restaurant,
                        entityID: publicShareEntityID,
                        enabled: canPublicShare
                    ) {
                        circularActionLabel("分享", systemImage: "square.and.arrow.up")
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
                        circularActionLabel("更多", systemImage: "ellipsis")
                    }
                    .accessibilityIdentifier("restaurant-action-more")
                }
            }
            .scrollIndicators(.hidden)
            if showsShareAvailabilityHint, !canPublicShare {
                Label("将本人主页设为公开，并至少公开一次到访后，才可生成餐厅公开链接。", systemImage: "hand.raised.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 4)
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

    private func circularAction(
        _ title: String,
        systemImage: String,
        enabled: Bool = true,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            circularActionLabel(title, systemImage: systemImage, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.48)
    }

    private func circularActionLabel(_ title: String, systemImage: String, isSelected: Bool = false) -> some View {
        VStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : TasteMapCoreTheme.brandDeep)
                .frame(width: 44, height: 44)
                .background(isSelected ? TasteMapCoreTheme.brand : TasteMapCoreTheme.brandSoft, in: Circle())
                .overlay { Circle().stroke(TasteMapCoreTheme.border) }
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(.primary)
        .frame(width: 62)
        .frame(minHeight: 64, alignment: .top)
        .contentShape(Rectangle())
    }
}
