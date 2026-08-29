import SwiftData
import SwiftUI

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(NativeAuthServices.self) private var authServices
    @Query private var restaurants: [Restaurant]
    @State private var selectedTab: AppTab = .map
    @State private var isShowingSearch = false
    @State private var requestedVisitCandidate: RestaurantCandidate?
    @State private var visitCandidate: RestaurantCandidate?
    @State private var isBottomNavigationHidden = false

    var body: some View {
        activeView
            .onPreferenceChange(TasteMapBottomNavigationHiddenPreferenceKey.self) {
                isBottomNavigationHidden = $0
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !isBottomNavigationHidden {
                    TasteMapBottomNavigation(
                        selection: $selectedTab,
                        onAddRestaurant: { isShowingSearch = true }
                    )
                }
            }
            .sheet(isPresented: $isShowingSearch, onDismiss: {
                if let requestedVisitCandidate {
                    // Let the acquisition sheet finish its dismissal before presenting
                    // VisitEditor. Presenting both in the same transaction is ignored on
                    // some iOS versions and leaves the user back on the map.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(200))
                        guard self.requestedVisitCandidate?.id == requestedVisitCandidate.id else { return }
                        self.requestedVisitCandidate = nil
                        visitCandidate = requestedVisitCandidate
                    }
                }
            }) {
                AddRestaurantView(
                    dependencies: acquisitionDependencies
                ) { candidate, action in
                    switch action {
                    case .wantToGo:
                        _ = try LocalTasteMapStore(context: modelContext).addToWantToGo(
                            candidate: candidate,
                            among: restaurants
                        )
                        selectedTab = .map
                    case .recordVisit:
                        requestedVisitCandidate = candidate
                    }
                }
            }
            .sheet(item: $visitCandidate) { candidate in
                VisitEditorView(candidate: candidate, onSaved: { _ in
                    selectedTab = .map
                })
            }
    }

    private var acquisitionDependencies: RestaurantAcquisitionDependencies {
#if DEBUG
        if TasteMapUITestFixtures.usesRestaurantAcquisitionFixture {
            return TasteMapUITestFixtures.restaurantAcquisitionDependencies
        }
#endif
        return .live(linkResolver: authServices.externalRestaurantLinkAPI)
    }

    @ViewBuilder
    private var activeView: some View {
        switch selectedTab {
        case .map:
            MapHomeView()
        case .discover:
            DiscoverHubView()
        case .profile:
            ProfileView()
        }
    }
}

private struct TasteMapBottomNavigationHiddenPreferenceKey: PreferenceKey {
    static let defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension View {
    func tasteMapBottomNavigationHidden(_ hidden: Bool = true) -> some View {
        preference(key: TasteMapBottomNavigationHiddenPreferenceKey.self, value: hidden)
    }
}

private enum DiscoverHubSection: String, CaseIterable, Identifiable {
    case discovery = "发现餐厅"
    case community = "社区动态"
    var id: Self { self }
}

struct DiscoverHubView: View {
    @State private var section: DiscoverHubSection = .discovery

    var body: some View {
        VStack(spacing: 0) {
            Picker("发现与社区", selection: $section) {
                ForEach(DiscoverHubSection.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
            if section == .discovery { DiscoveryView() }
            else { CommunityFeedView() }
        }
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case map
    case discover
    case profile

    var id: Self { self }

    var title: String {
        switch self {
        case .map: "地图"
        case .discover: "发现"
        case .profile: "我的"
        }
    }

    var systemImage: String {
        switch self {
        case .map: "map"
        case .discover: "globe.asia.australia"
        case .profile: "person"
        }
    }

    var selectedSystemImage: String {
        switch self {
        case .map: "map.fill"
        case .discover: "globe.asia.australia.fill"
        case .profile: "person.fill"
        }
    }
}
