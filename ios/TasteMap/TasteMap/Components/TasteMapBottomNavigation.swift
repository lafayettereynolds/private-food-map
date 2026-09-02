import SwiftUI

struct TasteMapBottomNavigation: View {
    @Binding var selection: AppTab
    let showsAddRestaurant: Bool
    let onAddRestaurant: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityLayout
            } else {
                standardLayout
            }
        }
    }

    private var standardLayout: some View {
        ZStack(alignment: .top) {
            tabItems
            .padding(.horizontal, 8)
            .frame(height: 58)
            .background(TasteMapCoreTheme.surface.opacity(0.95))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(TasteMapCoreTheme.border.opacity(0.85))
                    .frame(height: 1)
            }
            .shadow(color: TasteMapCoreTheme.cardShadow, radius: 14, y: -5)
            .padding(.top, showsAddRestaurant ? 30 : 0)

            if showsAddRestaurant {
                addRestaurantButton(fixedHeight: 38)
            }
        }
        .frame(height: showsAddRestaurant ? 88 : 58, alignment: .bottom)
    }

    private var accessibilityLayout: some View {
        VStack(spacing: 8) {
            if showsAddRestaurant {
                addRestaurantButton(fixedHeight: nil)
            }
            tabItems
                .padding(.horizontal, 8)
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(TasteMapCoreTheme.surface.opacity(0.97))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(TasteMapCoreTheme.border.opacity(0.85))
                .frame(height: 1)
        }
        .shadow(color: TasteMapCoreTheme.cardShadow, radius: 14, y: -5)
    }

    private var tabItems: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: selection == tab ? tab.selectedSystemImage : tab.systemImage)
                            .font(.system(size: 18, weight: .semibold))
                        Text(tab.title)
                            .font(.caption2.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(
                        selection == tab
                            ? TasteMapCoreTheme.brand
                            : TasteMapCoreTheme.textSecondary
                    )
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 4 : 0)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
                .accessibilityIdentifier("app-tab-\(tab.rawValue)")
            }
        }
    }

    private func addRestaurantButton(fixedHeight: CGFloat?) -> some View {
        Button(action: onAddRestaurant) {
            Label("添加餐厅", systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, fixedHeight == nil ? 8 : 0)
                .frame(height: fixedHeight)
                .frame(minHeight: fixedHeight == nil ? 44 : nil)
                .background(TasteMapCoreTheme.brand, in: Capsule())
                .shadow(color: TasteMapCoreTheme.brand.opacity(0.24), radius: 9, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("addRestaurantButton")
    }
}
