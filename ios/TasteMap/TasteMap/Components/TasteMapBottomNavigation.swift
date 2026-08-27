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
                        .foregroundStyle(selection == tab ? Color.accentColor : Color.secondary)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.title)
                    .accessibilityAddTraits(selection == tab ? .isSelected : [])
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 58)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Divider()
            }
            .padding(.top, 30)

            Button(action: onAddRestaurant) {
                Label("添加餐厅", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 38)
                    .background(Color.accentColor, in: Capsule())
                    .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("addRestaurantButton")
        }
        .frame(height: 88, alignment: .bottom)
    }
}
