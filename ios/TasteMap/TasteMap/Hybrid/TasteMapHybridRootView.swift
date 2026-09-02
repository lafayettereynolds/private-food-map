import SwiftData
import SwiftUI

struct TasteMapHybridDevelopmentRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(TasteMapHybridRuntime.self) private var runtime

    var body: some View {
        TasteMapPersistentHybridController(runtime: runtime)
            .ignoresSafeArea()
            .sheet(item: nativeRouteBinding) { route in
                TasteMapHybridNativeRouteHost(route: route)
                    .environment(runtime)
            }
            .task {
                _ = await runtime.ensureSessionRestored()
                loadPendingSharedImportIfNeeded()
                runtime.handleLifecycle(.foreground)
            }
            .onChange(of: scenePhase) { _, value in
                switch value {
                case .active:
                    runtime.handleLifecycle(.foreground)
                    loadPendingSharedImportIfNeeded()
                case .background: runtime.handleLifecycle(.background)
                case .inactive: break
                @unknown default: break
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                runtime.handleLifecycle(.memoryWarning)
            }
            .onOpenURL { url in
                if (try? TasteMapHybridDeepLinkParser.route(from: url)) != nil {
                    runtime.receive(url: url)
                } else if let pending = try? PendingRestaurantImportStore.live().enqueue(text: nil, url: url) {
                    runtime.receive(sharedImport: pending)
                }
            }
    }

    private var nativeRouteBinding: Binding<TasteMapHybridRouteDTO?> {
        Binding(
            get: { runtime.navigation.presentedNativeRoute },
            set: { if $0 == nil { runtime.navigation.dismissNativePresentation() } }
        )
    }

    private func loadPendingSharedImportIfNeeded() {
#if DEBUG
        guard !TasteMapUITestFixtures.usesVisualQA else { return }
#endif
        guard runtime.pendingSharedImport == nil,
              let store = try? PendingRestaurantImportStore.live(),
              let value = try? store.pending().first else { return }
        runtime.receive(sharedImport: value)
    }
}

private struct TasteMapPersistentHybridController: UIViewControllerRepresentable {
    let runtime: TasteMapHybridRuntime

    func makeUIViewController(context: Context) -> TasteMapHybridBridgeViewController {
        runtime.bridgeController
    }

    func updateUIViewController(_ uiViewController: TasteMapHybridBridgeViewController, context: Context) { }
}

private struct TasteMapHybridNativeRouteHost: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TasteMapHybridRuntime.self) private var runtime
    let route: TasteMapHybridRouteDTO

    var body: some View {
        NavigationStack {
            destination
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("返回") {
                            runtime.navigation.dismissNativePresentation()
                            dismiss()
                        }
                    }
                }
        }
        .interactiveDismissDisabled(false)
    }

    @ViewBuilder
    private var destination: some View {
        switch route.surface {
        case .map:
            MapHomeView()
        case .discovery:
            DiscoverHubView()
        case .add:
            TasteMapHybridNativeAddRoute()
        case .visit:
            TasteMapHybridNativeVisitRoute(identifier: route.identifier)
        case .lists:
            TasteMapHybridNativeListsRoute()
        case .roulette:
            RestaurantRouletteScreen()
        case .analytics:
            TasteProfileAnalysisScreen()
        case .premium:
            PremiumPaywallView(source: .profile)
        case .settings:
            TasteMapHybridNativeSettingsRoute()
        case .activity, .publicList:
            if let identifier = route.identifier {
                PublicShareLandingView(shareID: identifier, api: nativeAuthServices.publicSharingAPI)
            } else {
                unsupported
            }
        case .profile, .restaurant:
            unsupported
        }
    }

    @Environment(NativeAuthServices.self) private var nativeAuthServices

    private var unsupported: some View {
        TasteMapEmptyState(
            title: "此页面暂由原生路径承载",
            message: "路由已安全接收，但缺少有效的页面标识。",
            systemImage: "arrow.triangle.branch",
            presentation: .embedded,
            accessibilityIdentifier: "hybrid-native-route-unsupported"
        )
    }
}

private struct TasteMapHybridNativeAddRoute: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.localAccountScope) private var accountScope
    @Environment(NativeAuthServices.self) private var authServices
    @Environment(TasteMapHybridRuntime.self) private var runtime
    @Query private var restaurants: [Restaurant]
    @State private var requestedVisit: RestaurantCandidate?

    var body: some View {
        AddRestaurantView(
            dependencies: .live(linkResolver: authServices.externalRestaurantLinkAPI),
            initialSharedText: runtime.pendingSharedImport?.acquisitionText
        ) { candidate, action in
            switch action {
            case .wantToGo:
                _ = try LocalTasteMapStore(context: modelContext).addToWantToGo(
                    candidate: candidate,
                    among: scopedRestaurants,
                    actorUserID: accountScope.ownerUserID
                )
            case .recordVisit:
                requestedVisit = candidate
            }
            runtime.consumePendingSharedImport()
        }
        .sheet(item: $requestedVisit) { VisitEditorView(candidate: $0) }
    }

    private var scopedRestaurants: [Restaurant] {
        restaurants.filter { accountScope.contains(ownerUserID: $0.ownerUserID) }
    }
}

private struct TasteMapHybridNativeVisitRoute: View {
    @Environment(\.localAccountScope) private var accountScope
    @Query private var restaurants: [Restaurant]
    let identifier: String?

    var body: some View {
        if let restaurant = restaurants.first(where: {
            accountScope.contains(ownerUserID: $0.ownerUserID)
                && ($0.remoteID == identifier || $0.id.uuidString.caseInsensitiveCompare(identifier ?? "") == .orderedSame)
        }) {
            VisitEditorView(candidate: RestaurantCandidate(
                id: restaurant.id,
                name: restaurant.name,
                address: restaurant.address,
                city: restaurant.city,
                latitude: restaurant.latitude,
                longitude: restaurant.longitude
            ))
        } else {
            TasteMapEmptyState(
                title: "找不到这家餐厅",
                message: "返回后重新选择餐厅。",
                systemImage: "fork.knife",
                foodDiningVisualKind: .genericDining,
                presentation: .embedded,
                accessibilityIdentifier: "hybrid-visit-restaurant-missing"
            )
        }
    }
}

private struct TasteMapHybridNativeListsRoute: View {
    @Environment(\.localAccountScope) private var accountScope
    @Environment(NativeAuthServices.self) private var authServices

    var body: some View {
        if let userID = accountScope.authenticatedUserID {
            RestaurantListsOverviewView(currentUserID: userID, photoAPI: authServices.photoAPI)
        } else {
            TasteMapEmptyState(
                title: "需要登录",
                message: "请先完成 Taste Map 登录，再查看自己的食单。",
                systemImage: "person.crop.circle.badge.exclamationmark",
                presentation: .embedded,
                accessibilityIdentifier: "hybrid-lists-auth-required"
            )
        }
    }
}

private struct TasteMapHybridNativeSettingsRoute: View {
    @Environment(TasteMapHybridRuntime.self) private var runtime
    @Environment(\.localAccountScope) private var accountScope
    @Query private var profiles: [UserProfile]
    @Query private var photos: [PhotoAsset]
    @State private var user: AuthenticatedUserV1?

    var body: some View {
        TasteMapSettingsView(
            authenticatedUser: user,
            profile: profile,
            avatarPhoto: avatar,
            logoutAction: SettingsLogoutAction(perform: { await runtime.logoutFromNative() })
        )
        .task { user = await runtime.restoredUser() }
    }

    private var profile: UserProfile? {
        profiles.first { accountScope.contains(ownerUserID: $0.tasteMapUserID) && $0.deletedAt == nil }
    }

    private var avatar: PhotoAsset? {
        guard let id = profile?.avatarPhotoID else { return nil }
        return photos.first { ($0.remoteID ?? $0.id.uuidString.lowercased()) == id && $0.deletedAt == nil }
    }
}
