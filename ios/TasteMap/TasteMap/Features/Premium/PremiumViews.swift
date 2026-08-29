import SwiftUI

struct PremiumFeatureGate<Content: View>: View {
    @Environment(PremiumEntitlementService.self) private var entitlementService
    let feature: PremiumFeature
    private let content: () -> Content

    init(feature: PremiumFeature, @ViewBuilder content: @escaping () -> Content) {
        self.feature = feature
        self.content = content
    }

    var body: some View {
        switch entitlementService.access(for: feature, operation: .view) {
        case .allowed:
            content()
        case .denied:
            PremiumFeatureLockedView(feature: feature)
        case .loading:
            PremiumEntitlementLoadingView(feature: feature)
        }
    }
}

struct PremiumFeatureLockedView: View {
    @Environment(PremiumEntitlementService.self) private var entitlementService
    let feature: PremiumFeature

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                PremiumFoodMotif()
                    .frame(height: 156)
                VStack(spacing: 8) {
                    PremiumBadge()
                    Text(feature.definition.title)
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                    Text(feature.definition.valueDescription)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
                VStack(alignment: .leading, spacing: 11) {
                    Label("你的 Restaurant、Visit 和历史数据会继续正常保存", systemImage: "checkmark.circle.fill")
                    Label("开通后会直接基于完整历史生成，不会从零开始", systemImage: "clock.arrow.circlepath")
                }
                .font(.subheadline)
                .foregroundStyle(PremiumTheme.ink)
                .padding(18)
                .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                Button {
                    entitlementService.openPaywall(from: .feature(feature))
                } label: {
                    Label("查看 Taste Map Premium", systemImage: "arrow.right")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(PremiumTheme.brand)
                .accessibilityIdentifier("premium-feature-gate-open-paywall")
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 28)
        }
        .background(PremiumTheme.canvas.ignoresSafeArea())
        .navigationTitle(feature.definition.title)
        .navigationBarTitleDisplayMode(.inline)
        .tasteMapBottomNavigationHidden()
        .accessibilityIdentifier("premium-feature-gate-\(feature.rawValue)")
    }
}

private struct PremiumEntitlementLoadingView: View {
    @Environment(PremiumEntitlementService.self) private var entitlementService
    let feature: PremiumFeature

    var body: some View {
        ContentUnavailableView {
            Label("正在确认会员权益", systemImage: "checkmark.seal")
        } description: {
            Text(entitlementService.lastErrorMessage ?? "不会先显示免费页面再突然切换状态。")
        } actions: {
            if entitlementService.activeUserID != nil {
                Button("重试") { Task { await entitlementService.refresh() } }
                    .buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle(feature.definition.title)
        .navigationBarTitleDisplayMode(.inline)
        .tasteMapBottomNavigationHidden()
        .accessibilityIdentifier("premium-feature-loading-\(feature.rawValue)")
    }
}

struct PremiumPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PremiumEntitlementService.self) private var entitlementService
    let source: PremiumEntrySource

    @State private var products: [MembershipProduct] = []
    @State private var selectedProductID: String?
    @State private var isLoadingProducts = false
    @State private var actionInProgress = false
    @State private var message: String?
    @State private var productsLoaded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 22) {
                    hero
                    statusSummary
                    benefits
                    comparison
                    if entitlementService.membershipStatus == .premium ||
                        entitlementService.membershipStatus == .gracePeriod {
                        activeMemberActions
                    } else {
                        productSection
                    }
                    dataOwnershipNote
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
            }
            .background(PremiumTheme.canvas.ignoresSafeArea())
            .navigationTitle("Taste Map Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        entitlementService.dismissPaywall()
                        dismiss()
                    }
                    .accessibilityIdentifier("premium-paywall-close")
                }
            }
            .task { await loadProductsIfNeeded() }
        }
        // The Premium visual system is deliberately a light, food-first surface.
        // Keep it legible when the device uses Dark Mode instead of mixing white
        // cards with system-dark primary text colors.
        .environment(\.colorScheme, .light)
        .accessibilityIdentifier("premium-paywall")
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            PremiumFoodMotif().frame(height: 132)
            VStack(alignment: .leading, spacing: 8) {
                Text("TASTE MAP PREMIUM")
                    .font(.caption2.bold()).tracking(1.7)
                    .foregroundStyle(PremiumTheme.brand)
                Text("把长期记录，变成更懂你的分析。")
                    .font(.largeTitle.bold())
                    .foregroundStyle(PremiumTheme.ink)
                Text(source.contextCopy)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            LinearGradient(
                colors: [.white, PremiumTheme.brandSoft, PremiumTheme.cream],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 30, style: .continuous)
        )
    }

    @ViewBuilder
    private var statusSummary: some View {
        switch entitlementService.membershipStatus {
        case .loading, .unknown:
            HStack(spacing: 12) {
                ProgressView().tint(PremiumTheme.brand)
                VStack(alignment: .leading, spacing: 3) {
                    Text("正在确认会员状态").font(.headline)
                    Text(entitlementService.lastErrorMessage ?? "确认期间不会先降级你的本地权益。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .premiumStatusCard()
        case .premium, .gracePeriod:
            HStack(spacing: 12) {
                PremiumBurgerBadge().frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Taste Map Premium 已开通").font(.headline)
                    Text(memberStatusText).font(.caption).foregroundStyle(.secondary)
                    if entitlementService.isUsingOfflineCache {
                        Label("离线使用最近已验证的会员权益", systemImage: "wifi.slash")
                            .font(.caption2).foregroundStyle(PremiumTheme.brand)
                    }
                }
                Spacer()
            }
            .premiumStatusCard()
            .accessibilityIdentifier("premium-status-active")
        case .free:
            Label("当前为免费版，核心记录功能保持完整。", systemImage: "checkmark.circle.fill")
                .premiumStatusCard()
                .accessibilityIdentifier("premium-status-free")
        case .expired:
            Label("Premium 权益已到期；你的历史记录和照片不会被删除。", systemImage: "clock.badge.exclamationmark")
                .premiumStatusCard()
                .accessibilityIdentifier("premium-status-expired")
        }
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("更完整地理解自己的饮食生活")
                .font(.title3.bold()).foregroundStyle(PremiumTheme.ink)
            ForEach(PremiumFeatureRegistry.paywallHighlights) { feature in
                HStack(alignment: .top, spacing: 13) {
                    Image(systemName: feature.definition.symbol)
                        .font(.headline)
                        .foregroundStyle(PremiumTheme.brand)
                        .frame(width: 38, height: 38)
                        .background(PremiumTheme.brandSoft, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(feature.definition.title).font(.headline)
                        Text(feature.definition.valueDescription)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var comparison: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("免费版与 Premium")
                .font(.headline).padding(.bottom, 10)
            comparisonRow("Restaurant、Visit、想吃", free: "包含", premium: "包含")
            comparisonRow("基础个性化推荐", free: "包含", premium: "深度解释")
            comparisonRow("每次到访照片", free: "3 张", premium: "20 张")
            comparisonRow("完整分析与回顾", free: "预览", premium: "完整")
        }
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder
    private var productSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("开通方案").font(.headline)
            Text("价格只会由 App Store 按你的地区和币种提供。")
                .font(.caption).foregroundStyle(.secondary)
            if isLoadingProducts {
                HStack { ProgressView(); Text("正在获取 App Store 方案…") }
                    .frame(maxWidth: .infinity, minHeight: 70)
            } else if products.isEmpty {
                ContentUnavailableView(
                    "订阅方案暂时不可用",
                    systemImage: "cart.badge.questionmark",
                    description: Text("当前不会显示假价格或无法完成的购买按钮。")
                )
                .frame(minHeight: 150)
                .accessibilityIdentifier("premium-no-store-products")
#if DEBUG
                if entitlementService.developmentOverrideAvailable,
                   entitlementService.activeUserID != nil {
                    Button {
                        _ = entitlementService.setDevelopmentOverride(.premium)
                        message = "已启用仅限 Development 的测试 Premium。"
                    } label: {
                        Label("启用测试 Premium", systemImage: "wrench.and.screwdriver")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("premium-development-enable")
                }
#endif
            } else {
                ForEach(products) { product in
                    Button { selectedProductID = product.id } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(product.displayName).font(.headline)
                                Text(product.valueDescription).font(.caption).foregroundStyle(.secondary)
                                if !product.billingPeriodDescription.isEmpty {
                                    Text(product.billingPeriodDescription)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(product.displayPrice).font(.headline).foregroundStyle(PremiumTheme.brand)
                        }
                        .padding(15)
                        .background(
                            selectedProductID == product.id ? PremiumTheme.brandSoft : Color(uiColor: .secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 18)
                        )
                    }
                    .buttonStyle(.plain)
                }
                if entitlementService.productsProvider.capabilities.contains(.purchase),
                   let selectedProductID {
                    Button("开通 Premium") { Task { await purchase(productID: selectedProductID) } }
                        .buttonStyle(.borderedProminent).tint(PremiumTheme.brand)
                        .disabled(actionInProgress)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("premium-purchase")
                }
            }
            if entitlementService.productsProvider.capabilities.contains(.restore) {
                Button("恢复购买") { Task { await restore() } }
                    .disabled(actionInProgress)
                    .accessibilityIdentifier("premium-restore")
            }
            if let message {
                Text(message).font(.footnote).foregroundStyle(PremiumTheme.brandDeep)
                    .accessibilityIdentifier("premium-action-message")
            }
            legalLinks
        }
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder
    private var activeMemberActions: some View {
        VStack(spacing: 12) {
            if entitlementService.snapshot?.source?.isAppStoreSubscription == true,
               entitlementService.productsProvider.capabilities.contains(.manageSubscription) {
                Button("管理 App Store 订阅") { Task { await manageSubscription() } }
                    .buttonStyle(.borderedProminent).tint(PremiumTheme.brand)
                    .accessibilityIdentifier("premium-manage-subscription")
            }
            if entitlementService.productsProvider.capabilities.contains(.restore) {
                Button("恢复购买") { Task { await restore() } }
                    .disabled(actionInProgress)
                    .accessibilityIdentifier("premium-restore")
            }
            if let message {
                Text(message).font(.footnote).foregroundStyle(PremiumTheme.brandDeep)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var dataOwnershipNote: some View {
        Text("Premium 只控制功能访问，不会改变餐厅、到访、菜品、照片或社交隐私的所有权。到期或退出不会删除你的数据。")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
    }

    @ViewBuilder
    private var legalLinks: some View {
        let links = ReleaseConfiguration.current().legalLinks
        if links.termsOfServiceURL != nil || links.privacyPolicyURL != nil {
            HStack(spacing: 18) {
                if let terms = links.termsOfServiceURL {
                    Link("服务条款", destination: terms)
                }
                if let privacy = links.privacyPolicyURL {
                    Link("隐私政策", destination: privacy)
                }
            }
            .font(.caption)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .contain)
        }
    }

    private func comparisonRow(_ title: String, free: String, premium: String) -> some View {
        HStack(spacing: 8) {
            Text(title).frame(maxWidth: .infinity, alignment: .leading)
            Text(free).frame(width: 62)
            Text(premium).foregroundStyle(PremiumTheme.brand).frame(width: 76)
        }
        .font(.caption)
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Divider() }
    }

    private var memberStatusText: String {
        guard let snapshot = entitlementService.snapshot else { return "会员权益已验证" }
        let source = switch snapshot.source {
        case .appStoreMonthly: "App Store 月度方案"
        case .appStoreYearly: "App Store 年度方案"
        case .appStoreLifetime: "App Store 永久方案"
        case .adminGrant: "赠送资格"
        case .promo: "活动资格"
        case .redeemCode: "兑换资格"
        case .development: "Development 测试资格"
        case nil: "会员资格"
        }
        if snapshot.isLifetime { return "\(source) · 长期有效" }
        if let expiresAt = snapshot.expiresAt {
            return "\(source) · 有效期至 \(expiresAt.formatted(date: .abbreviated, time: .omitted))"
        }
        return source
    }

    @MainActor
    private func loadProductsIfNeeded() async {
        guard !productsLoaded,
              entitlementService.membershipStatus != .premium,
              entitlementService.membershipStatus != .gracePeriod else { return }
        productsLoaded = true
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            products = try await entitlementService.productsProvider.products()
            selectedProductID = products.first(where: { $0.period == .annual })?.id ?? products.first?.id
        } catch {
            products = []
            message = error.localizedDescription
        }
    }

    @MainActor
    private func purchase(productID: String) async {
        actionInProgress = true
        defer { actionInProgress = false }
        do {
            let result = try await entitlementService.productsProvider.purchase(productID: productID)
            if result.requiresEntitlementRefresh { await entitlementService.refresh() }
            message = switch result.outcome {
            case .completed: "购买已由服务器验证，会员状态已刷新。"
            case .pending: "购买正在等待批准，完成后会自动更新。"
            case .userCancelled: "已取消购买。"
            }
        } catch { message = error.localizedDescription }
    }

    @MainActor
    private func restore() async {
        actionInProgress = true
        defer { actionInProgress = false }
        do {
            let result = try await entitlementService.productsProvider.restore()
            if result.requiresEntitlementRefresh { await entitlementService.refresh() }
            message = "购买已恢复并由服务器重新验证。"
        } catch { message = error.localizedDescription }
    }

    @MainActor
    private func manageSubscription() async {
        do { try await entitlementService.productsProvider.manageSubscription() }
        catch { message = error.localizedDescription }
    }
}

struct PremiumBadge: View {
    var body: some View {
        HStack(spacing: 5) {
            PremiumBurgerBadge().frame(width: 18, height: 18)
            Text("Premium").font(.caption2.bold())
        }
        .foregroundStyle(PremiumTheme.brandDeep)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(PremiumTheme.brandSoft, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Taste Map Premium")
    }
}

struct PremiumFeatureInlineBadge: View {
    @Environment(PremiumEntitlementService.self) private var entitlementService
    let feature: PremiumFeature

    var body: some View {
        if entitlementService.access(for: feature) == .denied {
            Text("Premium")
                .font(.caption2.bold())
                .foregroundStyle(PremiumTheme.brandDeep)
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(PremiumTheme.brandSoft, in: Capsule())
                .accessibilityLabel("Premium 功能")
        }
    }
}

struct PremiumBurgerBadge: View {
    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            VStack(spacing: size * 0.035) {
                Capsule().fill(PremiumTheme.bun).frame(height: size * 0.3)
                Capsule().fill(PremiumTheme.leaf).frame(height: size * 0.13)
                Capsule().fill(PremiumTheme.patty).frame(height: size * 0.17)
                Capsule().fill(PremiumTheme.bun).frame(height: size * 0.22)
            }
            .padding(size * 0.12)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Taste Map Premium")
    }
}

private struct PremiumFoodMotif: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(PremiumTheme.cream)
                Circle().fill(.white).frame(width: min(proxy.size.width, proxy.size.height) * 0.68)
                    .shadow(color: PremiumTheme.brand.opacity(0.1), radius: 16, y: 8)
                Text("🍣  🥗\n  🍲  🍰")
                    .font(.system(size: min(proxy.size.width, proxy.size.height) * 0.19))
                    .multilineTextAlignment(.center)
                    .rotationEffect(.degrees(-4))
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title3.bold()).foregroundStyle(PremiumTheme.brand)
                    .padding(10).background(.white, in: Circle())
                    .position(x: proxy.size.width * 0.82, y: proxy.size.height * 0.24)
                Image(systemName: "receipt")
                    .font(.title3.bold()).foregroundStyle(PremiumTheme.caramel)
                    .padding(10).background(.white, in: Circle())
                    .position(x: proxy.size.width * 0.16, y: proxy.size.height * 0.75)
            }
        }
        .accessibilityHidden(true)
    }
}

private enum PremiumTheme {
    static let brand = Color(red: 80 / 255, green: 108 / 255, blue: 140 / 255)
    static let brandDeep = Color(red: 52 / 255, green: 79 / 255, blue: 105 / 255)
    static let brandSoft = Color(red: 232 / 255, green: 240 / 255, blue: 246 / 255)
    static let canvas = Color(red: 249 / 255, green: 248 / 255, blue: 244 / 255)
    static let cream = Color(red: 247 / 255, green: 240 / 255, blue: 224 / 255)
    static let bun = Color(red: 231 / 255, green: 184 / 255, blue: 94 / 255)
    static let leaf = Color(red: 121 / 255, green: 166 / 255, blue: 110 / 255)
    static let patty = Color(red: 164 / 255, green: 93 / 255, blue: 66 / 255)
    static let caramel = Color(red: 173 / 255, green: 117 / 255, blue: 60 / 255)
    static let ink = Color(red: 35 / 255, green: 44 / 255, blue: 50 / 255)
}

private extension View {
    func premiumStatusCard() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
