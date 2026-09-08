import SwiftData
import SwiftUI

struct TasteMapHybridDevelopmentRootView: View {
    @State private var referralReceived = false
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
            .onReceive(NotificationCenter.default.publisher(for: .tasteMapLocalDataDidChange)) { notification in
                runtime.localDataDidChange(
                    reason: notification.userInfo?["reason"] as? String ?? "localDataChanged"
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .tasteMapPremiumEntitlementChanged)) { _ in
                runtime.localDataDidChange(reason: "premiumEntitlementChanged")
            }
            .onReceive(NotificationCenter.default.publisher(for: .tasteMapSyncDidComplete)) { _ in
                runtime.localDataDidChange(reason: "syncCompleted")
            }
            .onOpenURL { url in
                if ReferralInvitationStore.receive(url) { referralReceived = true; return }
                if (try? TasteMapHybridDeepLinkParser.route(from: url)) != nil {
                    runtime.receive(url: url)
                } else if let pending = try? PendingRestaurantImportStore.live().enqueue(text: nil, url: url) {
                    runtime.receive(sharedImport: pending)
                }
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                if let url = activity.webpageURL, ReferralInvitationStore.receive(url) { referralReceived = true }
            }
            .alert("已收到 Taste Map 邀请", isPresented: $referralReceived) { Button("知道了", role: .cancel) {} } message: {
                Text("邀请码已暂存。请前往‘我的’，使用 Apple 登录创建新账号，并完成首次有效到访。已有账号不会重新绑定邀请人。")
            }
    }

    private var nativeRouteBinding: Binding<TasteMapHybridRouteDTO?> {
        Binding(
            get: { runtime.navigation.presentedNativeRoute },
            set: {
                // Explicit Native completions clear the typed route before the
                // SwiftUI sheet reports its own dismissal. Only consume a back
                // step while a Native route is still present; otherwise the
                // second callback would also pop the underlying Hybrid page.
                if $0 == nil, runtime.navigation.presentedNativeRoute != nil {
                    runtime.localDataDidChange(reason: "nativePresentationDismissed")
                    runtime.navigation.dismissNativePresentation()
                }
            }
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

    @ViewBuilder
    var body: some View {
        if route.surface == .socialNative {
            TasteMapHybridNativeSocialRoute(
                identifier: route.identifier,
                onClose: dismissNativePresentation
            )
            .interactiveDismissDisabled(false)
        } else if TasteMapHybridNativeNavigationPolicy.destinationOwnsNavigation(route.surface) {
            // These destinations already own a NavigationStack and an exit action.
            // Wrapping them adds a second back/cancel and can bypass their save lock.
            destination
        } else {
            NavigationStack {
                destination
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            TasteMapReturnButton(action: dismissNativePresentation)
                                .accessibilityLabel("返回")
                        }
                    }
            }
            .interactiveDismissDisabled(false)
        }
    }

    @ViewBuilder
    private var destination: some View {
        switch route.surface {
        case .map:
            MapHomeView()
        case .discovery:
            DiscoverHubView()
        case .add:
            TasteMapHybridNativeAddRoute(onOpenHybrid: dismissNativePresentation)
        case .acquisitionNative:
            TasteMapHybridNativeAddRoute(onOpenHybrid: dismissNativePresentation)
        case .visit:
            TasteMapHybridNativeVisitRoute(identifier: route.identifier)
        case .visitEdit:
            TasteMapHybridNativeVisitEditRoute(
                identifier: route.identifier,
                onSaved: dismissNativePresentation,
                onRestaurantDeleted: { restaurantIDs, visitIDs in
                    runtime.navigation.completeVisitDeletion(restaurantIDs: restaurantIDs, visitIDs: visitIDs)
                }
            )
        case .lists:
            TasteMapHybridNativeListsRoute(identifier: route.identifier)
        case .listManage:
            TasteMapHybridNativeListsRoute(identifier: route.identifier)
        case .roulette:
            RestaurantRouletteScreen()
        case .analytics:
            TasteProfileAnalysisScreen()
        case .premium:
            PremiumPaywallView(source: .profile)
        case .premiumStore:
            PremiumPaywallView(source: .profile)
        case .settings:
            TasteMapHybridNativeSettingsRoute()
        case .settingsNative:
            TasteMapHybridNativeSettingsRoute()
        case .accountSettings:
            TasteMapHybridNativeAccountSettingsRoute()
        case .dataBackup:
            TasteMapHybridNativeDataBackupRoute()
        case .dataClear:
            TasteMapHybridNativeDataClearRoute()
        case .privacySettings:
            TasteMapHybridNativePrivacySettingsRoute()
        case .permissions:
            PermissionsSettingsView(permissionOverride: nil)
        case .storage:
            StorageSettingsView(snapshotOverride: nil)
        case .helpSettings:
            HelpSettingsView(
                supportURL: ReleaseConfiguration.current().legalLinks.supportURL,
                showsConfigurationDiagnostics: false
            )
        case .aboutSettings:
            AboutSettingsView(
                releaseConfiguration: .current(),
                showsConfigurationDiagnostics: false
            )
        case .accountDelete:
            TasteMapHybridNativeAccountDeleteRoute()
        case .socialNative:
            TasteMapHybridNativeSocialRoute(
                identifier: route.identifier,
                onClose: dismissNativePresentation
            )
        case .profileEdit:
            TasteMapHybridNativeProfileEditRoute()
        case .restaurantEdit:
            TasteMapHybridNativeRestaurantEditRoute(identifier: route.identifier)
        case .restaurantDelete:
            TasteMapHybridNativeRestaurantDeleteRoute(identifier: route.identifier, onDeleted: {
                runtime.navigation.completeRestaurantDeletion()
                dismiss()
            })
        case .restaurantAddToList:
            TasteMapHybridNativeRestaurantAddToListRoute(identifier: route.identifier)
        case .restaurantWantToGo:
            TasteMapHybridNativeRestaurantWantToGoRoute(
                identifier: route.identifier,
                onSaved: dismissNativePresentation
            )
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

    private func dismissNativePresentation() {
        // Native routes own several write surfaces (profile/privacy, import,
        // lists and restaurant edits). Reconcile the still-running Hybrid UI
        // whenever one closes so a successful save is never mistaken for a
        // failure that only becomes visible after relaunching the app.
        runtime.localDataDidChange(reason: "nativePresentationDismissed")
        runtime.navigation.dismissNativePresentation()
        dismiss()
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

private struct TasteMapHybridNativeProfileEditRoute: View {
    @Environment(\.localAccountScope) private var accountScope
    @Query private var profiles: [UserProfile]
    @Query private var photos: [PhotoAsset]

    var body: some View {
        if let profile {
            ProfileEditorSheet(profile: profile, avatarPhoto: avatarPhoto)
        } else {
            TasteMapHybridNativeDismissibleFailure(title: "无法编辑个人资料")
        }
    }

    private var profile: UserProfile? {
        profiles.first { accountScope.contains(ownerUserID: $0.tasteMapUserID) && $0.deletedAt == nil }
    }

    private var avatarPhoto: PhotoAsset? {
        guard let id = profile?.avatarPhotoID else { return nil }
        return photos.first {
            accountScope.contains(ownerUserID: $0.ownerUserID)
                && $0.deletedAt == nil
                && ($0.remoteID == id || $0.id.uuidString.caseInsensitiveCompare(id) == .orderedSame)
        }
    }
}

private struct TasteMapHybridNativeAddRoute: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.localAccountScope) private var accountScope
    @Environment(NativeAuthServices.self) private var authServices
    @Environment(TasteMapHybridRuntime.self) private var runtime
    @Query private var restaurants: [Restaurant]
    @State private var requestedVisit: RestaurantCandidate?
    let onOpenHybrid: () -> Void

    var body: some View {
        AddRestaurantView(
            dependencies: .live(linkResolver: authServices.externalRestaurantLinkAPI),
            initialSharedText: runtime.pendingSharedImport?.acquisitionText,
            onCandidateSelected: openCanonicalDetail
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

    private func openCanonicalDetail(_ candidate: RestaurantCandidate) throws {
        guard let ownerUserID = accountScope.authenticatedUserID else {
            throw TasteMapHybridServiceError.authRequired
        }
        let identifier: String
        if let match = RestaurantDeduplicator.classifiedMatch(for: candidate, in: scopedRestaurants),
           match.kind == .exactProviderIdentity {
            identifier = match.restaurant.remoteID ?? match.restaurant.id.uuidString.lowercased()
        } else {
            identifier = try TasteMapHybridRestaurantReferenceResolver.cacheCandidate(
                candidate,
                ownerUserID: ownerUserID,
                context: modelContext
            )
        }
        runtime.consumePendingSharedImport()
        _ = try runtime.navigation.openHybrid(TasteMapHybridRouteDTO(
            surface: .restaurant,
            identifier: identifier
        ))
        onOpenHybrid()
    }
}

private struct TasteMapHybridNativeVisitRoute: View {
    @Environment(\.modelContext) private var modelContext
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
        } else if let reference {
            VisitEditorView(candidate: reference.projection.restaurantCandidate)
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

    private var reference: TasteMapHybridResolvedRestaurantReference? {
        guard let identifier, let ownerUserID = accountScope.authenticatedUserID else { return nil }
        return try? TasteMapHybridRestaurantReferenceResolver.resolve(
            identifier: identifier,
            ownerUserID: ownerUserID,
            context: modelContext
        )
    }
}

private struct TasteMapHybridNativeSocialRoute: View {
    @Environment(\.localAccountScope) private var accountScope
    @Environment(NativeAuthServices.self) private var authServices
    let identifier: String?
    let onClose: () -> Void

    var body: some View {
        if let userID = accountScope.authenticatedUserID {
            SocialHubView(
                currentUserID: userID,
                api: authServices.socialAPI,
                communityAPI: authServices.communityAPI,
                collaborationAPI: authServices.socialCollaborationAPI,
                interactionAPI: authServices.socialCollaborationAPI,
                safetyAPI: authServices.releaseSafetyAPI,
                photoAPI: authServices.photoAPI,
                restaurantListAPI: authServices.restaurantListAPI,
                initialSection: initialSection,
                initialSuggestions: initialSuggestions,
                navigationTitle: "好友与关注",
                onClose: onClose
            )
        } else {
            TasteMapEmptyState(
                title: "需要登录",
                message: "请先完成 Taste Map 登录，再搜索和添加好友。",
                systemImage: "person.2.badge.plus",
                presentation: .embedded,
                accessibilityIdentifier: "hybrid-social-auth-required"
            )
        }
    }

    private var initialSection: SocialHubSection {
        switch identifier {
        case "following": .following
        case "followers": .followers
        default: .recommendations
        }
    }

    private var initialSuggestions: [SocialSuggestionV1] {
#if DEBUG
        TasteMapUITestFixtures.socialSuggestions
#else
        []
#endif
    }
}

private struct TasteMapHybridNativeVisitEditRoute: View {
    @Environment(\.localAccountScope) private var accountScope
    @Query private var restaurants: [Restaurant]
    @Query private var visits: [Visit]
    let identifier: String?
    let onSaved: () -> Void
    let onRestaurantDeleted: (Set<String>, Set<String>) -> Void

    var body: some View {
        if let visit = editableVisit,
           let restaurant = restaurants.first(where: {
               accountScope.contains(ownerUserID: $0.ownerUserID)
                   && $0.deletedAt == nil
                   && $0.id == visit.restaurantId
           }) {
            let restaurantIDs = Set([restaurant.id.uuidString.lowercased(), restaurant.remoteID?.lowercased()].compactMap { $0 })
            let visitIDs = Set([visit.id.uuidString.lowercased(), visit.remoteID?.lowercased()].compactMap { $0 })
            VisitEditorView(restaurant: restaurant, visit: visit, onSaved: { _ in
                // VisitEditor owns the existing SwiftData/mutation-queue write.
                // The Hybrid host only closes the typed Native handoff so React
                // receives the canonical Restaurant route and refetches detail.
                onSaved()
            }, onRestaurantDeleted: { _ in
                onRestaurantDeleted(restaurantIDs, visitIDs)
            })
                .accessibilityIdentifier("hybrid-native-visit-edit-route")
        } else {
            TasteMapEmptyState(
                title: "无法编辑这次到访",
                message: "只有当前账户自己的到访记录可以编辑。",
                systemImage: "lock.shield",
                presentation: .embedded,
                accessibilityIdentifier: "hybrid-visit-edit-not-authorized"
            )
        }
    }

    private var editableVisit: Visit? {
        visits.first(where: {
            accountScope.contains(ownerUserID: $0.ownerUserID)
                && $0.deletedAt == nil
                && ($0.remoteID == identifier
                    || $0.id.uuidString.caseInsensitiveCompare(identifier ?? "") == .orderedSame)
        })
    }
}

private struct TasteMapHybridNativeListsRoute: View {
    @Environment(\.localAccountScope) private var accountScope
    @Environment(NativeAuthServices.self) private var authServices
    let identifier: String?

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

private struct TasteMapHybridNativeRestaurantEditRoute: View {
    @Environment(\.localAccountScope) private var accountScope
    @Query private var restaurants: [Restaurant]
    let identifier: String?

    var body: some View {
        if let restaurant = ownedRestaurant {
            RestaurantEditView(restaurant: restaurant)
        } else {
            TasteMapHybridNativeDismissibleFailure(title: "无法编辑这家餐厅")
        }
    }

    private var ownedRestaurant: Restaurant? {
        restaurants.first(where: {
            accountScope.contains(ownerUserID: $0.ownerUserID)
                && $0.deletedAt == nil
                && ($0.remoteID == identifier || $0.id.uuidString.caseInsensitiveCompare(identifier ?? "") == .orderedSame)
        })
    }
}

private struct TasteMapHybridNativeRestaurantAddToListRoute: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.localAccountScope) private var accountScope
    @Query private var restaurants: [Restaurant]
    let identifier: String?

    var body: some View {
        if let userID = accountScope.authenticatedUserID {
            if let restaurant = ownedRestaurant {
                AddRestaurantToListsSheet(restaurant: restaurant, currentUserID: userID)
            } else if let reference {
                AddPlaceToListsSheet(place: reference.projection, currentUserID: userID)
            } else {
                TasteMapHybridNativeDismissibleFailure(title: "无法把这家餐厅加入食单")
            }
        } else {
            TasteMapHybridNativeDismissibleFailure(title: "无法把这家餐厅加入食单")
        }
    }

    private var ownedRestaurant: Restaurant? {
        restaurants.first(where: {
            accountScope.contains(ownerUserID: $0.ownerUserID)
                && $0.deletedAt == nil
                && ($0.remoteID == identifier || $0.id.uuidString.caseInsensitiveCompare(identifier ?? "") == .orderedSame)
        })
    }


    private var reference: TasteMapHybridResolvedRestaurantReference? {
        guard let identifier, let ownerUserID = accountScope.authenticatedUserID else { return nil }
        return try? TasteMapHybridRestaurantReferenceResolver.resolve(
            identifier: identifier,
            ownerUserID: ownerUserID,
            context: modelContext
        )
    }
}

private struct TasteMapHybridNativeRestaurantWantToGoRoute: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.localAccountScope) private var accountScope
    @Query private var restaurants: [Restaurant]
    @State private var state: SaveState = .saving
    let identifier: String?
    let onSaved: () -> Void

    private enum SaveState { case saving, failed }

    var body: some View {
        Group {
            switch state {
            case .saving:
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在加入想吃").font(.headline)
                }
                .task { save() }
            case .failed:
                TasteMapEmptyState(
                    title: "没有加入想吃",
                    message: "这家餐厅已不在当前账户可见的正式来源中，请返回后刷新。",
                    systemImage: "bookmark.slash",
                    presentation: .embedded,
                    accessibilityIdentifier: "hybrid-want-to-go-failed"
                )
            }
        }
    }

    private func save() {
        guard let identifier,
              let ownerUserID = accountScope.authenticatedUserID,
              let reference = try? TasteMapHybridRestaurantReferenceResolver.resolve(
                  identifier: identifier,
                  ownerUserID: ownerUserID,
                  context: modelContext
              ) else {
            state = .failed
            return
        }
        do {
            _ = try LocalDiscoveryStore(context: modelContext).addToWantToGo(
                projection: reference.projection,
                among: restaurants.filter { accountScope.contains(ownerUserID: $0.ownerUserID) },
                currentUserID: ownerUserID
            )
            try LocalDiscoveryStore(context: modelContext).updateViewerState(
                globalKey: reference.projection.globalKey,
                currentUserID: ownerUserID,
                state: .wantToGo
            )
            try LocalCommunityStore(context: modelContext).updateViewerState(
                globalKey: reference.projection.globalKey,
                currentUserID: ownerUserID,
                state: .wantToGo
            )
            onSaved()
        } catch {
            state = .failed
        }
    }
}

private struct TasteMapHybridNativeRestaurantDeleteRoute: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.localAccountScope) private var accountScope
    @Query private var restaurants: [Restaurant]
    @State private var errorMessage: String?
    let identifier: String?
    let onDeleted: () -> Void

    var body: some View {
        if let restaurant = ownedRestaurant {
            VStack(spacing: 16) {
                FoodDiningVisualIcon(kind: .receipt, usage: .decorative, size: 56)
                Text("删除这家餐厅？").font(.title3.weight(.semibold))
                Text(RestaurantDeletionPresentation.restaurantMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("删除餐厅及其记录", role: .destructive) {
                    do {
                        try LocalTasteMapStore(context: modelContext).delete(
                            restaurant,
                            actorUserID: accountScope.authenticatedUserID
                        )
                        onDeleted()
                    } catch {
                        errorMessage = "当前账户无权删除，或删除没有完成。现有记录已保留。"
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .accessibilityIdentifier("hybrid-restaurant-delete-confirm")
            }
            .padding(24)
            .alert("无法删除", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) { Button("好", role: .cancel) {} } message: { Text(errorMessage ?? "请稍后重试。") }
        } else {
            unauthorized("无法删除这家餐厅")
        }
    }

    private var ownedRestaurant: Restaurant? {
        restaurants.first(where: {
            accountScope.contains(ownerUserID: $0.ownerUserID)
                && $0.deletedAt == nil
                && ($0.remoteID == identifier || $0.id.uuidString.caseInsensitiveCompare(identifier ?? "") == .orderedSame)
        })
    }
}

/// The same presentation owner also supplies an exit when data is unavailable.
private struct TasteMapHybridNativeDismissibleFailure: View {
    @Environment(\.dismiss) private var dismiss
    let title: String

    var body: some View {
        NavigationStack {
            unauthorized(title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        TasteMapReturnButton { dismiss() }
                    }
                }
        }
    }
}

@ViewBuilder
private func unauthorized(_ title: String) -> some View {
    TasteMapEmptyState(
        title: title,
        message: "只有当前账户自己的记录可以执行这个操作。",
        systemImage: "lock.shield",
        presentation: .embedded,
        accessibilityIdentifier: "hybrid-native-owner-authorization-failed"
    )
}

private struct TasteMapHybridNativeAccountSettingsRoute: View {
    @Environment(TasteMapHybridRuntime.self) private var runtime
    @Environment(\.localAccountScope) private var accountScope
    @Query private var profiles: [UserProfile]
    @Query private var photos: [PhotoAsset]
    @State private var user: AuthenticatedUserV1?

    var body: some View {
        AccountSettingsView(
            authenticatedUser: authenticatedUser,
            profile: profile,
            avatarPhoto: avatar,
            logoutAction: SettingsLogoutAction(perform: { await runtime.logoutFromNative() }),
            accountDeletedAction: SettingsAccountDeletedAction(perform: {
                await runtime.accountDeletionDidComplete()
            })
        )
        .task { user = await runtime.restoredUser() }
    }

    private var authenticatedUser: AuthenticatedUserV1? {
        if let user { return user }
        guard let userID = accountScope.authenticatedUserID else { return nil }
        return AuthenticatedUserV1(id: userID, email: nil)
    }

    private var profile: UserProfile? {
        profiles.first { accountScope.contains(ownerUserID: $0.tasteMapUserID) && $0.deletedAt == nil }
    }

    private var avatar: PhotoAsset? {
        guard let id = profile?.avatarPhotoID else { return nil }
        return photos.first { ($0.remoteID ?? $0.id.uuidString.lowercased()) == id && $0.deletedAt == nil }
    }
}

private struct TasteMapHybridNativePrivacySettingsRoute: View {
    @Environment(\.localAccountScope) private var accountScope
    @Query private var profiles: [UserProfile]
    @Query private var photos: [PhotoAsset]

    var body: some View {
        PrivacySettingsView(
            profile: profile,
            avatarPhoto: avatar,
            releaseConfiguration: .current(),
            showsConfigurationDiagnostics: false
        )
    }

    private var profile: UserProfile? {
        profiles.first { accountScope.contains(ownerUserID: $0.tasteMapUserID) && $0.deletedAt == nil }
    }

    private var avatar: PhotoAsset? {
        guard let id = profile?.avatarPhotoID else { return nil }
        return photos.first { ($0.remoteID ?? $0.id.uuidString.lowercased()) == id && $0.deletedAt == nil }
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
            logoutAction: SettingsLogoutAction(perform: { await runtime.logoutFromNative() }),
            localDataClearedAction: SettingsLocalDataClearedAction(perform: { _ in
                runtime.localDataDidClear()
            })
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

private struct TasteMapHybridNativeDataBackupRoute: View {
    @Environment(TasteMapHybridRuntime.self) private var runtime
    @State private var user: AuthenticatedUserV1?

    var body: some View {
        DataBackupSettingsView(
            isAuthenticated: user != nil,
            currentTasteMapUserID: user?.id,
            allowsImport: true
        )
        .task { user = await runtime.restoredUser() }
    }
}

private struct TasteMapHybridNativeDataClearRoute: View {
    @Environment(TasteMapHybridRuntime.self) private var runtime
    @Environment(\.localAccountScope) private var accountScope

    var body: some View {
        Group {
            if let userID {
                ClearLocalDataView(
                    currentUserID: userID,
                    completionAction: SettingsLocalDataClearedAction(perform: { _ in
                        runtime.localDataDidClear()
                    })
                )
            } else {
                unauthorized("登录后才能清除本机数据")
            }
        }
    }

    private var userID: String? {
        if case .authenticated(let userID) = accountScope { return userID }
        return nil
    }
}

private struct TasteMapHybridNativeAccountDeleteRoute: View {
    @Environment(TasteMapHybridRuntime.self) private var runtime
    @State private var user: AuthenticatedUserV1?

    var body: some View {
        Group {
            if let user {
                AccountDeletionView(
                    currentUserID: user.id,
                    completionAction: SettingsAccountDeletedAction(perform: {
                        await runtime.accountDeletionDidComplete()
                    })
                )
            } else {
                unauthorized("登录后才能删除账户")
            }
        }
        .task { user = await runtime.restoredUser() }
    }
}
