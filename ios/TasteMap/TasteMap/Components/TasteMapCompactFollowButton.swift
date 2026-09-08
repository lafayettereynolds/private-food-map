import SwiftUI

/// A row action, not a List Label: no hidden icon column or trailing title inset.
struct TasteMapCompactFollowButton: View {
    let userName: String
    let isPending: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("关注")
                .font(TasteMapDesignTokens.Typography.control)
                .lineLimit(1)
                .opacity(isPending ? 0 : 1)
                .padding(.horizontal, TasteMapDesignTokens.FollowAction.horizontalPadding)
                .frame(
                    minWidth: TasteMapDesignTokens.FollowAction.minimumWidth,
                    minHeight: TasteMapDesignTokens.FollowAction.visibleHeight,
                    alignment: .center
                )
                .foregroundStyle(TasteMapCoreTheme.onBrand)
                .overlay {
                    if isPending { ProgressView().controlSize(.small).tint(TasteMapCoreTheme.onBrand) }
                }
                .background(TasteMapCoreTheme.brand, in: Capsule())
                .frame(minHeight: TasteMapDesignTokens.Control.minimumHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .disabled(isPending)
        .accessibilityLabel("关注 \(userName)")
        .accessibilityValue(isPending ? "正在处理" : "")
    }
}
