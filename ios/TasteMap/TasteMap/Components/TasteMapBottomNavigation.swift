import SwiftUI

struct TasteMapBottomNavigation: View {
    @Binding var selection: AppTab
    let onAddRestaurant: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
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
                        }
                        .foregroundStyle(
                            selection == tab
                                ? TasteMapCoreTheme.brand
                                : TasteMapCoreTheme.textSecondary
                        )
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.title)
                    .accessibilityAddTraits(selection == tab ? .isSelected : [])
                    .accessibilityIdentifier("app-tab-\(tab.rawValue)")
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 58)
            .background(TasteMapCoreTheme.surface.opacity(0.95))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(TasteMapCoreTheme.border.opacity(0.85))
                    .frame(height: 1)
            }
            .shadow(color: TasteMapCoreTheme.cardShadow, radius: 14, y: -5)
            .padding(.top, 30)

            Button(action: onAddRestaurant) {
                Label("添加餐厅", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 38)
                    .background(TasteMapCoreTheme.brand, in: Capsule())
                    .shadow(color: TasteMapCoreTheme.brand.opacity(0.24), radius: 9, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("addRestaurantButton")
        }
        .frame(height: 88, alignment: .bottom)
    }
}
