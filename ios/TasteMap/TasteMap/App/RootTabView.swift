import SwiftData
import SwiftUI

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var restaurants: [Restaurant]
    @State private var selectedTab: AppTab = .map
    @State private var isShowingSearch = false
    @State private var pendingCandidate: RestaurantCandidate?
    @State private var isShowingVisitEditor = false

    var body: some View {
        activeView
            .safeAreaInset(edge: .bottom, spacing: 0) {
                TasteMapBottomNavigation(
                    selection: $selectedTab,
                    onAddRestaurant: { isShowingSearch = true }
                )
            }
            .sheet(isPresented: $isShowingSearch, onDismiss: {
                if pendingCandidate != nil {
                    isShowingVisitEditor = true
                }
            }) {
                RestaurantSearchView { candidate, action in
                    switch action {
                    case .wantToGo:
                        _ = try LocalTasteMapStore(context: modelContext).addToWantToGo(
                            candidate: candidate,
                            among: restaurants
                        )
                        selectedTab = .map
                    case .recordVisit:
                        pendingCandidate = candidate
                    }
                }
            }
            .sheet(isPresented: $isShowingVisitEditor, onDismiss: {
                pendingCandidate = nil
            }) {
                if let pendingCandidate {
                    VisitEditorView(candidate: pendingCandidate) { _ in
                        selectedTab = .map
                    }
                }
            }
    }

    @ViewBuilder
    private var activeView: some View {
        switch selectedTab {
        case .map:
            MapHomeView()
        case .discover:
            DiscoveryView()
        case .profile:
            ProfileView()
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
