import SwiftUI

/// One visible exit action. The owning editor retains save/unsaved-state policy.
struct TasteMapReturnButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: TasteMapDesignTokens.Icon.standard, weight: .semibold))
                .frame(
                    minWidth: TasteMapDesignTokens.Control.minimumHitTarget,
                    minHeight: TasteMapDesignTokens.Control.minimumHitTarget
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("返回上一页")
    }
}
