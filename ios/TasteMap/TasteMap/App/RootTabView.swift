import SwiftData
import SwiftUI

struct RootTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Environment(NativeAuthServices.self) private var authServices
    @Environment(\.localAccountScope) private var accountScope
    @Query private var restaurants: [Restaurant]
    @State private var selectedTab: AppTab
    @State private var isShowingSearch = false
    @State private var requestedVisitCandidate: RestaurantCandidate?
    @State private var visitCandidate: RestaurantCandidate?
    @State private var isBottomNavigationHidden = false
    @State private var pendingSharedImport: PendingRestaurantImport?
    @State private var publicShareRoute: PublicShareRouteSelection?

    init() {
#if DEBUG
        _selectedTab = State(initialValue: TasteMapUITestFixtures.coreParityInitialTab ?? .map)
#else
        _selectedTab = State(initialValue: .map)
#endif
    }

    private var scopedRestaurants: [Restaurant] {
        restaurants.filter { accountScope.contains(ownerUserID: $0.ownerUserID) }
    }

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
                presentRequestedVisitAfterAcquisitionDismissal()
            }) {
                AddRestaurantView(
                    dependencies: acquisitionDependencies
                ) { candidate, action in
                    switch action {
                    case .wantToGo:
                        _ = try LocalTasteMapStore(context: modelContext).addToWantToGo(
                            candidate: candidate,
                            among: scopedRestaurants,
                            actorUserID: accountScope.ownerUserID
                        )
                        selectedTab = .map
                    case .recordVisit:
                        requestedVisitCandidate = candidate
                    }
                }
            }
            .sheet(item: $pendingSharedImport, onDismiss: {
                presentRequestedVisitAfterAcquisitionDismissal()
            }) { pending in
                AddRestaurantView(
                    dependencies: acquisitionDependencies,
                    initialSharedText: pending.acquisitionText
                ) { candidate, action in
                    switch action {
                    case .wantToGo:
                        _ = try LocalTasteMapStore(context: modelContext).addToWantToGo(
                            candidate: candidate,
                            among: scopedRestaurants,
                            actorUserID: accountScope.ownerUserID
                        )
                        selectedTab = .map
                    case .recordVisit:
                        requestedVisitCandidate = candidate
                    }
                    try PendingRestaurantImportStore.live().consume(id: pending.id)
                }
            }
            .sheet(item: $visitCandidate) { candidate in
                VisitEditorView(candidate: candidate, onSaved: { _ in
                    selectedTab = .map
                })
            }
            .sheet(item: $publicShareRoute) { route in
                PublicShareLandingView(shareID: route.shareID, api: authServices.publicSharingAPI)
            }
            .task { loadPendingSharedImportIfNeeded() }
            .onChange(of: scenePhase) { _, value in
                if value == .active { loadPendingSharedImportIfNeeded() }
            }
            .onOpenURL { url in
                if let shareID = PublicShareRoute.shareID(from: url) {
                    publicShareRoute = PublicShareRouteSelection(shareID: shareID)
                    return
                }
                if url.path.hasPrefix("/share/") { return }
                if let pending = try? PendingRestaurantImportStore.live().enqueue(text: nil, url: url) {
                    pendingSharedImport = pending
                }
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

    private func loadPendingSharedImportIfNeeded() {
        guard pendingSharedImport == nil,
              let store = try? PendingRestaurantImportStore.live() else { return }
        pendingSharedImport = try? store.pending().first
    }

    private func presentRequestedVisitAfterAcquisitionDismissal() {
        guard let requestedVisitCandidate else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            guard self.requestedVisitCandidate?.id == requestedVisitCandidate.id else { return }
            self.requestedVisitCandidate = nil
            visitCandidate = requestedVisitCandidate
        }
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

enum DiscoverHubSection: String, CaseIterable, Identifiable {
    case following
    case forYou
    case similarTaste
    case latest
    case trending

    var id: Self { self }

    var title: String {
        switch self {
        case .following: "关注"
        case .forYou: "为你推荐"
        case .similarTaste: "同味之选"
        case .latest: "最新"
        case .trending: "趋势"
        }
    }

    var discoveryMode: DiscoveryModeV1? {
        switch self {
        case .forYou: .forYou
        case .similarTaste: .similarTaste
        case .trending: .trending
        case .following, .latest: nil
        }
    }

    var communityScope: CommunityFeedScopeV1? {
        switch self {
        case .following: .following
        case .latest: .latest
        case .forYou, .similarTaste, .trending: nil
        }
    }
}

struct DiscoverHubView: View {
    @State private var section: DiscoverHubSection = .forYou

    var body: some View {
        VStack(spacing: 0) {
            discoveryHeader
            discoveryNavigation
            Group {
                if let mode = section.discoveryMode {
                    DiscoveryView(
                        initialMode: mode,
                        showsModePicker: false,
                        showsNavigationTitle: false
                    )
                    .id(section)
                } else if let scope = section.communityScope {
                    CommunityFeedView(
                        initialScope: scope,
                        showsScopePicker: false,
                        showsNavigationTitle: false
                    )
                    .id(section)
                }
            }
        }
        .tasteMapCorePage()
    }

    private var discoveryHeader: some View {
        VStack(spacing: 3) {
            Text("发现")
                .font(.title2.bold())
                .foregroundStyle(TasteMapCoreTheme.textPrimary)
                .accessibilityIdentifier("discovery-header")
            Text("按照你的口味，找到更值得参考的人和下一家餐厅。")
                .font(.caption)
                .foregroundStyle(TasteMapCoreTheme.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(TasteMapCoreTheme.page)
    }

    private var discoveryNavigation: some View {
        TasteMapPrimaryTabBar(
            selection: $section,
            items: DiscoverHubSection.allCases.map {
                .init(
                    $0,
                    title: $0.title,
                    accessibilityIdentifier: "discovery-primary-\($0.rawValue)"
                )
            },
            accessibilityIdentifier: "discovery-primary-tabs"
        )
        .padding(.horizontal, 8)
        .padding(.top, 2)
        .overlay(alignment: .bottom) {
            Rectangle().fill(TasteMapCoreTheme.border).frame(height: 1)
        }
        .background(TasteMapCoreTheme.page)
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
