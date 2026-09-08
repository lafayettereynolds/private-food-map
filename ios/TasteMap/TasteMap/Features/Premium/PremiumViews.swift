import SwiftUI
import UIKit

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
                .background(TasteMapCoreTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
        TasteMapEmptyState(
            title: "正在确认会员权益",
            message: entitlementService.lastErrorMessage ?? "不会先显示免费页面再突然切换状态。",
            systemImage: "checkmark.seal",
            actionTitle: entitlementService.activeUserID != nil ? "重试" : nil,
            action: entitlementService.activeUserID != nil
                ? { Task { await entitlementService.refresh() } } : nil,
            presentation: .embedded,
            accessibilityIdentifier: "premium-entitlement-state"
        )
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
                    trialSection
                    if entitlementService.membershipStatus == .premium ||
                        entitlementService.membershipStatus == .gracePeriod {
                        activeMemberActions
                    } else {
                        productSection
                    }
                    benefits
                    comparison
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
            .task {
                await entitlementService.refresh()
                await entitlementService.refreshTrialEligibility()
                await loadProductsIfNeeded()
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(60)) } catch { return }
                    await entitlementService.refresh()
                }
            }
        }
        .accessibilityIdentifier("premium-paywall")
    }

    @ViewBuilder
    private var trialSection: some View {
        if entitlementService.trialEligibility?.eligible == true || entitlementService.trialMessage != nil {
            VStack(alignment: .leading, spacing: 10) {
                if entitlementService.trialEligibility?.eligible == true {
                    Text("免费体验 Premium 7 天").font(.headline)
                    Text("无需订阅，不会自动续费").font(.subheadline).foregroundStyle(.secondary)
                    Button {
                        Task { _ = try? await entitlementService.claimTrial() }
                    } label: {
                        Text(entitlementService.isClaimingTrial ? "正在领取…" : "免费领取 7 天")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent).tint(PremiumTheme.brand)
                    .disabled(entitlementService.isClaimingTrial)
                    .accessibilityIdentifier("premium-signup-trial-claim")
                }
                if let message = entitlementService.trialMessage {
                    Text(message).font(.footnote)
                        .accessibilityIdentifier("premium-signup-trial-message")
                }
            }
            .premiumStatusCard()
        }
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 17) {
            PremiumBurgerBadge()
                .frame(width: 76, height: 76)
                .padding(10)
                .background(TasteMapCoreTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: PremiumTheme.brand.opacity(0.12), radius: 12, y: 6)
            VStack(alignment: .leading, spacing: 8) {
                Text("TASTE MAP PREMIUM")
                    .font(.caption2.bold()).tracking(1.7)
                    .foregroundStyle(PremiumTheme.brand)
                Text("把长期记录，变成更懂你的分析。")
                    .font(.title2.bold())
                    .foregroundStyle(PremiumTheme.ink)
                Text(source.contextCopy)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            LinearGradient(
                colors: [TasteMapCoreTheme.surface, PremiumTheme.brandSoft, PremiumTheme.cream],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 30, style: .continuous)
        )
        .accessibilityIdentifier("premium-legacy-hierarchy-hero")
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
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(PremiumFeatureRegistry.paywallHighlights) { feature in
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: feature.definition.symbol)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PremiumTheme.brand)
                            .frame(width: 34, height: 34)
                            .background(PremiumTheme.brandSoft, in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(feature.definition.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)
                            Text(feature.definition.valueDescription)
                                .font(.caption2).foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
                    .padding(10)
                    .background(TasteMapCoreTheme.surfaceSubtle, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .padding(18)
        .background(TasteMapCoreTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityIdentifier("premium-legacy-benefit-grid")
    }

    private var comparison: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("免费版与 Premium")
                .font(.headline).padding(.bottom, 10)
            comparisonRow("Restaurant、Visit、想吃", free: "包含", premium: "包含")
            comparisonRow("基础个性化推荐", free: "包含", premium: "深度解释")
            comparisonRow("每次到访照片", free: "2 张", premium: "20 张")
            comparisonRow("完整分析与回顾", free: "预览", premium: "完整")
        }
        .padding(18)
        .background(TasteMapCoreTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
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
                TasteMapEmptyState(
                    title: "订阅方案暂时不可用",
                    message: "请检查网络后重新加载订阅方案。",
                    systemImage: "cart.badge.questionmark",
                    presentation: .embedded,
                    accessibilityIdentifier: "premium-no-store-products"
                )
                .frame(minHeight: 150)
                Button("重新加载订阅方案") {
                    productsLoaded = false
                    Task { await loadProductsIfNeeded() }
                }
                .buttonStyle(.bordered)
                .disabled(actionInProgress)
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
                            selectedProductID == product.id ? PremiumTheme.brandSoft : TasteMapCoreTheme.surfaceSubtle,
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
        .background(TasteMapCoreTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
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
        .background(TasteMapCoreTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
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
        if let giftStatus = snapshot.giftStatusText { return giftStatus }
        let source = switch snapshot.source {
        case .appStoreSubscription: "App Store 订阅"
        case .appStoreMonthly: "App Store 月度方案"
        case .appStoreYearly, .appStoreAnnual: "App Store 年度方案"
        case .giftAnnual, .giftLifetime: "赠送会员"
        case .signupTrial: "新用户 7 天体验"
        case .referralReward: "邀请奖励会员"
        case .appStoreLifetime: "App Store 永久方案"
        case .adminGrant: "赠送资格"
        case .promo, .promotion: "活动资格"
        case .redeemCode: "兑换资格"
        case .development: "Development 测试资格"
        case nil: "会员资格"
        }
        if snapshot.isLifetime { return "\(source) · 长期有效" }
        if let expiresAt = snapshot.expiresAt {
            return "\(source) · 有效期至 \(TasteMapDisplayDate.abbreviatedDate(expiresAt))"
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
            products = try await entitlementService.productsProvider.products().filter { $0.period == .monthly || $0.period == .annual }
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
        if entitlementService.access(for: feature) != .allowed {
            Label("Premium", systemImage: "lock.fill")
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
        Canvas { context, size in
            let scale = min(size.width, size.height) / PremiumBurgerAssetContract.viewBox
            context.translateBy(
                x: (size.width - PremiumBurgerAssetContract.viewBox * scale) / 2,
                y: (size.height - PremiumBurgerAssetContract.viewBox * scale) / 2
            )
            context.scaleBy(x: scale, y: scale)

            draw(
                Self.bunPath, fill: Self.bun, stroke: Self.bunStroke,
                in: &context
            )
            draw(
                Self.greensPath, fill: Self.greens, stroke: Self.greensStroke,
                in: &context
            )
            draw(
                Self.pattyPath, fill: Self.patty, stroke: Self.pattyStroke,
                in: &context
            )
            draw(
                Self.bottomPath, fill: Self.bun, stroke: Self.bunStroke,
                in: &context
            )
            for point in [CGPoint(x: 8.75, y: 7.6), .init(x: 12.05, y: 6.7), .init(x: 15.25, y: 7.6)] {
                context.fill(
                    Path(ellipseIn: CGRect(x: point.x - 0.45, y: point.y - 0.45, width: 0.9, height: 0.9)),
                    with: .color(Self.seed)
                )
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Taste Map Premium")
        .accessibilityIdentifier("premium-burger-approved-asset")
    }

    private static let bun = Color(red: 231 / 255, green: 184 / 255, blue: 94 / 255)
    private static let bunStroke = Color(red: 184 / 255, green: 120 / 255, blue: 37 / 255)
    private static let greens = Color(red: 121 / 255, green: 166 / 255, blue: 110 / 255)
    private static let greensStroke = Color(red: 85 / 255, green: 125 / 255, blue: 79 / 255)
    private static let patty = Color(red: 164 / 255, green: 93 / 255, blue: 66 / 255)
    private static let pattyStroke = Color(red: 119 / 255, green: 64 / 255, blue: 47 / 255)
    private static let seed = Color(red: 255 / 255, green: 244 / 255, blue: 203 / 255)

    private static let bunPath: Path = {
        var path = Path()
        path.move(to: CGPoint(x: 4.7, y: 10.2))
        path.addCurve(
            to: CGPoint(x: 12, y: 4.5),
            control1: CGPoint(x: 5.1, y: 6.8), control2: CGPoint(x: 7.9, y: 4.5)
        )
        path.addCurve(
            to: CGPoint(x: 19.3, y: 10.2),
            control1: CGPoint(x: 16.1, y: 4.5), control2: CGPoint(x: 18.9, y: 6.8)
        )
        path.closeSubpath()
        return path
    }()

    private static let greensPath: Path = {
        var path = Path()
        path.move(to: CGPoint(x: 4.5, y: 12))
        path.addLine(to: CGPoint(x: 19.5, y: 12))
        path.addLine(to: CGPoint(x: 17.5, y: 14.2))
        path.addLine(to: CGPoint(x: 15, y: 12.9))
        path.addLine(to: CGPoint(x: 12.2, y: 14.4))
        path.addLine(to: CGPoint(x: 9.6, y: 12.9))
        path.addLine(to: CGPoint(x: 7.2, y: 14.2))
        path.closeSubpath()
        return path
    }()

    private static let pattyPath = Path(
        roundedRect: CGRect(x: 5.2, y: 15.2, width: 13.6, height: 2.1),
        cornerRadius: 0.25
    )

    private static let bottomPath: Path = {
        var path = Path()
        path.move(to: CGPoint(x: 5.5, y: 18.2))
        path.addLine(to: CGPoint(x: 18.5, y: 18.2))
        path.addLine(to: CGPoint(x: 18.5, y: 18.5))
        path.addCurve(
            to: CGPoint(x: 16.8, y: 20.2),
            control1: CGPoint(x: 18.5, y: 19.45), control2: CGPoint(x: 17.75, y: 20.2)
        )
        path.addLine(to: CGPoint(x: 7.2, y: 20.2))
        path.addCurve(
            to: CGPoint(x: 5.5, y: 18.5),
            control1: CGPoint(x: 6.25, y: 20.2), control2: CGPoint(x: 5.5, y: 19.45)
        )
        path.closeSubpath()
        return path
    }()

    private func draw(
        _ path: Path,
        fill: Color,
        stroke: Color,
        in context: inout GraphicsContext
    ) {
        context.fill(path, with: .color(fill))
        context.stroke(
            path,
            with: .color(stroke),
            style: StrokeStyle(lineWidth: 1.15, lineCap: .round, lineJoin: .round)
        )
    }
}

nonisolated enum PremiumBurgerAssetContract {
    static let semanticVersion = "web-approved-hamburger-v1"
    static let viewBox: CGFloat = 24
}

nonisolated enum PremiumFoodMotifContract {
    static let kinds: [FoodDiningVisualKind] = [
        .food, .drink, .tableware, .menu, .receipt,
    ]
}

private struct PremiumFoodMotif: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(PremiumTheme.cream)
                Circle().fill(TasteMapCoreTheme.surface).frame(width: min(proxy.size.width, proxy.size.height) * 0.68)
                    .shadow(color: PremiumTheme.brand.opacity(0.1), radius: 16, y: 8)
                FoodDiningVisualIcon(
                    kind: PremiumFoodMotifContract.kinds[0], usage: .decorative,
                    size: min(proxy.size.width, proxy.size.height) * 0.42,
                    foregroundColor: PremiumTheme.brandDeep,
                    backgroundColor: TasteMapCoreTheme.surface
                )
                FoodDiningVisualIcon(
                    kind: PremiumFoodMotifContract.kinds[1], usage: .decorative,
                    size: min(proxy.size.width, proxy.size.height) * 0.24
                )
                .position(x: proxy.size.width * 0.30, y: proxy.size.height * 0.28)
                FoodDiningVisualIcon(
                    kind: PremiumFoodMotifContract.kinds[2], usage: .decorative,
                    size: min(proxy.size.width, proxy.size.height) * 0.23
                )
                .position(x: proxy.size.width * 0.69, y: proxy.size.height * 0.72)
                FoodDiningVisualIcon(
                    kind: PremiumFoodMotifContract.kinds[3], usage: .decorative,
                    size: min(proxy.size.width, proxy.size.height) * 0.20
                )
                .position(x: proxy.size.width * 0.72, y: proxy.size.height * 0.25)
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title3.bold()).foregroundStyle(PremiumTheme.brand)
                    .padding(10).background(TasteMapCoreTheme.surface, in: Circle())
                    .position(x: proxy.size.width * 0.82, y: proxy.size.height * 0.24)
                Image(systemName: "receipt")
                    .font(.title3.bold()).foregroundStyle(PremiumTheme.caramel)
                    .padding(10).background(TasteMapCoreTheme.surface, in: Circle())
                    .position(x: proxy.size.width * 0.16, y: proxy.size.height * 0.75)
            }
        }
        .accessibilityHidden(true)
    }
}

private enum PremiumTheme {
    static let brand = TasteMapCoreTheme.brand
    static let brandDeep = TasteMapCoreTheme.brandDeep
    static let brandSoft = TasteMapCoreTheme.brandSoft
    static let canvas = TasteMapCoreTheme.page
    static let cream = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 52 / 255, green: 46 / 255, blue: 35 / 255, alpha: 1)
            : UIColor(red: 247 / 255, green: 240 / 255, blue: 224 / 255, alpha: 1)
    })
    static let bun = Color(red: 231 / 255, green: 184 / 255, blue: 94 / 255)
    static let leaf = Color(red: 121 / 255, green: 166 / 255, blue: 110 / 255)
    static let patty = Color(red: 164 / 255, green: 93 / 255, blue: 66 / 255)
    static let caramel = Color(red: 173 / 255, green: 117 / 255, blue: 60 / 255)
    static let ink = TasteMapCoreTheme.textPrimary
}

private extension View {
    func premiumStatusCard() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(TasteMapCoreTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(TasteMapCoreTheme.border)
            }
    }
}
